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

# Check if ClickHouse is already running
CLICKHOUSE_RUNNING=false

# Check for ClickHouse container
if docker ps --format '{{.Names}}' | grep -q clickhouse 2>/dev/null; then
    EXISTING_CONTAINER=$(docker ps --format '{{.Names}}' | grep clickhouse | head -1)
    echo "✓ Found existing ClickHouse container: $EXISTING_CONTAINER"
    CLICKHOUSE_RUNNING=true
# Check for ClickHouse service/process
elif command -v clickhouse-client &> /dev/null && clickhouse-client -q "SELECT 1" &> /dev/null; then
    echo "✓ Found existing ClickHouse installation (running as service)"
    CLICKHOUSE_RUNNING=true
fi

if [ "$CLICKHOUSE_RUNNING" = true ]; then
    read -p "Use existing ClickHouse installation? (yes/no) [yes]: " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-yes}

    if [ "$USE_EXISTING" = "yes" ] || [ "$USE_EXISTING" = "y" ]; then
        echo "✓ Using existing ClickHouse installation"
        SKIP_CLICKHOUSE_INSTALL=true
    else
        echo "Will install new ClickHouse container..."
        SKIP_CLICKHOUSE_INSTALL=false
    fi
else
    echo "No ClickHouse installation detected."
    read -p "Install ClickHouse via Docker? (yes/no) [yes]: " INSTALL_CLICKHOUSE
    INSTALL_CLICKHOUSE=${INSTALL_CLICKHOUSE:-yes}

    if [ "$INSTALL_CLICKHOUSE" != "yes" ] && [ "$INSTALL_CLICKHOUSE" != "y" ]; then
        echo "✗ ClickHouse is required. Please install it manually."
        echo "  https://clickhouse.com/docs/en/install"
        exit 1
    fi
    SKIP_CLICKHOUSE_INSTALL=false
fi

echo ""

# ============================================================================
# STEP 7: Setup Grafana (Optional)
# ============================================================================
echo "Step 7: Setting up Grafana (optional)..."
echo ""

# Check if Grafana is already running
GRAFANA_RUNNING=false

# Check for Grafana container
if docker ps --format '{{.Names}}' | grep -q grafana 2>/dev/null; then
    EXISTING_GRAFANA=$(docker ps --format '{{.Names}}' | grep grafana | head -1)
    echo "✓ Found existing Grafana container: $EXISTING_GRAFANA"
    GRAFANA_RUNNING=true
# Check for Grafana service
elif systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo "✓ Found existing Grafana installation (running as service)"
    GRAFANA_RUNNING=true
# Check if Grafana is listening on port 3000
elif lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ Found Grafana running on port 3000"
    GRAFANA_RUNNING=true
fi

INSTALL_GRAFANA=false
GRAFANA_PORT=3000

if [ "$GRAFANA_RUNNING" = true ]; then
    echo "Grafana is already installed and running."
    read -p "Skip Grafana installation? (yes/no) [yes]: " SKIP_GRAFANA
    SKIP_GRAFANA=${SKIP_GRAFANA:-yes}

    if [ "$SKIP_GRAFANA" = "yes" ] || [ "$SKIP_GRAFANA" = "y" ]; then
        echo "⊘ Skipping Grafana installation (using existing)"
    else
        INSTALL_GRAFANA=true
    fi
else
    echo "No Grafana installation detected."
    echo ""
    echo "Grafana provides a beautiful dashboard for visualizing wash trading data."
    echo "Recommended: Grafana 11.2+ with ClickHouse datasource plugin"
    echo ""
    read -p "Install Grafana via Docker? (yes/no) [yes]: " INSTALL_GRAFANA_CHOICE
    INSTALL_GRAFANA_CHOICE=${INSTALL_GRAFANA_CHOICE:-yes}

    if [ "$INSTALL_GRAFANA_CHOICE" = "yes" ] || [ "$INSTALL_GRAFANA_CHOICE" = "y" ]; then
        INSTALL_GRAFANA=true

        # Check if port 3000 is available
        if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo "⚠️  Port 3000 is already in use"
            read -p "Enter alternative port for Grafana [3001]: " ALT_PORT
            GRAFANA_PORT=${ALT_PORT:-3001}
        fi
    else
        echo "⊘ Skipping Grafana installation (you can install it later)"
    fi
fi

echo ""

# ============================================================================
# STEP 8: Create Docker Compose Configuration
# ============================================================================
echo "Step 8: Creating Docker Compose configuration..."
echo ""

# Build docker-compose.yml based on what needs to be installed
cat > compose/docker-compose.yml << COMPOSEEOF
version: '3.8'

services:
COMPOSEEOF

