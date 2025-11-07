# Dev → Prod Dashboard Synchronization Guide

This guide explains how to develop dashboard changes in a dev environment and safely provision them to production.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Creating Grafana Service Account](#creating-grafana-service-account)
- [Synchronization Requirements](#synchronization-requirements)
- [Provisioning Workflow](#provisioning-workflow)
- [Troubleshooting](#troubleshooting)
- [Rollback Procedures](#rollback-procedures)

---

## Architecture Overview

### Two-Environment Setup

**Dev Grafana (Port 3000):**
- Purpose: Dashboard development and testing
- URL: `http://localhost:3000`
- Database: Shared ClickHouse (same as prod)
- Use case: Make UI changes, test queries, experiment with layouts

**Prod Grafana (Port 3002):**
- Purpose: Production public-facing dashboard
- URL: `http://localhost:3002` (proxied to `https://xrp-watchdog.grapedrop.xyz`)
- Database: Shared ClickHouse (same as dev)
- Use case: Stable, provisioned dashboard for public access

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Developer edits dashboard in Dev Grafana (port 3000)      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  provision-dev-to-prod.sh script                            │
│  ├─ Backs up production                                     │
│  ├─ Pulls dashboard JSON from dev via API                   │
│  ├─ Validates datasource UIDs                               │
│  ├─ Updates Git repository                                  │
│  ├─ Commits and pushes to GitHub                            │
│  └─ Provisions to prod + restarts Grafana                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  Production Grafana loads provisioned dashboard             │
│  Public URL: https://xrp-watchdog.grapedrop.xyz             │
└─────────────────────────────────────────────────────────────┘
```

### Key Concepts

**Dashboard Provisioning:**
Grafana loads dashboards from `/etc/grafana/provisioning/dashboards/` on startup. This is the "source of truth" for production.

**API Updates:**
Changes via API are temporary and will be overwritten on Grafana restart unless also saved to provisioning files.

**Git Source:**
The `grafana/xrp-watchdog-dashboard.json` file in the Git repository is the canonical source that gets provisioned to production.

---

## Prerequisites

### Required Software

1. **Two Grafana Instances Running:**
   ```bash
   # Dev Grafana
   docker ps | grep grafana-dev

   # Prod Grafana
   docker ps | grep grafana-prod-watchdog
   ```

2. **ClickHouse Database:**
   ```bash
   docker ps | grep clickhouse
   ```

3. **Git Repository:**
   - Local repo at: `/home/grapedrop/monitoring/xrp-watchdog`
   - Remote: `https://github.com/realgrapedrop/xrp-watchdog.git`

4. **Python 3 and jq:**
   ```bash
   which python3 jq
   ```

### Required Permissions

- **File System:** Write access to provisioning directory
- **Docker:** Ability to restart Grafana containers
- **Git:** Push access to repository
- **Grafana API:** Service account token (see next section)

---

## Creating Grafana Service Account

### Step 1: Access Service Accounts

1. Open dev Grafana: `http://localhost:3000`
2. Navigate to: **Administration** → **Service Accounts**
3. Click **"Add service account"**

### Step 2: Create Service Account

**Name:** `dashboard-provisioner`

**Display Name:** `Dashboard Provisioning Bot`

**Role:** `Editor`

**Why Editor?**
- Needs to read dashboards via API
- Needs to list datasources
- Does NOT need Admin (we're not creating users/orgs)

### Step 3: Generate Token

1. Click on the newly created service account
2. Click **"Add service account token"**
3. **Name:** `provision-script-token`
4. **Expiration:** Never (or set appropriate expiration for your security policy)
5. Click **"Generate token"**
6. **Copy the token** immediately (you won't see it again!)

**Token format:** `glsa_XXXXXXXXXXXXXXXXXXXXXXXXXXXX_XXXXXXXX`

### Step 4: Test Token

```bash
# Test token works
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  http://localhost:3000/api/user
```

**Expected response:**
```json
{
  "id": 2,
  "name": "dashboard-provisioner",
  "login": "sa-dashboard-provisioner",
  "email": "dashboard-provisioner@localhost",
  ...
}
```

### Step 5: Store Token

The provisioning script will prompt you for the token on first run and save it to:
```
/home/grapedrop/monitoring/xrp-watchdog/scripts/grafana/config.sh
```

**File permissions:** Automatically set to `600` (owner read/write only)

**Gitignored:** `config.sh` is in `.gitignore` to prevent committing secrets

---

## Synchronization Requirements

These items must match between dev and prod for clean provisioning:

### 1. ✅ Dashboard UID

**Must be:** `xrp-watchdog`

**Check in dev:**
```bash
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard.uid'
```

**Check in prod:**
```bash
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard.uid'
```

**Both should return:** `xrp-watchdog`

### 2. ✅ Datasource UID

**Must be:** `clickhouse` (for ClickHouse panels)

**Check dev dashboard:**
```bash
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard | .. | objects | select(has("datasource")) | .datasource | select(.uid) | .uid' | \
  sort -u
```

**Expected output:**
```
-- Grafana --
clickhouse
prometheus
```

**If you see different UIDs (e.g., `ef1kycnokfoxsa`)**, the script will fail validation.

#### How to Fix Datasource Mismatch

**Option A: Create matching datasource in dev**

1. Go to dev Grafana: `http://localhost:3000`
2. Configuration → Data Sources → Add data source
3. Select: **ClickHouse**
4. Configure:
   - Name: `ClickHouse`
   - **Important:** Set custom UID to `clickhouse` (in advanced settings)
   - Host: `localhost`
   - Port: `9000`
   - Protocol: `Native`
   - Default database: `xrp_watchdog`
   - Username: `default`
5. Save & test

**Option B: Update all panels in dev dashboard**

1. Open dashboard in dev Grafana
2. Edit each panel
3. Change datasource to the one with UID `clickhouse`
4. Save dashboard

**Option C: Use sed to fix dashboard JSON** (after export)

```bash
sed -i 's/"uid": "OLD_UID"/"uid": "clickhouse"/g' dashboard.json
```

### 3. ✅ Datasource Configuration

**Dev and prod must have a datasource with:**
- **Name:** Can differ
- **UID:** `clickhouse` (must match!)
- **Type:** `grafana-clickhouse-datasource`
- **Config:** Same ClickHouse connection (host, port, database)

**Check datasources:**

```bash
# Dev
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/datasources | \
  jq -r '.[] | select(.type == "grafana-clickhouse-datasource") | {name, uid, isDefault}'

# Prod
curl -s http://localhost:3002/api/datasources | \
  jq -r '.[] | select(.type == "grafana-clickhouse-datasource") | {name, uid, isDefault}'
```

### 4. Auto-Synced Items (No Action Needed)

These are automatically handled by the provisioning script:

- ✅ **Dashboard version** - Increments automatically
- ✅ **Dashboard ID** - Different per Grafana instance (dev=28, prod=2)
- ✅ **Panel IDs** - Preserved during import
- ✅ **Folder** - Dashboard is in root folder (no folder UID needed)

---

## Provisioning Workflow

### Quick Start

```bash
cd /home/grapedrop/monitoring/xrp-watchdog
./scripts/grafana/provision-dev-to-prod.sh
```

### Detailed Steps

#### Step 1: Make Changes in Dev

1. Open dev Grafana: `http://localhost:3000`
2. Open dashboard: XRP Watchdog
3. Make your changes:
   - Add/edit/delete panels
   - Change queries
   - Adjust layouts
   - Update styles (e.g., transparent backgrounds)
4. Save dashboard in Grafana UI

#### Step 2: Run Provisioning Script

```bash
cd /home/grapedrop/monitoring/xrp-watchdog
./scripts/grafana/provision-dev-to-prod.sh
```

#### Step 3: Script Execution

**The script will:**

1. **Check Token** (first run only)
   - Prompts for Grafana API token
   - Validates token
   - Saves to `config.sh` (chmod 600)

2. **Backup Production**
   ```
   📦 Step 1: Backing up production dashboard...
      ✅ Production backup: grafana/backups/prod-backup-TIMESTAMP.json
      ✅ Provisioning backup: .../xrp-watchdog-dashboard.json.backup-TIMESTAMP
   ```

3. **Pull from Dev**
   ```
   📥 Step 2: Pulling dashboard from dev Grafana...
      ✅ Pulled from dev (version: 72, panels: 15)
   ```

4. **Verify Datasource**
   ```
   🔍 Step 3: Verifying datasource UID...
      Datasource UIDs found: clickhouse
      ✅ Datasource UID 'clickhouse' confirmed
   ```

5. **Show Summary**
   ```
   📊 Step 4: Summary of changes...
      Transparent panels: 13
      Dashboard version: 72
   ```

6. **Update Git**
   ```
   📝 Step 5: Updating Git repository...
      ✅ Updated: grafana/xrp-watchdog-dashboard.json
   ```

7. **Preview Changes**
   ```
   🔍 Step 6: Git changes preview...
      Changes detected:
      grafana/xrp-watchdog-dashboard.json | 269 insertions(+), 257 deletions(-)
   ```

8. **Commit to GitHub** (interactive prompt)
   ```
   📤 Step 7: Commit and push to GitHub? (y/N): y
      [main abc1234] feat: Update dashboard from dev (v72)
      ✅ Pushed to GitHub
   ```

9. **Provision to Production**
   ```
   🚀 Step 8: Provisioning to production...
      ✅ Copied to: /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/
   ```

10. **Restart Grafana** (interactive prompt)
    ```
    🔄 Step 9: Restart production Grafana? (y/N): y
       Restarting Grafana container...
       ⏳ Waiting for Grafana to be ready...
       ✅ Grafana is ready!
    ```

11. **Verify Production**
    ```
    ✅ Step 10: Verifying production...
       Production Dashboard:
       - Version: 9
       - Transparent panels: 13
       - ClickHouse panels: 23

       ✅ Transparent count matches!
    ```

#### Step 4: Verify Live

Open production dashboard: https://xrp-watchdog.grapedrop.xyz

**Check:**
- ✅ All panels display data (no "Datasource not found" errors)
- ✅ Visual changes applied (e.g., transparent backgrounds)
- ✅ Queries return correct data
- ✅ No console errors in browser

---

## Troubleshooting

### Issue 1: "Datasource UID 'clickhouse' not found"

**Symptom:** Script validation fails at Step 3

**Cause:** Dev dashboard uses different datasource UID than production

**Fix:**
```bash
# Check what UID dev dashboard uses
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard | .. | objects | select(has("datasource")) | .datasource | select(.uid) | .uid' | \
  grep -v Grafana | grep -v prometheus

# If you see something other than "clickhouse", create matching datasource in dev
# OR update all panels in dev dashboard to use the correct datasource
```

See [Synchronization Requirements](#2--datasource-uid) for detailed fix.

### Issue 2: "Token validation failed"

**Symptom:** Script fails at startup with "Token validation failed!"

**Possible causes:**
1. Token expired (if you set expiration)
2. Service account was deleted
3. Token was revoked
4. Wrong Grafana URL (dev vs prod)

**Fix:**
```bash
# Delete invalid config
rm scripts/grafana/config.sh

# Re-run script (will prompt for new token)
./scripts/grafana/provision-dev-to-prod.sh
```

### Issue 3: Git push rejected (fetch first)

**Symptom:**
```
! [rejected]        main -> main (fetch first)
error: failed to push some refs
```

**Cause:** Remote has commits you don't have locally (e.g., changes from another machine)

**Fix:**
```bash
git pull --rebase
git push
```

**Script will handle this** if you answer `y` to commit prompt and it fails.

### Issue 4: Panels show "No data" after provisioning

**Symptom:** Dashboard loads but all panels show "No data"

**Possible causes:**
1. Datasource UID mismatch
2. ClickHouse is down
3. Queries have errors

**Debugging:**
```bash
# Check datasource UID in production dashboard
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard.panels[0].datasource'

# Check ClickHouse is running
docker ps | grep clickhouse

# Check ClickHouse has data
docker exec -it xrp-watchdog-clickhouse clickhouse-client -q \
  "SELECT count() FROM xrp_watchdog.token_stats"

# Check Grafana datasource health
curl -s http://localhost:3002/api/datasources/uid/clickhouse/health | jq '.'
```

### Issue 5: Grafana restart timeout

**Symptom:** Script waits 30 retries but Grafana doesn't respond

**Possible causes:**
1. Grafana container failed to start
2. Health check endpoint is broken
3. Port conflict

**Debugging:**
```bash
# Check container status
docker ps -a | grep grafana-prod-watchdog

# Check container logs
docker logs grafana-prod-watchdog --tail 50

# Check if port 3002 is listening
netstat -tlnp | grep 3002

# Manual restart
docker compose -f /home/grapedrop/monitoring/compose/prod-grafana-watchdog/docker-compose.yaml restart
```

### Issue 6: Changes not appearing in production

**Symptom:** Script completes successfully but changes aren't visible

**Possible causes:**
1. Browser cache (hard refresh: Ctrl+Shift+R)
2. Cloudflare cache (if using CDN)
3. Wrong dashboard opened (check UID in URL)

**Fix:**
```bash
# Hard refresh browser (Ctrl+Shift+R / Cmd+Shift+R)

# Verify dashboard version changed
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | jq -r '.dashboard.version'

# Check provisioned file was actually copied
ls -lah /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/xrp-watchdog-dashboard.json

# Check Grafana container has volume mounted
docker inspect grafana-prod-watchdog | jq -r '.[].Mounts[] | select(.Destination == "/etc/grafana/provisioning")'
```

---

## Rollback Procedures

### Scenario 1: Dashboard Broken After Provisioning

**Quick rollback:**

```bash
# Find your backup timestamp
ls -lth /home/grapedrop/monitoring/xrp-watchdog/grafana/backups/prod-backup-*.json | head -5

# Restore from backup (replace TIMESTAMP)
cp /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/xrp-watchdog-dashboard.json.backup-TIMESTAMP \
   /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/xrp-watchdog-dashboard.json

# Restart Grafana
docker compose -f /home/grapedrop/monitoring/compose/prod-grafana-watchdog/docker-compose.yaml restart
```

**Verify rollback:**
```bash
# Check version matches backup
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | jq -r '.dashboard.version'
```

### Scenario 2: Git Already Pushed, Need to Revert

**Revert the commit:**

```bash
# Find the commit hash
git log --oneline -5

# Revert the commit (creates new commit that undoes changes)
git revert COMMIT_HASH

# Push revert
git push

# Re-provision old version
./scripts/grafana/provision-dev-to-prod.sh
```

**OR reset to previous commit (if you haven't shared):**

```bash
git reset --hard HEAD~1  # Go back 1 commit
git push --force         # ⚠️ Use with caution!
```

### Scenario 3: Production Still Works, Just Redo Dev Changes

**No action needed on production!**

1. Fix changes in dev Grafana
2. Save dashboard
3. Re-run provisioning script

The backups are timestamped, so you can always compare:
```bash
# Compare current to backup
diff /home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/xrp-watchdog-dashboard.json \
     /home/grapedrop/monitoring/xrp-watchdog/grafana/backups/prod-backup-TIMESTAMP.json
```

---

## Best Practices

### 1. Always Test in Dev First

- Make changes in dev Grafana (port 3000)
- Verify queries return correct data
- Check panels render correctly
- Test on different screen sizes if public-facing

### 2. Use Descriptive Commit Messages

The script auto-generates commit messages like:
```
feat: Update dashboard from dev (v72)

- Transparent panels: 13
- Provisioned from dev Grafana
- Timestamp: 20251107-062122
```

These are good, but you can manually edit for more detail:
```bash
# After script runs, amend commit if needed
git commit --amend
```

### 3. Keep Backups

Backups are auto-created with timestamps. Clean up old ones periodically:

```bash
# Keep last 10 backups (auto-cleanup not implemented yet)
cd /home/grapedrop/monitoring/xrp-watchdog/grafana/backups
ls -t prod-backup-*.json | tail -n +11 | xargs rm
```

### 4. Document Major Changes

For significant dashboard changes, update `CHANGELOG.md` or create GitHub issues:

```bash
# After provisioning a major update
echo "## Dashboard v72 - 2025-11-07

- Added transparent backgrounds to 11 panels
- Improved visual clarity
- Synced datasource UIDs across environments

Provisioned via: ./scripts/grafana/provision-dev-to-prod.sh
" >> CHANGELOG.md
```

### 5. Monitor Production After Changes

After provisioning:

1. Check dashboard loads: https://xrp-watchdog.grapedrop.xyz
2. Check Grafana logs: `docker logs grafana-prod-watchdog --tail 100`
3. Check for errors in browser console (F12)
4. Verify data is updating (check timestamp on dashboard)

---

## Quick Reference

### Commands

```bash
# Provision dev to prod (full workflow)
./scripts/grafana/provision-dev-to-prod.sh

# Manual backup of production
curl -s http://localhost:3002/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard' > backup-$(date +%Y%m%d-%H%M%S).json

# Check dev datasource UIDs
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/dashboards/uid/xrp-watchdog | \
  jq -r '.dashboard | .. | objects | select(has("datasource")) | .datasource.uid' | sort -u

# Restart production Grafana
docker compose -f /home/grapedrop/monitoring/compose/prod-grafana-watchdog/docker-compose.yaml restart

# View production Grafana logs
docker logs grafana-prod-watchdog --tail 100 -f

# Test production datasource
curl -s http://localhost:3002/api/datasources/uid/clickhouse/health
```

### Files

| File | Purpose |
|------|---------|
| `scripts/grafana/provision-dev-to-prod.sh` | Main provisioning script |
| `scripts/grafana/config.sh` | API token storage (gitignored) |
| `grafana/xrp-watchdog-dashboard.json` | Git source of truth |
| `grafana/backups/prod-backup-*.json` | Production backups |
| `/home/grapedrop/monitoring/provisioning/prod-watchdog/dashboards/` | Prod provisioning dir |

### Ports

- **Dev Grafana:** `http://localhost:3000`
- **Prod Grafana:** `http://localhost:3002`
- **ClickHouse HTTP:** `http://localhost:8123`
- **ClickHouse Native:** `tcp://localhost:9000`

---

## Summary

**The provisioning workflow in 3 steps:**

1. **Edit** dashboard in dev Grafana (`http://localhost:3000`)
2. **Run** `./scripts/grafana/provision-dev-to-prod.sh`
3. **Verify** changes live at `https://xrp-watchdog.grapedrop.xyz`

**Safety guarantees:**
- ✅ Auto-backups before every change
- ✅ Datasource validation
- ✅ Git history for rollback
- ✅ Interactive prompts (commit, restart)
- ✅ Production verification

**Next time you need to update the dashboard, just run the script!** 🚀
