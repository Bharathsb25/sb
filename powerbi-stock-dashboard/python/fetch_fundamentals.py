"""
Fundamentals + analyst targets for the Power BI stock dashboard.

Two ways to run it
  1. Inside Power BI  - powerquery/13_Fundamentals.pq runs this file through Python.Execute and reads the
                        `fundamentals` DataFrame. Power BI injects the watchlist as the DataFrame `dataset`.
  2. Stand-alone      - python python/fetch_fundamentals.py --csv
                        writes output/fundamentals.csv (Power BI falls back to that file if Python.Execute fails).

Requirements:  pip install yfinance pandas
Data source :  Yahoo Finance via the open-source `yfinance` library (unofficial, free, occasionally incomplete
               for Indian small/mid caps - missing values are left blank and reported on the Validation page).
"""
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import yfinance as yf

MAX_WORKERS = 4          # keep low: Yahoo rate-limits aggressive callers
RETRIES = 2

# output column -> key in yfinance Ticker.info
NUMERIC_FIELDS = {
    "MarketCap": "marketCap",
    "PE": "trailingPE",
    "ForwardPE": "forwardPE",
    "PB": "priceToBook",
    "PEG": "trailingPegRatio",
    "EPS": "trailingEps",
    "ForwardEPS": "forwardEps",
    "BookValue": "bookValue",
    "ROE": "returnOnEquity",
    "ROA": "returnOnAssets",
    "ProfitMargin": "profitMargins",
    "OperatingMargin": "operatingMargins",
    "RevenueGrowth": "revenueGrowth",
    "EarningsGrowth": "earningsGrowth",
    "DebtToEquityPct": "debtToEquity",      # Yahoo reports this in percent (45 = 0.45x)
    "CurrentRatio": "currentRatio",
    "FreeCashFlow": "freeCashflow",
    "TotalRevenue": "totalRevenue",
    "Beta": "beta",
    "DividendRate": "dividendRate",
    "PayoutRatio": "payoutRatio",
    "TargetMean": "targetMeanPrice",
    "TargetMedian": "targetMedianPrice",
    "TargetHigh": "targetHighPrice",
    "TargetLow": "targetLowPrice",
    "AnalystCount": "numberOfAnalystOpinions",
    "RecMean": "recommendationMean",        # 1 = Strong Buy ... 5 = Strong Sell
    "InsiderHolding": "heldPercentInsiders",
    "InstitutionHolding": "heldPercentInstitutions",
}
TEXT_FIELDS = {
    "FSector": "sector",
    "Industry": "industry",
    "RecKey": "recommendationKey",
}
VOTE_FIELDS = ["strongBuy", "buy", "hold", "sell", "strongSell"]

COLUMNS = (
    ["Symbol", "FundStatus", "FetchedAt"]
    + list(TEXT_FIELDS)
    + list(NUMERIC_FIELDS)
    + ["DividendYield", "VotesStrongBuy", "VotesBuy", "VotesHold", "VotesSell", "VotesStrongSell"]
)


def _num(value):
    """Return a float, or None for missing / non-numeric / NaN / inf values."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    if f != f or f in (float("inf"), float("-inf")):
        return None
    return f


def _fetch_one(symbol):
    row = {c: None for c in COLUMNS}
    row["Symbol"] = symbol
    row["FetchedAt"] = time.strftime("%Y-%m-%d %H:%M:%S")
    last_error = "No data"
    for attempt in range(RETRIES + 1):
        try:
            ticker = yf.Ticker(symbol)
            info = ticker.info or {}
            if not info or all(info.get(k) is None for k in ("marketCap", "trailingPE", "targetMeanPrice", "sector")):
                last_error = "No fundamentals returned"
                time.sleep(1.5 * (attempt + 1))
                continue

            for out_col, key in NUMERIC_FIELDS.items():
                row[out_col] = _num(info.get(key))
            for out_col, key in TEXT_FIELDS.items():
                row[out_col] = info.get(key)

            # Compute yield ourselves: yfinance changed `dividendYield` between fraction and percent.
            price = _num(info.get("currentPrice")) or _num(info.get("regularMarketPrice")) or _num(info.get("previousClose"))
            if row["DividendRate"] is not None and price:
                row["DividendYield"] = row["DividendRate"] / price

            # Analyst vote breakdown (current month) - optional
            try:
                summary = ticker.recommendations_summary
                if summary is not None and len(summary) > 0:
                    cur = summary.iloc[0]
                    for out_col, key in zip(
                        ["VotesStrongBuy", "VotesBuy", "VotesHold", "VotesSell", "VotesStrongSell"], VOTE_FIELDS
                    ):
                        row[out_col] = _num(cur.get(key))
            except Exception:
                pass

            row["FundStatus"] = "OK"
            return row
        except Exception as exc:  # network / parsing / rate-limit
            last_error = "Error: " + str(exc)[:120]
            time.sleep(2 * (attempt + 1))
    row["FundStatus"] = last_error
    return row


def _load_symbols():
    try:
        return [str(s).strip() for s in dataset["Symbol"] if str(s).strip()]  # noqa: F821  (injected by Power BI)
    except NameError:
        here = os.path.dirname(os.path.abspath(__file__))
        csv_path = os.path.join(here, "..", "config", "watchlist.csv")
        return [str(s).strip() for s in pd.read_csv(csv_path)["Symbol"].dropna()]


def build_table(symbols):
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        rows = list(pool.map(_fetch_one, symbols))
    return pd.DataFrame(rows, columns=COLUMNS)


fundamentals = build_table(_load_symbols())

if "--csv" in sys.argv:
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "fundamentals.csv")
    fundamentals.to_csv(out_path, index=False)
    ok = int((fundamentals["FundStatus"] == "OK").sum())
    print(f"Wrote {out_path}: {ok}/{len(fundamentals)} symbols with fundamentals")
