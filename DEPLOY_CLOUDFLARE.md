# XRP Watchdog - Cloudflare Deployment Guide

Complete guide for deploying the XRP Watchdog dashboard publicly using Cloudflare Tunnel and Workers.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Configuration Files](#configuration-files)
- [Deployment Steps](#deployment-steps)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

The public dashboard uses a three-tier architecture:

```
┌─────────────────────────────────────────────────────────┐
│                  Public Internet                        │
│              https://xrp-watchdog.grapedrop.xyz         │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTPS
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Cloudflare Worker (Edge)                    │
│  • Serves HTML page with iframe                         │
│  • Embeds dashboard with kiosk parameters               │
│  • Clean URL (no visible params)                        │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTP (internal)
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Cloudflare Tunnel                           │
│  • Secure tunnel to local server                        │
│  • Routes traffic to Grafana                            │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ localhost:3002
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Grafana Container                           │
│  • Dashboard backend                                    │
│  • Anonymous authentication                             │
│  • ClickHouse datasource                                │
└─────────────────────────────────────────────────────────┘
```

**Key Design:**
- Worker returns HTML page (stays at clean URL)
- HTML contains iframe embedding Grafana with `?kiosk&refresh=10s`
- No redirects visible to user
- Matches XRP Pulse architecture exactly

---

## Prerequisites

### Required Tools
- Docker & Docker Compose
- Cloudflared CLI (`cloudflared tunnel`)
- Wrangler CLI (`wrangler`)
- jq (for JSON manipulation)

### Cloudflare Account Setup
- Active Cloudflare account
- Domain managed by Cloudflare (`grapedrop.xyz`)
- Cloudflared authenticated: `cloudflared tunnel login`
- Wrangler authenticated: `wrangler login`

### Existing Infrastructure
- Grafana running on port 3002
- ClickHouse database with XRP Watchdog data
- Dashboard available at `/d/xrp-watchdog/xrp-watchdog`

---

## Directory Structure

```
/home/grapedrop/monitoring/
├── compose/
│   └── prod-grafana-watchdog/
│       ├── docker-compose.yaml         # Grafana container config
│       ├── custom.css                  # Custom styling
│       └── index.html                  # Modified Grafana index
├── provisioning/
│   └── prod-watchdog/
│       ├── dashboards/
│       │   └── xrp-watchdog-dashboard.json
│       └── datasources/
│           └── clickhouse.yaml
├── workers/
│   └── xrp-watchdog/
│       ├── src/
│       │   └── index.js                # Worker code
│       └── wrangler.toml               # Worker config
└── xrp-watchdog/
    └── grafana/
        └── xrp-watchdog-dashboard.json # Source dashboard

~/.cloudflared/
├── config-xrp-watchdog.yml             # Tunnel config
└── <tunnel-id>.json                    # Tunnel credentials
```

---

## Configuration Files

### 1. Grafana Docker Compose

**File:** `/home/grapedrop/monitoring/compose/prod-grafana-watchdog/docker-compose.yaml`

```yaml
name: prod-grafana-watchdog

services:
  grafana-prod-watchdog:
    image: grafana/grafana:11.2.0
    container_name: grafana-prod-watchdog
    network_mode: host
    restart: unless-stopped

    user: "472:0"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL

    environment:
      # Server
      GF_SERVER_HTTP_PORT: "3002"
      GF_SERVER_ROOT_URL: "https://xrp-watchdog.grapedrop.xyz"
      GF_SERVER_ENABLE_GZIP: "true"
      GF_LOG_MODE: "console"
      GF_LOG_LEVEL: "warn"

      # SQLite
      GF_DATABASE_TYPE: "sqlite3"
      GF_DATABASE_WAL: "true"

      # Data proxy
      GF_DATAPROXY_TIMEOUT: "90s"
      GF_DATAPROXY_DIAL_TIMEOUT: "10s"
      GF_DATAPROXY_KEEP_ALIVE_SECONDS: "120"
      GF_DATAPROXY_IDLE_CONN_TIMEOUT_SECONDS: "90"
      GF_DATAPROXY_TLS_HANDSHAKE_TIMEOUT_SECONDS: "10"
      GF_DATAPROXY_MAX_CONNS_PER_HOST: "256"
      GF_DATAPROXY_MAX_IDLE_CONNECTIONS: "512"

      # Auth / Kiosk
      GF_USERS_DEFAULT_THEME: "dark"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
      GF_AUTH_ANONYMOUS_ORG_NAME: "Main Org."
      GF_AUTH_DISABLE_LOGIN_FORM: "true"
      GF_AUTH_BASIC_ENABLED: "false"
      GF_SECURITY_ALLOW_EMBEDDING: "true"
      GF_PANELS_DISABLE_SANITIZE_HTML: "true"

      # Dashboards
      GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH: "/etc/grafana/provisioning/dashboards/xrp-watchdog-dashboard.json"

      # Metrics
      GF_METRICS_ENABLED: "true"
      GF_METRICS_DISABLE_TOTAL_STATS: "true"

    volumes:
      - /home/grapedrop/monitoring/data/grafana-prod-watchdog:/var/lib/grafana
      - /home/grapedrop/monitoring/provisioning/prod-watchdog:/etc/grafana/provisioning:ro
      - /home/grapedrop/monitoring/compose/prod-grafana-watchdog/custom.css:/usr/share/grafana/public/css/custom.css:ro
      - /home/grapedrop/monitoring/compose/prod-grafana-watchdog/index.html:/usr/share/grafana/public/views/index.html:ro

    ulimits:
      nofile:
        soft: 262144
        hard: 262144

    cpus: "2.0"
    mem_limit: "4g"

    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3002/api/health"]
      interval: 30s
      timeout: 5s
      retries: 5
```

**Key Settings:**
- `GF_SERVER_ROOT_URL`: Must match public domain
- `GF_AUTH_ANONYMOUS_ENABLED`: Enables public viewing
- `GF_AUTH_DISABLE_LOGIN_FORM`: Hides login UI
- `GF_SECURITY_ALLOW_EMBEDDING`: Allows iframe embedding

---

### 2. Cloudflare Tunnel Configuration

**File:** `~/.cloudflared/config-xrp-watchdog.yml`

```yaml
tunnel: a1aec802-96a1-4b36-b87f-0bfcf169c213
credentials-file: /home/grapedrop/.cloudflared/a1aec802-96a1-4b36-b87f-0bfcf169c213.json
connections: 4

ingress:
  - hostname: xrp-watchdog.grapedrop.xyz
    service: http://127.0.0.1:3002
  - service: http_status:404
```

**Notes:**
- `tunnel`: Your tunnel UUID (get from `cloudflared tunnel list`)
- `hostname`: Public domain name
- `service`: Local Grafana URL
- `connections`: Number of concurrent tunnel connections

---

### 3. Cloudflare Worker

**File:** `/home/grapedrop/monitoring/workers/xrp-watchdog/src/index.js`

```javascript
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "ok" }), {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    if (url.pathname === "/" || url.pathname === "/index.html") {
      const kiosk = "/d/xrp-watchdog/xrp-watchdog?kiosk&refresh=10s";
      const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>XRP Watchdog</title>
    <style>
      html,body,iframe{margin:0;padding:0;height:100%;width:100%;border:0;background:#000}
      body{overflow:hidden}
    </style>
  </head>
  <body>
    <iframe src="${kiosk}" allow="fullscreen" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
  </body>
</html>`;
      return new Response(html, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    return fetch(req);
  }
}
```

**How it works:**
1. Root path (`/`) returns HTML page with iframe
2. Iframe embeds Grafana dashboard with kiosk parameters
3. All other requests pass through to Grafana
4. URL stays clean in browser address bar

---

**File:** `/home/grapedrop/monitoring/workers/xrp-watchdog/wrangler.toml`

```toml
name = "xrp-watchdog-kiosk"
main = "src/index.js"
compatibility_date = "2025-11-07"

routes = [
  { pattern = "xrp-watchdog.grapedrop.xyz/*", zone_name = "grapedrop.xyz" }
]
```

**Configuration:**
- `name`: Worker name in Cloudflare dashboard
- `main`: Entry point (must be in `src/` directory)
- `routes`: Domain pattern to intercept

---

## Deployment Steps

### Step 1: Create Cloudflare Tunnel

```bash
# Create tunnel (only needed once)
cloudflared tunnel create xrp-watchdog

# Note the tunnel ID from output
# Example: a1aec802-96a1-4b36-b87f-0bfcf169c213
```

### Step 2: Configure DNS

**In Cloudflare Dashboard:**

1. Go to DNS settings for `grapedrop.xyz`
2. Add CNAME record:
   - **Type:** CNAME
   - **Name:** `xrp-watchdog`
   - **Target:** `a1aec802-96a1-4b36-b87f-0bfcf169c213.cfargotunnel.com`
   - **Proxy status:** Enabled (orange cloud)
   - **TTL:** Auto

**Important:** Replace tunnel ID with your actual tunnel ID.

### Step 3: Create Tunnel Config

```bash
# Create config file
cat > ~/.cloudflared/config-xrp-watchdog.yml <<'EOF'
tunnel: a1aec802-96a1-4b36-b87f-0bfcf169c213
credentials-file: /home/grapedrop/.cloudflared/a1aec802-96a1-4b36-b87f-0bfcf169c213.json
connections: 4

ingress:
  - hostname: xrp-watchdog.grapedrop.xyz
    service: http://127.0.0.1:3002
  - service: http_status:404
EOF

# Replace with your tunnel ID
```

### Step 4: Install Tunnel as Systemd Service

```bash
# Create service file
sudo tee /etc/systemd/system/cloudflared-xrp-watchdog.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel (xrp-watchdog)
After=network-online.target
Wants=network-online.target

[Service]
User=grapedrop
Group=grapedrop
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/grapedrop/.cloudflared/config-xrp-watchdog.yml run
Restart=always
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable cloudflared-xrp-watchdog
sudo systemctl start cloudflared-xrp-watchdog

# Check status
systemctl status cloudflared-xrp-watchdog
```

### Step 5: Create Worker Files

```bash
# Create directory structure
mkdir -p /home/grapedrop/monitoring/workers/xrp-watchdog/src

# Create worker code
cat > /home/grapedrop/monitoring/workers/xrp-watchdog/src/index.js <<'EOF'
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "ok" }), {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    if (url.pathname === "/" || url.pathname === "/index.html") {
      const kiosk = "/d/xrp-watchdog/xrp-watchdog?kiosk&refresh=10s";
      const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>XRP Watchdog</title>
    <style>
      html,body,iframe{margin:0;padding:0;height:100%;width:100%;border:0;background:#000}
      body{overflow:hidden}
    </style>
  </head>
  <body>
    <iframe src="${kiosk}" allow="fullscreen" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
  </body>
</html>`;
      return new Response(html, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    return fetch(req);
  }
}
EOF

# Create wrangler config
cat > /home/grapedrop/monitoring/workers/xrp-watchdog/wrangler.toml <<'EOF'
name = "xrp-watchdog-kiosk"
main = "src/index.js"
compatibility_date = "2025-11-07"

routes = [
  { pattern = "xrp-watchdog.grapedrop.xyz/*", zone_name = "grapedrop.xyz" }
]
EOF
```

### Step 6: Deploy Worker

```bash
# Navigate to worker directory
cd /home/grapedrop/monitoring/workers/xrp-watchdog

# Deploy worker
wrangler deploy

# Expected output:
# ⛅️ wrangler 4.37.1
# Total Upload: 1.25 KiB / gzip: 0.62 KiB
# Uploaded xrp-watchdog-kiosk (3.15 sec)
# Deployed xrp-watchdog-kiosk triggers (1.68 sec)
#   xrp-watchdog.grapedrop.xyz/* (zone name: grapedrop.xyz)
```

### Step 7: Fix Dashboard Datasource UID

```bash
# Update dashboard to use correct datasource
cd /home/grapedrop/monitoring/xrp-watchdog/grafana

# Replace old datasource UID with 'clickhouse'
sed -i 's/"uid": "ef1kycnokfoxsa"/"uid": "clickhouse"/g' xrp-watchdog-dashboard.json

# Copy to provisioning directory
cp xrp-watchdog-dashboard.json /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/

# Restart Grafana to reload dashboard
cd /home/grapedrop/monitoring/compose/prod-grafana-watchdog
docker compose restart
```

---

## Verification

### 1. Check Grafana Health

```bash
curl http://localhost:3002/api/health
# Expected: {"database":"ok","version":"11.2.0",...}
```

### 2. Check Tunnel Status

```bash
systemctl status cloudflared-xrp-watchdog
# Expected: Active (running)

# Check connections
systemctl status cloudflared-xrp-watchdog | grep "Registered tunnel connection"
# Expected: 4 connections
```

### 3. Check Worker Deployment

```bash
cd /home/grapedrop/monitoring/workers/xrp-watchdog
wrangler deployments list
# Should show recent deployment
```

### 4. Test Public URL

```bash
# Check worker health endpoint
curl https://xrp-watchdog.grapedrop.xyz/health
# Expected: {"status":"ok"}

# Check HTML response
curl https://xrp-watchdog.grapedrop.xyz/ | head -20
# Should show HTML with iframe
```

### 5. Browser Test

Visit: **https://xrp-watchdog.grapedrop.xyz**

**Expected:**
- ✅ URL stays clean (no redirect visible)
- ✅ Dashboard loads in full-screen kiosk mode
- ✅ No sidebar or admin UI visible
- ✅ Data displays correctly (charts, tables, stats)
- ✅ Main row expanded by default

---

## Troubleshooting

### Issue: "No data" in panels

**Cause:** Datasource UID mismatch

**Solution:**
```bash
# Check current datasource
curl -s http://localhost:3002/api/datasources | jq '.[] | select(.isDefault == true) | {name, uid}'

# Check dashboard datasource
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | jq '.dashboard.panels[3].targets[0].datasource'

# If UIDs don't match, update dashboard source files (see Step 7)
```

### Issue: Worker not intercepting requests

**Cause:** DNS CNAME conflicting with Worker route

**Solution:**
- Ensure only ONE DNS record exists: `xrp-watchdog` → tunnel
- Worker routes traffic to this domain
- Do NOT create separate origin domain

### Issue: Tunnel not connecting

**Check logs:**
```bash
sudo journalctl -u cloudflared-xrp-watchdog -f
```

**Common issues:**
- Wrong tunnel ID in config
- Credentials file missing
- Grafana not running on localhost:3002

**Restart tunnel:**
```bash
sudo systemctl restart cloudflared-xrp-watchdog
```

### Issue: "Ugly dashboard" (sidebar visible)

**Cause:** Kiosk mode not enabled

**Check:**
1. Verify Worker is deployed and active
2. Clear browser cache or use incognito mode
3. Check iframe has `?kiosk&refresh=10s` parameters

### Issue: Dashboard rows collapsed

**Solution:**
Update dashboard JSON to set `"collapsed": false` for main row, then restart Grafana.

---

## Maintenance

### Update Worker Code

```bash
cd /home/grapedrop/monitoring/workers/xrp-watchdog
# Edit src/index.js
wrangler deploy
```

### Update Dashboard

```bash
# Edit source dashboard
vi /home/grapedrop/monitoring/xrp-watchdog/grafana/xrp-watchdog-dashboard.json

# Copy to provisioning
cp /home/grapedrop/monitoring/xrp-watchdog/grafana/xrp-watchdog-dashboard.json \
   /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/

# Restart Grafana
cd /home/grapedrop/monitoring/compose/prod-grafana-watchdog
docker compose restart
```

### Restart Services

```bash
# Restart Grafana
cd /home/grapedrop/monitoring/compose/prod-grafana-watchdog
docker compose restart

# Restart tunnel
sudo systemctl restart cloudflared-xrp-watchdog

# Worker changes take effect immediately (no restart needed)
```

### View Logs

```bash
# Grafana logs
docker logs grafana-prod-watchdog -f

# Tunnel logs
sudo journalctl -u cloudflared-xrp-watchdog -f

# Worker logs
# View in Cloudflare dashboard: Workers & Pages → xrp-watchdog-kiosk → Logs
```

---

## Architecture Notes

### Why Iframe Instead of Redirect?

**Iframe approach (XRP Pulse style):**
- ✅ Clean URL stays in address bar
- ✅ No visible redirects
- ✅ Simple Worker code
- ✅ Full-screen experience

**Redirect approach (attempted initially):**
- ❌ Ugly URL with query params visible
- ❌ User sees redirect happening
- ❌ More complex Worker logic

### Why Not Use Origin Domain?

**Single domain (current):**
- Worker serves xrp-watchdog.grapedrop.xyz
- Tunnel serves same domain
- Worker intercepts and returns HTML
- Simpler architecture

**Dual domain (overcomplicated):**
- Worker serves xrp-watchdog.grapedrop.xyz
- Tunnel serves watchdog-origin.grapedrop.xyz
- Worker proxies to origin
- Extra DNS record needed
- More complex troubleshooting

---

## Related Documentation

- **Main Project:** `README.md`
- **Project Context:** `CLAUDE.md`
- **Grafana Docs:** https://grafana.com/docs/
- **Cloudflared Docs:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **Wrangler Docs:** https://developers.cloudflare.com/workers/wrangler/

---

## Support

**Maintainer:** @realGrapedrop
**Live Dashboard:** https://xrp-watchdog.grapedrop.xyz
**Validator:** https://xrp-validator.grapedrop.xyz

For issues, check the main project documentation or open an issue in the GitHub repository.
