# XRP Watchdog

Real-time wash trading and token manipulation detection system for the XRP Ledger DEX.

## Overview

XRP Watchdog is a sophisticated monitoring system that analyzes DEX activity on the XRP Ledger to detect potential wash trading, pump-and-dump schemes, and other market manipulation tactics. The system provides a comprehensive Grafana dashboard with risk scoring, pattern analysis, and investigative tools.

### Key Features

- **Real-time Monitoring**: Collects and analyzes DEX trades every 5 minutes with 100% ledger coverage
- **Advanced Risk Scoring**: Multi-component algorithm (0-100 scale) detecting manipulation patterns
- **Burst Detection**: Identifies suspicious high-frequency trading clusters and bot activity
- **Token Whitelisting**: Excludes known legitimate tokens from risk analysis
- **Interactive Dashboard**: Beautiful Grafana interface with educational content
- **Account Tracking**: Monitors suspicious accounts trading high-risk tokens
- **Automated Analysis**: Self-healing system with comprehensive logging

## Quick Start

### Prerequisites

- Python 3.8+
- ClickHouse database
- Grafana 9.0+
- XRP Ledger full history node access (via RPC)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/xrp-watchdog.git
cd xrp-watchdog

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Initialize database
clickhouse-client < sql/schema.sql
clickhouse-client < sql/migrations/001_add_risk_score_v2.sql
clickhouse-client < sql/migrations/002_rename_risk_score_column.sql
```

### Configuration

1. **Configure ClickHouse connection** in collector and analyzer scripts:
   ```python
   CLICKHOUSE_HOST = "localhost"
   CLICKHOUSE_PORT = 8123
   CLICKHOUSE_DB = "xrp_watchdog"
   ```

2. **Set up cron job** for automated collection (every 5 minutes):
   ```bash
   crontab -e
   # Add:
   */5 * * * * /home/grapedrop/monitoring/xrp-watchdog/run_collection.sh >> /home/grapedrop/monitoring/xrp-watchdog/logs/cron.log 2>&1
   ```

3. **Configure Grafana**:
   - Add ClickHouse data source
   - Import dashboard panels using queries from `grafana/token_stats_queries.md`

### Manual Run

```bash
# Activate virtual environment
source venv/bin/activate

# Run collection (130 ledgers) with analysis
python collectors/collection_orchestrator.py 130 --analyze

