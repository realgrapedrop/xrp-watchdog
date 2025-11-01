-- {X}RP Watchdog Database Schema v2
-- Updated: 2025-10-19
-- Changes: Added book_changes, executed_trades, collection_state
--          Removed: trade_pairs (replaced by executed_trades)

-- ============================================
-- CLEANUP: Drop redundant table
-- ============================================
DROP TABLE IF EXISTS xrp_watchdog.trade_pairs;

-- ============================================
-- CLEANUP: Clear test data for fresh start
-- ============================================
TRUNCATE TABLE IF EXISTS xrp_watchdog.raw_events;
TRUNCATE TABLE IF EXISTS xrp_watchdog.offer_events;
TRUNCATE TABLE IF EXISTS xrp_watchdog.account_labels;
TRUNCATE TABLE IF EXISTS xrp_watchdog.detection_alerts;

-- ============================================
-- Table 1: raw_events (EXISTING - kept for archive)
-- ============================================
-- No changes needed - table already exists

-- ============================================
-- Table 2: offer_events (EXISTING - kept for Phase 3)
-- ============================================
-- No changes needed - table already exists

-- ============================================
-- Table 3: book_changes (NEW - volume screening)
-- ============================================
CREATE TABLE IF NOT EXISTS xrp_watchdog.book_changes (
    time DateTime64(3) COMMENT 'Ledger close time',
    ledger_index UInt32 COMMENT 'XRPL ledger number',
    ledger_hash FixedString(64) COMMENT 'Ledger hash',
    
    -- Trading pair
    currency_pair String COMMENT 'e.g., XRP_drops/issuer/USD',
    currency_code String COMMENT 'Token currency code',
    issuer String COMMENT 'Token issuer address',
    
    -- OHLC data
    open Float64 COMMENT 'Opening price',
    high Float64 COMMENT 'Highest price',
    low Float64 COMMENT 'Lowest price',
    close Float64 COMMENT 'Closing price',
    
    -- Volume
    volume_xrp Float64 COMMENT 'XRP volume in drops',
    volume_token Float64 COMMENT 'Token volume',
    
    -- Calculated flags
    price_variance Float64 COMMENT '(high-low)/open ratio',
    is_suspicious UInt8 COMMENT 'Flag: 1 if volume >=5M AND variance <0.01',
    
    INDEX idx_suspicious is_suspicious TYPE set(2) GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(time)
ORDER BY (time, volume_xrp)
TTL toDateTime(time) + INTERVAL 90 DAY
COMMENT 'DEX book changes for volume screening';

-- ============================================
-- Table 4: executed_trades (NEW - trade evidence)
-- ============================================
CREATE TABLE IF NOT EXISTS xrp_watchdog.executed_trades (
    time DateTime64(3) COMMENT 'Ledger close time',
    ledger_index UInt32 COMMENT 'XRPL ledger number',
    ledger_hash FixedString(64) COMMENT 'Ledger hash',
    tx_hash FixedString(64) COMMENT 'Transaction hash',
    tx_type Enum8('OfferCreate'=1, 'Payment'=2) COMMENT 'Transaction type',
    
    -- Accounts
    taker String COMMENT 'Account executing trade',
    counterparties Array(String) COMMENT 'Real counterparties (Modified/Deleted Offers only)',
    counterparty_count UInt8 COMMENT 'Number of counterparties',
    
    -- Posted terms (from tx body - reference)
    posted_gets String COMMENT 'Posted TakerGets (format: kind:code/issuer=value)',
    posted_pays String COMMENT 'Posted TakerPays (format: kind:code/issuer=value)',
    
    -- Executed amounts (from balance deltas - actual)
    exec_xrp Float64 COMMENT 'Executed XRP (fee-corrected, signed)',
    exec_iou_code String COMMENT 'IOU currency code',
    exec_iou_issuer String COMMENT 'IOU issuer',
    exec_iou Float64 COMMENT 'Executed IOU amount (absolute)',
    exec_price Float64 COMMENT 'Executed price (XRP per IOU)',
    
    -- Calculated
    total_volume_xrp Float64 COMMENT 'Abs(exec_xrp) for volume queries',
    
    INDEX idx_taker taker TYPE bloom_filter GRANULARITY 1,
    INDEX idx_hash tx_hash TYPE bloom_filter GRANULARITY 1,
    INDEX idx_volume total_volume_xrp TYPE minmax GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(time)
ORDER BY (time, total_volume_xrp)
TTL toDateTime(time) + INTERVAL 90 DAY
COMMENT 'Executed trades with real counterparties and balance-change volumes';

-- ============================================
-- Table 5: account_labels (EXISTING - kept)
-- ============================================
-- No changes needed - table already exists

-- ============================================
-- Table 6: detection_alerts (EXISTING - kept)
-- ============================================
-- No changes needed - table already exists

-- ============================================
-- Table 7: collection_state (NEW - progress tracking)
-- ============================================
CREATE TABLE IF NOT EXISTS xrp_watchdog.collection_state (
    collector_name String COMMENT 'Name of collector (book_screener, trade_collector)',
    last_ledger_hash FixedString(64) COMMENT 'Last processed ledger hash',
    last_ledger_index UInt32 COMMENT 'Last processed ledger index',
    last_update DateTime64(3) COMMENT 'When last updated',
    status Enum8('running'=1, 'stopped'=2, 'error'=3) COMMENT 'Current status',
    error_message String COMMENT 'Last error if status=error'
) ENGINE = ReplacingMergeTree(last_update)
ORDER BY collector_name
COMMENT 'Track collection progress and state';

-- ============================================
-- Verification Queries (for testing)
-- ============================================

-- Show all tables
-- SHOW TABLES FROM xrp_watchdog;

-- Show table row counts
-- SELECT 
--     table,
--     formatReadableSize(sum(bytes)) as size,
--     sum(rows) as rows
-- FROM system.parts
-- WHERE database = 'xrp_watchdog' AND active
-- GROUP BY table
-- ORDER BY table;

-- Token Whitelist
-- Known legitimate tokens that should be excluded from manipulation scoring
CREATE TABLE IF NOT EXISTS xrp_watchdog.token_whitelist (
    token_code String,
    token_issuer String,
    token_name String,
    category Enum8('stablecoin' = 1, 'major_token' = 2, 'exchange_token' = 3, 'verified' = 4),
    reason String,
    added_date DateTime DEFAULT now(),
    added_by String DEFAULT 'system'
) ENGINE = MergeTree()
ORDER BY (token_code, token_issuer)
COMMENT 'Whitelist of legitimate tokens to exclude from manipulation detection';

-- Insert known legitimate tokens
INSERT INTO xrp_watchdog.token_whitelist 
(token_code, token_issuer, token_name, category, reason) VALUES
-- RLUSD (Ripple USD Stablecoin)
('524C555344000000000000000000000000000000', 'rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De', 'RLUSD', 'stablecoin', 'Official Ripple USD stablecoin - low price variance by design'),
('524C555344000000000000000000000000000000', 'rrrrrrrrrrrrrrrrrrrrBZbvji', 'RLUSD', 'stablecoin', 'RLUSD black hole issuer variant'),

-- Add other known stablecoins as discovered
('USD', 'rKiCet8SdvWxPXnAgYarFUXMh1zCPz432Y', 'USD', 'stablecoin', 'USD stablecoin - naturally low variance');
