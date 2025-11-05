# XRP Watchdog Risk Scoring Algorithm

## Overview

XRP Watchdog is a real-time wash trading and market manipulation detection system for the XRP Ledger (XRPL) decentralized exchange. This document describes the risk scoring algorithm used to identify suspicious trading patterns.

**Current Version:** 2.0 (November 2025)
**Status:** Production Deployment (Implemented November 5, 2025)
**Maintainer:** @realGrapedrop

**v2.0 Changes:**
- Volume component: 50 → 60 points max
- Dual-window scoring: 24h patterns + 7d impact assessment
- Impact Factor: Smooth logarithmic curve (0-1.0)
- Final Priority = Risk Score × Impact Factor
- Minimum trades: 3 → 5 (reduces noise)
- Two-view dashboard: Actionable (≥10 XRP) + Research (all patterns)

---

## Algorithm Design Philosophy

The algorithm assigns a **Risk Score (0-100)** to tokens based on trading patterns that indicate potential market manipulation. The score combines multiple components:

1. **Volume Component** (max 50 points) - Scale of trading activity
2. **Token Focus Component** (max 30 points) - Account concentration
3. **Price Stability Component** (max 20 points) - Bot-like precision
4. **Burst Detection Component** (max 15 points) - Temporal clustering
5. **Trade Size Uniformity Component** (max 10 points) - Robotic patterns

**Total Maximum:** 125 points (capped at 100)

---

## Component Breakdown

### 1. Volume Component (Max 50 Points)

**Purpose:** Measure the scale of trading activity.

**Formula:**
```python
volume_score = min(50, log10(total_xrp_volume / 1_000_000 + 1) * 12.5)
```

**Rationale:**
- Logarithmic scaling prevents extreme outliers from dominating
- Manipulation requires sufficient volume to be impactful
- Small trades (<1 XRP) receive minimal weight

**Examples:**
| XRP Volume | Score |
|------------|-------|
| 0.1 XRP | 0.0 |
| 1 XRP | 0.4 |
| 10 XRP | 5.0 |
| 100 XRP | 12.5 |
| 1,000 XRP | 18.8 |
| 10,000 XRP | 31.3 |
| 100,000 XRP | 43.8 |
| 1,000,000 XRP | 50.0 |

**Known Issue:**
- Current implementation caps at 50 points, which may underweight large-volume manipulation
- Consideration: Should volume have higher max (60-70 points)?

---

### 2. Token Focus Component (Max 30 Points)

**Purpose:** Detect account concentration on a single token.

**Formula:**
```python
if unique_takers <= 2:  score += 30
elif unique_takers <= 5:  score += 22
elif unique_takers <= 10: score += 15
elif unique_takers <= 20: score += 8
else: score += 3
```

**Rationale:**
- Normal traders diversify across multiple tokens
- Wash traders focus on single tokens to manipulate
- Few accounts = higher concentration = higher suspicion

**Examples:**
| Unique Traders | Score | Interpretation |
|----------------|-------|----------------|
| 1 | 30 | Single account monopoly |
| 2 | 30 | Potential wash trading pair |
| 5 | 22 | Small concentrated group |
| 10 | 15 | Moderate concentration |
| 20 | 8 | Some concentration |
| 50+ | 3 | Normal distribution |

---

### 3. Price Stability Component (Max 20 Points)

**Purpose:** Detect bot-like trading precision.

**Formula:**
```python
price_variance_pct = (price_stddev / avg_price) * 100

if price_variance_pct < 0.5:  score += 20  # Extreme precision
elif price_variance_pct < 1:  score += 16
elif price_variance_pct < 3:  score += 12
elif price_variance_pct < 5:  score += 8
elif price_variance_pct < 10: score += 4
else: score += 1
```

**Rationale:**
- Real markets have natural price variance
- Bots execute trades with algorithmic precision
- <0.5% variance indicates automated trading patterns

