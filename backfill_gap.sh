#!/bin/bash

# Backfill script for Oct 19-29 data gap
# Safe incremental collection with delays

SCRIPT_DIR="/home/grapedrop/monitoring/xrp-watchdog"
LOG_FILE="$SCRIPT_DIR/logs/backfill.log"
BATCH_SIZE=13
DELAY_SECONDS=5

# Activate virtual environment
cd "$SCRIPT_DIR"
source venv/bin/activate

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get current ledger from validator
CURRENT_LEDGER=$(docker exec rippledvalidator rippled server_info | grep -oP '"seq"\s*:\s*\K[0-9]+' | head -1)

# Start ledger (Oct 19 21:25 - ledger ~99638589)
START_LEDGER=99638589

# End ledger (Oct 29 03:34 - ledger ~99837467) 
END_LEDGER=99837467

# Calculate total batches
TOTAL_LEDGERS=$((END_LEDGER - START_LEDGER))
TOTAL_BATCHES=$((TOTAL_LEDGERS / BATCH_SIZE))

log "=== BACKFILL STARTED ==="
log "Start ledger: $START_LEDGER"
log "End ledger: $END_LEDGER"
log "Total ledgers to process: $TOTAL_LEDGERS"
log "Total batches: $TOTAL_BATCHES"
log "Batch size: $BATCH_SIZE"
log "Delay between batches: ${DELAY_SECONDS}s"
log ""

BATCH_COUNT=0
CURRENT_START=$START_LEDGER

while [ $CURRENT_START -lt $END_LEDGER ]; do
    BATCH_COUNT=$((BATCH_COUNT + 1))
    
    log "Batch $BATCH_COUNT/$TOTAL_BATCHES - Starting at ledger $CURRENT_START"
    
    # Run collection
    python "$SCRIPT_DIR/collectors/collection_orchestrator.py" $BATCH_SIZE >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "✓ Batch $BATCH_COUNT completed successfully"
    else
        log "✗ Batch $BATCH_COUNT FAILED - Check log for errors"
        log "Consider rerunning from ledger $CURRENT_START"
    fi
    
    # Update for next batch
    CURRENT_START=$((CURRENT_START + BATCH_SIZE))
    
    # Progress indicator
    PROGRESS=$((BATCH_COUNT * 100 / TOTAL_BATCHES))
    log "Progress: $PROGRESS% complete ($BATCH_COUNT/$TOTAL_BATCHES batches)"
    log ""
    
    # Delay to prevent validator overload
    if [ $CURRENT_START -lt $END_LEDGER ]; then
        sleep $DELAY_SECONDS
    fi
done

log "=== BACKFILL COMPLETE ==="
log "Processed $BATCH_COUNT batches"
log "Check ClickHouse for updated data"
