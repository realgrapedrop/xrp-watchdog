#!/bin/bash
# Provision XRP Watchdog dashboard from Dev to Production
# Usage: ./provision-dev-to-prod.sh

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/home/grapedrop/monitoring/xrp-watchdog"
DASHBOARD_UID="xrp-watchdog"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Grafana URLs
DEV_URL="http://localhost:3000"
PROD_URL="http://localhost:3002"

# Token management
CONFIG_FILE="$SCRIPT_DIR/config.sh"

# Function to validate token
validate_token() {
  local url=$1
  local token=$2

  if curl -s -f -H "Authorization: Bearer $token" "$url/api/user" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to prompt for token
prompt_for_token() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Grafana API Token Required"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "To provision dashboards, you need a Grafana service account token."
  echo ""
  echo "📋 Required Permissions:"
  echo "   - Dashboards: Read, Write"
  echo "   - Folders: Read"
  echo ""
  echo "🔧 To create a token:"
  echo "   1. Go to: http://localhost:3000 → Administration → Service Accounts"
  echo "   2. Create a new service account (e.g., 'dashboard-provisioner')"
  echo "   3. Add role: Editor"
  echo "   4. Generate token and copy it"
  echo ""
  read -p "Enter your Grafana API token: " -r NEW_TOKEN
  echo ""

  # Validate token
  echo "🔍 Validating token..."
  if validate_token "$DEV_URL" "$NEW_TOKEN"; then
    echo "✅ Token is valid!"
    echo ""

    # Save to config file
    cat > "$CONFIG_FILE" << EOF
#!/bin/bash
# Grafana API configuration
# This file contains sensitive credentials - DO NOT commit to git

GRAFANA_URL="$DEV_URL"
GRAFANA_TOKEN="$NEW_TOKEN"
DASHBOARD_UID="$DASHBOARD_UID"
PROJECT_ROOT="$PROJECT_ROOT"
EOF

    chmod 600 "$CONFIG_FILE"
    echo "✅ Token saved to: $CONFIG_FILE"
    echo "   (File permissions set to 600 for security)"
    echo ""

    DEV_TOKEN="$NEW_TOKEN"
  else
    echo "❌ Token validation failed!"
    echo "   Please check your token and try again."
    exit 1
  fi
}

# Load config or prompt for token
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
  DEV_TOKEN="$GRAFANA_TOKEN"

  # Validate existing token
  if ! validate_token "$DEV_URL" "$DEV_TOKEN"; then
    echo "⚠️  Existing token in config.sh is invalid or expired."
    prompt_for_token
  fi
else
  prompt_for_token
fi

# Paths
BACKUPS_DIR="$PROJECT_ROOT/grafana/backups"
GIT_DASHBOARD="$PROJECT_ROOT/grafana/xrp-watchdog-dashboard.json"
PROVISIONING_DASHBOARD="/home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/xrp-watchdog-dashboard.json"
COMPOSE_FILE="/home/grapedrop/monitoring/compose/prod-grafana-watchdog/docker-compose.yaml"

echo "════════════════════════════════════════════════════════════════"
echo "  XRP Watchdog Dashboard: Dev → Prod Provisioning"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Backup Production
echo "📦 Step 1: Backing up production dashboard..."
mkdir -p "$BACKUPS_DIR"

curl -s "$PROD_URL/api/dashboards/uid/$DASHBOARD_UID" | \
  jq -r '.dashboard' > "$BACKUPS_DIR/prod-backup-$TIMESTAMP.json"

BACKUP_SIZE=$(du -h "$BACKUPS_DIR/prod-backup-$TIMESTAMP.json" | cut -f1)
echo "   ✅ Production backup: $BACKUPS_DIR/prod-backup-$TIMESTAMP.json ($BACKUP_SIZE)"

# Also backup provisioning file
cp "$PROVISIONING_DASHBOARD" "$PROVISIONING_DASHBOARD.backup-$TIMESTAMP"
echo "   ✅ Provisioning backup: $PROVISIONING_DASHBOARD.backup-$TIMESTAMP"
echo ""

# Step 2: Pull from Dev
echo "📥 Step 2: Pulling dashboard from dev Grafana..."
curl -s -H "Authorization: Bearer $DEV_TOKEN" \
  "$DEV_URL/api/dashboards/uid/$DASHBOARD_UID" | \
  jq -r '.dashboard' > /tmp/dashboard-from-dev.json

DEV_VERSION=$(jq -r '.version' /tmp/dashboard-from-dev.json)
DEV_PANELS=$(jq '[.panels[]] | length' /tmp/dashboard-from-dev.json)
echo "   ✅ Pulled from dev (version: $DEV_VERSION, panels: $DEV_PANELS)"
echo ""

# Step 3: Verify datasource UID
echo "🔍 Step 3: Verifying datasource UID..."
DATASOURCE_UIDS=$(jq -r '.. | objects | select(has("datasource")) | .datasource | select(.uid) | .uid' /tmp/dashboard-from-dev.json | sort -u | grep -v "Grafana" | grep -v "prometheus" || true)
echo "   Datasource UIDs found: $DATASOURCE_UIDS"

