# Stock Investment Dashboard for Power BI

A daily investing cockpit that **pulls live data from the internet on every refresh** and scores every stock on your watchlist:

| Page | What it answers |
|---|---|
| **1. Market Pulse** | Global indices, India sector heat map, stock heat map, market breadth and mood, top headlines |
| **2. Stock Picks** | Which stocks can I invest in? Rating, composite score, analyst target and upside, thesis checklist |
| **3. Value and 52-Week Lows** | Value-for-money stocks, quality stocks near their 52-week low, deep discounts, breakout candidates |
| **4. Stock Deep Dive** | One stock end to end: price vs 50/200-DMA, valuation vs sector, analyst range, 8-point checklist, news, trade plan |
| **5. Global Markets and Macro** | US, Europe, Asia, India indices, commodities, USD/INR, bond yield, crypto, VIX risk mode, rebased 1-year comparison |
| **6. News and Sentiment** | Live market and per-stock headlines with sentiment scoring |
| **7. Data Validation** | Did every ticker download? Fresh? Do the 52-week figures agree across sources? How complete are the fundamentals? |

> **Status, read this first.** The queries, DAX and scoring logic were written and checked offline (bracket/syntax lint, column cross-references, a Python port of the scoring run on sample stocks, and the Python fundamentals script run against a mocked `yfinance`). They have **not** been run against the live Yahoo/Google endpoints or opened in Power BI Desktop, because this build environment could not reach those sites and has no Power BI. Expect to fix a small thing or two on the first refresh. The **Data Validation** page and the `Status` column in `StgStocks` show exactly which ticker or step failed.
>
> This is a decision-support tool, **not investment advice**. Data is delayed and comes from unofficial free endpoints.

## Data sources (all free, no API keys)

| Data | Source | How |
|---|---|---|
| Prices, 52-week range, technicals, indices, commodities, FX | Yahoo Finance chart API | Power Query, no install needed |
| News + sentiment | Google News RSS | Power Query, no install needed |
| P/E, P/B, ROE, debt, growth, **analyst target and recommendation** | Yahoo Finance via `yfinance` | Python (needs one-time install) |

Without Python the dashboard still works for prices, heat maps, 52-week lows, trend/momentum ratings, indices and news. Valuation, quality and analyst scores stay blank and the Validation page tells you why.

## Folder layout

```
config/       watchlist.csv, indices.csv, news_topics.csv   <- edit these to change what is tracked
powerquery/   17 numbered .pq files                          <- paste into Power BI in order
python/       fetch_fundamentals.py                          <- fundamentals + analyst targets
dax/          measures.dax
theme/        market-dark.json
docs/         METHODOLOGY.md (how scores work), REPORT_LAYOUT.md (page-by-page build guide)
output/       fundamentals.csv is written here by the Python fallback
```

## Setup (about 20 minutes, once)

**Prerequisites:** Power BI Desktop for Windows. Optional but recommended: Python 3.9+ and `pip install yfinance pandas`, then in Power BI *File > Options > Python scripting* point to that Python.

