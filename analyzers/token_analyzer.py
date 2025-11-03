#!/usr/bin/env python3
"""
XRP Watchdog - Token Risk Analyzer
Calculates manipulation risk scores for tokens using advanced detection algorithms
Populates the token_stats table with aggregated metrics and risk assessments
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

    # Legacy v1.0 algorithm - DEPRECATED November 2025
    # Removed in favor of v2.0 algorithm with logarithmic scaling and burst detection
    # def calculate_risk_score_v1(self, stats: dict, is_whitelisted: bool) -> float:
    #     ...

    def calculate_risk_score(self, stats: dict, is_whitelisted: bool) -> float:
        """
        Calculate manipulation risk score (0-100)

        Algorithm components:
        - Logarithmic volume scaling (max 50 points)
        - Token focus / account concentration (max 30 points)
        - Price stability / variance detection (max 20 points)
        - Burst detection / temporal clustering (max 15 points)
        - Trade size uniformity / bot detection (max 10 points)
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

    def detect_bridge_pattern(self, stats: dict) -> tuple[str, float]:
        """
        Detect if token exhibits bridge/legitimate protocol patterns

        Returns: (classification, confidence_score)

        Classifications:
        - 'bridge': Cross-chain bridge protocol (Axelar, Wanchain, etc.)
        - 'manipulation': Likely wash trading / market manipulation
        - 'legitimate': Normal trading activity
        - 'unknown': Insufficient data or unclear pattern

        Confidence: 0.0-1.0 (how confident we are in the classification)
        """

        # Bridge detection criteria
        bridge_signals = 0
        bridge_confidence = 0.0

        # Signal 1: Very few unique traders (1-3) + high volume = automated bridge
        if stats['unique_takers'] <= 3 and stats['total_xrp_volume'] > 10000:
            bridge_signals += 3
            bridge_confidence += 0.4

        # Signal 2: Extremely low price variance (<1%) = algorithmic pricing
        if stats['price_variance_percent'] < 1.0 and stats['total_trades'] > 10:
            bridge_signals += 2
            bridge_confidence += 0.25

        # Signal 3: Very uniform trade sizes (<5% variance) = automated
        if stats['size_variance_percent'] < 5.0 and stats['total_trades'] > 10:
            bridge_signals += 2
            bridge_confidence += 0.25

        # Signal 4: High volume but few traders = centralized operation
        if stats['unique_takers'] <= 5 and stats['total_xrp_volume'] > 50000:
            bridge_signals += 2
            bridge_confidence += 0.1

        # Signal 5: Token name patterns (check for common bridge prefixes)
        token_name = stats['token_code'].upper()
        bridge_keywords = ['AXL', 'BRIDGE', 'WRAPPED', 'W', 'X', 'ANY', 'MULTI']
        if any(keyword in token_name for keyword in bridge_keywords):
            bridge_signals += 1
            bridge_confidence += 0.15

        # Decision tree
        if bridge_signals >= 5:
            # Strong bridge pattern
            return ('bridge', min(1.0, bridge_confidence))
        elif bridge_signals >= 3 and stats['total_xrp_volume'] > 20000:
            # Likely bridge (high volume + some signals)
            return ('bridge', min(0.8, bridge_confidence))
        elif stats['unique_takers'] > 20 and stats['total_trades'] > 100:
            # Legitimate organic activity
            return ('legitimate', 0.6)
        elif stats['unique_takers'] <= 5 and stats['total_xrp_volume'] > 1000:
            # Suspicious but not clearly a bridge - likely manipulation
            return ('manipulation', 0.7)
        else:
            # Unclear pattern
            return ('unknown', 0.3)

    def refresh_token_stats(self):
        """Refresh token_stats table with latest data"""
        self.start_time = time.time()

        print("=== Token Risk Analyzer ===")
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
            stddevPop(abs(exec_xrp)) as trade_size_stddev
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

          -- Calculate time-based metrics (optimized - no array loading)
          -- Average time gap = total active seconds / (number of trades - 1)
          CASE
            WHEN tb.total_trades > 1 AND tb.seconds_active > 0
            THEN tb.seconds_active / (tb.total_trades - 1)
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
        print("Step 2: Calculating risk scores...")
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

            # Detect bridge patterns BEFORE calculating risk score
            classification, confidence = self.detect_bridge_pattern(stats)

            # Calculate risk scores
            risk_score = self.calculate_risk_score(stats, is_whitelisted)
            burst = self.calculate_burst_score(stats['trade_density'], is_whitelisted)

            # Reduce risk score for detected bridges (they're not manipulation)
            if classification == 'bridge' and confidence >= 0.6:
                risk_score = risk_score * 0.3  # Reduce to 30% of original
                burst = burst * 0.3

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
                risk_score,
                burst,
                classification,
                round(confidence, 3),
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
                "trades_per_account", "xrp_volume_per_account", "risk_score",
                "burst_score", "classification", "classification_confidence", "last_updated"
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
        print("="*80)
        print("Top 10 Tokens by Risk Score:")
        print("="*80)

        result = self.client.query("""
            SELECT
                CASE
                  WHEN length(token_code) = 40 THEN
                    upper(replaceRegexpAll(unhex(token_code), '\0', ''))
                  ELSE upper(token_code)
                END as token_code,
                SUBSTRING(token_issuer, 1, 10) || '...' as issuer_short,
                total_trades,
                unique_takers,
                ROUND(total_xrp_volume, 0) as volume_xrp,
                is_whitelisted,
                ROUND(risk_score, 1) as risk,
                ROUND(trade_density, 1) as density,
                ROUND(burst_score, 0) as burst
            FROM token_stats
            ORDER BY risk_score DESC
            LIMIT 10
        """)

        print(f"{'Token':<12} {'Issuer':<14} {'Trades':<7} {'Takers':<7} {'Volume':<12} {'WL':<3} {'Risk':<6} {'TPH':<6} {'Burst':<5}")
        print("-"*80)

        for row in result.result_rows:
            token_code = row[0][:12]
            issuer = row[1]
            trades = row[2]
            takers = row[3]
            volume = f"{row[4]:,.0f}"
            whitelisted = "✓" if row[5] else ""
            risk = row[6]
            density = row[7]
            burst = row[8]

            print(f"{token_code:<12} {issuer:<14} {trades:<7} {takers:<7} {volume:<12} {whitelisted:<3} {risk:<6} {density:<6} {burst:<5}")

        print()

        # Summary statistics
        result = self.client.query("""
            SELECT
                COUNT(*) as total,
                SUM(IF(risk_score >= 70, 1, 0)) as high_risk,
                SUM(IF(is_whitelisted = 1, 1, 0)) as whitelisted,
                AVG(risk_score) as avg_risk
            FROM token_stats
        """)

        if result.result_rows:
            total, high_risk, whitelisted, avg_risk = result.result_rows[0]
            print(f"Total tokens analyzed: {total}")
            print(f"Whitelisted (risk=0): {whitelisted}")
            print(f"High risk (≥70): {high_risk}")
            print(f"Average risk score: {avg_risk:.1f}")


def main():
    """Main entry point"""
    analyzer = TokenAnalyzer()
    analyzer.refresh_token_stats()


if __name__ == "__main__":
    main()
