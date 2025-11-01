#!/usr/bin/env python3
"""
XRP Watchdog - Trade Collector
Enhanced with RippleState parsing for complete IOU tracking
Combines getMakerTaker.sh accuracy with Python RippleState extraction
"""

import subprocess
import sys
import csv
import json
from io import StringIO
from datetime import datetime
from typing import Dict, List, Optional
import clickhouse_connect

# Configuration
RIPPLED_CONTAINER = "rippledvalidator"
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

class TradeCollector:
    def __init__(self):
        """Initialize ClickHouse connection"""
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
        )
    
    def get_transaction_details(self, tx_hash: str) -> Optional[Dict]:
        """
        Fetch full transaction details including metadata
        
        Args:
            tx_hash: Transaction hash
        
        Returns:
            Full transaction JSON or None
        """
        cmd = [
            "docker", "exec", RIPPLED_CONTAINER,
            "rippled", "-q", "json", "tx",
            f'{{"transaction":"{tx_hash}","binary":false}}'
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            return data.get("result")
        except Exception as e:
            print(f"    Warning: Could not fetch tx {tx_hash[:8]}: {e}")
            return None
    
    def extract_iou_from_ripplestate(self, tx_data: Dict, taker: str) -> Dict:
        """
        Extract IOU changes from RippleState nodes
        
        Args:
            tx_data: Full transaction data with metadata
            taker: Taker account address
        
        Returns:
            Dict with exec_iou_code, exec_iou_issuer, exec_iou, exec_price
        """
        if not tx_data or "meta" not in tx_data:
            return {"exec_iou_code": "", "exec_iou_issuer": "", "exec_iou": 0.0, "exec_price": 0.0}
        
        affected_nodes = tx_data["meta"].get("AffectedNodes", [])
        
        # Find RippleState nodes
        for node_wrapper in affected_nodes:
            node = node_wrapper.get("ModifiedNode") or node_wrapper.get("DeletedNode")
            if not node or node.get("LedgerEntryType") != "RippleState":
                continue
            
            final_fields = node.get("FinalFields", {})
            prev_fields = node.get("PreviousFields", {})
            
            # Check if this RippleState involves the taker
            low_limit = final_fields.get("LowLimit", {})
            high_limit = final_fields.get("HighLimit", {})
            
            taker_is_low = low_limit.get("issuer") == taker
            taker_is_high = high_limit.get("issuer") == taker
            
            if not (taker_is_low or taker_is_high):
                continue
            
            # Get balance change
            final_balance = final_fields.get("Balance", {})
            prev_balance = prev_fields.get("Balance", {})
            
            if not isinstance(final_balance, dict) or not isinstance(prev_balance, dict):
                continue
            
            try:
                final_val = float(final_balance.get("value", 0))
                prev_val = float(prev_balance.get("value", 0))
                raw_change = final_val - prev_val
                
                # Determine sign based on which side taker is on
                if taker_is_low:
                    iou_change = -raw_change  # Low side: negative balance = owed TO them
                else:
                    iou_change = raw_change   # High side: positive balance = they owe
                
                # Extract token info
                currency = final_balance.get("currency", "")
                # Issuer is the OTHER party (not taker)
                if taker_is_low:
                    issuer = high_limit.get("issuer", "")
                else:
                    issuer = low_limit.get("issuer", "")
                
                # Calculate price if we have both IOU and XRP data
                # (Price calculation done after merging with XRP data)
                
                return {
                    "exec_iou_code": currency,
                    "exec_iou_issuer": issuer,
                    "exec_iou": abs(iou_change),
                    "exec_price": 0.0  # Will calculate after merging
                }
                
            except (ValueError, TypeError) as e:
                continue
        
        # No RippleState found for this taker
        return {"exec_iou_code": "", "exec_iou_issuer": "", "exec_iou": 0.0, "exec_price": 0.0}
    
    def run_get_maker_taker(self, ledger_hash: str) -> str:
        """
        Run getMakerTaker.sh script and return TSV output
        
        Args:
            ledger_hash: Ledger hash to query
        
        Returns:
            TSV output as string
        """
        script_path = "/home/grapedrop/monitoring/xrp-watchdog/scripts/getMakerTaker.sh"
        cmd = [script_path, "1", "hash", ledger_hash]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            env={"RIPPLED_CONTAINER": RIPPLED_CONTAINER}
        )
        
        return result.stdout
    
    def parse_tsv_output(self, tsv_data: str) -> List[Dict]:
        """
        Parse getMakerTaker.sh TSV output and deduplicate
        
        Args:
            tsv_data: TSV string from script
        
        Returns:
            List of unique trade dicts (deduplicated by tx_hash)
        """
        trades = []
        seen_tx_hashes = set()
        
        reader = csv.DictReader(StringIO(tsv_data), delimiter='\t')
        
        for row in reader:
            if not row.get('counterparties') or row['counterparties'] == '':
                continue
            
            tx_hash = row['tx_hash']
            if tx_hash in seen_tx_hashes:
                continue
            seen_tx_hashes.add(tx_hash)
            
            trades.append({
                'ledger_index': int(row['ledger_index']),
                'close_time': row['close_time'],
                'tx_hash': tx_hash,
                'tx_type': row['tx_type'],
                'taker': row['taker'],
                'posted_gets': row['posted_gets'],
                'posted_pays': row['posted_pays'],
                'exec_xrp': float(row['exec_xrp']) if row['exec_xrp'] else 0.0,
                'counterparties': row['counterparties'].split(',') if row['counterparties'] else []
            })
        
        return trades
    
    def enrich_with_ripplestate(self, trades: List[Dict]) -> List[Dict]:
        """
        Enrich trades with RippleState IOU data
        
        Args:
            trades: List of trades from getMakerTaker.sh
        
        Returns:
            Enriched trades with IOU data
        """
        enriched = []
        
        for trade in trades:
            # Fetch full transaction
            tx_data = self.get_transaction_details(trade['tx_hash'])
            
            # Extract IOU data
            iou_data = self.extract_iou_from_ripplestate(tx_data, trade['taker'])
            
            # Calculate price if we have both XRP and IOU
            if iou_data['exec_iou'] > 0 and trade['exec_xrp'] != 0:
                iou_data['exec_price'] = abs(trade['exec_xrp']) / iou_data['exec_iou']
            
            # Merge data
            enriched_trade = {**trade, **iou_data}
            enriched.append(enriched_trade)
        
        return enriched
    
    def insert_trades(self, trades: List[Dict], ledger_hash: str):
        """
        Insert trades into ClickHouse
        
        Args:
            trades: List of trade dicts
            ledger_hash: Ledger hash for reference
        """
        if not trades:
            return
        
        rows = []
        for trade in trades:
            close_time_str = trade['close_time']
            try:
                dt = datetime.strptime(close_time_str.split('.')[0], "%Y-%b-%d %H:%M:%S")
            except:
                dt = datetime.now()
            
            tx_type_map = {'OfferCreate': 1, 'Payment': 2}
            tx_type_val = tx_type_map.get(trade['tx_type'], 1)
            
            row = (
                dt,
                trade['ledger_index'],
                ledger_hash,
                trade['tx_hash'],
                tx_type_val,
                trade['taker'],
                trade['counterparties'],
                len(trade['counterparties']),
                trade['posted_gets'],
                trade['posted_pays'],
                trade['exec_xrp'],
                trade.get('exec_iou_code', ''),
                trade.get('exec_iou_issuer', ''),
                trade.get('exec_iou', 0.0),
                trade.get('exec_price', 0.0),
                abs(trade['exec_xrp'])
            )
            rows.append(row)
        
        self.client.insert(
            "executed_trades",
            rows,
            column_names=[
                "time", "ledger_index", "ledger_hash", "tx_hash", "tx_type",
                "taker", "counterparties", "counterparty_count",
                "posted_gets", "posted_pays",
                "exec_xrp", "exec_iou_code", "exec_iou_issuer", "exec_iou", "exec_price",
                "total_volume_xrp"
            ]
        )
    
    def collect_for_ledger(self, ledger_hash: str):
        """
        Collect executed trades for a specific ledger
        
        Args:
            ledger_hash: Ledger hash to analyze
        """
        print(f"Collecting trades for ledger hash: {ledger_hash}")
        
        try:
            # Step 1: Run getMakerTaker.sh
            tsv_output = self.run_get_maker_taker(ledger_hash)
            
            # Step 2: Parse TSV
            trades = self.parse_tsv_output(tsv_output)
            
            if not trades:
                print(f"  No executed trades found")
                return
            
            print(f"  Found {len(trades)} trades, enriching with RippleState data...")
            
            # Step 3: Enrich with RippleState IOU data
            enriched_trades = self.enrich_with_ripplestate(trades)
            
            # Step 4: Insert to ClickHouse
            self.insert_trades(enriched_trades, ledger_hash)
            
            iou_count = sum(1 for t in enriched_trades if t.get('exec_iou_code'))
            print(f"  Inserted {len(enriched_trades)} trades ({iou_count} with IOU data)")
            
        except subprocess.CalledProcessError as e:
            print(f"  ERROR running getMakerTaker.sh: {e}")
            if e.stderr:
                print(f"  stderr: {e.stderr}")
        except Exception as e:
            print(f"  ERROR: {e}")

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="XRP Watchdog Trade Collector")
    parser.add_argument("ledger_hash", help="Ledger hash to collect")
    
    args = parser.parse_args()
    
    collector = TradeCollector()
    collector.collect_for_ledger(args.ledger_hash)

if __name__ == "__main__":
    main()
