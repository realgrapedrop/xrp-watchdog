-- Migration 003: Add bridge/manipulation classification fields
-- Date: 2025-11-02
-- Description: Add classification and confidence columns to distinguish bridges from manipulation
-- Purpose: Reduce false positives by automatically detecting legitimate bridge protocols

-- Step 1: Add new columns to existing table
ALTER TABLE xrp_watchdog.token_stats
ADD COLUMN IF NOT EXISTS classification Enum8(
  'manipulation' = 1,
  'bridge' = 2,
  'legitimate' = 3,
  'unknown' = 4
) DEFAULT 'unknown' COMMENT 'Token classification based on trading patterns';

ALTER TABLE xrp_watchdog.token_stats
ADD COLUMN IF NOT EXISTS classification_confidence Float32 DEFAULT 0.0 COMMENT 'Confidence in classification (0.0-1.0)';

-- Verification Query
-- Check that columns were added successfully
-- SELECT name, type, default_expression FROM system.columns
-- WHERE database = 'xrp_watchdog' AND table = 'token_stats'
-- AND name IN ('classification', 'classification_confidence');
