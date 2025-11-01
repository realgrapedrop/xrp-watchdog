-- Deep dive into specific account pair
-- Shows chronological trade sequence with detailed metrics

SELECT 
  time,
  ledger_index,
  tx_hash,
  taker,
  counterparties,
  ROUND(exec_xrp, 4) as exec_xrp,
  exec_iou_code,
  ROUND(exec_iou, 4) as exec_iou,
  ROUND(exec_price, 6) as exec_price,
  posted_gets,
  posted_pays
FROM xrp_watchdog.executed_trades
WHERE 
  (taker = 'rUHG1zwFNuRnN52hEo1Nmjd9xeWfMK5tA' 
   AND has(counterparties, 'rswb3M3QRukbMWNhKmSsQFSU1DjQaUMF6d'))
  OR
  (taker = 'rswb3M3QRukbMWNhKmSsQFSU1DjQaUMF6d' 
   AND has(counterparties, 'rUHG1zwFNuRnN52hEo1Nmjd9xeWfMK5tA'))
ORDER BY time ASC
FORMAT Vertical;
