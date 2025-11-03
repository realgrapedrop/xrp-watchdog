#!/usr/bin/env python3
"""
XRP Watchdog - Book Changes Screener
Scans ledgers for high-volume trading activity using book_changes API
Flags suspicious ledgers for detailed analysis
"""

import subprocess
import json
import sys
from datetime import datetime, timezone
from typing import Dict, List, Optional
import clickhouse_connect

# Configuration
RIPPLED_CONTAINER = "rippledvalidator"
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

# Thresholds
VOLUME_THRESHOLD_XRP = 5_000_000  # 5M XRP in drops
PRICE_VARIANCE_THRESHOLD = 0.01    # 1% variance

class BookScreener:
    def __init__(self):
        """Initialize ClickHouse connection"""
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
        )
    
    def get_ledger_hash(self, ledger_spec: Optional[str] = None) -> Dict:
        """
        Get ledger hash (latest closed or specific)
        
        Args:
            ledger_spec: Optional ledger index or hash
        
        Returns:
            Dict with ledger_hash, ledger_index, close_time
        """
        if ledger_spec:
            # Specific ledger requested
            cmd = [
                "docker", "exec", RIPPLED_CONTAINER,
                "rippled", "-q", "json", "ledger",
                f'{{"ledger_index":{ledger_spec}}}'
            ]
        else:
            # Get latest closed ledger
            cmd = [
                "docker", "exec", RIPPLED_CONTAINER,
                "rippled", "-q", "ledger", "closed"
            ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        
        if ledger_spec:
            return {
                "ledger_hash": data["result"]["ledger_hash"],
                "ledger_index": data["result"]["ledger_index"],
                "close_time": data["result"]["ledger"]["close_time_human"]
            }
        else:
            return {
                "ledger_hash": data["result"]["ledger_hash"],
                "ledger_index": data["result"]["ledger_index"]
            }
    
    def get_book_changes(self, ledger_hash: str) -> Dict:
        """
        Fetch book_changes for a specific ledger
        
        Args:
            ledger_hash: Ledger hash to query
        
        Returns:
            Dict with ledger info and changes
        """
        # Get ledger info
        cmd_ledger = [
            "docker", "exec", RIPPLED_CONTAINER,
            "rippled", "-q", "ledger", ledger_hash
        ]
        ledger_result = subprocess.run(cmd_ledger, capture_output=True, text=True, check=True)
        ledger_data = json.loads(ledger_result.stdout)
        
        # Get book changes
        cmd_book = [
            "docker", "exec", RIPPLED_CONTAINER,
            "rippled", "-q", "book_changes", ledger_hash
        ]
        book_result = subprocess.run(cmd_book, capture_output=True, text=True, check=True)
        book_data = json.loads(book_result.stdout)
        
        return {
            "ledger_index": ledger_data["result"]["ledger_index"],
            "ledger_hash": ledger_hash,
            "close_time": ledger_data["result"]["ledger"]["close_time_human"],
            "changes": book_data["result"].get("changes", [])
        }
    
    def parse_currency_pair(self, change: Dict) -> Dict:
        """
        Parse currency_a and currency_b into structured format
        
        Args:
            change: Book change entry
        
        Returns:
            Dict with currency_code and issuer
        """
        currency_b = change["currency_b"]
        
        if "/" in currency_b:
            parts = currency_b.split("/")
            return {
                "currency_code": parts[1] if len(parts) > 1 else parts[0],
                "issuer": parts[0]
            }
        else:
            return {
                "currency_code": currency_b,
                "issuer": ""
            }
    
    def calculate_variance(self, change: Dict) -> float:
        """
        Calculate price variance: (high - low) / open
        
        Args:
            change: Book change entry
        
        Returns:
            Variance ratio (0.0 to 1.0+)
        """
        try:
            open_price = float(change["open"])
            high_price = float(change["high"])
            low_price = float(change["low"])
            
            if open_price == 0:
                return 0.0
            
            variance = (high_price - low_price) / open_price
            return variance
        except (ValueError, KeyError, ZeroDivisionError):
            return 0.0
    
    def is_suspicious(self, volume_xrp: float, variance: float) -> bool:
        """
        Determine if trading activity is suspicious
        
        Args:
            volume_xrp: XRP volume in drops
            variance: Price variance ratio
        
        Returns:
            True if suspicious
        """
        return (volume_xrp >= VOLUME_THRESHOLD_XRP and 
                variance < PRICE_VARIANCE_THRESHOLD)
    
    def insert_book_changes(self, ledger_data: Dict):
        """
        Insert book changes into ClickHouse
        
        Args:
            ledger_data: Parsed ledger data with changes
        """
        if not ledger_data["changes"]:
            print(f"  No book changes in ledger {ledger_data['ledger_index']}")
            return
        
        rows = []
        for change in ledger_data["changes"]:
            # Parse currency pair
            pair_info = self.parse_currency_pair(change)
            currency_pair = f"{change['currency_a']}/{pair_info['issuer']}/{pair_info['currency_code']}"
            
            # Calculate metrics
            volume_xrp = float(change["volume_a"])
            variance = self.calculate_variance(change)
            suspicious = 1 if self.is_suspicious(volume_xrp, variance) else 0
            
            # Convert close_time to DateTime
            # Format: "2025-Oct-19 08:59:20.000000000 UTC"
            close_time_str = ledger_data["close_time"]
            try:
                dt = datetime.strptime(close_time_str.split('.')[0], "%Y-%b-%d %H:%M:%S").replace(tzinfo=timezone.utc)
                time_value = dt
            except:
                time_value = datetime.now(timezone.utc)
            
            row = (
                time_value,                          # time
                ledger_data["ledger_index"],         # ledger_index
                ledger_data["ledger_hash"],          # ledger_hash
                currency_pair,                       # currency_pair
                pair_info["currency_code"],          # currency_code
                pair_info["issuer"],                 # issuer
                float(change["open"]),               # open
                float(change["high"]),               # high
                float(change["low"]),                # low
                float(change["close"]),              # close
                volume_xrp,                          # volume_xrp
                float(change["volume_b"]),           # volume_token
                variance,                            # price_variance
                suspicious                           # is_suspicious
            )
            rows.append(row)
        
        # Insert batch
        self.client.insert(
            "book_changes",
            rows,
            column_names=[
                "time", "ledger_index", "ledger_hash", "currency_pair",
                "currency_code", "issuer", "open", "high", "low", "close",
                "volume_xrp", "volume_token", "price_variance", "is_suspicious"
            ]
        )
        
        suspicious_count = sum(1 for r in rows if r[13] == 1)
        print(f"  Inserted {len(rows)} book changes ({suspicious_count} suspicious)")
    
    def scan_ledgers(self, count: int = 1, start_ledger: Optional[str] = None):
        """
        Scan N ledgers backwards from starting point
        
        Args:
            count: Number of ledgers to scan
            start_ledger: Starting ledger index/hash (None = latest)
        """
        print(f"Starting book screener: {count} ledgers")
        
        # Get starting ledger
        if start_ledger:
            current = self.get_ledger_hash(start_ledger)
        else:
            current = self.get_ledger_hash()
            # Get full info
            full_current = self.get_book_changes(current["ledger_hash"])
            current["close_time"] = full_current["close_time"]
        
        current_hash = current["ledger_hash"]
        
        for i in range(count):
            print(f"\nScanning ledger {i+1}/{count}: {current['ledger_index']}")
            
            try:
                # Get book changes
                ledger_data = self.get_book_changes(current_hash)
                
                # Insert to ClickHouse
                self.insert_book_changes(ledger_data)
                
                # Get parent hash for next iteration
                cmd_parent = [
                    "docker", "exec", RIPPLED_CONTAINER,
                    "rippled", "-q", "ledger", current_hash
                ]
                result = subprocess.run(cmd_parent, capture_output=True, text=True, check=True)
                data = json.loads(result.stdout)
                current_hash = data["result"]["ledger"]["parent_hash"]
                current["ledger_index"] = data["result"]["ledger_index"] - 1
                
            except Exception as e:
                print(f"  ERROR: {e}")
                break
        
        print(f"\nBook screening complete!")

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="XRP Watchdog Book Screener")
    parser.add_argument("count", type=int, help="Number of ledgers to scan")
    parser.add_argument("--start", help="Starting ledger index (default: latest)")
    
    args = parser.parse_args()
    
    screener = BookScreener()
    screener.scan_ledgers(count=args.count, start_ledger=args.start)

if __name__ == "__main__":
    main()
