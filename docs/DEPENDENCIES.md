# XRP Watchdog Dependencies

Complete list of all dependencies required for production and development environments.

---

## System Requirements

### Operating System
- **Ubuntu 20.04+** or similar Linux distribution
- **Kernel**: 6.14.0+ (tested with 6.14.0-32-generic)
- **Architecture**: x86_64

### Hardware Requirements

**Minimum (Development):**
- CPU: 2 cores
- RAM: 4 GB
- Disk: 20 GB

**Recommended (Production):**
- CPU: 4+ cores
- RAM: 8+ GB
- Disk: 100+ GB (for ClickHouse data growth)

---

## Core System Dependencies

### 1. Docker & Container Runtime
- **Docker**: v28.3.3 or later
  - Installation: https://docs.docker.com/get-docker/
- **Docker Compose**: v2.39.1 or later
  - Usually included with Docker Desktop
  - Standalone: https://docs.docker.com/compose/install/

**Usage:**
```bash
docker --version
docker compose version
```

### 2. Python Environment
- **Python**: 3.12.3 (tested) or 3.8+ (minimum)
- **pip**: Latest version (for package management)
- **venv**: Python virtual environment module

**Installation (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install python3 python3-pip python3-venv
```

### 3. System Utilities
- **curl**: 7.x+ (HTTP requests, health checks)
- **wget**: 1.x+ (File downloads, Grafana health checks)
- **jq**: 1.6+ (JSON processing in scripts)
- **git**: 2.x+ (Version control)

**Installation:**
```bash
sudo apt install curl wget jq git
```

---

## Python Dependencies

All Python packages installed in virtual environment (`venv/`):

### Production Runtime
| Package | Version | Purpose |
|---------|---------|---------|
| clickhouse-connect | 0.10.0 | ClickHouse database client |
| requests | 2.32.5 | HTTP library for XRPL API calls |
| pytz | 2025.2 | Timezone handling |
| certifi | 2025.11.12 | SSL certificate validation |
| urllib3 | 2.5.0 | HTTP client (requests dependency) |
| charset-normalizer | 3.4.4 | Character encoding detection |
| idna | 3.11 | Internationalized domain names |
| lz4 | 4.4.5 | Compression (ClickHouse dependency) |
| zstandard | 0.25.0 | Compression (ClickHouse dependency) |

### Installation
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install clickhouse-connect requests
```

**Note:** No `requirements.txt` currently exists. Dependencies are installed manually.

---

## Docker Containers

### Production Stack

#### 1. ClickHouse Database
```yaml
Image: clickhouse/clickhouse-server:24.3
Container: xrp-watchdog-clickhouse
Ports:
  - 8123 (HTTP interface)
  - 9000 (Native protocol)
Resources:
  - ulimits: 262144 file descriptors
Network: xrp-watchdog-network (bridge)
Health Check: SELECT 1 query every 10s
```

**Purpose:** Primary data storage for trades and risk analysis

#### 2. Grafana Production
```yaml
Image: grafana/grafana:11.2.0
Container: grafana-prod-watchdog
Port: 3002
Network Mode: host
User: 472:0 (grafana user)
Plugins:
  - grafana-clickhouse-datasource @ 4.11.2
Security:
  - no-new-privileges
  - All capabilities dropped
Resources:
  - CPU: 2.0
  - Memory: 4GB
  - ulimits: 262144 file descriptors
```

**Purpose:** Production dashboard visualization at https://xrp-watchdog.grapedrop.xyz

#### 3. Grafana Development
```yaml
Image: grafana/grafana:11.2.0
Container: grafana-dev
Port: 3000
Plugins:
  - grafana-clickhouse-datasource @ 4.11.2
```

**Purpose:** Development/testing environment for dashboard changes

### External Dependencies

#### XRP Ledger Full History Node
```yaml
Image: xrpllabsofficial/xrpld:2.6.1
Container: rippledvalidator
Purpose: Source of ledger data via RPC
Access: Local RPC endpoint
```

**Required for:** Fetching ledger data for trade collection

---

## Cloudflare Services

### 1. Cloudflare Tunnel (cloudflared)
- **Version**: 2025.10.0 (built 2025-10-14)
- **Binary**: `/usr/local/bin/cloudflared`
- **Purpose**: Secure tunnel for public dashboard access

**Installation:**
```bash
sudo curl -L --output /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo chmod +x /usr/local/bin/cloudflared
cloudflared tunnel login
```

**Systemd Service:**
- Service: `cloudflared-xrp-watchdog.service`
- Config: `~/.cloudflared/config-xrp-watchdog.yml`
- Connections: 4 concurrent tunnels to Cloudflare edge

### 2. Wrangler (Cloudflare Workers CLI)
- **Version**: 4.37.1
- **Binary**: `~/.nvm/versions/node/v22.17.1/bin/wrangler`
- **Purpose**: Deploy Cloudflare Workers for dashboard routing

**Installation:**
```bash
npm install -g wrangler
wrangler login
```

**Dependencies:**
- Node.js: v22.17.1
- npm: 11.6.0

---

## System Services

### Cron
- **Service**: `cron.service`
- **Purpose**: Automated data collection every 5 minutes
- **Cron Job:**
  ```
  */5 * * * * /home/grapedrop/projects/xrp-watchdog/run_collection.sh >> /home/grapedrop/projects/xrp-watchdog/logs/auto_collection.log 2>&1
  ```

**Verify:**
```bash
systemctl status cron
crontab -l
```

---

## Grafana Plugins

### ClickHouse Datasource Plugin
- **ID**: grafana-clickhouse-datasource
- **Version**: 4.11.2
- **Installation**: Automatically installed in container

**Manual Installation (if needed):**
```bash
docker exec grafana-prod-watchdog grafana cli plugins install grafana-clickhouse-datasource
docker restart grafana-prod-watchdog
```

---

## Network Dependencies

### Required Outbound Access

#### XRP Ledger Node (Local)
- **Protocol**: HTTP/HTTPS
- **Port**: Configured RPC port (typically 51234)
- **Purpose**: Fetch ledger data

#### Cloudflare Services
- **API**: https://api.cloudflare.com
- **Tunnel**: Outbound HTTPS (port 443) to Cloudflare edge
- **Workers**: https://workers.cloudflare.com (for deployment)

#### Python Package Repositories
- **PyPI**: https://pypi.org (pip packages)
- **Purpose**: Install Python dependencies

#### Docker Registries
- **Docker Hub**: https://hub.docker.com
  - `clickhouse/clickhouse-server`
  - `grafana/grafana`
- **XRP Ledger Labs**: https://hub.docker.com/u/xrpllabsofficial
  - `xrpllabsofficial/xrpld`

### Required Inbound Access

**None** - All services bind to localhost only. Public access via Cloudflare Tunnel.

**Local Development Ports:**
- `3000` - Grafana Dev (localhost only)
- `3002` - Grafana Prod (localhost only)
- `8123` - ClickHouse HTTP (localhost only)
- `9000` - ClickHouse Native (localhost only)

---

## Optional Development Tools

### Node.js & npm (for Cloudflare Workers)
- **Node.js**: v22.17.1
- **npm**: 11.6.0
- **nvm**: Node Version Manager (recommended)

**Installation:**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 22
nvm use 22
```

### Shell Scripting Dependencies
- **bash**: 5.x+ (script execution)
- **jq**: 1.6+ (JSON processing in getMakerTaker.sh)
- **grep, awk, sed**: Standard text processing

---

## Environment-Specific Dependencies

### Production Only
- **Cloudflare Tunnel**: Public access via `cloudflared-xrp-watchdog.service`
- **Cloudflare Worker**: Deployed at xrp-watchdog.grapedrop.xyz
- **Production Grafana**: Port 3002, anonymous auth enabled
- **Systemd Services**: Tunnel service auto-start on boot

### Development Only
- **Development Grafana**: Port 3000, admin access
- **Direct ClickHouse Access**: For query testing
- **Git**: For dashboard version control

---

## Dependency Installation Script

Quick installation of all system dependencies (Ubuntu/Debian):

```bash
#!/bin/bash
# Install XRP Watchdog dependencies

# System packages
sudo apt update
sudo apt install -y \
  python3 \
  python3-pip \
  python3-venv \
  curl \
  wget \
  jq \
  git \
  docker.io \
  docker-compose

# Enable Docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Install cloudflared
sudo curl -L --output /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo chmod +x /usr/local/bin/cloudflared

# Install nvm (Node.js version manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22

# Install Wrangler
npm install -g wrangler

# Python virtual environment
cd /home/grapedrop/projects/xrp-watchdog
python3 -m venv venv
source venv/bin/activate
pip install clickhouse-connect requests

echo "✓ All dependencies installed!"
echo "Note: Log out and back in for Docker group changes to take effect"
```

---

## Verification Commands

Check all dependencies are installed:

```bash
# System tools
docker --version
docker compose version
python3 --version
pip3 --version
jq --version
git --version

# Cloudflare tools
cloudflared --version
wrangler --version

# Node.js (if using Cloudflare Workers)
node --version
npm --version

# Docker containers
docker ps | grep -E 'clickhouse|grafana'

# Systemd services
systemctl status cron
systemctl status cloudflared-xrp-watchdog

# Python packages
source venv/bin/activate
pip list | grep -E 'clickhouse|requests'

# Grafana plugins
docker exec grafana-prod-watchdog grafana cli plugins ls
```

---

## Dependency Update Policy

### Critical Security Updates
- **Docker Images**: Update immediately for security patches
- **Python Packages**: Update within 1 week of CVE disclosure
- **System Packages**: Follow Ubuntu LTS security update schedule

### Feature Updates
- **Grafana**: Test in dev before updating production
- **ClickHouse**: Test with backup data before upgrading
- **Python Packages**: Test in dev environment first

### Update Commands

```bash
# Update Docker images
cd /home/grapedrop/projects/xrp-watchdog/compose
docker compose pull
docker compose up -d

# Update Python packages
source venv/bin/activate
pip install --upgrade clickhouse-connect requests

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update cloudflared
sudo curl -L --output /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo chmod +x /usr/local/bin/cloudflared
sudo systemctl restart cloudflared-xrp-watchdog

# Update Grafana plugins
docker exec grafana-prod-watchdog grafana cli plugins update-all
docker restart grafana-prod-watchdog
```

---

## Troubleshooting

### Missing Dependencies

**Problem**: "command not found" errors
```bash
# Verify all system tools
which docker jq curl wget git python3 pip3 cloudflared wrangler
```

**Problem**: Python packages not found
```bash
# Ensure virtual environment is activated
source /home/grapedrop/projects/xrp-watchdog/venv/bin/activate
pip list
```

**Problem**: Docker containers won't start
```bash
# Check Docker service
sudo systemctl status docker
# Check disk space
df -h
# Check container logs
docker logs xrp-watchdog-clickhouse
```

---

**Last Updated**: November 14, 2025
**System Tested**: Ubuntu 24.04 LTS (Noble) with Kernel 6.14.0-32-generic
