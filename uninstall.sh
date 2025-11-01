#!/bin/bash
# XRP Watchdog - Complete Uninstall Script
# Surgically removes all components created by this project

set -e

echo "=== XRP Watchdog Uninstall ==="
echo "This will remove:"
echo "  - ClickHouse container and data"
echo "  - All collected data"
echo "  - Python virtual environment"
echo "  - Cron jobs"
echo "  - All project files"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

INSTALL_DIR="/home/grapedrop/monitoring/xrp-watchdog"

echo ""
echo "Step 1: Stopping and removing ClickHouse container..."
if docker ps -a | grep -q xrp-watchdog-clickhouse; then
    docker stop xrp-watchdog-clickhouse 2>/dev/null || true
    docker rm xrp-watchdog-clickhouse 2>/dev/null || true
    echo "  ✓ ClickHouse container removed"
else
    echo "  ℹ No ClickHouse container found"
fi

echo ""
echo "Step 2: Removing Docker Compose setup..."
if [ -f "$INSTALL_DIR/compose/docker-compose.yml" ]; then
    cd "$INSTALL_DIR/compose"
    docker compose down 2>/dev/null || true
    echo "  ✓ Docker Compose services stopped"
else
    echo "  ℹ No Docker Compose file found"
fi

echo ""
echo "Step 3: Removing cron jobs..."
CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "xrp-watchdog" || echo "0")
if [ "$CRON_COUNT" -gt 0 ]; then
    crontab -l 2>/dev/null | grep -v "xrp-watchdog" | crontab -
    echo "  ✓ Removed $CRON_COUNT cron job(s)"
else
    echo "  ℹ No cron jobs found"
fi

echo ""
echo "Step 4: Removing data directories..."
if [ -d "$INSTALL_DIR/data" ]; then
    rm -rf "$INSTALL_DIR/data"
    echo "  ✓ Removed data directory"
else
    echo "  ℹ No data directory found"
fi

echo ""
echo "Step 5: Removing Python virtual environment..."
if [ -d "$INSTALL_DIR/venv" ]; then
    rm -rf "$INSTALL_DIR/venv"
    echo "  ✓ Removed virtual environment"
else
    echo "  ℹ No virtual environment found"
fi

echo ""
echo "Step 6: Removing log files..."
if [ -d "$INSTALL_DIR/logs" ]; then
    rm -rf "$INSTALL_DIR/logs"
    echo "  ✓ Removed logs directory"
else
    echo "  ℹ No logs directory found"
fi

echo ""
echo "Step 7: Removing all project files..."
read -p "Remove entire project directory $INSTALL_DIR? (yes/no): " REMOVE_ALL

if [ "$REMOVE_ALL" = "yes" ]; then
    cd /home/grapedrop/monitoring
    rm -rf xrp-watchdog
    echo "  ✓ Removed entire project directory"
    echo ""
    echo "=== Uninstall Complete ==="
    echo "All XRP Watchdog components have been removed."
else
    echo "  ℹ Kept project directory (code and configs remain)"
    echo ""
    echo "=== Partial Uninstall Complete ==="
    echo "Data and services removed, code preserved."
    echo "To remove code: rm -rf $INSTALL_DIR"
fi

echo ""
echo "Note: This does not affect your rippled validator."
echo "Your validator continues running normally."
