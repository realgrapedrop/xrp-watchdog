#!/bin/bash

# XRP Watchdog Health Check Script
# Run manually to verify all components are working

echo "=========================================="
echo "XRP Watchdog Health Check"
echo "=========================================="
echo ""
date
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo "  → $1"
}

# ==========================================
# 1. Check Cron Service
# ==========================================
echo "1. Cron Service Status"
echo "---"
systemctl is-active --quiet cron
print_status $? "Cron daemon running"

# Check if cron job exists
CRON_EXISTS=$(crontab -l 2>/dev/null | grep -c "collection_orchestrator")
if [ $CRON_EXISTS -gt 0 ]; then
    print_status 0 "Collection cron job configured"
    CRON_SCHEDULE=$(crontab -l | grep "collection_orchestrator" | awk '{print $1,$2,$3,$4,$5}')
    print_info "Schedule: $CRON_SCHEDULE (every 15 minutes expected: */15 * * * *)"
else
    print_status 1 "Collection cron job NOT found"
fi
echo ""

# ==========================================
# 2. Check ClickHouse
# ==========================================
echo "2. ClickHouse Database"
echo "---"
docker ps | grep -q xrp-watchdog-clickhouse
print_status $? "ClickHouse container running"

# Test database connection
CLICKHOUSE_TEST=$(timeout 5 docker exec xrp-watchdog-clickhouse clickhouse-client -q "SELECT 1" 2>/dev/null)
if [ "$CLICKHOUSE_TEST" = "1" ]; then
    print_status 0 "ClickHouse responding"
else
    print_status 1 "ClickHouse NOT responding"
fi
echo ""

# ==========================================
# 3. Check Validator
# ==========================================
echo "3. XRPL Validator Status"
echo "---"
docker ps | grep -q rippledvalidator
print_status $? "Validator container running"

# Check validator state
VALIDATOR_STATE=$(timeout 5 docker exec rippledvalidator rippled server_info 2>/dev/null | grep -oP '"server_state"\s*:\s*"\K[^"]+' | head -1)
if [ "$VALIDATOR_STATE" = "proposing" ]; then
    print_status 0 "Validator state: $VALIDATOR_STATE"
elif [ ! -z "$VALIDATOR_STATE" ]; then
    print_warning "Validator state: $VALIDATOR_STATE (expected: proposing)"
else
    print_status 1 "Cannot determine validator state"
fi
echo ""

# ==========================================
# 4. Check Recent Data Collection
# ==========================================
echo "4. Data Collection Status"
echo "---"

# Get latest trade timestamp
LATEST_TRADE=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT MAX(time) FROM xrp_watchdog.executed_trades
" 2>/dev/null)

CURRENT_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
MINUTES_AGO=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT dateDiff('minute', MAX(time), now()) 
FROM xrp_watchdog.executed_trades
" 2>/dev/null)

if [ ! -z "$LATEST_TRADE" ]; then
    print_info "Latest trade: $LATEST_TRADE UTC"
    print_info "Current time: $CURRENT_TIME UTC"
    print_info "Last collection: $MINUTES_AGO minutes ago"
    
    if [ $MINUTES_AGO -lt 30 ]; then
        print_status 0 "Recent data collection (< 30 min)"
    elif [ $MINUTES_AGO -lt 60 ]; then
        print_warning "Data collection delayed ($MINUTES_AGO minutes)"
    else
        print_status 1 "Data collection STALE ($MINUTES_AGO minutes)"
    fi
else
    print_status 1 "Cannot query database"
fi
echo ""

# ==========================================
# 5. Database Statistics
# ==========================================
echo "5. Database Statistics"
echo "---"

DB_STATS=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT 
    COUNT(*) as total_trades,
    COUNT(DISTINCT exec_iou_code) as unique_tokens,
    COUNT(DISTINCT taker) as unique_accounts,
    MIN(time) as earliest,
    MAX(time) as latest
FROM xrp_watchdog.executed_trades
FORMAT Vertical
" 2>/dev/null)

if [ ! -z "$DB_STATS" ]; then
    print_status 0 "Database accessible"
    echo "$DB_STATS" | grep -v "^$"
else
    print_status 1 "Cannot retrieve database statistics"
fi
echo ""

# ==========================================
# 6. Check Collection Logs
# ==========================================
echo "6. Collection Log Status"
echo "---"