**Examples:**
| Price Variance % | Score | Interpretation |
|------------------|-------|----------------|
| 0.0% | 20 | Identical prices (bot) |
| 0.3% | 20 | Extreme precision |
| 2.0% | 12 | Low variance |
| 7.5% | 4 | Moderate variance |
| 15.0% | 1 | Normal variance |

---

### 4. Burst Detection Component (Max 15 Points)

**Purpose:** Identify rapid-fire trading (pump-and-dump schemes).

**Formula:**
```python
trade_density = total_trades / (active_period_seconds / 3600)  # trades/hour

if trade_density >= 100:  score += 15  # >100 trades/hour
elif trade_density >= 50:  score += 12
elif trade_density >= 20:  score += 8
elif trade_density >= 10:  score += 5
else: score += 2
```

**Rationale:**
- Pump-and-dump schemes show burst activity
- High trades/hour indicates bot execution
- Complements volume component

**Examples:**
| Trades/Hour | Score | Interpretation |
|-------------|-------|----------------|
| 300 | 15 | Extreme burst (3 trades in 1 second) |
| 100 | 15 | Very high frequency |
| 50 | 12 | High frequency |
| 20 | 8 | Moderate frequency |
| 5 | 2 | Normal frequency |

**Edge Case:**
- If all trades happen in the same second: `period_seconds = 0`
- Calculation: `3 trades / 0.0001 hours = 300 trades/hour`
- This correctly identifies burst patterns

---

### 5. Trade Size Uniformity Component (Max 10 Points)

**Purpose:** Detect robotic trading patterns.

**Formula:**
```python
size_variance_pct = (trade_size_stddev / avg_trade_size) * 100

if size_variance_pct < 2:  score += 10  # Bot-like uniformity
elif size_variance_pct < 5:  score += 7
elif size_variance_pct < 10: score += 4
else: score += 1
```

**Rationale:**
- Human traders vary trade sizes naturally
- Bots execute identical amounts
- <2% variance indicates programmatic execution

**Examples:**
| Size Variance % | Score | Interpretation |
|-----------------|-------|----------------|
| 0.0% | 10 | Identical amounts (bot) |
| 1.5% | 10 | Extreme uniformity |
| 7.0% | 4 | Low variance |
| 15.0% | 1 | Normal variance |

---

## Risk Score Tiers

| Risk Score | Tier | Interpretation |
|------------|------|----------------|
| 80-100 | CRITICAL | Very high likelihood of manipulation |
| 70-79 | HIGH | Strong manipulation signals |
| 50-69 | MEDIUM | Moderate suspicious patterns |
| 0-49 | LOW | Normal trading behavior |

---

## Real-World Example: XRPNORTH Token

**Scenario:** 3 trades in 24-hour window

**Raw Data:**
- Total Trades: 3
- Unique Traders: 1
- Volume: 0.11 XRP (~$0.20)
- Trade Timestamps: All in same second (2025-11-04 22:22:21)
- XRP Amounts: -0.036622, -0.036622, -0.036622 (identical)
- Price Variance: 0.0%
- Trades/Hour: 300 (3 trades / 0.0001 hours)

**Score Breakdown:**
1. Volume Component: 0 points (0.11 XRP too small)
2. Token Focus: 30 points (only 1 unique trader)
3. Price Stability: 20 points (0% variance = bot)
4. Burst Detection: 15 points (300 trades/hour)
5. Trade Uniformity: 10 points (identical amounts)

**Total Risk Score: 75 (HIGH)**

**Pattern Detected:** ✅ Bot-like behavior confirmed
**Market Impact:** ❌ Negligible ($0.20 volume)

---

## v2.0 Implementation (DEPLOYED)

### Three-Score System

The v2.0 algorithm implements expert-reviewed recommendations from ChatGPT-5 and Grok-4:

```
Risk Score (0-100)     = Behavioral pattern detection (24h window)
Impact Factor (0-1.0)  = Market relevance (7d volume)
Final Priority         = Risk Score × Impact Factor
```

### Volume Component Update

