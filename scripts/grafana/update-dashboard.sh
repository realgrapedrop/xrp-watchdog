#!/bin/bash
# Update Grafana dashboard from local JSON file

set -e

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DASHBOARD_FILE="$PROJECT_ROOT/grafana/xrp-watchdog-dashboard.json"

# Verify dashboard file exists
if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "❌ Dashboard file not found: $DASHBOARD_FILE"
  exit 1
fi

# Verify it's valid JSON
if ! jq empty "$DASHBOARD_FILE" 2>/dev/null; then
  echo "❌ Invalid JSON in dashboard file"
  exit 1
fi

echo "📤 Updating dashboard from: $DASHBOARD_FILE"

# Show current version
CURRENT_VERSION=$(jq -r '.version // "unknown"' "$DASHBOARD_FILE")
TITLE=$(jq -r '.title' "$DASHBOARD_FILE")
echo "   Title: $TITLE"
echo "   Current version: $CURRENT_VERSION"

# Create backup first
echo ""
echo "🔄 Creating backup before update..."
"$SCRIPT_DIR/backup-dashboard.sh"

echo ""
echo "📤 Pushing updated dashboard to Grafana..."

# Create update payload
UPDATE_PAYLOAD=$(jq -n \
  --argjson dashboard "$(cat "$DASHBOARD_FILE")" \
  '{
    dashboard: $dashboard,
    overwrite: true,
    message: "Updated via API script"
  }')

# Push to Grafana API
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$UPDATE_PAYLOAD" \
  "$GRAFANA_URL/api/dashboards/db")

# Check response
if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null 2>&1; then
  NEW_VERSION=$(echo "$RESPONSE" | jq -r '.version')
  DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url')
  echo "✅ Dashboard updated successfully!"
  echo "   New version: $NEW_VERSION"
  echo "   URL: $GRAFANA_URL$DASHBOARD_URL"
  echo ""
  echo "🔄 Refresh your browser to see changes!"
else
  echo "❌ Update failed!"
  echo "$RESPONSE" | jq '.'
  exit 1
fi