1. **Copy this folder** to your PC, e.g. `C:\Users\you\powerbi-stock-dashboard`.
2. **Privacy setting (avoids `Formula.Firewall` errors):** *File > Options and settings > Options > Current File > Privacy > Ignore the Privacy Levels...*
3. **Slower, safer refresh (avoids Yahoo HTTP 429):** *Options > Current File > Data Load > untick "Enable parallel loading of tables".*
4. **Create the queries.** *Home > Transform data*. For each file in `powerquery/`, in numeric order: *New Source > Blank Query > Advanced Editor*, delete the template, paste the file contents (drop the leading `//` comment lines if you like), Done, then rename the query exactly as below.

   | File | Query name | Load to model? |
   |---|---|---|
   | 01 | `ProjectFolder` (a Parameter: *Manage Parameters > New*, Text, value = your folder path; or paste the file and edit the path) | no |
   | 02 | `Watchlist` | no |
   | 03 | `IndexList` | no |
   | 04 | `fnFetchChart` | no |
   | 05 | `fnTechnicals` | no |
   | 06 | `StgStocks` | no |
   | 07 | `StgIndices` | no |
   | 08 | `Prices` | **yes** |
   | 09 | `IndexPrices` | **yes** |
   | 10 | `Quotes` | no |
   | 11 | `Indices` | **yes** |
   | 12 | `LastRefresh` | **yes** |
   | 13 | `Fundamentals` | no |
   | 14 | `News` | **yes** |
   | 15 | `Scorecard` | **yes** |
   | 16 | `Checks` | **yes** |
   | 17 | `Validation` | **yes** |

   To switch load off: right-click the query > untick *Enable load*. Prompts for data-source credentials: choose **Anonymous** for the web sources.
5. **Close and Apply.** The first refresh downloads about 100 tickers plus ~60 news feeds, so allow 1-3 minutes.
6. **Relationships** (Model view; Power BI usually auto-detects them, verify):
   - `Scorecard[Symbol]` 1 -> * `Prices[Symbol]`
   - `Scorecard[Symbol]` 1 -> * `Checks[Symbol]`
   - `Scorecard[Symbol]` 1 -> * `News[Symbol]`
   - `Indices[Symbol]` 1 -> * `IndexPrices[Symbol]`

   `Validation` and `LastRefresh` stay unrelated. Set `News[Link]` to *Data category: Web URL*.
7. **Add the DAX** from `dax/measures.dax` (one at a time; the file explains where each goes).
8. **Apply the theme:** *View > Themes > Browse for themes >* `theme/market-dark.json`.
9. **Build the pages** following `docs/REPORT_LAYOUT.md`. It lists the visual type, fields and formatting for each visual.
10. **Save** as `StockDashboard.pbix`. Each morning: open it and press **Refresh**.

## Daily use

- **Refresh** pulls fresh prices, indices, news and (if Python is available) fundamentals and analyst targets.
- **Add or remove stocks:** edit `config/watchlist.csv` (NSE = `SYMBOL.NS`, BSE = `SYMBOL.BO`, US = plain ticker) and refresh. Same for `indices.csv` and `news_topics.csv`.
- **Python cache:** `python python/fetch_fundamentals.py --csv` writes `output/fundamentals.csv`. Power BI falls back to it automatically if `Python.Execute` fails.
- **Scheduled refresh in the Power BI service:** the config and Python files are local, so you need a *personal gateway* (or move the CSVs to OneDrive/SharePoint and drop the Python step). Refreshing in Desktop always works.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Formula.Firewall ... Query references other queries` | Step 2 above (Ignore privacy levels) |
| Many tickers show `Error: ... 429` on the Validation page | Step 3, then refresh again in a few minutes |
| One ticker `Error: no price rows` | Symbol changed or delisted (corporate actions, e.g. demergers or renames). Look it up on finance.yahoo.com and fix `watchlist.csv` |
| All valuation/analyst columns blank | Python step failed. Install `yfinance pandas`, set the Python home directory in Options, or run the `--csv` fallback |
| `Python.Execute` asks for permission | Approve once (*Options > Security > Python scripting*) |
| News empty | Google News rate limit; refresh later. Headlines cover the last 3 days only |
| GIFT Nifty is missing | Not available from Yahoo; add a source of your choice as a new query |

## Known limits

- Yahoo's free data is roughly 15 minutes delayed for some exchanges and occasionally incomplete for mid/small caps.
- Analyst targets exist only for well-covered stocks; the analyst pillar needs at least 3 analysts.
- News sentiment is a simple headline keyword score. Treat it as a flag, not a verdict.
- The rating is a rules-based screen, not a forecast. Read `docs/METHODOLOGY.md` and change the weights to fit your own style.
