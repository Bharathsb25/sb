# Report build guide

Canvas: 16:9 (1280x720). Theme: `theme/market-dark.json`. Every page has a header strip with the page title, the **Last Updated** measure (top right), and a footer text box: *"Decision-support only, not investment advice. Data delayed, source Yahoo Finance and Google News."*
Add **Page navigator > Pages** (Insert > Buttons > Navigator) to the header.

Global slicers (sync across pages 1-4 via *View > Sync slicers*): `Scorecard[Sector]`, `Scorecard[Rating]`, `Scorecard[Cap Bucket]`.

Conditional-format colours: use *Format style: Field value* with the colour measures in `measures.dax` (`Heat Color`, `Index Heat Color`, `Rating Color`, `Score Color`, `Market Mood Color`).

---
## Page 1 - Market Pulse

| Visual | Type | Fields | Notes |
|---|---|---|---|
| Index tiles (8) | Card (new) | `Indices[Price]` + `Index Day Change %` | One card per index; visual filter `Indices[Name]` = Nifty 50, Sensex, Bank Nifty, S&P 500, Nasdaq, Nikkei 225, India VIX, USD/INR. Colour the change with `Index Heat Color` |
| Market mood | Card | `Market Mood`, `Breadth %`, `Advancers`, `Decliners` | Font colour from `Market Mood Color` |
| **Stock heat map** | Treemap | Group: `Sector` > `Name`; Values: `Scorecard[HeatSize]`; Tooltips: `Price`, `DayChangePct`, `Rating` | Colours > Field value > `Heat Color`. Larger tile = larger market cap |
| **Sector heat map** | Treemap | Group: `Indices[Name]`; Values: `Indices[Price]` (or constant); filter `Group = India Sector` | Colours from `Index Heat Color` |
| Top gainers / losers | Clustered bar x2 | `Name` by `DayChangePct` | Top N filter 5 (top) and 5 (bottom) |
| Breadth | Donut | `Advancers`, `Decliners`, `Unchanged` | |
| Market headlines | Table | `News[Published]`, `Headline`, `Source` | Filter `Topic` is not Stock; Top N 8 by `Published`; make `Headline` a link using `Link` (Format > Cell elements > Web URL) |

## Page 2 - Stock Picks

| Visual | Type | Fields |
|---|---|---|
| KPI row | Cards | `Buy Signals`, `Value + Quality Picks`, `Avg Analyst Upside %`, `Top Pick`, `Top Pick Score` |
| **Screener** | Table | `Name`, `Sector`, `Price`, `DayChangePct`, `Rating`, `Composite`, `TargetMean`, `UpsidePct`, `PE`, `ROE`, `ChecksText`, `Risk`, `Signals`. Data bars on `Composite` and `UpsidePct`; `Rating` background via `Rating Color`; sort `Composite` descending |
| Top 10 by score | Bar | `Name` by `Composite`, Top N 10 |
| Upside vs quality | Scatter | X `QualityScore`, Y `UpsidePct`, size `MarketCap`, legend `Rating`, details `Name` |
| Pillar profile | Radar (AppSource "Radar chart") or clustered bar | `ValuationScore`, `QualityScore`, `GrowthScore`, `MomentumScore`, `AnalystScore` for the selected row |

Right-click any `Name` > **Drill through > Stock Deep Dive**.

## Page 3 - Value and 52-Week Lows

| Visual | Type | Fields |
|---|---|---|
| KPIs | Cards | `Near 52W Low (<=10%)`, `Quality Near 52W Low`, `Deep Discount (>30% off high)`, `Near 52W High (<=3%)` |
| **52-week low list** | Table | `Name`, `Price`, `Low52`, `PctFromLow`, `High52`, `PctFromHigh`, `Range52Pos` (data bar 0-1), `QualityScore`, `Rating`, `Signals`. Filter `PctFromLow <= 0.15`, sort ascending |
| Value-for-money | Table | Filter `ValuationScore >= 65` and `QualityScore >= 55`. Show `PE`, `PEvsSector`, `PB`, `PEG`, `ROE`, `DividendYield`, `UpsidePct` |
| **Value map** | Scatter | X `PE`, Y `ROE`, size `MarketCap`, legend `Sector`. Bottom-right is expensive/low-return, top-left is cheap/high-return |
| Range position | Bar | `Name` by `Range52Pos`; reference line at 0.2 (near lows) |
| Breakouts | Table | Filter `Signals` contains "Breakout" |

