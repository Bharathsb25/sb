# How the Scorecard works

All logic lives in `powerquery/15_Scorecard.pq`. Every threshold is an editable list in that file.

## Five pillars, each scored 0-100

Each pillar is a weighted average of a few metrics. **Missing metrics are ignored** (not treated as zero). A composite is only produced when at least 3 pillars have data.

| Pillar | Weight | Metrics (weight inside pillar) | Better when |
|---|---|---|---|
| **Valuation** | 25% | P/E relative to the sector median (2), P/B (1), PEG (1) | cheaper. Negative P/E scores 10 |
| **Quality** | 25% | ROE (2), profit margin (1), debt/equity (1), current ratio (0.5) | higher ROE/margins, lower debt. Debt and current ratio are skipped for Financial Services |
| **Growth** | 15% | Revenue growth (1), earnings growth (1.5) | faster growth |
| **Momentum** | 15% | Above 200-DMA (2), above 50-DMA (1), 3-month return (1.5), RSI(14) (1) | uptrend; RSI 50-65 scores best, over 75 or under 30 is penalised |
| **Analyst** | 20% | Upside to mean target (2), consensus recommendation 1-5 (1.5) | more upside, stronger consensus. Requires 3 or more analysts |

Sector-relative P/E uses the median of positive P/Es in the stock's sector, or the whole watchlist if the sector has fewer than 3 names.

## Rating

| Composite | Rating |
|---|---|
| 72 or more **and** at least 75% of checklist tests passed | Strong Buy |
| 62 or more | Buy |
| 52 or more | Accumulate |
| 42 or more | Hold / Watch |
| below 42 | Avoid |
| fewer than 3 pillars available | Insufficient data (use **TechRating**: Bullish / Neutral / Bearish, from momentum only) |

## Thesis checklist (the "detailed validation")

Eight pass/fail tests per stock, shown on the Deep Dive page. `n/a` means the data was unavailable and the test is not counted.

1. P/E below sector median
2. ROE at least 15%
3. Debt/equity at most 1x (skipped for financials)
4. Earnings growth positive
5. Price above 200-day average
6. RSI between 30 and 70 (not stretched)
7. Analyst upside at least 10% (3+ analysts)
8. At least 15% below the 52-week high (margin of safety)

## Signals column

Value + Quality (valuation 70+ and quality 60+) - Quality near 52W low (within 15% of low, quality 60+) - Near 52W low with weak fundamentals (a possible value trap) - Deep discount (30%+ below high) - Breakout (within 3% of high on 1.2x average volume) - Oversold/Overbought (RSI) - Negative news flow (average headline sentiment -0.25 or worse).

## Risk and indicative trade plan

- **Risk:** High if annual volatility is 45% or more, or debt/equity over 2x; Medium at 30% or more; otherwise Low.
- **Stop-loss (indicative):** price x (1 - clamp(0.30 x annual volatility, 6%, 15%)). This is about 1.5 standard deviations of a 10-day move.
- **Target:** the analyst mean target, when available.
- **Risk/reward:** (target - price) / (price - stop).

## Data caveats

- `debtToEquity` from Yahoo is in percent (45 means 0.45x); the model divides by 100.
- Dividend yield is computed as annual dividend / price to avoid Yahoo's inconsistent yield field.
- "52-week" figures use Yahoo's own high/low. The Validation page cross-checks them against the 1-year candles and warns above a 5% mismatch.
- Day change uses the last two daily closes, so during market hours it reflects the live session versus the previous close.
