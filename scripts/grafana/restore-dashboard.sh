#!/bin/bash
# Restore Grafana dashboard from backup

set -e

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check arguments
if [ -z "$1" ]; then
  echo "Usage: $0 <backup-file>"
  echo ""
  echo "Available backups:"
  ls -1t "$PROJECT_ROOT/grafana/backups/"dashboard-backup-*.json 2>/dev/null | head -10
  exit 1
fi

BACKUP_FILE="$1"

# Handle relative paths
if [[ ! "$BACKUP_FILE" = /* ]]; then
  BACKUP_FILE="$PROJECT_ROOT/grafana/backups/$BACKUP_FILE"
fi

# Verify backup exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Backup file not found: $BACKUP_FILE"
  exit 1
fi

# Show what we're restoring
VERSION=$(jq -r '.version' "$BACKUP_FILE")
TITLE=$(jq -r '.title' "$BACKUP_FILE")
echo "🔄 Restoring dashboard: $TITLE (version $VERSION)"
echo "   From: $BACKUP_FILE"

# Create restore payload
RESTORE_PAYLOAD=$(jq -n \
  --argjson dashboard "$(cat "$BACKUP_FILE")" \
  '{
    dashboard: $dashboard,
    overwrite: true,
    message: "Restored from backup"
  }')

# Push to Grafana API
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$RESTORE_PAYLOAD" \
  "$GRAFANA_URL/api/dashboards/db")

# Check response
if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null 2>&1; then
  NEW_VERSION=$(echo "$RESPONSE" | jq -r '.version')
  echo "✅ Dashboard restored successfully!"
  echo "   New version: $NEW_VERSION"
  echo "   URL: $GRAFANA_URL/d/$DASHBOARD_UID"
else
  echo "❌ Restore failed!"
  echo "$RESPONSE" | jq '.'
  exit 1
fi
