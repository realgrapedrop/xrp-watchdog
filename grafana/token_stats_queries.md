# Grafana Dashboard Queries for XRP Watchdog

Complete query reference for the XRP Watchdog Grafana dashboard, including all panels and visualizations.

## Overview Panel - Risk Score Statistics

**Query Name:** Risk Score Overview
**Visualization:** Stat Panel (3 columns)

```sql
SELECT
    COUNT(*) as "Total Tokens",
    ROUND(AVG(risk_score), 1) as "Avg Risk Score",
    SUM(IF(risk_score >= 60, 1, 0)) as "High Risk (≥60)"
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND total_trades >= 3
```

## Top Suspicious Tokens

**Query Name:** Top 20 High Risk Tokens
**Visualization:** Table

```sql
SELECT
    CASE
      WHEN length(token_code) = 40 THEN
        upper(replaceRegexpAll(unhex(token_code), '\0', ''))
      ELSE upper(token_code)
    END as "Token",
    token_issuer as "Issuer",
    ROUND(risk_score, 1) as "Risk Score",
    total_trades as "Trades",
    ROUND(total_xrp_volume, 0) as "Volume (XRP)",
    ROUND(price_variance_percent, 1) as "Price Var %",
    ROUND(trade_density, 1) as "Trades/Hour",
    ROUND(burst_score, 0) as "Burst",
    formatDateTime(last_updated, '%Y-%m-%d %H:%M') as "Updated"
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 0
  AND total_trades >= 3
ORDER BY risk_score DESC
LIMIT 20
```

**Panel Configuration:**
- **Hex Decoding**: Token codes in 40-character hex format are automatically decoded to ASCII (e.g., `0000000000000000000000004F504D0000000000` → "OPM")
- **Column Width**: Set "Issuer" column min width to 400px in Overrides to show full XRPL addresses
- **Sorting**: Add Transform → Sort by "Risk Score" (Descending) to ensure highest risk tokens appear first
- **Links**: Set "Issuer" column as clickable link to `https://xrpscan.com/account/${__value.raw}`

## Top Suspicious Accounts

**Query Name:** Accounts Trading High Risk Tokens
**Visualization:** Table

```sql
SELECT
    CASE
      WHEN length(token_code) = 40 THEN
        upper(replaceRegexpAll(unhex(token_code), '\0', ''))
      ELSE upper(token_code)
    END as "Token",
    taker as "Account",
    COUNT(DISTINCT tx_hash) as "Trades",
    ROUND(SUM(abs(exec_xrp)), 0) as "Volume (XRP)",
    MIN(time) as "First Seen",
    MAX(time) as "Last Seen"
FROM xrp_watchdog.executed_trades
WHERE (exec_iou_code, exec_iou_issuer) IN (
    SELECT token_code, token_issuer
    FROM xrp_watchdog.token_stats
    WHERE risk_score >= 60
      AND is_whitelisted = 0
    ORDER BY risk_score DESC
    LIMIT 10
)
GROUP BY token_code, taker
ORDER BY COUNT(DISTINCT tx_hash) DESC
LIMIT 30
```

**Panel Configuration:**
- **Column Width**: Set "Account" column min width to 400px to show full XRPL addresses
- **Links**: Set "Account" column as clickable link to `https://xrpscan.com/account/${__value.raw}`

## Whitelisted Tokens Panel

**Query Name:** Whitelisted Tokens
**Visualization:** Table

```sql
SELECT
    CASE
      WHEN length(token_code) = 40 THEN
        upper(replaceRegexpAll(unhex(token_code), '\0', ''))
      ELSE upper(token_code)
    END as "Token",
    token_issuer as "Issuer",
    whitelist_category as "Category",
    total_trades as "Trades",
    ROUND(total_xrp_volume, 0) as "Volume (XRP)",
    formatDateTime(last_updated, '%Y-%m-%d %H:%M') as "Updated"
FROM xrp_watchdog.token_stats
WHERE is_whitelisted = 1
ORDER BY total_xrp_volume DESC
```

**Panel Configuration:**
- **Column Width**: Set "Issuer" column min width to 400px to show full XRPL addresses
- **Links**: Set "Issuer" column as clickable link to `https://xrpscan.com/account/${__value.raw}`

## Methodology Guide / Learning Panel

**Query Name:** Educational Content
**Visualization:** Text (Markdown mode)
**Panel Type:** Collapsible Row

This panel provides educational content about wash trading detection, risk scoring methodology, and investigation techniques.

