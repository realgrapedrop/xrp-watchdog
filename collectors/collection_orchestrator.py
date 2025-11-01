#!/usr/bin/env python3
"""
XRP Watchdog - Collection Orchestrator
Coordinates book screening and trade collection
Manages collection state and error handling
"""

import sys
import time
from datetime import datetime, timedelta
from typing import Optional
import clickhouse_connect

from book_screener import BookScreener
from trade_collector import TradeCollector

# Configuration
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

class CollectionOrchestrator:
    def __init__(self):
        """Initialize orchestrator"""
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
        )
        self.book_screener = BookScreener()
        self.trade_collector = TradeCollector()
        self.start_time = None
    
    def get_last_state(self, collector_name: str) -> Optional[dict]:
        """Get last collection state"""
        result = self.client.query(
            f"SELECT * FROM collection_state WHERE collector_name = '{collector_name}' ORDER BY last_update DESC LIMIT 1"
        )
        
        if result.result_rows:
            row = result.result_rows[0]
            return {
                "collector_name": row[0],
                "last_ledger_hash": row[1],
                "last_ledger_index": row[2],
                "last_update": row[3],
                "status": row[4],
                "error_message": row[5]
            }
        return None
    
    def update_state(self, collector_name: str, ledger_hash: str, 
                    ledger_index: int, status: str = "running", 
                    error_message: str = ""):
        """Update collection state"""
        status_map = {"running": 1, "stopped": 2, "error": 3}
        status_val = status_map.get(status, 1)
        
        self.client.insert(
            "collection_state",
            [(collector_name, ledger_hash, ledger_index, datetime.now(), status_val, error_message)],
            column_names=["collector_name", "last_ledger_hash", "last_ledger_index", 
                         "last_update", "status", "error_message"]
        )
    
    def get_suspicious_ledgers(self, limit: int = 100) -> list:
        """Get suspicious ledgers that need detailed collection"""
        result = self.client.query(f"""
            SELECT DISTINCT ledger_hash, ledger_index
            FROM book_changes
            WHERE is_suspicious = 1
            AND ledger_hash NOT IN (
                SELECT DISTINCT ledger_hash FROM executed_trades
            )
            ORDER BY ledger_index DESC
            LIMIT {limit}
        """)
        
        ledgers = []
        for row in result.result_rows:
            ledger_hash = row[0]
            if isinstance(ledger_hash, bytes):
                ledger_hash = ledger_hash.decode('utf-8')
            ledgers.append((ledger_hash, row[1]))
        
        return ledgers
    
    def format_duration(self, seconds: float) -> str:
        """Format duration in human-readable format"""
        if seconds < 60:
            return f"{seconds:.1f}s"
        elif seconds < 3600:
            minutes = seconds / 60
            return f"{minutes:.1f}m ({seconds:.0f}s)"
        else:
            hours = seconds / 3600
            minutes = (seconds % 3600) / 60
            return f"{hours:.1f}h ({minutes:.0f}m)"
    
    def collect_batch(self, ledger_count: int = 10, start_ledger: Optional[str] = None):
        """Collect a batch of ledgers"""
        self.start_time = time.time()
        
        print(f"=== Collection Orchestrator Starting ===")
        print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Batch size: {ledger_count} ledgers")
        print(f"Using: TradeCollector (getMakerTaker.sh + RippleState extraction)\n")
        
        # Phase 1: Screen for volume
        phase1_start = time.time()
        print("Phase 1: Screening for suspicious volume...")
        try:
            self.book_screener.scan_ledgers(count=ledger_count, start_ledger=start_ledger)
            self.update_state("book_screener", "latest", 0, "running")
            phase1_duration = time.time() - phase1_start
            print(f"Phase 1 completed in {self.format_duration(phase1_duration)}")
        except Exception as e:
            print(f"ERROR in book screening: {e}")
            self.update_state("book_screener", "", 0, "error", str(e))
            return
        
        # Phase 2: Collect detailed trades for suspicious ledgers
        phase2_start = time.time()
        print("\n" + "="*50)
        print("Phase 2: Collecting detailed trades for suspicious ledgers...")
        
        suspicious = self.get_suspicious_ledgers(limit=ledger_count)
        
        if not suspicious:
            print("  No new suspicious ledgers to analyze")
        else:
            print(f"  Found {len(suspicious)} suspicious ledgers to analyze\n")
            
            for i, (ledger_hash, ledger_index) in enumerate(suspicious, 1):
                ledger_start = time.time()
                print(f"Analyzing {i}/{len(suspicious)}: Ledger {ledger_index}", end=" ")
                try:
                    self.trade_collector.collect_for_ledger(ledger_hash)
                    self.update_state("trade_collector", ledger_hash, ledger_index, "running")
                    ledger_duration = time.time() - ledger_start
                    print(f"({ledger_duration:.1f}s)")
                except Exception as e:
                    print(f"  ERROR: {e}")
                    self.update_state("trade_collector", ledger_hash, ledger_index, "error", str(e))
        
        phase2_duration = time.time() - phase2_start
        print(f"\nPhase 2 completed in {self.format_duration(phase2_duration)}")
        
        # Summary
        total_duration = time.time() - self.start_time
        print("\n" + "="*50)
        print("=== Collection Complete ===")
        print(f"Total duration: {self.format_duration(total_duration)}")
        print(f"End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Average: {total_duration/ledger_count:.2f}s per ledger")
        
        self.print_summary()
    
    def print_summary(self):
        """Print collection summary statistics"""
        result = self.client.query("""
            SELECT 
                COUNT(*) as total,
                SUM(is_suspicious) as suspicious
            FROM book_changes
        """)
        
        if result.result_rows:
            total, suspicious = result.result_rows[0]
            print(f"\nBook Changes: {total} total, {suspicious} suspicious ({suspicious/total*100:.1f}%)")
        
        result = self.client.query("""
            SELECT 
                COUNT(*) as total,
                COUNT(DISTINCT ledger_index) as ledgers,
                COUNT(DISTINCT taker) as unique_accounts,
                COUNT(DISTINCT exec_iou_code) as unique_tokens
            FROM executed_trades
            WHERE exec_iou_code != ''
        """)
        
        if result.result_rows:
            total, ledgers, accounts, tokens = result.result_rows[0]
            print(f"Executed Trades: {total} trades across {ledgers} ledgers")
            print(f"  - {accounts} unique accounts")
            print(f"  - {tokens} unique IOU tokens tracked")

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="XRP Watchdog Collection Orchestrator")
    parser.add_argument("count", type=int, help="Number of ledgers to collect")
    parser.add_argument("--start", help="Starting ledger index (default: latest)")
    
    args = parser.parse_args()
    
    orchestrator = CollectionOrchestrator()
    orchestrator.collect_batch(ledger_count=args.count, start_ledger=args.start)

if __name__ == "__main__":
    main()
