#!/bin/bash
# Emergency restore to v1.0 dashboard
# Run if v2.0 breaks something

echo "🔄 Restoring dashboard to v1.0 (backup: dashboard-backup-20251105-055753.json)"

bash /home/grapedrop/monitoring/xrp-watchdog/scripts/grafana/restore-dashboard.sh \
  grafana/backups/dashboard-backup-20251105-055753.json

echo "✅ Restored! Refresh Grafana at http://localhost:3000"
