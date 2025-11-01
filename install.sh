#!/bin/bash
# XRP Watchdog - Interactive Installation Script
# Detects environment and configures system automatically

set -e

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INSTALL_DIR"

echo "╔════════════════════════════════════════════════════════╗"
echo "║        XRP Watchdog Installation                       ║"
echo "║        Wash Trading Detection for XRPL                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Check if already installed
if [ -f "config.env" ]; then
    echo "⚠️  XRP Watchdog appears to be already installed."
    echo "   Found existing config.env file."
    read -p "Reinstall? This will overwrite config.env (yes/no): " REINSTALL
    if [ "$REINSTALL" != "yes" ]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo ""
fi

# ============================================================================
# STEP 1: Check Prerequisites
# ============================================================================
echo "Step 1: Checking prerequisites..."
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "✗ Docker is not installed"
    echo "  Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo "✓ Docker found: $(docker --version | cut -d' ' -f3)"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo "✗ Docker Compose is not installed"
    echo "  Please install Docker Compose"
    exit 1
fi
echo "✓ Docker Compose found"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "✗ Python 3 is not installed"
    echo "  Please install Python 3.8 or higher"
    exit 1
fi
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "✓ Python found: $PYTHON_VERSION"

# Check pip
if ! command -v pip3 &> /dev/null; then
    echo "✗ pip3 is not installed"
    echo "  Please install pip3"
    exit 1
fi
echo "✓ pip3 found"

echo ""

# ============================================================================
# STEP 2: Detect Rippled Configuration
# ============================================================================
echo "Step 2: Detecting rippled configuration..."
echo ""

# Try to find rippled containers
RIPPLED_CONTAINERS=$(docker ps --format '{{.Names}}' | grep -i rippled || echo "")

if [ ! -z "$RIPPLED_CONTAINERS" ]; then
    # Count containers
    CONTAINER_COUNT=$(echo "$RIPPLED_CONTAINERS" | wc -l)
    
    if [ "$CONTAINER_COUNT" -eq 1 ]; then
        echo "✓ Found rippled container: $RIPPLED_CONTAINERS"
        read -p "Use this container? (yes/no/custom): " USE_DETECTED
        
        if [ "$USE_DETECTED" = "yes" ] || [ "$USE_DETECTED" = "y" ] || [ -z "$USE_DETECTED" ]; then
            RIPPLED_CONTAINER="$RIPPLED_CONTAINERS"
        else
            read -p "Enter rippled container name: " RIPPLED_CONTAINER
        fi
    else
        echo "Found multiple rippled containers:"
        echo "$RIPPLED_CONTAINERS"
        echo ""
        read -p "Which container should we use? " RIPPLED_CONTAINER
    fi
else
    echo "⚠️  No rippled container detected."
    echo ""
    echo "Options:"
    echo "  1. Docker container (enter container name)"
    echo "  2. Local rippled binary (enter 'local')"
    echo ""
    read -p "Enter rippled container name or 'local': " RIPPLED_CONTAINER
fi

# Test rippled connection
echo ""
echo "Testing rippled connection..."
if [ "$RIPPLED_CONTAINER" = "local" ]; then
    if rippled server_info > /dev/null 2>&1; then
        echo "✓ Local rippled connection successful!"
    else
        echo "✗ Could not connect to local rippled"
        echo "  Make sure rippled is running and accessible"
        exit 1
    fi
else
    if docker exec "$RIPPLED_CONTAINER" rippled server_info > /dev/null 2>&1; then
        echo "✓ Rippled container connection successful!"
    else
        echo "✗ Could not connect to rippled container: $RIPPLED_CONTAINER"
        echo "  Make sure the container name is correct and rippled is running"
        exit 1
    fi
fi

echo ""

# ============================================================================
# STEP 3: Check Port Availability
# ============================================================================
echo "Step 3: Checking port availability..."
echo ""

