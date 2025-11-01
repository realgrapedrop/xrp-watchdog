#!/usr/bin/env python3
"""
XRP Watchdog - Storage Monitoring Script
Checks database size, growth rate, and provides storage projections
"""

import clickhouse_connect
from datetime import datetime

CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

def main():
    client = clickhouse_connect.get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        database=CLICKHOUSE_DB
    )

    print("=" * 80)
    print("XRP Watchdog - Storage Monitoring Report")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)

    # Get current database size
    result = client.query("""
        SELECT
            table,
            formatReadableSize(sum(bytes)) as size,
            formatReadableSize(sum(bytes_on_disk)) as size_on_disk,
            sum(rows) as rows,
            sum(bytes) as bytes_raw
        FROM system.parts
        WHERE database = 'xrp_watchdog'
          AND active = 1
        GROUP BY table
        ORDER BY sum(bytes) DESC
    """)

    print("\n### Current Database Size ###\n")
    print(f"{'Table':<20} {'Size (Memory)':<15} {'Size (Disk)':<15} {'Rows':>12}")
    print("-" * 70)

    total_bytes = 0
    total_rows = 0
    for row in result.result_rows:
        table, size, size_disk, rows, bytes_raw = row
        print(f"{table:<20} {size:<15} {size_disk:<15} {rows:>12,}")
        total_bytes += bytes_raw
        total_rows += rows

    print("-" * 70)
    print(f"{'TOTAL':<20} {format_bytes(total_bytes):<15} {'':<15} {total_rows:>12,}")

    # Get data time range
    result = client.query("""
        SELECT
            MIN(time) as oldest,
            MAX(time) as newest,
            COUNT(*) as total_trades,
            dateDiff('day', MIN(time), MAX(time)) as days_collected
        FROM executed_trades
    """)

    if result.result_rows:
        oldest, newest, total_trades, days = result.result_rows[0]
        days = max(days, 1)  # Avoid division by zero

        print(f"\n### Data Collection Period ###\n")
        print(f"Oldest trade:     {oldest}")
        print(f"Newest trade:     {newest}")
        print(f"Days collected:   {days}")
        print(f"Total trades:     {total_trades:,}")
        print(f"Avg trades/day:   {total_trades/days:,.0f}")

        # Calculate growth rate
        mb_per_day = (total_bytes / (1024 * 1024)) / days

        print(f"\n### Growth Rate ###\n")
        print(f"Current size:     {format_bytes(total_bytes)}")
        print(f"Growth rate:      {mb_per_day:.2f} MiB/day")

        # Projections
        print(f"\n### Storage Projections ###\n")
        periods = [
            ("30 days", 30),
            ("90 days (TTL)", 90),
            ("6 months", 180),
            ("1 year", 365),
        ]

        print(f"{'Period':<20} {'Projected Size':>20} {'Projected Rows':>20}")
        print("-" * 70)

        for period_name, days_proj in periods:
            projected_bytes = (total_bytes / days) * days_proj
            projected_rows = (total_rows / days) * days_proj
            print(f"{period_name:<20} {format_bytes(projected_bytes):>20} {projected_rows:>20,.0f}")

    # Check TTL policies
    print(f"\n### Data Retention Policies ###\n")

    for table in ['executed_trades', 'book_changes', 'token_stats']:
        result = client.query(f"SHOW CREATE TABLE {table}")
        create_statement = result.result_rows[0][0]

        if 'TTL' in create_statement:
            for line in create_statement.split('\n'):
                if 'TTL' in line:
                    ttl_info = line.strip().replace('TTL', '').strip()
                    print(f"{table:<20} TTL: {ttl_info}")
                    break
        else:
            print(f"{table:<20} No TTL (indefinite retention)")

    print(f"\n### Recommendations ###\n")

    # Calculate when we'll reach steady state (90 days)
    if days < 90:
        days_to_steady = 90 - days
        steady_state_size = (total_bytes / days) * 90
        print(f"• System will reach steady state in {days_to_steady} days")
        print(f"• Steady state size (90 days): {format_bytes(steady_state_size)}")
    else:
        print(f"• System at steady state (90-day TTL)")
        print(f"• Current size: {format_bytes(total_bytes)}")

    print(f"• Storage is very manageable - no action needed")
    print(f"• Consider running OPTIMIZE TABLE monthly for best performance")

    print("\n" + "=" * 80)

def format_bytes(bytes_val):
    """Format bytes to human readable string"""
    if bytes_val < 1024:
        return f"{bytes_val} B"
    elif bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.2f} KiB"
    elif bytes_val < 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.2f} MiB"
    else:
        return f"{bytes_val / (1024 * 1024 * 1024):.2f} GiB"

if __name__ == "__main__":
    main()