if echo "$DATASOURCE_UIDS" | grep -q "clickhouse"; then
  echo "   ✅ Datasource UID 'clickhouse' confirmed"
else
  echo "   ❌ ERROR: Expected datasource UID 'clickhouse' not found!"
  echo "   Found UIDs: $DATASOURCE_UIDS"
  exit 1
fi
echo ""

# Step 4: Show changes summary
echo "📊 Step 4: Summary of changes..."
TRANSPARENT_COUNT=$(jq -r '[.. | objects | select(has("transparent") and .transparent == true)] | length' /tmp/dashboard-from-dev.json)
echo "   Transparent panels: $TRANSPARENT_COUNT"
echo "   Dashboard version: $DEV_VERSION"
echo ""

# Step 5: Update Git source
echo "📝 Step 5: Updating Git repository..."
cp /tmp/dashboard-from-dev.json "$GIT_DASHBOARD"
echo "   ✅ Updated: $GIT_DASHBOARD"
echo ""

# Step 6: Git diff preview
echo "🔍 Step 6: Git changes preview..."
cd "$PROJECT_ROOT"
if git diff --quiet grafana/xrp-watchdog-dashboard.json; then
  echo "   ⚠️  No changes detected in Git"
else
  echo "   Changes detected:"
  git diff --stat grafana/xrp-watchdog-dashboard.json
fi
echo ""

# Step 7: Commit to GitHub (ask for confirmation)
read -p "📤 Step 7: Commit and push to GitHub? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  git add grafana/xrp-watchdog-dashboard.json
  git commit -m "feat: Update dashboard from dev (v$DEV_VERSION)

- Transparent panels: $TRANSPARENT_COUNT
- Provisioned from dev Grafana
- Timestamp: $TIMESTAMP"

  git push
  echo "   ✅ Pushed to GitHub"
else
  echo "   ⏭️  Skipped GitHub commit (you can commit manually later)"
fi
echo ""

# Step 8: Provision to production
echo "🚀 Step 8: Provisioning to production..."
cp "$GIT_DASHBOARD" "$PROVISIONING_DASHBOARD"
echo "   ✅ Copied to: $PROVISIONING_DASHBOARD"
echo ""

# Step 9: Restart Grafana
read -p "🔄 Step 9: Restart production Grafana? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "   Restarting Grafana container..."
  docker compose -f "$COMPOSE_FILE" restart

  echo "   ⏳ Waiting for Grafana to be ready..."
  sleep 10

  # Wait for health check
  MAX_RETRIES=30
  RETRY_COUNT=0
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s "$PROD_URL/api/health" | grep -q "ok"; then
      echo "   ✅ Grafana is ready!"
      break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "   Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
  done

  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "   ⚠️  Timeout waiting for Grafana (check manually)"
  fi
else
  echo "   ⏭️  Skipped restart (restart manually: docker compose -f $COMPOSE_FILE restart)"
fi
echo ""

# Step 10: Verify production
echo "✅ Step 10: Verifying production..."
PROD_VERSION=$(curl -s "$PROD_URL/api/dashboards/uid/$DASHBOARD_UID" | jq -r '.dashboard.version')
PROD_TRANSPARENT=$(curl -s "$PROD_URL/api/dashboards/uid/$DASHBOARD_UID" | jq -r '[.dashboard | .. | objects | select(has("transparent") and .transparent == true)] | length')
PROD_DATASOURCE=$(curl -s "$PROD_URL/api/dashboards/uid/$DASHBOARD_UID" | jq -r '.dashboard | .. | objects | select(has("datasource")) | .datasource | select(.uid) | .uid' | grep clickhouse | wc -l)

echo "   Production Dashboard:"
echo "   - Version: $PROD_VERSION"
echo "   - Transparent panels: $PROD_TRANSPARENT"
echo "   - ClickHouse panels: $PROD_DATASOURCE"
echo ""

if [ "$PROD_TRANSPARENT" = "$TRANSPARENT_COUNT" ]; then
  echo "   ✅ Transparent count matches!"
else
  echo "   ⚠️  Transparent count mismatch (expected: $TRANSPARENT_COUNT, got: $PROD_TRANSPARENT)"
fi
echo ""

# Final summary
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Provisioning Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🌐 Production: https://xrp-watchdog.grapedrop.xyz"
echo "📦 Backups:"
echo "   - $BACKUPS_DIR/prod-backup-$TIMESTAMP.json"
echo "   - $PROVISIONING_DASHBOARD.backup-$TIMESTAMP"
echo ""
echo "🔄 To rollback, run:"
echo "   cp $PROVISIONING_DASHBOARD.backup-$TIMESTAMP $PROVISIONING_DASHBOARD"
echo "   docker compose -f $COMPOSE_FILE restart"
echo ""