```html
<table style="width: 100%; border: none;">
<tr style="vertical-align: top;">
<td style="width: 33%; padding-right: 15px;">

## 🎯 What Are We Detecting?

**Token-level manipulation** on XRPL DEX using coordinated accounts to create artificial activity.

**Goal:** Make token appear popular/valuable
**Result:** Real traders buy inflated token, manipulators dump for profit

---

## 🎭 Manipulation Tactics

**Wash Trading:** Same entity trades with itself to fake volume

**Layering:** Fake orders create demand illusion

**Pump & Dump:** Coordinate buying, sell at peak

**Bot Campaigns:** Automated trading over days/weeks

**Examples from data:**
- GOAT: 257 trades/hour burst activity
- CHILLGUY: 1,151 trades, 2 unique accounts
- OPM: 530 XRP volume, 263 trades/hour

---

## ✅ Table Columns Explained

- **Token** - Which token is being manipulated
- **Risk Score** - 0-100 manipulation likelihood
- **Trades/Hour** - Activity density (bots = high)
- **Burst** - Rapid-fire trading score (0-100)
- **Price Var %** - Price consistency (low = suspicious)

---

## 📊 Detection Capabilities

**What We Catch & Monitor:**
- Automated bot campaigns
- Pump & dump schemes
- Coordinated wash trading
- Fake volume generation
- 100% ledger coverage
- Updates every 5 minutes

</td>
<td style="width: 33%; padding: 0 15px;">

## 🏮 Risk Score Algorithm (5 Components)

### 1. Volume (max 50 pts) 📈
Logarithmic scaling of XRP volume

**Why:** Large volumes can indicate manipulation, but prevents extreme outliers from dominating

### 2. Token Focus (max 30 pts) 🪙
How many unique accounts trade this token

**Points:** ≤2 accounts=30, ≤5=22, ≤10=15

**Why:** Manipulators use few accounts, real tokens have many traders

### 3. Price Stability (max 20 pts) 💵
Variance in trade prices

**Why:** Bots trade at precise prices; real markets have natural variance

### 4. Burst Detection (max 15 pts) ⚡
Trades per hour (temporal clustering)

**Points:** ≥100/hr=15, ≥50/hr=12, ≥20/hr=8

**Why:** Catches pump-and-dump schemes and bot bursts

### 5. Trade Uniformity (max 10 pts) 🤖
Consistency of trade sizes

**Why:** Bots trade uniform amounts; humans vary

---

## 📈 Score Example

**GOAT Token (Risk: 66)**
- Volume: 6 XRP → 5 pts
- Focus: 1 trader → 30 pts
- Price Var: Low → 16 pts
- Burst: 257/hr → 15 pts
- Uniformity: High → 0 pts
- **Total: 66 points**

</td>
<td style="width: 33%; padding-left: 15px;">

## 🔍 Investigation Guide

**Click Issuer → XRPScan**
View token issuer's transaction history, all tokens, counterparties

**Check Token Details:**
- New token? Low liquidity?
- Suspicious name or copycat?
- How many holders?

**Analyze Patterns:**
- **High Burst (≥75):** Pump & dump attempt
- **Low Price Var (<1%):** Bot-executed trades
- **Few Takers (≤5):** Coordinated manipulation
- **High Trades/Hour (≥50):** Automated campaign

---

## 🎯 Risk Tiers

- **CRITICAL (80-100)** - Very high likelihood
- **HIGH (70-79)** - Strong manipulation signals
- **MEDIUM (50-69)** - Moderate suspicious patterns
- **LOW (<50)** - Normal trading behavior

**Current Average:** 32.6 (healthy market)

---

## 🚨 Red Flags

- ✗ Only 1-2 unique traders
- ✗ Burst score ≥75
- ✗ Price variance <1%
- ✗ Trades/hour ≥100
- ✗ High volume, few traders

---

## ✅ Whitelist Status

**Legitimate tokens show Risk = 0**

Known legitimate tokens are whitelisted and excluded from risk scoring. Check the "Whitelisted Tokens" panel for established tokens.

**Categories include:**
- Established DEX tokens
- Known stablecoins
- Verified projects
- Long-standing issuers

</td>
</tr>
</table>
```

**Setup Instructions:**
1. Add a new **Text** panel
2. Select **Markdown** mode
3. Paste the HTML/markdown above
4. Set the panel to be **collapsed by default** using panel options
5. Title: "Methodology Guide (Click to Learn About Wash Trading)"

## Usage Instructions

### Setting up in Grafana:

1. **Create a new dashboard** or edit existing XRP Watchdog dashboard
2. **Add a new panel** for each query above
3. **Select ClickHouse as data source**
4. **Paste the SQL query** into the query editor
5. **Configure visualization** type as specified
6. **Set refresh interval** to 5 minutes (matches collection frequency)

### Recommended Dashboard Layout:

```
Row 1: Overview Stats (Stat Panel)
- Risk Score Overview (3 stats: Total Tokens, Avg Risk, High Risk Count)

Row 2: Main Tables
- Top Suspicious Tokens (20 rows)
- Top Suspicious Accounts (30 rows)

Row 3: Whitelisted Tokens
- Whitelisted Tokens Table

Row 4: Educational Content (Collapsed by default)
- Methodology Guide Panel (Text/Markdown)
```

### Panel Configuration Tips:

**Top Suspicious Tokens:**
- Enable **column sorting** for interactive exploration
- Set **"Issuer" column as a link**: `https://xrpscan.com/account/${__value.raw}`
- Use **conditional formatting** for Risk Score:
  - Red (≥70), Orange (60-69), Yellow (50-59), Blue (40-49), Green (<40)

**Top Suspicious Accounts:**
- Set **"Account" column as a link**: `https://xrpscan.com/account/${__value.raw}`
- Set **"Token" column as a link**: Use token issuer from joined data

**Risk Score Overview:**
- Use **Big Value** graph mode for stats
- Set color thresholds:
  - Avg Risk: Green (<40), Yellow (40-59), Orange (60-69), Red (≥70)
  - High Risk Count: Green (<5), Yellow (5-9), Orange (10-19), Red (≥20)

### Variables (Optional):

Add these dashboard variables for interactive filtering:

```
$min_trades: Minimum number of trades (default: 3)
$min_risk: Minimum risk score to display (default: 0)
```

Then use in queries like:
```sql
WHERE total_trades >= $min_trades
  AND risk_score >= $min_risk
```

## Data Freshness

- **Collection Frequency:** Every 5 minutes
- **Ledger Coverage:** 100% (130 ledgers per collection)
- **Analysis Latency:** Token stats updated after each collection (~40ms analyzer runtime)
- **Dashboard Refresh:** Recommended 5-minute auto-refresh

## Notes

- All queries exclude whitelisted tokens unless specifically querying the whitelist
- Token codes in hex format (40 characters) are automatically decoded to ASCII
- Risk scores are rounded to 1 decimal place for readability
- Timestamps use ClickHouse's `formatDateTime()` for consistent formatting
