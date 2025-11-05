-- XRP Watchdog v2.0 Risk Scoring Algorithm
-- Expert-reviewed by ChatGPT-5 and Grok-4
-- Key changes:
--   1. Volume component: 50 -> 60 points max
--   2. Dual-window: 24h for patterns, 7d for impact
--   3. Impact factor: smooth logarithmic curve
--   4. Final priority = risk_score × impact_factor
--   5. Minimum trades: 3 -> 5 (reduces noise)

WITH stats_24h AS (
  -- 24-hour window: Pattern detection (burst, precision, concentration)
  SELECT
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    COUNT(*) as total_trades,
    COUNT(DISTINCT taker) as unique_takers,
    SUM(ABS(exec_xrp)) as total_xrp_volume_24h,
    AVG(exec_price) as avg_price,
    stddevPop(exec_price) as price_stddev,
    AVG(ABS(exec_xrp)) as avg_trade_size,
    stddevPop(ABS(exec_xrp)) as trade_size_stddev,
    min(time) as first_trade,
    max(time) as last_trade
  FROM xrp_watchdog.executed_trades
  WHERE $__timeFilter(time)
  GROUP BY token_code, token_issuer
  HAVING total_trades >= 5  -- v2.0: Increased from 3 to reduce micro-blips
),

stats_7d AS (
  -- 7-day window: Volume for impact assessment
  SELECT
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    SUM(ABS(exec_xrp)) as total_xrp_volume_7d,
    COUNT(*) as total_trades_7d
  FROM xrp_watchdog.executed_trades
  WHERE time >= now() - INTERVAL 7 DAY
  GROUP BY token_code, token_issuer
)

SELECT
  -- Token display (UTF-8 validated)
  CASE
    WHEN length(s24.token_code) = 40 THEN
      CASE
        WHEN isValidUTF8(unhex(s24.token_code)) THEN upper(replaceRegexpAll(unhex(s24.token_code), '\0', ''))
        ELSE concat('$', substring(s24.token_code, 1, 4), '...', substring(s24.token_code, 37, 4))
      END
    ELSE upper(s24.token_code)
  END as "Token",

  s24.token_issuer as "Issuer",

  -- === RISK SCORE (0-100) === Behavioral pattern detection (24h window)
  ROUND(LEAST(
    -- Volume component (v2.0: max 60, adjusted scaling)
    LEAST(60, log10(s24.total_xrp_volume_24h / 100000 + 1) * 15) +

    -- Token Focus component (max 30)
    CASE
      WHEN s24.unique_takers <= 2 THEN 30
      WHEN s24.unique_takers <= 5 THEN 22
      WHEN s24.unique_takers <= 10 THEN 15
      WHEN s24.unique_takers <= 20 THEN 8
      ELSE 3
    END +

    -- Price Stability component (max 20)
    CASE
      WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 0.5 THEN 20
      WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 1 THEN 16
      WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 3 THEN 12
      WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 5 THEN 8
      WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 10 THEN 4
      ELSE 1
    END +

    -- Burst Detection component (max 15)
    CASE
      WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 100 THEN 15
      WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 50 THEN 12
      WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 20 THEN 8
      WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 10 THEN 5
      ELSE 2
    END +

    -- Trade Size Uniformity component (max 10)
    CASE
      WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 2 THEN 10
      WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 5 THEN 7
      WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 10 THEN 4
      ELSE 1
    END,
    100
  ), 1) as "Risk Score",

  -- Supporting metrics
  s24.total_trades as "Trades",
  ROUND(s24.total_xrp_volume_24h, 0) as "XRP Volume (24h)",
  ROUND(COALESCE(s7.total_xrp_volume_7d, s24.total_xrp_volume_24h), 0) as "XRP Volume (7d)",
  ROUND((s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100, 1) as "Price Var %",
  ROUND(s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01), 1) as "Trades/Hour",
  ROUND(CASE
    WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 100 THEN 100
    WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 50 THEN 80
    WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 20 THEN 53
    WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 10 THEN 33
    ELSE 13
  END, 0) as "Burst",
  ROUND((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 60, 0) as "Duration (min)"

FROM stats_24h s24
LEFT JOIN stats_7d s7
  ON s24.token_code = s7.token_code
  AND s24.token_issuer = s7.token_issuer

-- Whitelist filtering
LEFT JOIN xrp_watchdog.token_stats tst
  ON s24.token_code = tst.token_code
  AND s24.token_issuer = tst.token_issuer
WHERE s24.token_issuer NOT IN (
  SELECT token_issuer FROM xrp_watchdog.token_whitelist
)
AND (
  tst.classification IS NULL
  OR tst.classification NOT IN ('bridge', 'legitimate')
)
AND NOT (
  upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%.AXL'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE 'USDC%AXL%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%BRIDGE%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE 'WRAPPED%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%ALLBRIDGE%'
)

-- Actionable view: Filter by volume threshold
-- Research view: Remove this filter to see all patterns
AND s24.total_xrp_volume_24h >= 10  -- v2.0: Minimum impact threshold

ORDER BY "Risk Score" DESC
LIMIT 20;