**v1.0:** `min(50, log10(volume / 1_000_000 + 1) * 12.5)`
**v2.0:** `min(60, log10(volume / 100_000 + 1) * 15)`

**Impact:**
- 100 XRP: 12.5 → 18.0 points (+44%)
- 10,000 XRP: 31.3 → 39.0 points (+25%)
- 1,000,000 XRP: 50.0 → 60.0 points (+20%)

### Impact Factor (ChatGPT-5's Smooth Curve)

```sql
impact_factor = min(1.0, log10(volume_7d / 10 + 1))
```

| 7-Day Volume | Impact Factor | Effect on Final Priority |
|--------------|---------------|---------------------------|
| 0.1 XRP | 0.04 | 96% reduction |
| 10 XRP | 0.30 | 70% reduction |
| 100 XRP | 0.66 | 34% reduction |
| 1,000 XRP | 0.90 | 10% reduction |
| 10,000+ XRP | 1.00 | No reduction |

### Dual-Window Scoring

- **24-hour window:** Pattern detection (burst, precision, concentration)
- **7-day window:** Volume for impact assessment
- **Why:** Avoids single-day micro-blips looking "big"

### Dashboard Views

**Actionable Threats (Default):**
- Filter: `volume_24h >= 10 XRP`
- Displays: Risk Score, Impact Factor, Final Priority, volumes
- Sorted by: Final Priority DESC
- Purpose: Real threats that matter

**Research / Low Impact Patterns (Collapsible):**
- Filter: None (all patterns shown)
- Displays: Same as Actionable + Impact Tier badges
- Badges: ⚪ Negligible, 🟢 Low, 🟡 Moderate, 🟠 High, 🔴 Critical
- Purpose: Early detection, bot research

### Example: XRPNORTH Token

**v1.0 Result:**
- Risk Score: 75 (HIGH)
- Display: ✅ Top 10 dashboard (prominent)

**v2.0 Result:**
- Risk Score: 75 (behavioral patterns detected)
- 7d Volume: 20 XRP
- Impact Factor: 0.38
- **Final Priority: 28.5**
- Display: 🔍 Research view only (hidden from main)

### Files Updated

- `queries/v2_risk_scoring.sql` - Actionable threats query
- `queries/v2_research_view.sql` - Research patterns query
- `grafana/xrp-watchdog-dashboard.json` - Dual-panel dashboard
- `scripts/update_dashboard_v2.py` - Dashboard update automation

---

## Known Issues and Limitations (v1.0 - RESOLVED in v2.0)

### Issue #1: Small Volume, High Score (FIXED)

**Problem:**
- Tokens with <1 XRP volume can score 70+ due to behavioral patterns
- Example: XRPNORTH (0.11 XRP = score 75)
- Pattern detection works, but impact is negligible

**Discussion Points:**
1. Should we add minimum volume threshold for dashboard display?
2. Should volume component have higher max weight (60-70 vs 50)?
3. Should we use a multiplicative approach (pattern_score × volume_factor)?
4. Should scores be impact-weighted?

**Proposed Solution A: Minimum Volume Filter**
```sql
WHERE total_xrp_volume >= 10  -- Only show tokens with 10+ XRP
```

**Proposed Solution B: Volume Multiplier**
```python
if total_xrp_volume < 1:
    final_score *= 0.1  # Reduce by 90%
elif total_xrp_volume < 10:
    final_score *= 0.5  # Reduce by 50%
else:
    final_score *= 1.0  # No reduction
```

**Proposed Solution C: Impact Tiers**
```python
if risk_score >= 70 and volume >= 1000:
    tier = "CRITICAL"
elif risk_score >= 70 and volume >= 100:
    tier = "HIGH"
elif risk_score >= 70 and volume >= 10:
    tier = "MEDIUM"
elif risk_score >= 70 and volume < 10:
    tier = "LOW IMPACT"  # High score, but negligible impact
```

### Issue #2: Time Window Sensitivity

**Problem:**
- 24-hour window may not capture full trading context
- XRPNORTH: 0.11 XRP in 24h, but 20 XRP over 7 days
- Different time windows produce different scores

