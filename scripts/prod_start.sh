#!/bin/bash
# XRP Watchdog Production Stack - START
# Starts all production services in correct order

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GRAFANA_CONTAINER="grafana-prod-watchdog"
CLICKHOUSE_CONTAINER="xrp-watchdog-clickhouse"
TUNNEL_SERVICE="cloudflared-xrp-watchdog"
GRAFANA_COMPOSE_DIR="/home/grapedrop/monitoring/compose/prod-grafana-watchdog"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  XRP Watchdog Production Stack - STARTING${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Start ClickHouse first (data layer)
echo -e "${YELLOW}[1/3] Starting ClickHouse...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q "^${CLICKHOUSE_CONTAINER}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CLICKHOUSE_CONTAINER}$"; then
        echo -e "${GREEN}  ✓ ClickHouse already running${NC}"
    else
        docker start $CLICKHOUSE_CONTAINER
        echo -e "${GREEN}  ✓ ClickHouse started${NC}"
    fi
else
    echo -e "${RED}  ✗ ClickHouse container not found!${NC}"
    exit 1
fi

# Wait for ClickHouse to be healthy
echo -e "${BLUE}    Waiting for ClickHouse to be healthy...${NC}"
RETRIES=30
COUNT=0
while [ $COUNT -lt $RETRIES ]; do
    if docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}    ✓ ClickHouse is healthy${NC}"
        break
    fi
    COUNT=$((COUNT + 1))
    sleep 2
done

if [ $COUNT -eq $RETRIES ]; then
    echo -e "${RED}    ✗ ClickHouse failed to become healthy${NC}"
    exit 1
fi

# Start Grafana
echo -e "${YELLOW}[2/3] Starting Grafana...${NC}"
cd $GRAFANA_COMPOSE_DIR
if docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}$"; then
    echo -e "${GREEN}  ✓ Grafana already running${NC}"
else
    docker compose up -d
    echo -e "${GREEN}  ✓ Grafana started${NC}"
fi

# Wait for Grafana to be healthy
echo -e "${BLUE}    Waiting for Grafana to be healthy...${NC}"
RETRIES=30
COUNT=0
while [ $COUNT -lt $RETRIES ]; do
    if curl -sf http://localhost:3002/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}    ✓ Grafana is healthy${NC}"
        break
    fi
    COUNT=$((COUNT + 1))
    sleep 2
done

if [ $COUNT -eq $RETRIES ]; then
    echo -e "${RED}    ✗ Grafana failed to become healthy${NC}"
    exit 1
fi

# Start Cloudflare Tunnel
echo -e "${YELLOW}[3/3] Starting Cloudflare Tunnel...${NC}"
if systemctl is-active --quiet $TUNNEL_SERVICE 2>/dev/null; then
    echo -e "${GREEN}  ✓ Tunnel already running${NC}"
else
    sudo systemctl start $TUNNEL_SERVICE
    echo -e "${GREEN}  ✓ Tunnel started${NC}"
fi

# Wait for tunnel connections
echo -e "${BLUE}    Waiting for tunnel connections...${NC}"
sleep 5
CONNECTIONS=$(systemctl status $TUNNEL_SERVICE --no-pager 2>/dev/null | grep -c "Registered tunnel connection" || echo "0")
if [ "$CONNECTIONS" -ge 2 ]; then
    echo -e "${GREEN}    ✓ Tunnel has $CONNECTIONS active connections${NC}"
else
    echo -e "${YELLOW}    ⚠ Tunnel has only $CONNECTIONS connections (expected 4)${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Production Stack Started Successfully${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Service Status:${NC}"

# Check container status
if docker ps --format '{{.Names}}\t{{.Status}}' | grep -E "grafana-prod-watchdog|xrp-watchdog-clickhouse"; then
    echo ""
fi

# Check tunnel status
echo -e "${BLUE}Tunnel Status:${NC}"
systemctl status $TUNNEL_SERVICE --no-pager | head -3 | tail -1

# Check cron
echo ""
echo -e "${BLUE}Data Collection:${NC}"
if systemctl is-active --quiet cron 2>/dev/null; then
    echo -e "  • Cron service: ${GREEN}RUNNING${NC}"
    echo -e "  • Collection runs every 5 minutes"
else
    echo -e "  • Cron service: ${RED}NOT RUNNING${NC}"
fi

echo ""
echo -e "${BLUE}Endpoints:${NC}"
echo -e "  • Public: ${GREEN}https://xrp-watchdog.grapedrop.xyz${NC}"
echo -e "  • Local:  ${GREEN}http://localhost:3002${NC}"
echo ""

# Run a quick health check
echo -e "${YELLOW}Running final health checks...${NC}"
HEALTH_OK=true

# Check ClickHouse data
TRADE_COUNT=$(docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "SELECT COUNT(*) FROM xrp_watchdog.executed_trades" 2>/dev/null || echo "0")
if [ "$TRADE_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ClickHouse: $TRADE_COUNT trades in database"
else
    echo -e "  ${RED}✗${NC} ClickHouse: No data found"
    HEALTH_OK=false
fi

# Check Grafana datasource
if curl -sf http://localhost:3002/api/datasources/uid/clickhouse > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Grafana: ClickHouse datasource configured"
else
    echo -e "  ${YELLOW}⚠${NC} Grafana: ClickHouse datasource not found"
fi

# Check public URL
if curl -sf -I https://xrp-watchdog.grapedrop.xyz > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Public URL: Accessible"
else
    echo -e "  ${YELLOW}⚠${NC} Public URL: Not accessible (may take a few minutes)"
fi

echo ""
if [ "$HEALTH_OK" = true ]; then
    echo -e "${GREEN}✓ All systems operational${NC}"
else
    echo -e "${YELLOW}⚠ Some issues detected - check logs${NC}"
fi
echo ""
