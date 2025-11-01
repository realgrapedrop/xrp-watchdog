#!/usr/bin/env python3
"""
XRP Watchdog - Token Whitelist Manager
Add or remove tokens from the whitelist (stablecoins, verified tokens, etc.)
"""

import sys
import clickhouse_connect
from datetime import datetime

CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

class WhitelistManager:
    def __init__(self):
        """Initialize whitelist manager"""
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
        )

    def list_whitelist(self):
        """List all whitelisted tokens"""
        result = self.client.query("""
            SELECT
                token_code,
                token_issuer,
                token_name,
                category,
                reason,
                added_date,
                added_by
            FROM token_whitelist
            ORDER BY category, token_name
        """)

        if not result.result_rows:
            print("No tokens in whitelist.")
            return

        print("\n" + "="*100)
        print(f"{'Token Code':<40} {'Issuer':<35} {'Name':<15} {'Category':<15}")
        print("="*100)

        for row in result.result_rows:
            token_code = row[0][:38]
            issuer = row[1][:33]
            name = row[2]
            category = row[3]
            reason = row[4]
            added = row[5].strftime("%Y-%m-%d")

            print(f"{token_code:<40} {issuer:<35} {name:<15} {category:<15}")
            print(f"  Reason: {reason}")
            print(f"  Added: {added} by {row[6]}")
            print()

        print(f"Total whitelisted tokens: {len(result.result_rows)}\n")

    def add_token(self, token_code: str, token_issuer: str, token_name: str,
                  category: str = "verified", reason: str = "", added_by: str = "admin"):
        """Add a token to the whitelist"""

        # Validate category
        valid_categories = ['stablecoin', 'major_token', 'exchange_token', 'verified']
        if category not in valid_categories:
            print(f"ERROR: Invalid category '{category}'")
            print(f"Valid categories: {', '.join(valid_categories)}")
            return False

        # Check if already exists
        result = self.client.query(f"""
            SELECT COUNT(*) FROM token_whitelist
            WHERE token_code = '{token_code}' AND token_issuer = '{token_issuer}'
        """)

        if result.result_rows[0][0] > 0:
            print(f"WARNING: Token {token_name} ({token_code}) already in whitelist")
            return False

        # Insert
        category_map = {
            'stablecoin': 1,
            'major_token': 2,
            'exchange_token': 3,
            'verified': 4
        }

        self.client.insert(
            "token_whitelist",
            [(token_code, token_issuer, token_name, category_map[category], reason, datetime.now(), added_by)],
            column_names=["token_code", "token_issuer", "token_name", "category", "reason", "added_date", "added_by"]
        )

        print(f"✓ Added {token_name} ({token_code}) to whitelist as {category}")
        return True

    def remove_token(self, token_code: str, token_issuer: str):
        """Remove a token from the whitelist"""

        # Check if exists
        result = self.client.query(f"""
            SELECT token_name FROM token_whitelist
            WHERE token_code = '{token_code}' AND token_issuer = '{token_issuer}'
        """)

        if not result.result_rows:
            print(f"ERROR: Token {token_code} not found in whitelist")
            return False

        token_name = result.result_rows[0][0]

        # Delete
        self.client.command(f"""
            ALTER TABLE token_whitelist DELETE
            WHERE token_code = '{token_code}' AND token_issuer = '{token_issuer}'
        """)

        print(f"✓ Removed {token_name} ({token_code}) from whitelist")
        return True

    def find_token(self, search: str):
        """Find tokens in executed_trades by code or name"""
        result = self.client.query(f"""
            SELECT DISTINCT
                exec_iou_code,
                exec_iou_issuer,
                COUNT(*) as trade_count
            FROM executed_trades
            WHERE exec_iou_code LIKE '%{search}%'
            GROUP BY exec_iou_code, exec_iou_issuer
            ORDER BY trade_count DESC
            LIMIT 20
        """)

        if not result.result_rows:
            print(f"No tokens found matching '{search}'")
            return

        print(f"\nTokens matching '{search}':")
        print("="*80)
        print(f"{'Token Code':<45} {'Issuer':<35} {'Trades':<10}")
        print("="*80)

        for row in result.result_rows:
            code = row[0][:43]
            issuer = row[1][:33]
            trades = row[2]
            print(f"{code:<45} {issuer:<35} {trades:<10}")

        print()


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="XRP Watchdog Whitelist Manager")
    subparsers = parser.add_subparsers(dest="command", help="Command")

    # List command
    parser_list = subparsers.add_parser("list", help="List all whitelisted tokens")

    # Add command
    parser_add = subparsers.add_parser("add", help="Add token to whitelist")
    parser_add.add_argument("token_code", help="Token currency code (e.g., USD, RLUSD)")
    parser_add.add_argument("token_issuer", help="Token issuer address")
    parser_add.add_argument("token_name", help="Human-readable token name")
    parser_add.add_argument("--category", default="verified",
                           choices=["stablecoin", "major_token", "exchange_token", "verified"],
                           help="Token category (default: verified)")
    parser_add.add_argument("--reason", default="", help="Reason for whitelisting")
    parser_add.add_argument("--added-by", default="admin", help="Who added this token")

    # Remove command
    parser_remove = subparsers.add_parser("remove", help="Remove token from whitelist")
    parser_remove.add_argument("token_code", help="Token currency code")
    parser_remove.add_argument("token_issuer", help="Token issuer address")

    # Find command
    parser_find = subparsers.add_parser("find", help="Find tokens by code/name")
    parser_find.add_argument("search", help="Search term")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    manager = WhitelistManager()

    if args.command == "list":
        manager.list_whitelist()
    elif args.command == "add":
        manager.add_token(
            args.token_code,
            args.token_issuer,
            args.token_name,
            args.category,
            args.reason,
            args.added_by
        )
    elif args.command == "remove":
        manager.remove_token(args.token_code, args.token_issuer)
    elif args.command == "find":
        manager.find_token(args.search)


if __name__ == "__main__":
    main()
