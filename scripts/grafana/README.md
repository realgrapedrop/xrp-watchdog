# Grafana Dashboard Management Scripts

Helper scripts for managing the XRP Watchdog Grafana dashboard via API.

## Setup

1. Edit `config.sh` with your Grafana credentials (already configured)
2. The API token is stored in `config.sh` (DO NOT commit to git)

## Scripts

### 📦 backup-dashboard.sh
Creates a timestamped backup of the current dashboard from Grafana.

```bash
./backup-dashboard.sh
```

**What it does:**
- Fetches current dashboard via API
- Saves to `grafana/backups/dashboard-backup-YYYYMMDD-HHMMSS.json`
- Updates `grafana/xrp-watchdog-dashboard.json` with latest version
- Keeps only last 10 backups (auto-cleanup)

**Use case:** Before making any changes, run this to create a safety backup.

---

### 🔄 restore-dashboard.sh
Restores dashboard from a backup file.

```bash
# List available backups
./restore-dashboard.sh

# Restore from specific backup
./restore-dashboard.sh dashboard-backup-20251102-230500.json

# Or with full path
./restore-dashboard.sh /path/to/backup.json
```

**What it does:**
- Loads specified backup file
- Pushes to Grafana via API
- Overwrites current dashboard

**Use case:** Something broke? Instantly rollback to previous working version.

---

### 📤 update-dashboard.sh
Pushes local `grafana/xrp-watchdog-dashboard.json` to Grafana.

```bash
./update-dashboard.sh
```

**What it does:**
- Creates automatic backup first (safety!)
- Validates JSON syntax
- Pushes updated dashboard via API
- Shows new version number

**Use case:** After editing dashboard JSON locally, push changes to Grafana instantly.

---

## Workflow Example

### Scenario: Update panel description

```bash
# 1. Backup current version
./backup-dashboard.sh

# 2. Edit dashboard JSON
nano ../../grafana/xrp-watchdog-dashboard.json

# 3. Push changes to Grafana
./update-dashboard.sh

# 4. Refresh browser to see changes

# 5. If something broke, rollback
./restore-dashboard.sh dashboard-backup-20251102-230500.json
```

---

## Security Notes

- **config.sh** contains API token - keep secure!
- Token has Editor permissions for dashboards
- Can be revoked anytime in Grafana: Administration → Service accounts
- Backups are stored locally (not in git)

---

## Backup Management

- Backups stored in: `../../grafana/backups/`
- Auto-cleanup keeps last 10 backups
- Manual cleanup: `rm grafana/backups/dashboard-backup-*.json`
- Backups include full dashboard state (panels, queries, settings)

---

## Troubleshooting

**"curl: (6) Could not resolve host"**
- Use `localhost:3000` instead of `ubuntu.grapedrop.xyz:3000`
- Scripts already configured correctly

**"401 Unauthorized"**
- Check API token in `config.sh`
- Verify token is still active in Grafana

**"Invalid JSON"**
- Run: `jq empty grafana/xrp-watchdog-dashboard.json`
- Fix syntax errors before pushing

---

## Development Workflow

These scripts enable fast iteration:
1. Make changes to dashboard JSON locally
2. Run `update-dashboard.sh` to push changes
3. Refresh browser to see updates instantly
4. If issues arise, run `restore-dashboard.sh` to rollback
5. No more manual export/SCP/import cycle!

**Speed improvement:** 30 seconds → 3 seconds per iteration 🚀