# Run analyzer separately
python analyzers/token_analyzer.py
```

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    XRP Ledger Node                      │
│                 (Full History via RPC)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Collection Orchestrator                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │  • Fetches 130 ledgers every 5 minutes           │  │
│  │  • Extracts executed trades (OfferCreate txs)    │  │
│  │  • Processes payment transactions                │  │
│  │  • Inserts into ClickHouse                       │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  ClickHouse Database                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Tables:                                         │  │
│  │  • executed_trades - Raw trade data             │  │
│  │  • token_stats - Aggregated risk metrics        │  │
│  │  • token_whitelist - Legitimate tokens          │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                 Token Analyzer                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  • Calculates risk scores (5 components)         │  │
│  │  • Detects burst patterns                        │  │
│  │  • Applies whitelist exclusions                  │  │
│  │  • Updates token_stats table                     │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                 Grafana Dashboard                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │  • Risk Score Overview                           │  │
│  │  • Top Suspicious Tokens                         │  │
│  │  • Top Suspicious Accounts                       │  │
│  │  • Whitelisted Tokens                            │  │
│  │  • Methodology Guide (Educational)               │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Risk Scoring Algorithm

The system uses a 5-component algorithm (0-100 scale) to detect manipulation:

#### 1. Volume Component (max 50 points)
- **Formula**: `min(50, log10(volume_millions + 1) × 12.5)`
- **Purpose**: Logarithmic scaling prevents extreme outliers from dominating scores
- **Why**: Large volumes can indicate manipulation, but linear scaling would be unfair

#### 2. Token Focus (max 30 points)
- **Metric**: Number of unique accounts trading the token
- **Scoring**:
  - ≤2 takers: 30 pts (extreme concentration)
  - 3-5 takers: 22 pts (high concentration)
  - 6-10 takers: 15 pts (moderate concentration)
  - 11-20 takers: 8 pts (low concentration)
  - 20+ takers: 3 pts (normal distribution)
- **Why**: Manipulators typically use few accounts; real tokens have many traders

#### 3. Price Stability (max 20 points)
- **Metric**: Coefficient of variation in trade prices
- **Why**: Bots trade at precise prices; real markets have natural variance
- **Threshold**: <0.5% variance = maximum suspicion

#### 4. Burst Detection (max 15 points)
- **Metric**: Trades per hour (temporal clustering)
- **Scoring**:
  - ≥100/hr: 15 pts (extreme burst)
  - ≥50/hr: 12 pts (high burst)
  - ≥20/hr: 8 pts (moderate burst)
- **Why**: Catches pump-and-dump schemes and bot-driven campaigns

#### 5. Trade Uniformity (max 10 points)
- **Metric**: Coefficient of variation in trade sizes
- **Why**: Bots trade uniform amounts; humans vary
- **Threshold**: <2% variance = robotic pattern

### Data Flow

1. **Collection Phase** (every 5 minutes):
   - Fetch latest 130 ledgers from XRP Ledger node
   - Extract OfferCreate transactions with executed trades
   - Store raw trade data in `executed_trades` table
   - ~48,000+ trades collected to date

2. **Analysis Phase** (after collection):
   - Aggregate trades by token (currency code + issuer)
   - Calculate statistical metrics (price variance, trade density, etc.)
   - Compute risk scores using 5-component algorithm
   - Update `token_stats` table
   - Runtime: ~40ms for 360+ tokens

3. **Visualization Phase** (continuous):
   - Grafana queries ClickHouse every 5 minutes
   - Real-time dashboard updates
   - Interactive exploration with XRPScan integration

## Dashboard

### Overview Panel
Three key metrics:
- **Total Tokens**: Non-whitelisted tokens with ≥3 trades
- **Avg Risk Score**: Market health indicator (current: ~32.6)
- **High Risk Count**: Tokens with risk ≥60

### Top Suspicious Tokens
Table showing 20 highest-risk tokens with:
- Token code (hex decoded to ASCII)
- Issuer address (truncated, clickable to XRPScan)
- Risk score, trades, volume, price variance
- Burst score and trades/hour
- Last updated timestamp

### Top Suspicious Accounts
Accounts actively trading high-risk tokens:
- Account address (clickable to XRPScan)
- Token being traded
- Trade count and volume
- First seen / last seen timestamps

### Methodology Guide
Collapsible educational panel with:
- Manipulation tactics explained
- Risk score algorithm breakdown
- Investigation workflow
- Risk tiers and red flags
- Real examples from collected data

## File Structure

```
xrp-watchdog/
├── analyzers/
│   └── token_analyzer.py          # Risk scoring engine
├── collectors/
│   └── collection_orchestrator.py # Ledger data collector
├── grafana/
│   └── token_stats_queries.md     # Dashboard query reference
├── logs/
│   ├── auto_collection.log        # Automated collection log
│   └── cron.log                   # Cron execution log
├── sql/
│   ├── schema.sql                 # Database schema
│   └── migrations/
│       ├── 001_add_risk_score_v2.sql
│       └── 002_rename_risk_score_column.sql
├── CLAUDE.md                      # Comprehensive project documentation
├── README.md                      # This file
├── requirements.txt               # Python dependencies
├── run_analyzer.sh                # Analyzer execution script
└── run_collection.sh              # Collection execution script
```

## Performance Metrics

- **Collection Frequency**: Every 5 minutes
- **Ledger Coverage**: 100% (130 ledgers per run)
- **Analysis Speed**: ~40ms for 360+ tokens
- **Total Trades Collected**: 48,000+
- **Tokens Analyzed**: 360+
- **Database Size**: Optimized with ReplacingMergeTree
- **Query Performance**: <100ms for dashboard queries

## Whitelist Management

Add legitimate tokens to exclude from risk scoring:

```sql
INSERT INTO xrp_watchdog.token_whitelist VALUES
    ('USD', 'rhub8VRN55s94qWKDv6jmDy1pUykJzF3wq', 'stablecoin'),
    ('BTC', 'rcA8X3TVMST1n3CJeAdGk1RdRCHii7N2h', 'established');
