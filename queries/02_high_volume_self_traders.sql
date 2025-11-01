-- High-Volume Self-Traders Detector
-- Identifies accounts with concentrated counterparty relationships
-- Indicators: Many trades with single counterparty, high volume, repetitive behavior

WITH account_counterparty_stats AS (
  SELECT 
    taker,
    arrayJoin(counterparties) as counterparty,
    COUNT(*) as trade_count,
    SUM(abs(exec_xrp)) as total_volume_xrp,
    COUNT(DISTINCT ledger_index) as ledger_span,
    COUNT(DISTINCT exec_iou_code) as token_count,
    MIN(time) as first_trade,
    MAX(time) as last_trade,
    ROUND(AVG(abs(exec_xrp)), 2) as avg_trade_size,
    ROUND(stddevPop(abs(exec_xrp)), 2) as trade_size_stddev,
    groupArray(exec_iou_code) as tokens_traded
  FROM xrp_watchdog.executed_trades
  WHERE exec_xrp != 0
  GROUP BY taker, counterparty
)

SELECT 
  taker,
  counterparty,
  trade_count,
  ROUND(total_volume_xrp, 2) as total_volume_xrp,
  ledger_span,
  token_count,
  first_trade,
  last_trade,
  dateDiff('hour', first_trade, last_trade) as time_span_hours,
  avg_trade_size,
  trade_size_stddev,
  ROUND((trade_size_stddev / nullIf(avg_trade_size, 0)) * 100, 2) as size_variance_percent,
  arrayDistinct(tokens_traded) as tokens_list
FROM account_counterparty_stats
WHERE 
  trade_count >= 5  -- At least 5 trades
  AND total_volume_xrp >= 10  -- At least 10 XRP total
ORDER BY 
  trade_count DESC,
  total_volume_xrp DESC
LIMIT 30
FORMAT Vertical;