# Add ClickHouse service if needed
if [ "$SKIP_CLICKHOUSE_INSTALL" = false ]; then
    cat >> compose/docker-compose.yml << CLICKHOUSEEOF
  clickhouse:
    image: clickhouse/clickhouse-server:latest
    container_name: xrp-watchdog-clickhouse
    hostname: clickhouse
    ports:
      - "$CLICKHOUSE_HTTP_PORT:8123"
      - "$CLICKHOUSE_NATIVE_PORT:9000"
    volumes:
      - ../data/clickhouse:/var/lib/clickhouse
      - ../logs/clickhouse:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: xrp_watchdog
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    restart: unless-stopped
CLICKHOUSEEOF
fi

# Add Grafana service if needed
if [ "$INSTALL_GRAFANA" = true ]; then
    cat >> compose/docker-compose.yml << 'GRAFANAEOF'
  grafana:
    image: grafana/grafana:11.2.0
    container_name: xrp-watchdog-grafana
    ports:
      - "GRAFANAEOF
    echo "      - \"$GRAFANA_PORT:3000\"" >> compose/docker-compose.yml
    cat >> compose/docker-compose.yml << 'GRAFANAEOF'
    volumes:
      - ../data/grafana:/var/lib/grafana
    environment:
      - GF_INSTALL_PLUGINS=grafana-clickhouse-datasource
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
GRAFANAEOF

    # Only add depends_on if ClickHouse is being installed via Docker
    if [ "$SKIP_CLICKHOUSE_INSTALL" = false ]; then
        cat >> compose/docker-compose.yml << 'GRAFANAEOF'
    depends_on:
      - clickhouse
GRAFANAEOF
    fi

    cat >> compose/docker-compose.yml << 'GRAFANAEOF'
    restart: unless-stopped
GRAFANAEOF
fi

echo "✓ Created docker-compose.yml"

# Start services
if [ "$SKIP_CLICKHOUSE_INSTALL" = false ] || [ "$INSTALL_GRAFANA" = true ]; then
    echo "Starting Docker services..."
    cd compose
    docker compose up -d
    cd ..

    if [ "$SKIP_CLICKHOUSE_INSTALL" = false ]; then
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
    fi

    if [ "$INSTALL_GRAFANA" = true ]; then
        echo "✓ Started Grafana container"
        echo ""
        echo "Grafana Access:"
        echo "  URL:      http://localhost:$GRAFANA_PORT"
        echo "  Username: admin"
        echo "  Password: admin (change on first login)"
        echo ""
        echo "Note: ClickHouse datasource plugin will be installed automatically."
        echo "      Import dashboard from: grafana/xrp-watchdog-dashboard.json"
    fi
fi

echo ""

# ============================================================================
# STEP 9: Fix Permissions
# ============================================================================
echo "Step 9: Fixing directory permissions..."
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
# STEP 10: Setup Auto-Collection (Optional)
# ============================================================================
echo "Step 10: Setup automatic data collection..."
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
# STEP 11: Run Initial Collection
# ============================================================================
echo "Step 11: Running initial data collection..."
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
if [ "$INSTALL_GRAFANA" = true ]; then
    echo "  Grafana URL:       http://localhost:$GRAFANA_PORT"
fi
echo "  Install directory: $INSTALL_DIR"
echo ""

if [ "$INSTALL_GRAFANA" = true ]; then
    echo "Grafana Dashboard:"
    echo "  1. Open http://localhost:$GRAFANA_PORT"
    echo "  2. Login with admin/admin (change password on first login)"
    echo "  3. Go to Dashboards → Import"
    echo "  4. Upload: grafana/xrp-watchdog-dashboard.json"
    echo "  5. Select ClickHouse datasource and import"
    echo ""
fi

echo "Quick Start:"
echo "  1. Collect data manually:"
echo "     cd $INSTALL_DIR"
echo "     source venv/bin/activate"
echo "     python collectors/collection_orchestrator.py 130 --analyze"
echo ""
echo "  2. View token risk scores:"
echo "     python analyzers/token_analyzer.py"
echo ""
echo "  3. Check storage usage:"
echo "     python scripts/check_storage.py"
echo ""
echo "  4. View auto-collection logs (if enabled):"
echo "     tail -f logs/auto_collection.log"
echo ""
echo "Documentation:"
echo "  - README.md - Complete project documentation"
echo "  - CLAUDE.md - Developer documentation"
echo "  - docs/STORAGE_MANAGEMENT.md - Storage and retention guide"
echo "  - grafana/token_stats_queries.md - Dashboard query reference"
echo ""
echo "To uninstall:"
echo "  ./uninstall.sh"
echo ""
echo "Happy hunting for wash traders! 🔍"
