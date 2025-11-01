-- Ping-Pong Trading Detector
-- Identifies account pairs that trade back and forth repeatedly
-- Indicators: Multiple trades, near-zero net flow, reciprocal relationship

-- Step 1: Get all taker→counterparty relationships with aggregated metrics
WITH account_pairs AS (
  SELECT 
    taker,
    arrayJoin(counterparties) as counterparty,
    COUNT(*) as trade_count,
    SUM(exec_xrp) as total_xrp,
    SUM(exec_iou) as total_iou,
    COUNT(DISTINCT ledger_index) as ledger_span,
    MIN(time) as first_trade,
    MAX(time) as last_trade
  FROM xrp_watchdog.executed_trades
  GROUP BY taker, counterparty
),

-- Step 2: Find reciprocal pairs (A→B AND B→A exist)
reciprocal_pairs AS (
  SELECT 
    a.taker as account_a,
    a.counterparty as account_b,
    a.trade_count as a_to_b_count,
    b.trade_count as b_to_a_count,
    a.total_xrp as a_to_b_xrp,
    b.total_xrp as b_to_a_xrp,
    a.total_iou as a_to_b_iou,
    b.total_iou as b_to_a_iou,
    a.ledger_span as a_ledger_span,
    b.ledger_span as b_ledger_span,
    a.first_trade as a_first_trade,
    b.first_trade as b_first_trade
  FROM account_pairs a
  INNER JOIN account_pairs b
    ON a.taker = b.counterparty 
    AND a.counterparty = b.taker
  WHERE a.taker < a.counterparty  -- Avoid duplicate pairs (only keep A<B, not B<A)
)

-- Step 3: Calculate suspicion metrics and filter
SELECT 
  account_a,
  account_b,
  a_to_b_count,
  b_to_a_count,
  (a_to_b_count + b_to_a_count) as total_trades,
  ROUND(a_to_b_xrp, 2) as a_to_b_xrp,
  ROUND(b_to_a_xrp, 2) as b_to_a_xrp,
  ROUND(a_to_b_xrp + b_to_a_xrp, 2) as net_flow_xrp,
  ROUND(abs(a_to_b_xrp + b_to_a_xrp), 2) as abs_net_flow_xrp,
  ROUND((abs(a_to_b_xrp + b_to_a_xrp) / (abs(a_to_b_xrp) + abs(b_to_a_xrp))) * 100, 2) as balance_ratio_percent,
  (a_ledger_span + b_ledger_span) as total_ledgers,
  dateDiff('hour', least(a_first_trade, b_first_trade), greatest(a_first_trade, b_first_trade)) as time_span_hours
FROM reciprocal_pairs
WHERE 
  (a_to_b_count + b_to_a_count) >= 3  -- At least 3 total trades
  AND abs(a_to_b_xrp + b_to_a_xrp) < 100  -- Net flow under 100 XRP (nearly balanced)
ORDER BY 
  total_trades DESC,
  abs_net_flow_xrp ASC
FORMAT Vertical;
