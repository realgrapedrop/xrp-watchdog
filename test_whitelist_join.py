#!/usr/bin/env python3
import clickhouse_connect

client = clickhouse_connect.get_client(host='localhost', port=8123, database='xrp_watchdog')

# Test the join directly
result = client.query("""
SELECT
    t.exec_iou_code,
    t.exec_iou_issuer,
    tw.token_code,
    tw.token_issuer,
    IF(tw.token_code IS NOT NULL, 1, 0) as is_whitelisted,
    isNull(tw.token_code) as is_null_check,
    tw.token_code = '' as is_empty_check
FROM (
    SELECT DISTINCT exec_iou_code, exec_iou_issuer
    FROM executed_trades
    WHERE exec_iou_code != ''
    LIMIT 10
) t
LEFT JOIN token_whitelist tw
    ON t.exec_iou_code = tw.token_code
    AND t.exec_iou_issuer = tw.token_issuer
""")

print("Testing whitelist join:")
print("="*120)
for row in result.result_rows:
    token_code = row[0][:20] if row[0] else "None"
    issuer = row[1][:20] if row[1] else "None"
    wl_code = str(row[2])[:20] if row[2] else "NULL"
    is_wl = row[4]
    is_null = row[5]
    is_empty = row[6]
    print(f'Token: {token_code:<20} | WL_code: {wl_code:<20} | is_wl={is_wl} | isNull={is_null} | isEmpty={is_empty}')
