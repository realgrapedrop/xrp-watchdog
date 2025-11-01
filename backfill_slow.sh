#!/bin/bash

# Slow, safe backfill with 30-second delays
# Designed to run without overwhelming validator or ClickHouse

SCRIPT_DIR="/home/grapedrop/monitoring/xrp-watchdog"
LOG_FILE="$SCRIPT_DIR/logs/backfill_slow.log"
BATCH_SIZE=13
DELAY_SECONDS=30

# Activate virtual environment
cd "$SCRIPT_DIR"
source venv/bin/activate

# Function to log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create log file with correct permissions
touch "$LOG_FILE"
chmod 664 "$LOG_FILE"

# Get ledger info from ClickHouse
LATEST_LEDGER=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "SELECT MAX(ledger_index) FROM xrp_watchdog.executed_trades" 2>/dev/null)
CURRENT_LEDGER=$(docker exec rippledvalidator rippled server_info 2>/dev/null | grep -oP '"seq"\s*:\s*\K[0-9]+' | head -1)

# Fallback if queries fail
if [ -z "$LATEST_LEDGER" ]; then
    LATEST_LEDGER=99638589
fi

if [ -z "$CURRENT_LEDGER" ]; then
    CURRENT_LEDGER=99859512
fi

# Target: collect up to current ledger
START_LEDGER=$LATEST_LEDGER
END_LEDGER=$CURRENT_LEDGER

# Calculate estimates
TOTAL_LEDGERS=$((END_LEDGER - START_LEDGER))
TOTAL_BATCHES=$((TOTAL_LEDGERS / BATCH_SIZE))
ESTIMATED_HOURS=$(echo "scale=1; ($TOTAL_BATCHES * 35) / 3600" | bc)

log "=== SLOW BACKFILL STARTED ==="
log "Start ledger: $START_LEDGER"
log "End ledger: $END_LEDGER"
log "Total ledgers: $TOTAL_LEDGERS"
log "Total batches: $TOTAL_BATCHES"
log "Estimated time: ${ESTIMATED_HOURS} hours"
log "Batch size: $BATCH_SIZE"
log "Delay: ${DELAY_SECONDS}s between batches"
log ""

BATCH_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0

while [ $BATCH_COUNT -lt $TOTAL_BATCHES ]; do
    BATCH_COUNT=$((BATCH_COUNT + 1))
    
    log "Batch $BATCH_COUNT/$TOTAL_BATCHES"
    
    # Run collection with timeout
    timeout 120 python "$SCRIPT_DIR/collectors/collection_orchestrator.py" $BATCH_SIZE >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        log "✓ Success"
    elif [ $EXIT_CODE -eq 124 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "✗ TIMEOUT (>120s) - Skipping batch"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "✗ FAILED (exit code: $EXIT_CODE)"
    fi
    
    # Progress
    PROGRESS=$((BATCH_COUNT * 100 / TOTAL_BATCHES))
    log "Progress: $PROGRESS% | Success: $SUCCESS_COUNT | Failed: $FAIL_COUNT"
    log ""
    
    # Safety: Stop if too many failures
    if [ $FAIL_COUNT -gt 10 ]; then
        log "⚠️  TOO MANY FAILURES ($FAIL_COUNT) - STOPPING"
        log "Check validator and ClickHouse status"
        break
    fi
    
    # Delay between batches
    if [ $BATCH_COUNT -lt $TOTAL_BATCHES ]; then
        sleep $DELAY_SECONDS
    fi
done

log "=== BACKFILL COMPLETE ==="
log "Total batches: $BATCH_COUNT"
log "Successful: $SUCCESS_COUNT"
log "Failed: $FAIL_COUNT"
log "Success rate: $(echo "scale=1; $SUCCESS_COUNT * 100 / $BATCH_COUNT" | bc)%"
