# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XRP Watchdog is a wash trading detection system for the XRP Ledger (XRPL). It monitors DEX activity by collecting executed trades, screening for suspicious volume patterns, and identifying potential market manipulation.

**Architecture**: Two-phase collection pipeline feeding ClickHouse analytics
- **Phase 1**: Book screener scans ledgers for high-volume, low-variance trading (suspicious indicators)
- **Phase 2**: Trade collector analyzes suspicious ledgers in detail, extracting trade counterparties and IOU balances

## Core Components

### Data Collection Pipeline

1. **collectors/book_screener.py** - Volume screening using rippled's `book_changes` API
   - Flags ledgers with high volume (≥5M XRP) + low price variance (<1%)
   - Writes to `book_changes` table with `is_suspicious` flag
   - Used for initial filtering before expensive detailed analysis

2. **collectors/trade_collector.py** - Detailed trade extraction
   - Combines shell script `getMakerTaker.sh` output with Python RippleState parsing
   - Extracts real counterparties from Modified/Deleted offers in transaction metadata
   - Parses IOU balance changes from RippleState nodes
   - Writes to `executed_trades` table with full trade details

3. **collectors/collection_orchestrator.py** - Coordinates the pipeline
   - Runs book_screener for batch of ledgers
   - Identifies suspicious ledgers not yet analyzed in detail
   - Runs trade_collector on suspicious ledgers only
   - Tracks progress in `collection_state` table

4. **scripts/getMakerTaker.sh** - Shell script for extracting maker/taker relationships
   - Called by trade_collector.py for accurate counterparty identification
   - Outputs TSV format consumed by Python collector

### Database Schema

**ClickHouse tables** (see `sql/schema.sql`):
- `book_changes` - OHLC data from book_changes API, flagged for suspicious activity
- `executed_trades` - Detailed trade records with counterparties, XRP/IOU amounts, prices
- `collection_state` - Collection progress tracking
- `token_whitelist` - Legitimate tokens (RLUSD, stablecoins) excluded from manipulation scoring

### Configuration

- **config.env** - Runtime configuration (created by install.sh)
  - `RIPPLED_CONTAINER` - Docker container name for rippled validator
  - `CLICKHOUSE_HTTP_PORT` / `CLICKHOUSE_NATIVE_PORT` - Database ports
  - `COLLECTION_BATCH_SIZE` - Ledgers per collection run
  - `CRON_SCHEDULE` - Auto-collection schedule (default: every 15 minutes)

- **config.env.example** - Template with defaults

## Common Commands

### Setup
```bash
# Interactive installation (detects environment, sets up DB, configures cron)
./install.sh

# Manual setup of Python environment
python3 -m venv venv
source venv/bin/activate
pip install clickhouse-connect

# Start ClickHouse
cd compose && docker compose up -d && cd ..

# Create database schema
docker exec -i xrp-watchdog-clickhouse clickhouse-client --multiquery < sql/schema.sql
```

### Data Collection
```bash
# Activate Python environment first
source venv/bin/activate

# Collect 13 ledgers (standard batch)
python collectors/collection_orchestrator.py 13

# Collect from specific starting ledger
python collectors/collection_orchestrator.py 13 --start 99638589

# Run book screener only
python collectors/book_screener.py 13

# Run trade collector for specific ledger hash
python collectors/trade_collector.py <ledger_hash>
```

### Backfilling
```bash
# Smart backfill - automatically fills gaps without duplicates
./backfill_smart.sh

# Manual gap filling (adjust START_LEDGER and END_LEDGER in script)
./backfill_gap.sh

# Slow, careful backfill (longer delays between batches)
./backfill_slow.sh
```

### Health Monitoring
```bash
# Run comprehensive health check
./health_check.sh

# Check auto-collection logs
tail -f logs/auto_collection.log

# Check cron job
crontab -l | grep collection_orchestrator
```

### Database Queries
```bash
# Query database directly
docker exec xrp-watchdog-clickhouse clickhouse-client -q "SELECT COUNT(*) FROM xrp_watchdog.executed_trades"

# Run detection queries
cat queries/01_ping_pong_detector.sql | docker exec -i xrp-watchdog-clickhouse clickhouse-client --multiquery
cat queries/03_token_manipulation_leaderboard.sql | docker exec -i xrp-watchdog-clickhouse clickhouse-client --multiquery
```

## Development Workflow