# Check ClickHouse HTTP port (8123)
CLICKHOUSE_HTTP_PORT=8123
if lsof -Pi :$CLICKHOUSE_HTTP_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port $CLICKHOUSE_HTTP_PORT is already in use"
    read -p "Enter alternative port for ClickHouse HTTP [8124]: " ALT_PORT
    CLICKHOUSE_HTTP_PORT=${ALT_PORT:-8124}
    echo "   Using port: $CLICKHOUSE_HTTP_PORT"
else
    echo "✓ Port $CLICKHOUSE_HTTP_PORT available for ClickHouse HTTP"
fi

# Check ClickHouse Native port (9000)
CLICKHOUSE_NATIVE_PORT=9000
if lsof -Pi :$CLICKHOUSE_NATIVE_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port $CLICKHOUSE_NATIVE_PORT is already in use"
    read -p "Enter alternative port for ClickHouse Native [9001]: " ALT_PORT
    CLICKHOUSE_NATIVE_PORT=${ALT_PORT:-9001}
    echo "   Using port: $CLICKHOUSE_NATIVE_PORT"
else
    echo "✓ Port $CLICKHOUSE_NATIVE_PORT available for ClickHouse Native"
fi

echo ""

# ============================================================================
# STEP 4: Create Configuration
# ============================================================================
echo "Step 4: Creating configuration..."
echo ""

cat > config.env << ENVEOF
# XRP Watchdog Configuration
# Generated by install.sh on $(date)

# Rippled Configuration
RIPPLED_CONTAINER=$RIPPLED_CONTAINER

# ClickHouse Ports
CLICKHOUSE_HTTP_PORT=$CLICKHOUSE_HTTP_PORT
CLICKHOUSE_NATIVE_PORT=$CLICKHOUSE_NATIVE_PORT

# ClickHouse Database
CLICKHOUSE_HOST=localhost
CLICKHOUSE_DB=xrp_watchdog

# Collection Settings
COLLECTION_BATCH_SIZE=50

# Auto-collection schedule (cron format)
CRON_SCHEDULE="*/15 * * * *"
ENVEOF

echo "✓ Configuration saved to config.env"
echo ""

# ============================================================================
# STEP 5: Setup Python Environment
# ============================================================================
echo "Step 5: Setting up Python environment..."
echo ""

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✓ Created virtual environment"
else
    echo "✓ Virtual environment exists"
fi

source venv/bin/activate

# Upgrade pip
pip install --upgrade pip > /dev/null 2>&1
echo "✓ Upgraded pip"

# Install dependencies
echo "Installing Python dependencies..."
pip install clickhouse-connect > /dev/null 2>&1
echo "✓ Installed clickhouse-connect"

echo ""

# ============================================================================
# STEP 6: Setup ClickHouse
# ============================================================================
echo "Step 6: Setting up ClickHouse database..."
echo ""

# Update docker-compose.yml with custom ports
cat > compose/docker-compose.yml << COMPOSEEOF
version: '3.8'

services:
  clickhouse:
    image: clickhouse/clickhouse-server:latest
    container_name: xrp-watchdog-clickhouse
    hostname: clickhouse
    ports:
      - "${CLICKHOUSE_HTTP_PORT}:8123"
      - "${CLICKHOUSE_NATIVE_PORT}:9000"
    volumes:
      - ../data/clickhouse:/var/lib/clickhouse
      - ../logs:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: xrp_watchdog
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    restart: unless-stopped
COMPOSEEOF

echo "✓ Updated docker-compose.yml"

# Start ClickHouse
cd compose
docker compose up -d
cd ..
echo "✓ Started ClickHouse container"

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse to be ready..."
for i in {1..30}; do
    if docker exec xrp-watchdog-clickhouse clickhouse-client -q "SELECT 1" > /dev/null 2>&1; then
        echo "✓ ClickHouse is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "✗ ClickHouse failed to start"
        exit 1
    fi
    sleep 1
done

