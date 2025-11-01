# Grafana Dashboard Queries for Token Risk Scoring v1.0 vs v2.0

## Overview Panel - Risk Score Statistics

**Query Name:** Risk Score Overview
**Visualization:** Stat Panel (3 columns)

```sql
SELECT
    COUNT(*) as total_tokens,
    SUM(IF(risk_score_v2 >= 70, 1, 0)) as high_risk_v2,
    AVG(risk_score_v2) as avg_risk_v2
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
```

## Top Suspicious Tokens (v2.0)

**Query Name:** Top 20 High Risk Tokens
**Visualization:** Table

```sql
SELECT
    token_code,
    SUBSTRING(token_issuer, 1, 15) || '...' as issuer,
    total_trades,
    unique_takers,
    ROUND(total_xrp_volume, 0) as volume_xrp,
    ROUND(risk_score_v1, 1) as score_v1,
    ROUND(risk_score_v2, 1) as score_v2,
    ROUND(risk_score_v2 - risk_score_v1, 1) as score_diff,
    ROUND(trade_density, 1) as trades_per_hour,
    ROUND(burst_score, 0) as burst,
    last_updated
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
ORDER BY risk_score_v2 DESC
LIMIT 20
```

## Risk Score Comparison Histogram

**Query Name:** v1.0 vs v2.0 Score Distribution
**Visualization:** Bar Chart (Grouped)

```sql
SELECT
    CASE
        WHEN risk_score_v1 < 20 THEN '0-20'
        WHEN risk_score_v1 < 40 THEN '20-40'
        WHEN risk_score_v1 < 60 THEN '40-60'
        WHEN risk_score_v1 < 80 THEN '60-80'
        ELSE '80-100'
    END as score_range,
    COUNT(*) as count_v1
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
GROUP BY score_range
ORDER BY score_range

UNION ALL

SELECT
    CASE
        WHEN risk_score_v2 < 20 THEN '0-20'
        WHEN risk_score_v2 < 40 THEN '20-40'
        WHEN risk_score_v2 < 60 THEN '40-60'
        WHEN risk_score_v2 < 80 THEN '60-80'
        ELSE '80-100'
    END as score_range,
    COUNT(*) as count_v2
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
GROUP BY score_range
ORDER BY score_range
```

## Burst Detection - High Frequency Trading

**Query Name:** High Burst Score Tokens
**Visualization:** Table

```sql
SELECT
    token_code,
    SUBSTRING(token_issuer, 1, 15) || '...' as issuer,
    total_trades,
    ROUND(trade_density, 1) as trades_per_hour,
    ROUND(avg_time_gap_seconds, 1) as avg_gap_seconds,
    ROUND(burst_score, 0) as burst_score,
    ROUND(risk_score_v2, 1) as risk_v2
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND burst_score >= 50
ORDER BY burst_score DESC, trade_density DESC
LIMIT 20
```

## v1.0 vs v2.0 Score Scatter Plot

**Query Name:** Score Correlation
**Visualization:** Scatter Plot

```sql
SELECT
    risk_score_v1 as x_axis,
    risk_score_v2 as y_axis,
    token_code as label,
    total_trades as size
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND total_trades >= 10
```

## Whitelisted Tokens Panel

**Query Name:** Whitelisted Tokens
**Visualization:** Table

```sql
SELECT
    token_code,
    token_issuer,
    whitelist_category,
    total_trades,
    ROUND(total_xrp_volume, 0) as volume_xrp,
    last_updated
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 1
ORDER BY total_xrp_volume DESC
```

## Score Improvement/Degradation

**Query Name:** Biggest Score Changes
**Visualization:** Table (shows tokens where v2.0 differs most from v1.0)