**Options:**
- Use 7-day rolling window (captures more context)
- Use 30-day window (better baseline)
- Use all-time stats (most comprehensive)

### Issue #3: Logarithmic Volume Scaling

**Problem:**
- Current scaling may underweight large-volume manipulation
- 100,000 XRP = 43.8 points (only 87.6% of max)
- Massive manipulation still capped below max

**Discussion:**
- Should mega-volume (>100K XRP) automatically score higher?
- Should volume component have higher max weight?

---

## Detection Patterns

### Pattern 1: Wash Trading
**Signature:**
- Two accounts trading same token back-and-forth
- Both accounts show similar risk scores
- Consistent trade intervals (bot behavior)
- Minimal price variance

**Example:** OPULENCE token (358 trades each, both scored 90)

### Pattern 2: Burst Manipulation
**Signature:**
- Large volume in very short timeframe
- Few trades (5-10) with massive XRP amounts
- Active period < 1 day

**Example:** EUR token (75,690 XRP in 54 seconds, 8 trades, score 85)

### Pattern 3: Sustained Bot Campaigns
**Signature:**
- High trade count (400+) over many days
- Consistent intervals (30-60 minutes)
- Single token focus
- Price stability (bot-executed)

**Example:** TAZZ (453 trades, 37.8 min intervals, 11.9 days, score 95)

### Pattern 4: Single-Account Monopoly
**Signature:**
- Only 1-2 accounts trading a token
- Repeated identical trade amounts
- Bot-like precision timing

**Example:** XRPNORTH (1 account, 3 identical trades in 1 second, score 75)

---

## Questions for Review

We're seeking feedback on the following:

1. **Volume Weighting:**
   - Is 50-point max for volume component appropriate?
   - Should large volumes (>100K XRP) be weighted more heavily?

2. **Minimum Thresholds:**
   - Should we filter tokens with <10 XRP volume from dashboard?
   - What minimum volume indicates "meaningful" manipulation?

3. **Impact Assessment:**
   - Should we add a volume multiplier to final score?
   - Should we display "Impact Tier" separately from "Risk Score"?

4. **Time Windows:**
   - Is 24-hour window appropriate, or should we use 7-day?
   - Should we compare short-term vs long-term patterns?

5. **Algorithm Philosophy:**
   - Should we focus on **pattern detection** (current approach)?
   - Or **market impact** (volume-weighted approach)?
   - Or a hybrid approach?

---

## Data Sources

**Database:** ClickHouse time-series database
**Table:** `xrp_watchdog.executed_trades`

**Key Fields:**
- `time`: Transaction timestamp (millisecond precision)
- `taker`: Account initiating the trade
- `exec_iou_code`: Token being traded (3-char or 40-hex)
- `exec_iou_issuer`: Account that issued the token
- `exec_xrp`: XRP amount exchanged (negative = sold, positive = bought)
- `exec_price`: Exchange rate (XRP per token)

