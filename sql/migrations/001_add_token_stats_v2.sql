-- Migration: Add token_stats table with v2.0 risk scoring
-- Created: 2025-10-31
-- Purpose: Add parallel v1.0 and v2.0 risk scoring with stablecoin filtering

-- ============================================
-- Step 1: Create token_stats table
-- ============================================
-- This table stores aggregated token statistics with both v1.0 and v2.0 risk scores
-- Populated by analyzers/token_analyzer.py (run after each collection batch)

CREATE TABLE IF NOT EXISTS xrp_watchdog.token_stats (
  token_code String,
  token_issuer String,
  total_trades UInt32,
  unique_takers UInt32,
  unique_counterparties UInt32,
  total_xrp_volume Float64,
  total_token_volume Float64,
  ledger_span UInt32,
  days_active Int32,
  first_seen DateTime64(3),
  last_seen DateTime64(3),
  avg_price Float64,
  price_stddev Float64,
  avg_trade_xrp Float64,
  trade_size_stddev Float64,

  -- Whitelist status
  is_whitelisted UInt8,
  whitelist_category String,

  -- V2.0 metrics
  avg_time_gap_seconds Float64,
  trade_density Float64 COMMENT 'Trades per hour',

  -- Calculated ratios
  price_variance_percent Float64,
  size_variance_percent Float64,
  trades_per_account Float64,
  xrp_volume_per_account Float64,

  -- Risk scores
  risk_score_v1 Float32 COMMENT 'Original risk score (0-100)',
  risk_score_v2 Float32 COMMENT 'Enhanced risk score with burst detection (0-100)',
  burst_score Float32 COMMENT 'Burst trading detection score (0-100)',

  -- Metadata
  last_updated DateTime64(3) DEFAULT now()
) ENGINE = ReplacingMergeTree(last_updated)
ORDER BY (risk_score_v2, token_code, token_issuer)
COMMENT 'Aggregated token statistics with v1.0 and v2.0 risk scoring';

-- ============================================
-- Step 2: Create refresh query (used by Python analyzer)
-- ============================================
-- This query will be executed by analyzers/token_analyzer.py

-- The query below is embedded in analyzers/token_analyzer.py
-- Kept here for reference and manual testing
*/

-- ============================================
-- Step 2: Update whitelist with additional stablecoins
-- ============================================
-- Add EUR and other common stablecoins that were mentioned in the docs
-- Note: This uses INSERT OR IGNORE pattern for ClickHouse compatibility

-- First, let's check what's already in the whitelist
-- SELECT * FROM xrp_watchdog.token_whitelist;

-- ============================================
-- Verification Queries
-- ============================================
-- Run these to verify the migration worked correctly

-- Check table was created
-- SELECT name, engine, total_rows FROM system.tables WHERE database = 'xrp_watchdog' AND name = 'token_stats';

-- After running the analyzer, compare v1.0 vs v2.0 scores
-- SELECT
--   token_code,
--   token_issuer,
--   total_trades,
--   unique_takers,
--   is_whitelisted,
--   risk_score_v1,
--   risk_score_v2,
--   (risk_score_v2 - risk_score_v1) as score_diff,
--   trade_density,
--   burst_score
-- FROM xrp_watchdog.token_stats
-- ORDER BY risk_score_v2 DESC
-- LIMIT 20;