```

Categories:
- `stablecoin` - USD/EUR pegged tokens
- `established` - Long-running legitimate projects
- `verified` - Verified by community/exchanges

## Troubleshooting

### Collection Issues

**Problem**: Collection fails to fetch ledgers
- **Check**: XRP Ledger node connectivity
- **Solution**: Verify RPC endpoint in collector script

**Problem**: Duplicate trades inserted
- **Check**: ClickHouse ReplacingMergeTree is working
- **Solution**: Run `OPTIMIZE TABLE executed_trades FINAL;`

### Analysis Issues

**Problem**: Risk scores not updating
- **Check**: Token analyzer execution in cron logs
- **Solution**: Manually run `python analyzers/token_analyzer.py`

**Problem**: Whitelisted tokens showing risk scores
- **Check**: Token code and issuer match exactly in whitelist
- **Solution**: Verify case sensitivity and whitespace

### Dashboard Issues

**Problem**: Grafana shows no data
- **Check**: ClickHouse data source connection
- **Solution**: Test query in ClickHouse client first

**Problem**: Token names showing as hex
- **Check**: Query includes `unhex()` and `replaceRegexpAll()` functions
- **Solution**: Use updated queries from `grafana/token_stats_queries.md`

## Development

### Running Tests

```bash
# Activate virtual environment
source venv/bin/activate

# Run collector in dry-run mode
python collectors/collection_orchestrator.py 10 --dry-run

# Run analyzer with verbose output
python analyzers/token_analyzer.py
```

### Adding New Features

1. **Database Schema Changes**: Create migration in `sql/migrations/`
2. **Collector Enhancements**: Modify `collection_orchestrator.py`
3. **Risk Algorithm Updates**: Update `token_analyzer.py` and `CLAUDE.md`
4. **Dashboard Changes**: Document queries in `grafana/token_stats_queries.md`

### Code Style

- Python: PEP 8 compliant
- SQL: Uppercase keywords, 2-space indentation
- Documentation: Markdown with clear sections

## Monitoring

### Log Files

- **auto_collection.log**: Collection status, trade counts, errors
- **cron.log**: Cron execution timestamps and exit codes

### Monitoring Collection

```bash
# Tail collection log
tail -f logs/auto_collection.log

# Check cron execution
tail -f logs/cron.log

# Verify cron schedule
crontab -l
```

### Health Checks

```bash
# Check recent trades
clickhouse-client --query "SELECT COUNT(*) FROM xrp_watchdog.executed_trades WHERE time > now() - INTERVAL 1 HOUR"

# Check token stats freshness
clickhouse-client --query "SELECT MAX(last_updated) FROM xrp_watchdog.token_stats"

# Check disk usage
clickhouse-client --query "SELECT formatReadableSize(sum(bytes)) as size FROM system.parts WHERE database = 'xrp_watchdog'"
```

## Known Limitations

1. **Historical Data**: System only analyzes trades from collection start date
2. **Cross-Chain Activity**: Only monitors XRP Ledger DEX (not CEXs or other chains)
3. **False Positives**: Legitimate low-liquidity tokens may score high
4. **Real-time Detection**: 5-minute delay between trade execution and detection
5. **Burst Scoring**: Requires multiple trades; single large trades not detected

## Roadmap

### Completed
- ✅ Basic trade collection from XRP Ledger
- ✅ Risk scoring algorithm v1.0 (linear scaling)
- ✅ Risk scoring algorithm v2.0 (logarithmic scaling + burst detection)
- ✅ Grafana dashboard with educational content
- ✅ Token whitelisting system
- ✅ Automated 5-minute collection
- ✅ Account-level tracking

### Future Enhancements
- [ ] Historical risk score tracking (time series)
- [ ] Alert system (email/Slack notifications for high-risk tokens)
- [ ] Network graph visualization (account clustering)
- [ ] ML-based anomaly detection
- [ ] API for programmatic access
- [ ] Multi-chain support (Ethereum DEX, etc.)
- [ ] Advanced pattern recognition (coordinated trading across tokens)

## Contributing

This is currently a personal monitoring project. If you'd like to contribute:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- **XRP Ledger Foundation** - For excellent documentation and RPC infrastructure
- **ClickHouse** - For blazing-fast analytical database
- **Grafana** - For beautiful visualization capabilities
- **XRPL Community** - For insights into DEX manipulation patterns

## Contact

For questions, issues, or suggestions, please open a GitHub issue.

---

**Disclaimer**: This tool is for educational and research purposes. It detects *potential* manipulation patterns and should not be used as the sole basis for trading decisions. Always conduct thorough research before trading any token.
