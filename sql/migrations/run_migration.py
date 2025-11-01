#!/usr/bin/env python3
"""
Run SQL migration scripts
"""
import sys
import clickhouse_connect

CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = 8123
CLICKHOUSE_DB = "xrp_watchdog"

def run_migration(migration_file: str):
    """Run a SQL migration file"""
    print(f"Running migration: {migration_file}")

    # Read migration file
    with open(migration_file, 'r') as f:
        sql_content = f.read()

    # Remove comments and split into statements
    # ClickHouse doesn't support multi-statement execution well,
    # so we need to execute each CREATE TABLE separately
    statements = []
    current_statement = []
    in_comment_block = False

    for line in sql_content.split('\n'):
        # Skip comment blocks
        if '/*' in line:
            in_comment_block = True
        if '*/' in line:
            in_comment_block = False
            continue
        if in_comment_block:
            continue

        # Skip single-line comments
        if line.strip().startswith('--'):
            continue

        # Collect statement
        if line.strip():
            current_statement.append(line)

        # Check if statement is complete (ends with semicolon)
        if line.strip().endswith(';'):
            stmt = '\n'.join(current_statement)
            if stmt.strip():
                statements.append(stmt)
            current_statement = []

    # Connect to ClickHouse
    client = clickhouse_connect.get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        database=CLICKHOUSE_DB
    )

    # Execute each statement
    for i, stmt in enumerate(statements, 1):
        try:
            # Extract statement type for logging
            stmt_type = stmt.strip().split()[0:3]
            stmt_desc = ' '.join(stmt_type)
            print(f"  [{i}/{len(statements)}] Executing: {stmt_desc}...")

            client.command(stmt)
            print(f"  ✓ Success")
        except Exception as e:
            print(f"  ✗ Error: {e}")
            # Continue on error (some statements may already exist)
            continue

    print(f"\n✓ Migration complete!")

    # Verify table was created
    result = client.query("SELECT name, engine FROM system.tables WHERE database = 'xrp_watchdog' AND name = 'token_stats'")
    if result.result_rows:
        name, engine = result.result_rows[0]
        print(f"✓ Table 'token_stats' created with engine: {engine}")
    else:
        print("⚠ Warning: token_stats table not found")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        migration_file = sys.argv[1]
    else:
        migration_file = "/home/grapedrop/monitoring/xrp-watchdog/sql/migrations/001_add_token_stats_v2.sql"

    run_migration(migration_file)
