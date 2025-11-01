#!/bin/bash

# Smart Backfill - Fills gaps without duplicates
# Safe to run multiple times

SCRIPT_DIR="/home/grapedrop/monitoring/xrp-watchdog"
LOG_FILE="$SCRIPT_DIR/logs/backfill_smart.log"
BATCH_SIZE=13
DELAY_SECONDS=30

cd "$SCRIPT_DIR"
source venv/bin/activate

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create log file
touch "$LOG_FILE"
chmod 664 "$LOG_FILE"

log "=== SMART BACKFILL STARTED ==="
log ""

# Target period: Oct 19 - Oct 29
# Ledger estimates:
# Oct 19 17:00 ≈ ledger 99638589
# Oct 29 03:34 ≈ ledger 99837467

START_LEDGER=99638589
END_LEDGER=99837467

log "Target range: Ledger $START_LEDGER → $END_LEDGER"
log ""

# Query ClickHouse for existing ledger coverage
log "Checking existing ledger coverage in database..."

EXISTING_LEDGERS=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT groupArray(ledger_index) 
FROM (
    SELECT DISTINCT ledger_index 
    FROM xrp_watchdog.executed_trades
    WHERE ledger_index >= $START_LEDGER 
      AND ledger_index <= $END_LEDGER
    ORDER BY ledger_index
)
FORMAT JSONCompact
" 2>/dev/null)

if [ $? -ne 0 ]; then
    log "✗ Cannot query database - check ClickHouse status"
    exit 1
fi

# Count existing ledgers
EXISTING_COUNT=$(echo "$EXISTING_LEDGERS" | jq -r '.data[0][]' 2>/dev/null | wc -l)
TOTAL_LEDGERS=$((END_LEDGER - START_LEDGER))
MISSING_LEDGERS=$((TOTAL_LEDGERS - EXISTING_COUNT))

log "Ledger coverage analysis:"
log "  Total ledgers in range: $TOTAL_LEDGERS"
log "  Already collected: $EXISTING_COUNT"
log "  Missing/gaps: $MISSING_LEDGERS"
log ""

if [ $MISSING_LEDGERS -le 0 ]; then
    log "✓ No gaps to fill! All ledgers already collected."
    exit 0
fi

# Estimate time
ESTIMATED_BATCHES=$((MISSING_LEDGERS / BATCH_SIZE))
ESTIMATED_HOURS=$(echo "scale=1; ($ESTIMATED_BATCHES * 35) / 3600" | bc)

log "Backfill plan:"
log "  Estimated batches: $ESTIMATED_BATCHES"
log "  Estimated time: ${ESTIMATED_HOURS} hours"
log "  Batch size: $BATCH_SIZE ledgers"
log "  Delay: ${DELAY_SECONDS}s between batches"
log ""

# The collector automatically gets the next uncollected ledgers
# We just need to run it repeatedly until the gap is filled

BATCH_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0
CONSECUTIVE_FAILS=0

log "Starting collection loop..."
log ""

while true; do
    BATCH_COUNT=$((BATCH_COUNT + 1))
    
    log "Batch $BATCH_COUNT"
    
    # Run collection
    timeout 120 python "$SCRIPT_DIR/collectors/collection_orchestrator.py" $BATCH_SIZE >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        CONSECUTIVE_FAILS=0
        log "✓ Success"
    elif [ $EXIT_CODE -eq 124 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
        log "✗ TIMEOUT (>120s)"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
        log "✗ FAILED (exit code: $EXIT_CODE)"
    fi
    
    # Safety: Stop if too many consecutive failures
    if [ $CONSECUTIVE_FAILS -ge 5 ]; then
        log ""
        log "⚠️  5 CONSECUTIVE FAILURES - STOPPING"
        log "Check validator and ClickHouse status"
        break
    fi
    
    # Check progress every 10 batches
    if [ $((BATCH_COUNT % 10)) -eq 0 ]; then
        CURRENT_COUNT=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
            SELECT COUNT(DISTINCT ledger_index)
            FROM xrp_watchdog.executed_trades
            WHERE ledger_index >= $START_LEDGER 
              AND ledger_index <= $END_LEDGER
        " 2>/dev/null)
        
        if [ ! -z "$CURRENT_COUNT" ]; then
            PROGRESS=$((CURRENT_COUNT * 100 / TOTAL_LEDGERS))
            REMAINING=$((TOTAL_LEDGERS - CURRENT_COUNT))
            log "Progress: $PROGRESS% | Collected: $CURRENT_COUNT/$TOTAL_LEDGERS | Remaining: $REMAINING"
            
            # Stop if we've covered the range
            if [ $REMAINING -le 50 ]; then
                log ""
                log "✓ Backfill complete! Only $REMAINING ledgers remaining (acceptable gap)"
                break
            fi
        fi
    fi
    
    log ""
    
    # Stop after reasonable attempt
    if [ $BATCH_COUNT -ge 500 ]; then
        log "⚠️  Reached 500 batches - stopping to prevent infinite loop"
        log "Run again if more backfill needed"
        break
    fi
    
    # Delay between batches
    sleep $DELAY_SECONDS
done

log ""
log "=== BACKFILL COMPLETE ==="
log "Total batches: $BATCH_COUNT"
log "Successful: $SUCCESS_COUNT"
log "Failed: $FAIL_COUNT"
if [ $SUCCESS_COUNT -gt 0 ]; then
    log "Success rate: $(echo "scale=1; $SUCCESS_COUNT * 100 / $BATCH_COUNT" | bc)%"
fi
log ""

# Final coverage check
FINAL_COUNT=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
    SELECT COUNT(DISTINCT ledger_index)
    FROM xrp_watchdog.executed_trades
    WHERE ledger_index >= $START_LEDGER 
      AND ledger_index <= $END_LEDGER
" 2>/dev/null)

if [ ! -z "$FINAL_COUNT" ]; then
    FINAL_PROGRESS=$((FINAL_COUNT * 100 / TOTAL_LEDGERS))
    log "Final coverage: $FINAL_COUNT/$TOTAL_LEDGERS ledgers ($FINAL_PROGRESS%)"
fi

log ""
log "Check dashboard at: http://localhost:3000"
