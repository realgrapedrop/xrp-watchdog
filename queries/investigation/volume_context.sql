-- Volume context analysis
-- Compare ping-pong volumes to overall market activity

-- Part 1: Distribution of trade sizes
SELECT 
  'Trade Size Distribution' as metric,
  COUNT(*) as total_trades,
  ROUND(MIN(abs(exec_xrp)), 2) as min_xrp,
  ROUND(quantile(0.25)(abs(exec_xrp)), 2) as p25_xrp,
  ROUND(quantile(0.50)(abs(exec_xrp)), 2) as median_xrp,
  ROUND(quantile(0.75)(abs(exec_xrp)), 2) as p75_xrp,
  ROUND(quantile(0.95)(abs(exec_xrp)), 2) as p95_xrp,
  ROUND(MAX(abs(exec_xrp)), 2) as max_xrp,
  ROUND(AVG(abs(exec_xrp)), 2) as avg_xrp
FROM xrp_watchdog.executed_trades
WHERE exec_xrp != 0

UNION ALL

-- Part 2: Volume from book_changes (aggregate market activity)
SELECT 
  'Book Changes Volume' as metric,
  COUNT(*) as total_changes,
  ROUND(MIN(volume_xrp / 1000000), 2) as min_xrp,
  ROUND(quantile(0.25)(volume_xrp / 1000000), 2) as p25_xrp,
  ROUND(quantile(0.50)(volume_xrp / 1000000), 2) as median_xrp,
  ROUND(quantile(0.75)(volume_xrp / 1000000), 2) as p75_xrp,
  ROUND(quantile(0.95)(volume_xrp / 1000000), 2) as p95_xrp,
  ROUND(MAX(volume_xrp / 1000000), 2) as max_xrp,
  ROUND(AVG(volume_xrp / 1000000), 2) as avg_xrp
FROM xrp_watchdog.book_changes

UNION ALL

-- Part 3: Our ping-pong pair specifically
SELECT 
  'Ping-Pong Pair (Barron)' as metric,
  COUNT(*) as total_trades,
  ROUND(MIN(abs(exec_xrp)), 2) as min_xrp,
  0 as p25_xrp,
  ROUND(AVG(abs(exec_xrp)), 2) as median_xrp,
  0 as p75_xrp,
  0 as p95_xrp,
  ROUND(MAX(abs(exec_xrp)), 2) as max_xrp,
  ROUND(AVG(abs(exec_xrp)), 2) as avg_xrp
FROM xrp_watchdog.executed_trades
WHERE 
  (taker = 'rUHG1zwFNuRnN52hEo1Nmjd9xeWfMK5tA' 
   AND has(counterparties, 'rswb3M3QRukbMWNhKmSsQFSU1DjQaUMF6d'))
  OR
  (taker = 'rswb3M3QRukbMWNhKmSsQFSU1DjQaUMF6d' 
   AND has(counterparties, 'rUHG1zwFNuRnN52hEo1Nmjd9xeWfMK5tA'))

FORMAT Vertical;
