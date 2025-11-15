#!/bin/bash
# XRP Watchdog Production Stack - STOP
# Stops all production services gracefully

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
echo -e "${BLUE}  XRP Watchdog Production Stack - STOPPING${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Stop Cloudflare Tunnel
echo -e "${YELLOW}[1/3] Stopping Cloudflare Tunnel...${NC}"
if systemctl is-active --quiet $TUNNEL_SERVICE 2>/dev/null; then
    sudo systemctl stop $TUNNEL_SERVICE
    echo -e "${GREEN}  ✓ Tunnel stopped${NC}"
else
    echo -e "${YELLOW}  ⚠ Tunnel already stopped${NC}"
fi

# Stop Grafana
echo -e "${YELLOW}[2/3] Stopping Grafana...${NC}"
if docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}$"; then
    cd $GRAFANA_COMPOSE_DIR
    docker compose stop
    echo -e "${GREEN}  ✓ Grafana stopped${NC}"
else
    echo -e "${YELLOW}  ⚠ Grafana already stopped${NC}"
fi

# Stop ClickHouse
echo -e "${YELLOW}[3/3] Stopping ClickHouse...${NC}"
if docker ps --format '{{.Names}}' | grep -q "^${CLICKHOUSE_CONTAINER}$"; then
    docker stop $CLICKHOUSE_CONTAINER
    echo -e "${GREEN}  ✓ ClickHouse stopped${NC}"
else
    echo -e "${YELLOW}  ⚠ ClickHouse already stopped${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Production Stack Stopped${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Status:${NC}"
echo -e "  • Dashboard: ${RED}OFFLINE${NC} (https://xrp-watchdog.grapedrop.xyz)"
echo -e "  • Data Collection: ${YELLOW}PAUSED${NC} (cron job will fail until restart)"
echo ""
echo -e "${YELLOW}Note: Cron job is still active but will fail until services are restarted${NC}"
echo -e "${BLUE}To restart: ${NC}./scripts/prod_start.sh"
echo ""
