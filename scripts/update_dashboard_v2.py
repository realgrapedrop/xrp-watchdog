#!/usr/bin/env python3
"""
Update Grafana dashboard to v2.0
- Replace Top 10 Suspicious Tokens query with Actionable Threats view
- Add new Research/Patterns panel
- Add volume threshold variable
"""

import json
import sys
from pathlib import Path

# Load queries
actionable_query = Path("queries/v2_risk_scoring.sql").read_text()
research_query = Path("queries/v2_research_view.sql").read_text()

# Load dashboard
dashboard_path = Path("grafana/xrp-watchdog-dashboard.json")
with open(dashboard_path) as f:
    dashboard = json.load(f)

print(f"📊 Loaded dashboard: {dashboard['title']} (version {dashboard['version']})")
print(f"   Panels: {len(dashboard['panels'])}")

# Find the table panel (ID 7)
table_panel = None
table_panel_index = None
for i, panel in enumerate(dashboard['panels']):
    if panel.get('id') == 7 and panel.get('type') == 'table':
        table_panel = panel
        table_panel_index = i
        break

if not table_panel:
    print("❌ Could not find table panel (ID 7)")
    sys.exit(1)

print(f"✅ Found table panel at index {table_panel_index}")

# Update table panel with v2.0 Actionable query
if 'targets' in table_panel and len(table_panel['targets']) > 0:
    old_query_preview = table_panel['targets'][0].get('rawSql', '')[:100]
    print(f"📝 Old query preview: {old_query_preview}...")

    table_panel['targets'][0]['rawSql'] = actionable_query
    table_panel['title'] = "🎯 Actionable Threats (≥10 XRP)"
    table_panel['description'] = "High-impact manipulation patterns with significant XRP volume. These tokens warrant immediate investigation."

    print("✅ Updated table panel with v2.0 Actionable query")
    print("   New title: 🎯 Actionable Threats (≥10 XRP)")
else:
    print("❌ Table panel has no targets")
    sys.exit(1)

# Update panel 13 (row) title
for panel in dashboard['panels']:
    if panel.get('id') == 13:
        panel['title'] = "📊 v2.0 Detection Results"
        print("✅ Updated row title to: 📊 v2.0 Detection Results")
        break

# Create new Research panel (copy of table panel with different query)
research_panel = json.loads(json.dumps(table_panel))  # Deep copy
research_panel['id'] = 20  # New ID
research_panel['title'] = "🔍 Research / Low Impact Patterns"
research_panel['description'] = "All high-risk behavioral patterns regardless of volume. Useful for research and early detection."
research_panel['targets'][0]['rawSql'] = research_query
research_panel['gridPos']['y'] = table_panel['gridPos']['y'] + table_panel['gridPos']['h'] + 1  # Position below

# Make it collapsible/hidden by default (collapsed row)
research_row = {
    "collapsed": True,
    "datasource": None,
    "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": research_panel['gridPos']['y']
    },
    "id": 21,
    "panels": [research_panel],
    "title": "🔬 Research: All High-Risk Patterns (Low Impact)",
    "type": "row"
}

# Insert research row after table panel
dashboard['panels'].insert(table_panel_index + 1, research_row)
print("✅ Added Research panel (collapsed row)")

# Increment version
dashboard['version'] += 1
print(f"📦 Incremented version: {dashboard['version'] - 1} → {dashboard['version']}")

# Save updated dashboard
output_path = Path("grafana/xrp-watchdog-dashboard-v2.json")
with open(output_path, 'w') as f:
    json.dump(dashboard, f, indent=2)

print(f"\n✅ Saved updated dashboard to: {output_path}")
print(f"   File size: {output_path.stat().st_size / 1024:.1f} KB")

# Validation
try:
    with open(output_path) as f:
        json.load(f)
    print("✅ JSON validation: OK")
except json.JSONDecodeError as e:
    print(f"❌ JSON validation failed: {e}")
    sys.exit(1)

print("\n🎉 Dashboard update complete!")
print("\nNext steps:")
print("1. Review: less grafana/xrp-watchdog-dashboard-v2.json")
print("2. Test push: bash scripts/grafana/update-dashboard.sh grafana/xrp-watchdog-dashboard-v2.json")
print("3. If broken: ./RESTORE_v1.sh")