### Testing Data Collection
When modifying collectors, test with a small batch first:
```bash
source venv/bin/activate
python collectors/collection_orchestrator.py 1  # Single ledger test
```

### Key Data Extraction Logic

**IOU Balance Extraction** (collectors/trade_collector.py:56-131):
- RippleState nodes have `LowLimit` and `HighLimit` representing the two accounts in trust line
- Balance sign interpretation depends on which side the taker is on:
  - If taker is `LowLimit.issuer`: balance is negated (negative = owed TO them)
  - If taker is `HighLimit.issuer`: balance is direct (positive = they owe)
- Token issuer is always the OTHER party (not the taker)

**Counterparty Identification**:
- Real counterparties come from Modified/Deleted offers in transaction metadata
- Created offers are NOT counterparties (they're posted by taker)
- getMakerTaker.sh handles this extraction, trade_collector.py parses the TSV output

### Rippled API Access
All collectors interact with rippled through Docker:
```bash
docker exec $RIPPLED_CONTAINER rippled -q <command> [args]
```

Key commands used:
- `ledger closed` - Get latest closed ledger
- `ledger <hash>` - Get specific ledger details
- `book_changes <hash>` - Get OHLC data for ledger
- `tx <hash>` - Get full transaction with metadata

### ⚠️ CRITICAL: Dangerous Rippled Commands

**NEVER USE**: `docker exec rippledvalidator rippled ledger full` or `docker exec rippledvalidator rippled -q ledger full`

This command returns the **entire XRPL validator ledger** and will:
- Severely overstress the validator
- Cripple validator performance
- Potentially crash the validator process

Always specify a ledger hash, index, or use `closed`/`current` modifiers when querying ledger data. Never use the `full` parameter.

## System Architecture Notes

### Why Two-Phase Collection?
Phase 1 (book_changes) is fast but limited - provides OHLC aggregates without transaction details.
Phase 2 (trade extraction) is expensive - requires fetching and parsing full transaction metadata for every trade.

By screening first, we only run expensive extraction on suspicious ledgers (~5-10% of total), reducing data collection time by 90%+ while maintaining detection accuracy.

### Deduplication Strategy
- Trade collector deduplicates by `tx_hash` since same transaction may match multiple offers
- Smart backfill checks existing ledgers in DB before collection to avoid reprocessing

### State Management
`collection_state` table tracks progress with ReplacingMergeTree engine:
- Ordered by collector_name (book_screener, trade_collector)
- Replaced on each update based on last_update timestamp
- Enables resumable collection after interruptions

## Wash Trading Detection

### Detection Indicators

The system flags suspicious activity based on:
- **High volume**: ≥5M XRP traded in a single ledger
- **Low price variance**: <1% price movement despite high volume

This pattern suggests coordinated trading between related accounts (wash trading) to artificially inflate volume without genuine price discovery.

### ⚠️ Important: Stablecoins Are NOT Suspicious

**Stablecoins naturally exhibit high volume + low variance** because they're pegged to fiat currencies. This is legitimate behavior, not manipulation.

Examples of legitimate low-variance tokens:
- **RLUSD** - Ripple's official USD stablecoin
- **USDC** - USD Coin
- Other USD/EUR-pegged tokens

### Filtering Stablecoins from Detection Queries

Always exclude whitelisted tokens when running manipulation detection queries:

```sql
-- Example: Filter out legitimate stablecoins
SELECT
    taker,
    exec_iou_code,
    COUNT(*) as trade_count,
    SUM(total_volume_xrp) as volume
FROM xrp_watchdog.executed_trades
WHERE exec_iou_code NOT IN (
    SELECT token_code FROM xrp_watchdog.token_whitelist
)
AND exec_iou_issuer NOT IN (
    SELECT token_issuer FROM xrp_watchdog.token_whitelist
)
GROUP BY taker, exec_iou_code
ORDER BY volume DESC
```

**Adding tokens to whitelist**:
```sql
INSERT INTO xrp_watchdog.token_whitelist
(token_code, token_issuer, token_name, category, reason)
VALUES
('YOUR_TOKEN_CODE', 'rISSUER_ADDRESS', 'Token Name', 'stablecoin', 'Reason for exclusion');
```

Categories: `stablecoin`, `major_token`, `exchange_token`, `verified`

## Uninstallation
```bash
./uninstall.sh  # Removes cron job, stops containers, cleans up data
```