LOG_FILE="/home/grapedrop/monitoring/xrp-watchdog/logs/auto_collection.log"

if [ -f "$LOG_FILE" ]; then
    print_status 0 "Collection log exists"
    
    # Check log file permissions
    LOG_OWNER=$(stat -c '%U:%G' "$LOG_FILE")
    if [ "$LOG_OWNER" = "grapedrop:grapedrop" ]; then
        print_status 0 "Log file permissions correct"
    else
        print_warning "Log file owned by: $LOG_OWNER (expected: grapedrop:grapedrop)"
    fi
    
    # Get last log entry timestamp
    LAST_LOG=$(tail -1 "$LOG_FILE" 2>/dev/null)
    if [ ! -z "$LAST_LOG" ]; then
        print_info "Last log entry:"
        print_info "$(echo "$LAST_LOG" | head -c 100)..."
    fi
else
    print_status 1 "Collection log NOT found: $LOG_FILE"
fi
echo ""

# ==========================================
# 7. Grafana Status
# ==========================================
echo "7. Grafana Dashboard"
echo "---"

docker ps | grep -q grafana-prod
print_status $? "Grafana container running"

# Check if Grafana is accessible
GRAFANA_STATUS=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
if [ "$GRAFANA_STATUS" = "200" ] || [ "$GRAFANA_STATUS" = "302" ]; then
    print_status 0 "Grafana web interface accessible"
else
    print_warning "Grafana HTTP status: $GRAFANA_STATUS"
fi
echo ""

# ==========================================
# 8. Recent Collection Activity
# ==========================================
echo "8. Recent Collection Activity (Last Hour)"
echo "---"

HOURLY_STATS=$(docker exec xrp-watchdog-clickhouse clickhouse-client -q "
SELECT 
    toStartOfHour(time) as hour,
    COUNT(*) as trades,
    COUNT(DISTINCT exec_iou_code) as tokens
FROM xrp_watchdog.executed_trades
WHERE time >= now() - INTERVAL 1 HOUR
GROUP BY hour
ORDER BY hour DESC
FORMAT Vertical
" 2>/dev/null)

if [ ! -z "$HOURLY_STATS" ]; then
    echo "$HOURLY_STATS" | grep -v "^$"
    
    RECENT_COUNT=$(echo "$HOURLY_STATS" | grep -c "trades:")
    if [ $RECENT_COUNT -gt 0 ]; then
        print_status 0 "Active collection in last hour"
    else
        print_warning "No trades collected in last hour (may be normal if market is quiet)"
    fi
else
    print_status 1 "Cannot query recent activity"
fi
echo ""

# ==========================================
# 9. System Resources
# ==========================================
echo "9. System Resources"
echo "---"

# ClickHouse container resources
CH_STATS=$(docker stats --no-stream xrp-watchdog-clickhouse 2>/dev/null | tail -1)
if [ ! -z "$CH_STATS" ]; then
    CH_CPU=$(echo "$CH_STATS" | awk '{print $3}')
    CH_MEM=$(echo "$CH_STATS" | awk '{print $4}')
    print_info "ClickHouse: CPU: $CH_CPU | Memory: $CH_MEM"
fi

# Disk space
DISK_USAGE=$(df -h /home/grapedrop/monitoring/xrp-watchdog | tail -1 | awk '{print $5}')
print_info "Disk usage: $DISK_USAGE"

# Check if disk is getting full
DISK_PCT=$(echo "$DISK_USAGE" | sed 's/%//')
if [ $DISK_PCT -lt 80 ]; then
    print_status 0 "Disk space healthy"
elif [ $DISK_PCT -lt 90 ]; then
    print_warning "Disk usage high: $DISK_USAGE"
else
    print_status 1 "Disk space CRITICAL: $DISK_USAGE"
fi
echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "Health Check Complete"
echo "=========================================="
echo ""
echo "Quick Actions:"
echo "  - View collection log: tail -50 $LOG_FILE"
echo "  - Manual collection test: cd /home/grapedrop/monitoring/xrp-watchdog && source venv/bin/activate && python collectors/collection_orchestrator.py 13"
echo "  - Check cron jobs: crontab -l"
echo "  - Grafana dashboard: http://localhost:3000"
echo ""
