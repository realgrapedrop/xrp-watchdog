#!/bin/bash
# Backup Grafana dashboard with timestamp

set -e

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Create backup directory
BACKUP_DIR="$PROJECT_ROOT/grafana/backups"
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/dashboard-backup-$TIMESTAMP.json"

# Fetch dashboard via API
echo "📦 Backing up dashboard: $DASHBOARD_UID"
curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | \
  jq -r '.dashboard' > "$BACKUP_FILE"

# Verify backup
if [ -s "$BACKUP_FILE" ]; then
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  VERSION=$(jq -r '.version' "$BACKUP_FILE")
  echo "✅ Backup created: $BACKUP_FILE"
  echo "   Size: $SIZE"
  echo "   Version: $VERSION"

  # Also update the main dashboard file
  cp "$BACKUP_FILE" "$PROJECT_ROOT/grafana/xrp-watchdog-dashboard.json"
  echo "✅ Updated: grafana/xrp-watchdog-dashboard.json"

  # Keep only last 10 backups
  cd "$BACKUP_DIR"
  ls -t dashboard-backup-*.json | tail -n +11 | xargs -r rm
  echo "🗑️  Cleaned old backups (keeping last 10)"
else
  echo "❌ Backup failed!"
  exit 1
fi