**Query:**
```sql
WITH trade_stats AS (
  SELECT
    exec_iou_code as token_code,
    exec_iou_issuer as token_issuer,
    COUNT(*) as total_trades,
    COUNT(DISTINCT taker) as unique_takers,
    SUM(ABS(exec_xrp)) as total_xrp_volume,
    AVG(exec_price) as avg_price,
    stddevPop(exec_price) as price_stddev,
    AVG(ABS(exec_xrp)) as avg_trade_size,
    stddevPop(ABS(exec_xrp)) as trade_size_stddev,
    min(time) as first_trade,
    max(time) as last_trade
  FROM xrp_watchdog.executed_trades
  WHERE time >= now() - INTERVAL 24 HOUR
  GROUP BY token_code, token_issuer
  HAVING total_trades >= 3
)
SELECT
  token_code,
  token_issuer,
  -- Volume component (max 50)
  LEAST(50, log10(total_xrp_volume / 1000000 + 1) * 12.5) +
  -- Token focus component (max 30)
  CASE
    WHEN unique_takers <= 2 THEN 30
    WHEN unique_takers <= 5 THEN 22
    WHEN unique_takers <= 10 THEN 15
    WHEN unique_takers <= 20 THEN 8
    ELSE 3
  END +
  -- Price stability component (max 20)
  CASE
    WHEN (price_stddev / GREATEST(avg_price, 0.0001)) * 100 < 0.5 THEN 20
    WHEN (price_stddev / GREATEST(avg_price, 0.0001)) * 100 < 1 THEN 16
    WHEN (price_stddev / GREATEST(avg_price, 0.0001)) * 100 < 3 THEN 12
    WHEN (price_stddev / GREATEST(avg_price, 0.0001)) * 100 < 5 THEN 8
    WHEN (price_stddev / GREATEST(avg_price, 0.0001)) * 100 < 10 THEN 4
    ELSE 1
  END +
  -- Burst detection component (max 15)
  CASE
    WHEN total_trades / GREATEST((dateDiff('second', first_trade, last_trade) / 3600.0), 0.01) >= 100 THEN 15
    WHEN total_trades / GREATEST((dateDiff('second', first_trade, last_trade) / 3600.0), 0.01) >= 50 THEN 12
    WHEN total_trades / GREATEST((dateDiff('second', first_trade, last_trade) / 3600.0), 0.01) >= 20 THEN 8
    WHEN total_trades / GREATEST((dateDiff('second', first_trade, last_trade) / 3600.0), 0.01) >= 10 THEN 5
    ELSE 2
  END +
  -- Trade size uniformity component (max 10)
  CASE
    WHEN (trade_size_stddev / GREATEST(avg_trade_size, 0.0001)) * 100 < 2 THEN 10
    WHEN (trade_size_stddev / GREATEST(avg_trade_size, 0.0001)) * 100 < 5 THEN 7
    WHEN (trade_size_stddev / GREATEST(avg_trade_size, 0.0001)) * 100 < 10 THEN 4
    ELSE 1
  END AS risk_score
FROM trade_stats
ORDER BY risk_score DESC;
```

---

## Whitelist Exclusions

Legitimate stablecoins and bridge tokens are excluded:

**Whitelisted Tokens:**
- RLUSD (Ripple USD stablecoin)
- USD (various stablecoin issuers)
- EUR (Gatehub Euro stablecoin)
- Coreum bridge tokens (COREUM* series)
- Tokens matching patterns: `*.AXL`, `*BRIDGE*`, `WRAPPED*`, `*ALLBRIDGE*`

**Management:**
```bash
python scripts/manage_whitelist.py list
python scripts/manage_whitelist.py add <code> <issuer> <name> --category stablecoin
```

---

## Performance Metrics

**Production Stats (November 2025):**
- **Total Trades Monitored:** 109,763+
- **Unique Tokens:** 360+
- **Data Coverage:** 16+ days continuous
- **Collection Frequency:** Every 5 minutes
- **Analyzer Runtime:** 0.04 seconds per batch
- **Average Risk Score:** 32.1
- **High Risk Tokens (≥70):** 8-12 at any time

---

## Feedback Requested

Please review this algorithm and provide feedback on:

1. **Is the volume weighting appropriate?**
   - Should tokens with <10 XRP volume be filtered out?
   - Should volume component have higher max weight?

2. **Is the pattern detection balanced?**
   - Are we over-detecting low-impact manipulation?
   - Are we under-weighting high-impact manipulation?

3. **What changes would you recommend?**
   - Minimum volume thresholds?
   - Volume multipliers?
   - Different time windows?
   - Adjusted component weights?

4. **Does the algorithm align with "XRP Watchdog" mission?**
   - Should focus be on XRP-scale manipulation?
   - Or should we catch all behavioral patterns regardless of scale?

---

**Document Version:** 1.0
**Last Updated:** November 5, 2025
**Maintainer:** @realGrapedrop
**Repository:** https://github.com/realgrapedrop/xrp-watchdog
