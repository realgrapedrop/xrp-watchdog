-- Market Impact Leaderboard (Whitelist-Filtered)
-- Focuses on tokens with meaningful volume that can affect prices
-- Excludes whitelisted legitimate tokens (stablecoins, verified tokens)

WITH token_stats AS (
  SELECT 
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    COUNT(DISTINCT tx_hash) as total_trades,
    COUNT(DISTINCT taker) as unique_takers,
    SUM(abs(exec_xrp)) as total_xrp_volume,
    AVG(exec_price) as avg_price,
    stddevPop(exec_price) as price_stddev,
    ROUND(AVG(abs(exec_xrp)), 2) as avg_trade_xrp
  FROM xrp_watchdog.executed_trades
  WHERE exec_iou_code != ''
    AND exec_xrp != 0
    -- Exclude whitelisted tokens
    AND (exec_iou_code, exec_iou_issuer) NOT IN (
      SELECT token_code, token_issuer FROM xrp_watchdog.token_whitelist
    )
  GROUP BY exec_iou_code, exec_iou_issuer
)

SELECT 
  token_code,
  token_issuer,
  total_trades,
  unique_takers,
  ROUND(total_xrp_volume, 2) as total_xrp_volume,
  avg_trade_xrp,
  ROUND((price_stddev / nullIf(avg_price, 0)) * 100, 2) as price_variance_percent,
  
  -- Market Impact Score (0-100)
  ROUND(
    LEAST(100,
      -- Volume factor (0-50 points): More volume = higher impact
      LEAST(50, total_xrp_volume / 20)
      +
      -- Concentration factor (0-30 points): Fewer participants = higher risk
      (CASE WHEN unique_takers = 1 THEN 30
            WHEN unique_takers = 2 THEN 25
            WHEN unique_takers <= 5 THEN 15
            ELSE 5 END)
      +
      -- Pattern severity (0-20 points): Lower variance = more coordinated
      (CASE WHEN (price_stddev / nullIf(avg_price, 0) * 100) < 0.1 THEN 20
            WHEN (price_stddev / nullIf(avg_price, 0) * 100) < 1 THEN 15
            WHEN (price_stddev / nullIf(avg_price, 0) * 100) < 5 THEN 10
            ELSE 5 END)
    ), 
  0) as market_impact_score,
  
  -- Impact tier
  CASE 
    WHEN total_xrp_volume >= 1000 AND unique_takers <= 3 THEN 'CRITICAL'
    WHEN total_xrp_volume >= 500 AND unique_takers <= 5 THEN 'HIGH'
    WHEN total_xrp_volume >= 200 THEN 'MEDIUM'
    WHEN total_xrp_volume >= 50 THEN 'LOW'
    ELSE 'MINIMAL'
  END as impact_tier

FROM token_stats
WHERE total_trades >= 3
  AND total_xrp_volume >= 50  -- Only show tokens with meaningful volume
ORDER BY market_impact_score DESC, total_xrp_volume DESC
LIMIT 20
FORMAT Vertical;