Treat "near 52-week low, weak fundamentals" as a **value trap warning**, not a buy. The `Signals` column separates the two cases.

## Page 4 - Stock Deep Dive (drill-through target)

Add `Scorecard[Name]` to *Drill through > Keep all filters*.

| Visual | Type | Fields |
|---|---|---|
| Title + verdict | Card x2 | `Selected Stock`, `Selected Verdict` |
| **Price and trend** | Line | Axis `Prices[Date]`; Values `Close`, `SMA 50`, `SMA 200` |
| Returns | Column | `Ret1M`, `Ret3M`, `Ret6M`, `RetYtd`, `Ret1Y` (unpivot in the visual by using a multi-row card or five small cards) |
| Valuation vs sector | Clustered bar | `PE` vs `SectorPE`; also `PB`, `PEG` as cards |
| Analyst view | Cards | `Analyst Target Range`, `UpsidePct`, `AnalystCount`, `RecKey`, and stacked bar of `VotesStrongBuy` ... `VotesStrongSell` |
| **Thesis checklist** | Matrix | Rows `Checks[Check]` (sort by `Checks[Sort]`), Columns none, Values `Checks[Result]`; conditional colour: Pass green, Fail red, n/a grey |
| Trade plan | Cards | `Price`, `StopLoss`, `StopPct`, `TargetMean`, `RiskReward` |
| Quality and risk | Cards | `Risk`, `Volatility`, `Beta`, `DebtToEquity`, `ROE`, `ProfitMargin` |
| Latest news | Table | `News[Published]`, `Headline`, `SentimentLabel`; the relationship filters it to the selected stock |

## Page 5 - Global Markets and Macro

| Visual | Type | Fields |
|---|---|---|
| Regional tables | Table x4 | `Indices[Name]`, `Price`, `DayChangePct`, `RetYtd`, `Ret1Y`, `PctFromHigh`, `Trend`; visual filter by `Region` (North America, Europe, Asia Pacific, India) |
| **World scoreboard** | Bar | `Name` by `Index Day Change %`, filter `Group = Equity Index`, colours from `Index Heat Color` |
| Commodities / FX / Yields / Crypto | Cards or table | Filter `Group` = Commodity, Currency, Bond Yield, Crypto |
| Risk gauge | Card | `Global Risk Mode` + VIX and India VIX |
| **1-year relative performance** | Line | Axis `IndexPrices[Date]`, Values `Rebased 100 (Indices)`, Legend `IndexPrices[Name]`; slicer on `Name` (default Nifty 50, S&P 500, Nikkei 225, Gold) |
| Trend map | Matrix | Rows `Name`, Values `Trend`, `Rsi14` (conditional colour) |

## Page 6 - News and Sentiment

| Visual | Type | Fields |
|---|---|---|
| KPIs | Cards | `Headlines`, `News Mood`, `Positive %`, `Negative %` |
| Sentiment by topic | Bar | `News[Topic]` by `Avg Sentiment` |
| Sentiment by stock | Bar | `Scorecard[Name]` by `Avg Sentiment`, Top N 10 most negative and 10 most positive |
| **Headline feed** | Table | `Published`, `Topic`, `Headline` (URL link), `Source`, `SentimentLabel`; slicers on `Topic` and `SentimentLabel` |

## Page 7 - Data Validation

| Visual | Type | Fields |
|---|---|---|
| Health cards | Cards | `Symbols Checked`, `Symbols Good`, `Symbols Warning`, `Symbols Failed`, `Data Health %`, `Fundamentals Coverage %` |
| Status donut | Donut | `Validation[Overall]` |
| **Exceptions** | Table | `Type`, `Symbol`, `Name`, `Overall`, `Issues`, `DaysSinceTrade`, `HistRows`, `FundSource`, `FundCoverage`; sort so Failed/Warning are on top |
| Method notes | Text box | Summarise `docs/METHODOLOGY.md` |

## Finishing touches

- *View > Mobile layout* for a phone view of Page 1 (mood, tiles, top movers).
- *Bookmarks* for "Bullish set-up", "Value hunt" (Page 3 filters), then a bookmark navigator.
- Pin Page 1 to a dashboard if you publish to the Power BI service.
