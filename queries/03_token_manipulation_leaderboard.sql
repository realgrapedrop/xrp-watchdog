-- Token Manipulation Leaderboard
-- Aggregates manipulation patterns by token
-- Scores tokens based on wash trading indicators

WITH token_stats AS (
  SELECT 
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    COUNT(DISTINCT tx_hash) as total_trades,
    COUNT(DISTINCT taker) as unique_takers,
    COUNT(DISTINCT arrayJoin(counterparties)) as unique_counterparties,
    COUNT(DISTINCT ledger_index) as ledger_span,
    SUM(abs(exec_xrp)) as total_xrp_volume,
    SUM(exec_iou) as total_token_volume,
    AVG(exec_price) as avg_price,
    stddevPop(exec_price) as price_stddev,
    MIN(time) as first_seen,
    MAX(time) as last_seen,
    dateDiff('day', MIN(time), MAX(time)) as days_active,
    ROUND(AVG(abs(exec_xrp)), 2) as avg_trade_xrp,
    ROUND(stddevPop(abs(exec_xrp)), 2) as trade_size_stddev
  FROM xrp_watchdog.executed_trades
  WHERE exec_iou_code != ''  -- Only IOU tokens (not pure XRP pairs)
    AND exec_xrp != 0
  GROUP BY exec_iou_code, exec_iou_issuer
)

SELECT 
  ts.token_code,
  ts.token_issuer,
  ts.total_trades,
  ts.unique_takers,
  ts.unique_counterparties,
  ROUND(ts.total_xrp_volume, 2) as total_xrp_volume,
  ROUND(ts.total_token_volume, 2) as total_token_volume,
  ts.ledger_span,
  ts.days_active,
  ts.first_seen,
  ts.last_seen,
  
  -- Manipulation indicators
  ROUND(ts.avg_price, 6) as avg_price,
  ROUND(ts.price_stddev / nullIf(ts.avg_price, 0) * 100, 2) as price_variance_percent,
  ts.avg_trade_xrp,
  ROUND(ts.trade_size_stddev / nullIf(ts.avg_trade_xrp, 0) * 100, 2) as size_variance_percent,
  ROUND(ts.total_trades / nullIf(ts.unique_takers, 0), 2) as trades_per_account,
  
  -- Risk score (0-100, higher = more suspicious)
  ROUND(
    LEAST(100,
      -- Few unique participants (max 40 points)
      (CASE WHEN ts.unique_takers <= 2 THEN 40
            WHEN ts.unique_takers <= 5 THEN 30
            WHEN ts.unique_takers <= 10 THEN 20
            ELSE 10 END)
      +
      -- Low price variance (max 25 points)
      (CASE WHEN (ts.price_stddev / nullIf(ts.avg_price, 0) * 100) < 1 THEN 25
            WHEN (ts.price_stddev / nullIf(ts.avg_price, 0) * 100) < 5 THEN 15
            WHEN (ts.price_stddev / nullIf(ts.avg_price, 0) * 100) < 10 THEN 10
            ELSE 5 END)
      +
      -- Low trade size variance (max 20 points)
      (CASE WHEN (ts.trade_size_stddev / nullIf(ts.avg_trade_xrp, 0) * 100) < 5 THEN 20
            WHEN (ts.trade_size_stddev / nullIf(ts.avg_trade_xrp, 0) * 100) < 10 THEN 15
            ELSE 5 END)
      +
      -- High trades per account (max 15 points)
      (CASE WHEN (ts.total_trades / nullIf(ts.unique_takers, 0)) >= 10 THEN 15
            WHEN (ts.total_trades / nullIf(ts.unique_takers, 0)) >= 5 THEN 10
            ELSE 5 END)
    ), 
  0) as risk_score

FROM token_stats ts
WHERE ts.total_trades >= 3  -- At least 3 trades
ORDER BY risk_score DESC, total_trades DESC
LIMIT 20
FORMAT Vertical;