```sql
-- Tokens with biggest score DECREASE (v2.0 is more lenient)
SELECT
    token_code,
    SUBSTRING(token_issuer, 1, 15) || '...' as issuer,
    total_trades,
    unique_takers,
    ROUND(risk_score_v1, 1) as v1_score,
    ROUND(risk_score_v2, 1) as v2_score,
    ROUND(risk_score_v2 - risk_score_v1, 1) as score_change,
    'More Lenient' as v2_effect
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND (risk_score_v2 - risk_score_v1) < -10
ORDER BY (risk_score_v2 - risk_score_v1) ASC
LIMIT 10

UNION ALL

-- Tokens with biggest score INCREASE (v2.0 is stricter)
SELECT
    token_code,
    SUBSTRING(token_issuer, 1, 15) || '...' as issuer,
    total_trades,
    unique_takers,
    ROUND(risk_score_v1, 1) as v1_score,
    ROUND(risk_score_v2, 1) as v2_score,
    ROUND(risk_score_v2 - risk_score_v1, 1) as score_change,
    'Stricter' as v2_effect
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND (risk_score_v2 - risk_score_v1) > 10
ORDER BY (risk_score_v2 - risk_score_v1) DESC
LIMIT 10
```

## Real-time Token Stats (Time Series)

**Query Name:** Token Risk Over Time
**Visualization:** Time Series Graph
**Note:** Requires storing historical token_stats snapshots

```sql
-- This is a placeholder - requires setting up a history table
-- For now, use current stats with last_updated timestamp
SELECT
    last_updated as time,
    token_code,
    risk_score_v2 as risk_score
FROM xrp_watchdog.token_stats
WHERE token_code IN (
    SELECT token_code FROM xrp_watchdog.token_stats
    WHERE is_whitelisted = 0
    ORDER BY risk_score_v2 DESC
    LIMIT 5
)
ORDER BY time ASC
```

## Algorithm Component Breakdown

**Query Name:** Risk Score Components (v2.0)
**Visualization:** Stacked Bar Chart

```sql
WITH components AS (
    SELECT
        token_code,
        -- Calculate individual component scores
        LEAST(50, log10(total_xrp_volume / 1000000.0 + 1) * 12.5) as volume_component,
        CASE
            WHEN unique_takers <= 2 THEN 30
            WHEN unique_takers <= 5 THEN 22
            WHEN unique_takers <= 10 THEN 15
            WHEN unique_takers <= 20 THEN 8
            ELSE 3
        END as concentration_component,
        CASE
            WHEN price_variance_percent < 0.5 THEN 20
            WHEN price_variance_percent < 1 THEN 16
            WHEN price_variance_percent < 3 THEN 12
            WHEN price_variance_percent < 5 THEN 8
            WHEN price_variance_percent < 10 THEN 4
            ELSE 1
        END as price_stability_component,
        CASE
            WHEN trade_density >= 100 THEN 15
            WHEN trade_density >= 50 THEN 12
            WHEN trade_density >= 20 THEN 8
            WHEN trade_density >= 10 THEN 5
            ELSE 2
        END as burst_component,
        risk_score_v2
    FROM xrp_watchdog.token_stats
    WHERE is_whitelisted = 0
      AND risk_score_v2 >= 50
    ORDER BY risk_score_v2 DESC
    LIMIT 10
)
SELECT
    token_code,
    ROUND(volume_component, 1) as volume,
    ROUND(concentration_component, 1) as concentration,
    ROUND(price_stability_component, 1) as price_stability,
    ROUND(burst_component, 1) as burst,
    ROUND(risk_score_v2, 1) as total
FROM components
```

## Usage Instructions

### Setting up in Grafana:

1. **Create a new dashboard** or edit existing XRP Watchdog dashboard
2. **Add a new panel** for each query above
3. **Select ClickHouse as data source**
4. **Paste the SQL query** into the query editor
5. **Configure visualization** type as specified
6. **Set refresh interval** to match your collection frequency (e.g., 5 minutes)

### Recommended Dashboard Layout:

```
Row 1: Overview Stats
- Total Tokens | High Risk Count | Average Risk Score

Row 2: Main Tables
- Top 20 High Risk Tokens (v2.0) | Biggest Score Changes

Row 3: Burst Detection
- High Burst Score Tokens | Trade Density Chart

Row 4: Comparisons
- v1.0 vs v2.0 Distribution | Score Correlation Scatter

Row 5: Whitelist & Components
- Whitelisted Tokens | Risk Score Component Breakdown
```

### Variables (Optional):

Add these dashboard variables for interactive filtering:

```
$min_trades: Minimum number of trades (default: 3)
$min_risk: Minimum risk score to display (default: 0)
$token_filter: Token code filter (default: %)
```

Then use in queries like:
```sql
WHERE total_trades >= $min_trades
  AND risk_score_v2 >= $min_risk
  AND token_code LIKE '$token_filter'
```
