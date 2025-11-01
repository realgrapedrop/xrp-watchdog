-- Migration 002: Rename risk_score_v2 to risk_score
-- Author: Claude Code
-- Date: 2025-11-01
-- Description: Simplify column naming by removing v2 suffix
-- Note: Column is part of ORDER BY key, so we recreate the table

-- Step 1: Create new table with correct column name
CREATE TABLE IF NOT EXISTS xrp_watchdog.token_stats_new (
  token_code String,
  token_issuer String,
  total_trades UInt32,
  unique_takers UInt32,
  unique_counterparties UInt32,
  total_xrp_volume Float64,
  total_token_volume Float64,
  ledger_span UInt32,
  days_active UInt32,
  first_seen DateTime64(3),
  last_seen DateTime64(3),
  avg_price Float64,
  price_stddev Float64,
  avg_trade_xrp Float64,
  trade_size_stddev Float64,
  is_whitelisted UInt8,
  whitelist_category String,
  avg_time_gap_seconds Float64,
  trade_density Float64,
  price_variance_percent Float64,
  size_variance_percent Float64,
  trades_per_account Float64,
  xrp_volume_per_account Float64,
  risk_score Float32,              -- RENAMED from risk_score_v2
  burst_score Float32,
  last_updated DateTime64(3)
) ENGINE = ReplacingMergeTree(last_updated)
ORDER BY (risk_score, token_code, token_issuer);  -- UPDATED

-- Step 2: Copy data from old table to new table
INSERT INTO xrp_watchdog.token_stats_new
SELECT
  token_code,
  token_issuer,
  total_trades,
  unique_takers,
  unique_counterparties,
  total_xrp_volume,
  total_token_volume,
  ledger_span,
  days_active,
  first_seen,
  last_seen,
  avg_price,
  price_stddev,
  avg_trade_xrp,
  trade_size_stddev,
  is_whitelisted,
  whitelist_category,
  avg_time_gap_seconds,
  trade_density,
  price_variance_percent,
  size_variance_percent,
  trades_per_account,
  xrp_volume_per_account,
  risk_score_v2 as risk_score,  -- Rename during copy
  burst_score,
  last_updated
FROM xrp_watchdog.token_stats;

-- Step 3: Drop old table
DROP TABLE xrp_watchdog.token_stats;

-- Step 4: Rename new table to original name
RENAME TABLE xrp_watchdog.token_stats_new TO xrp_watchdog.token_stats;