# Create database schema
echo "Creating database schema..."
docker exec -i xrp-watchdog-clickhouse clickhouse-client --multiquery < sql/schema.sql
echo "✓ Database schema created"

echo ""

# ============================================================================
# STEP 7: Fix Permissions
# ============================================================================
echo "Step 7: Fixing directory permissions..."
echo ""

# Fix logs directory permissions
if [ -d "logs" ]; then
    chown -R $(whoami):$(whoami) logs 2>/dev/null || \
    sudo chown -R $(whoami):$(whoami) logs
    echo "✓ Fixed logs directory permissions"
fi

# Fix data directory permissions if needed
if [ -d "data" ]; then
    chmod -R u+w data 2>/dev/null || true
    echo "✓ Fixed data directory permissions"
fi

echo ""

# ============================================================================
# STEP 8: Setup Auto-Collection (Optional)
# ============================================================================
echo "Step 8: Setup automatic data collection..."
echo ""

read -p "Enable automatic collection every hour? (yes/no) [yes]: " ENABLE_CRON
ENABLE_CRON=${ENABLE_CRON:-yes}

if [ "$ENABLE_CRON" = "yes" ] || [ "$ENABLE_CRON" = "y" ]; then
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "xrp-watchdog"; then
        echo "⚠️  Cron job already exists, skipping"
    else
        # Add cron job
        (crontab -l 2>/dev/null; echo "# XRP Watchdog - Automatic data collection") | crontab -
        (crontab -l 2>/dev/null; echo "*/15 * * * * cd $INSTALL_DIR && source venv/bin/activate && python collectors/collection_orchestrator.py 13 >> logs/auto_collection.log 2>&1") | crontab -
        echo "✓ Cron job installed (runs every 15 minutes)"
    fi
else
    echo "⊘ Skipped cron setup (you can run collection manually)"
fi

echo ""

# ============================================================================
# STEP 9: Run Initial Collection
# ============================================================================
echo "Step 9: Running initial data collection..."
echo ""

read -p "Collect initial sample data (50 ledgers)? (yes/no) [yes]: " RUN_INITIAL
RUN_INITIAL=${RUN_INITIAL:-yes}

if [ "$RUN_INITIAL" = "yes" ] || [ "$RUN_INITIAL" = "y" ]; then
    echo "Collecting data (this will take ~15 seconds)..."
    python collectors/collection_orchestrator.py 13
    echo "✓ Initial collection complete"
else
    echo "⊘ Skipped initial collection"
fi

echo ""

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
echo "╔════════════════════════════════════════════════════════╗"
echo "║           Installation Complete! 🎉                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Rippled container: $RIPPLED_CONTAINER"
echo "  ClickHouse HTTP:   localhost:$CLICKHOUSE_HTTP_PORT"
echo "  ClickHouse Native: localhost:$CLICKHOUSE_NATIVE_PORT"
echo "  Install directory: $INSTALL_DIR"
echo ""
echo "Quick Start:"
echo "  1. Collect data manually:"
echo "     cd $INSTALL_DIR"
echo "     source venv/bin/activate"
echo "     python collectors/collection_orchestrator.py 13"
echo ""
echo "  2. View collected data:"
echo "     docker exec xrp-watchdog-clickhouse clickhouse-client -q \\"
echo "       \"SELECT COUNT(*) FROM xrp_watchdog.executed_trades\""
echo ""
echo "  3. Run detection queries:"
echo "     cat queries/04_market_impact_leaderboard.sql | \\"
echo "       docker exec -i xrp-watchdog-clickhouse clickhouse-client --multiquery"
echo ""
echo "  4. View auto-collection logs (if enabled):"
echo "     tail -f logs/auto_collection.log"
echo ""
echo "Documentation:"
echo "  - README.md (coming soon)"
echo "  - queries/ directory for detection queries"
echo "  - config.env for configuration"
echo ""
echo "To uninstall:"
echo "  ./uninstall.sh"
echo ""
echo "Happy hunting for wash traders! 🔍"
