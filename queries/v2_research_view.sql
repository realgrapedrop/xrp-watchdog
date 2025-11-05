-- XRP Watchdog v2.0 Research View
-- Shows ALL high-risk behavioral patterns (no volume filter)
-- Purpose: Catch early-stage manipulation, bot testing, emerging threats
-- Display: Collapsible panel labeled "Research / Low Impact Patterns"

-- Same as Actionable view but:
--   1. No 10 XRP minimum filter
--   2. Shows "Impact Tier" badge column
--   3. Includes micro-volume patterns for research

WITH stats_24h AS (
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
  HAVING total_trades >= 5
),

stats_7d AS (
  SELECT
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    SUM(ABS(exec_xrp)) as total_xrp_volume_7d
  FROM xrp_watchdog.executed_trades
  WHERE time >= now() - INTERVAL 7 DAY
  GROUP BY token_code, token_issuer
)

SELECT
  -- Token display
  CASE
    WHEN length(s24.token_code) = 40 THEN
      CASE
        WHEN isValidUTF8(unhex(s24.token_code)) THEN upper(replaceRegexpAll(unhex(s24.token_code), '\0', ''))
        ELSE concat('$', substring(s24.token_code, 1, 4), '...', substring(s24.token_code, 37, 4))
      END
    ELSE upper(s24.token_code)
  END as "Token",

  s24.token_issuer as "Issuer",

  -- Risk Score (same calculation as Actionable view)
  ROUND(LEAST(
    LEAST(60, log10(s24.total_xrp_volume_24h / 100000 + 1) * 15) +
    CASE WHEN s24.unique_takers <= 2 THEN 30 WHEN s24.unique_takers <= 5 THEN 22 WHEN s24.unique_takers <= 10 THEN 15 WHEN s24.unique_takers <= 20 THEN 8 ELSE 3 END +
    CASE WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 0.5 THEN 20 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 1 THEN 16 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 3 THEN 12 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 5 THEN 8 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 10 THEN 4 ELSE 1 END +
    CASE WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 100 THEN 15 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 50 THEN 12 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 20 THEN 8 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 10 THEN 5 ELSE 2 END +
    CASE WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 2 THEN 10 WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 5 THEN 7 WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 10 THEN 4 ELSE 1 END,
    100
  ), 1) as "Risk Score",

  -- Impact Factor (7d volume)
  ROUND(LEAST(1.0, log10(COALESCE(s7.total_xrp_volume_7d, s24.total_xrp_volume_24h) / 10 + 1)), 2) as "Impact Factor",

  -- Final Priority
  ROUND(
    LEAST(
      LEAST(60, log10(s24.total_xrp_volume_24h / 100000 + 1) * 15) +
      CASE WHEN s24.unique_takers <= 2 THEN 30 WHEN s24.unique_takers <= 5 THEN 22 WHEN s24.unique_takers <= 10 THEN 15 WHEN s24.unique_takers <= 20 THEN 8 ELSE 3 END +
      CASE WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 0.5 THEN 20 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 1 THEN 16 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 3 THEN 12 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 5 THEN 8 WHEN (s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100 < 10 THEN 4 ELSE 1 END +
      CASE WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 100 THEN 15 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 50 THEN 12 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 20 THEN 8 WHEN s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01) >= 10 THEN 5 ELSE 2 END +
      CASE WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 2 THEN 10 WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 5 THEN 7 WHEN (s24.trade_size_stddev / GREATEST(s24.avg_trade_size, 0.0001)) * 100 < 10 THEN 4 ELSE 1 END,
      100
    ) * LEAST(1.0, log10(COALESCE(s7.total_xrp_volume_7d, s24.total_xrp_volume_24h) / 10 + 1))
  , 1) as "Final Priority",

  -- Impact Tier badge (Research view exclusive)
  CASE
    WHEN s24.total_xrp_volume_24h < 1 THEN '⚪ Negligible'
    WHEN s24.total_xrp_volume_24h < 10 THEN '🟢 Low Impact'
    WHEN s24.total_xrp_volume_24h < 100 THEN '🟡 Moderate'
    WHEN s24.total_xrp_volume_24h < 1000 THEN '🟠 High'
    ELSE '🔴 Critical'
  END as "Impact Tier",

  -- Supporting metrics
  s24.total_trades as "Trades",
  ROUND(s24.total_xrp_volume_24h, 2) as "Volume (24h)",
  ROUND(COALESCE(s7.total_xrp_volume_7d, s24.total_xrp_volume_24h), 0) as "Volume (7d)",
  ROUND((s24.price_stddev / GREATEST(s24.avg_price, 0.0001)) * 100, 1) as "Price Var %",
  ROUND(s24.total_trades / GREATEST((toUnixTimestamp(s24.last_trade) - toUnixTimestamp(s24.first_trade)) / 3600.0, 0.01), 1) as "Trades/Hour",
  formatDateTime(s24.last_trade, '%Y-%m-%d %H:%M') as "Updated"

FROM stats_24h s24
LEFT JOIN stats_7d s7
  ON s24.token_code = s7.token_code
  AND s24.token_issuer = s7.token_issuer

-- Whitelist filtering
LEFT JOIN xrp_watchdog.token_stats tst
  ON s24.token_code = tst.token_code
  AND s24.token_issuer = tst.token_issuer
WHERE s24.token_issuer NOT IN (SELECT token_issuer FROM xrp_watchdog.token_whitelist)
AND (tst.classification IS NULL OR tst.classification NOT IN ('bridge', 'legitimate'))
AND NOT (
  upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%.AXL'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE 'USDC%AXL%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%BRIDGE%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE 'WRAPPED%'
  OR upper(CASE WHEN length(s24.token_code) = 40 THEN replaceRegexpAll(unhex(s24.token_code), '\0', '') ELSE s24.token_code END) LIKE '%ALLBRIDGE%'
)

-- NO volume minimum filter (shows all patterns)
-- Filter by risk score to keep relevant

ORDER BY "Risk Score" DESC, "Final Priority" DESC
LIMIT 20;
