#!/usr/bin/env python3
"""
XRP Watchdog - Token Risk Analyzer
Calculates both v1.0 and v2.0 risk scores for tokens
Populates the token_stats table with aggregated metrics
"""

import sys
import math
import time
from datetime import datetime
from typing import Optional
import clickhouse_connect

# Configuration
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

class TokenAnalyzer:
    def __init__(self):
        """Initialize analyzer"""
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
        )
        self.start_time = None

    def calculate_risk_score_v1(self, stats: dict, is_whitelisted: bool) -> float:
        """
        Calculate v1.0 risk score (0-100)
        Original algorithm: Few participants + Low price variance + Low trade size variance
        """
        if is_whitelisted:
            return 0.0

        score = 0.0

        # Few unique participants (max 40 points)
        if stats['unique_takers'] <= 2:
            score += 40
        elif stats['unique_takers'] <= 5:
            score += 30
        elif stats['unique_takers'] <= 10:
            score += 20
        else:
            score += 10

        # Low price variance (max 25 points)
        price_var = stats['price_variance_percent']
        if price_var < 1:
            score += 25
        elif price_var < 5:
            score += 15
        elif price_var < 10:
            score += 10
        else:
            score += 5

        # Low trade size variance (max 20 points)
        size_var = stats['size_variance_percent']
        if size_var < 5:
            score += 20
        elif size_var < 10:
            score += 15
        else:
            score += 5

        # High trades per account (max 15 points)
        trades_per_acc = stats['trades_per_account']
        if trades_per_acc >= 10:
            score += 15
        elif trades_per_acc >= 5:
            score += 10
        else:
            score += 5

        return min(100.0, score)

    def calculate_risk_score_v2(self, stats: dict, is_whitelisted: bool) -> float:
        """
        Calculate v2.0 risk score (0-100)
        Enhanced algorithm with:
        - Logarithmic volume scaling
        - Burst detection (temporal clustering)
        - Enhanced price stability
        - Trade size uniformity detection
        """
        if is_whitelisted:
            return 0.0

        score = 0.0

        # Volume component (max 50 points) - LOGARITHMIC scaling
        # Prevents extreme outliers from dominating the score
        volume_xrp = stats['total_xrp_volume'] / 1000000.0  # Convert to millions
        volume_score = min(50, math.log10(volume_xrp + 1) * 12.5)
        score += volume_score

        # Token focus component (max 30 points) - Account concentration
        unique_takers = stats['unique_takers']
        if unique_takers <= 2:
            score += 30
        elif unique_takers <= 5:
            score += 22
        elif unique_takers <= 10:
            score += 15
        elif unique_takers <= 20:
            score += 8
        else:
            score += 3

        # Price stability component (max 20 points) - Enhanced variance detection
        price_var = stats['price_variance_percent']
        if price_var < 0.5:
            score += 20
        elif price_var < 1:
            score += 16
        elif price_var < 3:
            score += 12
        elif price_var < 5:
            score += 8
        elif price_var < 10:
            score += 4
        else:
            score += 1

        # NEW: Burst detection component (max 15 points) - Temporal clustering
        trade_density = stats['trade_density']  # trades per hour
        if trade_density >= 100:
            score += 15
        elif trade_density >= 50:
            score += 12
        elif trade_density >= 20:
            score += 8
        elif trade_density >= 10:
            score += 5
        else:
            score += 2

        # NEW: Trade size uniformity (max 10 points) - Robotic pattern detection
        size_var = stats['size_variance_percent']
        if size_var < 2:
            score += 10
        elif size_var < 5:
            score += 7
        elif size_var < 10:
            score += 4
        else:
            score += 1

        return min(100.0, round(score, 2))

    def calculate_burst_score(self, trade_density: float, is_whitelisted: bool) -> float:
        """Calculate burst score (0-100) based on trade density"""
        if is_whitelisted:
            return 0.0

        if trade_density >= 100:
            return 95.0
        elif trade_density >= 50:
            return 75.0
        elif trade_density >= 20:
            return 50.0
        elif trade_density >= 10:
            return 25.0
        else:
            return 5.0

    def refresh_token_stats(self):
        """Refresh token_stats table with latest data"""
        self.start_time = time.time()

        print("=== Token Risk Analyzer v2.0 ===")
        print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

        # Step 1: Query base token statistics
        print("Step 1: Querying token statistics from executed_trades...")
        query = """
        WITH
        -- Base token statistics
        token_base AS (
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
            dateDiff('second', MIN(time), MAX(time)) as seconds_active,
            dateDiff('day', MIN(time), MAX(time)) as days_active,
            AVG(abs(exec_xrp)) as avg_trade_xrp,
            stddevPop(abs(exec_xrp)) as trade_size_stddev,
            groupArray(time) as trade_times
          FROM executed_trades
          WHERE exec_iou_code != ''
            AND exec_xrp != 0
          GROUP BY exec_iou_code, exec_iou_issuer
        )

        SELECT
          tb.token_code,
          tb.token_issuer,
          tb.total_trades,
          tb.unique_takers,
          tb.unique_counterparties,
          tb.total_xrp_volume,
          tb.total_token_volume,
          tb.ledger_span,
          tb.days_active,
          tb.first_seen,
          tb.last_seen,
          tb.avg_price,
          tb.price_stddev,
          tb.avg_trade_xrp,
          tb.trade_size_stddev,
          tb.seconds_active,

          -- Check whitelist status (must check for empty string, not just NULL)
          IF(tw.token_code != '' AND tw.token_code IS NOT NULL, 1, 0) as is_whitelisted,
          toString(tw.category) as whitelist_category,

          -- Calculate metrics
          ROUND(tb.price_stddev / nullIf(tb.avg_price, 0) * 100, 2) as price_variance_percent,
          ROUND(tb.trade_size_stddev / nullIf(tb.avg_trade_xrp, 0) * 100, 2) as size_variance_percent,
          ROUND(tb.total_trades / nullIf(tb.unique_takers, 0), 2) as trades_per_account,
          ROUND(tb.total_xrp_volume / nullIf(tb.unique_takers, 0), 2) as xrp_volume_per_account,

          -- Calculate time-based metrics
          CASE
            WHEN length(tb.trade_times) > 1
            THEN arrayReduce('avg',
              arrayMap(i -> dateDiff('second',
                arrayElement(tb.trade_times, i),
                arrayElement(tb.trade_times, if(i + 1 <= length(tb.trade_times), i + 1, i))
              ),
              range(1, length(tb.trade_times)))
            )
            ELSE 0
          END as avg_time_gap_seconds,

          -- Trade density (trades per hour)
          CASE
            WHEN tb.seconds_active > 0
            THEN tb.total_trades / (tb.seconds_active / 3600.0)
            ELSE 0
          END as trade_density

        FROM token_base tb
        LEFT JOIN token_whitelist tw
          ON tb.token_code = tw.token_code
          AND tb.token_issuer = tw.token_issuer
        WHERE tb.total_trades >= 3
        ORDER BY tb.total_xrp_volume DESC
        """

        result = self.client.query(query)
        tokens = result.result_rows
        print(f"  Found {len(tokens)} tokens with >= 3 trades\n")

        if not tokens:
            print("No tokens to analyze. Exiting.")
            return

        # Step 2: Calculate risk scores and prepare data
        print("Step 2: Calculating risk scores (v1.0 and v2.0)...")
        token_stats_data = []

        for row in tokens:
            # Parse row data
            stats = {
                'token_code': row[0],
                'token_issuer': row[1],
                'total_trades': row[2],
                'unique_takers': row[3],
                'unique_counterparties': row[4],
                'total_xrp_volume': row[5],
                'total_token_volume': row[6],
                'ledger_span': row[7],
                'days_active': row[8],
                'first_seen': row[9],
                'last_seen': row[10],
                'avg_price': row[11],
                'price_stddev': row[12],
                'avg_trade_xrp': row[13],
                'trade_size_stddev': row[14],
                'seconds_active': row[15],
                'is_whitelisted': row[16],
                'whitelist_category': row[17],
                'price_variance_percent': row[18] if row[18] is not None else 0,
                'size_variance_percent': row[19] if row[19] is not None else 0,
                'trades_per_account': row[20] if row[20] is not None else 0,
                'xrp_volume_per_account': row[21] if row[21] is not None else 0,
                'avg_time_gap_seconds': row[22] if row[22] is not None else 0,
                'trade_density': row[23] if row[23] is not None else 0
            }

            is_whitelisted = bool(stats['is_whitelisted'])

            # Handle empty whitelist category
            whitelist_cat = stats['whitelist_category'] if stats['whitelist_category'] else 'none'

            # Calculate risk scores
            risk_v1 = self.calculate_risk_score_v1(stats, is_whitelisted)
            risk_v2 = self.calculate_risk_score_v2(stats, is_whitelisted)
            burst = self.calculate_burst_score(stats['trade_density'], is_whitelisted)

            # Prepare row for insertion
            token_stats_data.append((
                stats['token_code'],
                stats['token_issuer'],
                stats['total_trades'],
                stats['unique_takers'],
                stats['unique_counterparties'],
                stats['total_xrp_volume'],
                stats['total_token_volume'],
                stats['ledger_span'],
                stats['days_active'],
                stats['first_seen'],
                stats['last_seen'],
                stats['avg_price'],
                stats['price_stddev'],
                stats['avg_trade_xrp'],
                stats['trade_size_stddev'],
                stats['is_whitelisted'],
                whitelist_cat,
                stats['avg_time_gap_seconds'],
                stats['trade_density'],
                stats['price_variance_percent'],
                stats['size_variance_percent'],
                stats['trades_per_account'],
                stats['xrp_volume_per_account'],
                risk_v1,
                risk_v2,
                burst,
                datetime.now()
            ))

        print(f"  Calculated scores for {len(token_stats_data)} tokens\n")

        # Step 3: Truncate and insert
        print("Step 3: Updating token_stats table...")
        self.client.command("TRUNCATE TABLE token_stats")
        self.client.insert(
            "token_stats",
            token_stats_data,
            column_names=[
                "token_code", "token_issuer", "total_trades", "unique_takers",
                "unique_counterparties", "total_xrp_volume", "total_token_volume",
                "ledger_span", "days_active", "first_seen", "last_seen",
                "avg_price", "price_stddev", "avg_trade_xrp", "trade_size_stddev",
                "is_whitelisted", "whitelist_category", "avg_time_gap_seconds",
                "trade_density", "price_variance_percent", "size_variance_percent",
                "trades_per_account", "xrp_volume_per_account", "risk_score_v1",
                "risk_score_v2", "burst_score", "last_updated"
            ]
        )
        print(f"  ✓ Inserted {len(token_stats_data)} token statistics\n")

        # Step 4: Print summary
        self.print_summary()

        duration = time.time() - self.start_time
        print(f"\n=== Analysis Complete ===")
        print(f"Duration: {duration:.2f}s")
        print(f"End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    def print_summary(self):
        """Print summary of risk scores"""
        print("="*70)
        print("Top 10 Tokens by Risk Score v2.0:")
        print("="*70)

        result = self.client.query("""
            SELECT
                token_code,
                SUBSTRING(token_issuer, 1, 10) || '...' as issuer_short,
                total_trades,
                unique_takers,
                ROUND(total_xrp_volume, 0) as volume_xrp,
                is_whitelisted,
                ROUND(risk_score_v1, 1) as v1,
                ROUND(risk_score_v2, 1) as v2,
                ROUND(risk_score_v2 - risk_score_v1, 1) as diff,
                ROUND(trade_density, 1) as density,
                ROUND(burst_score, 0) as burst
            FROM token_stats
            ORDER BY risk_score_v2 DESC
            LIMIT 10
        """)

        print(f"{'Token':<12} {'Issuer':<14} {'Trades':<7} {'Takers':<7} {'Volume':<12} {'WL':<3} {'v1.0':<5} {'v2.0':<5} {'Δ':<6} {'TPH':<6} {'Burst':<5}")
        print("-"*70)

        for row in result.result_rows:
            token_code = row[0][:12]
            issuer = row[1]
            trades = row[2]
            takers = row[3]
            volume = f"{row[4]:,.0f}"
            whitelisted = "✓" if row[5] else ""
            v1 = row[6]
            v2 = row[7]
            diff = row[8]
            density = row[9]
            burst = row[10]

            print(f"{token_code:<12} {issuer:<14} {trades:<7} {takers:<7} {volume:<12} {whitelisted:<3} {v1:<5} {v2:<5} {diff:>+5} {density:<6} {burst:<5}")

        print()

        # Compare v1 vs v2 distribution
        result = self.client.query("""
            SELECT
                COUNT(*) as total,
                SUM(IF(risk_score_v1 >= 70, 1, 0)) as high_risk_v1,
                SUM(IF(risk_score_v2 >= 70, 1, 0)) as high_risk_v2,
                SUM(IF(is_whitelisted = 1, 1, 0)) as whitelisted,
                AVG(risk_score_v1) as avg_v1,
                AVG(risk_score_v2) as avg_v2
            FROM token_stats
        """)

        if result.result_rows:
            total, high_v1, high_v2, whitelisted, avg_v1, avg_v2 = result.result_rows[0]
            print(f"Total tokens analyzed: {total}")
            print(f"Whitelisted (risk=0): {whitelisted}")
            print(f"High risk (≥70) - v1.0: {high_v1}  |  v2.0: {high_v2}")
            print(f"Average risk score - v1.0: {avg_v1:.1f}  |  v2.0: {avg_v2:.1f}")


def main():
    """Main entry point"""
    analyzer = TokenAnalyzer()
    analyzer.refresh_token_stats()


if __name__ == "__main__":
    main()
