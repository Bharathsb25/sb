"""Generates the .pbip project (TMDL semantic model + legacy-format report) from powerquery/*.pq and dax/measures.dax."""
import os, re, json, uuid, glob, shutil
ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "pbip")
shutil.rmtree(OUT, ignore_errors=True)
SM = os.path.join(OUT, "StockDashboard.SemanticModel"); RP = os.path.join(OUT, "StockDashboard.Report")
os.makedirs(os.path.join(SM, "definition", "tables")); os.makedirs(RP)
g = lambda: str(uuid.uuid4())
def q(n): return "'" + n.replace("'", "''") + "'" if re.search(r"[^A-Za-z0-9_]", n) else n

# ---- column typing -------------------------------------------------------
T = "string"; D = "double"; I = "int64"; DT = "dateTime"; B = "boolean"
tech = {**{c: D for c in "Price PrevClose DayChange DayChangePct High52 Low52 High52Candles Low52Candles PctFromLow PctFromHigh Range52Pos Sma50 Sma200 Rsi14 Ret1M Ret3M Ret6M Ret1Y RetYtd Volatility Volume AvgVolume20 VolumeRatio".split()},
        "Above50": B, "Above200": B, "Trend": T, "Currency": T, "Exchange": T, "LongName": T, "LastTradeTime": DT, "LastDate": DT, "HistRows": I}
fund = {**{c: D for c in "MarketCap PE ForwardPE PB PEG EPS ROE ROA ProfitMargin OperatingMargin RevenueGrowth EarningsGrowth DebtToEquityPct CurrentRatio FreeCashFlow Beta DividendYield PayoutRatio TargetMean TargetMedian TargetHigh TargetLow AnalystCount RecMean VotesStrongBuy VotesBuy VotesHold VotesSell VotesStrongSell InsiderHolding InstitutionHolding".split()},
        "FundStatus": T, "FundSource": T, "Industry": T, "RecKey": T}
score = {**{c: D for c in "DebtToEquity PEvsSector UpsidePct ValuationScore QualityScore GrowthScore MomentumScore AnalystScore Composite PassRate StopPct StopLoss RiskReward FundCoverage".split()},
         "Rating": T, "TechRating": T, "Risk": T, "ChecksPassed": I, "ChecksEvaluated": I, "ChecksText": T, "FailedChecks": T, "Signals": T,
         **{c: T for c in "Chk_Valuation Chk_ROE Chk_Debt Chk_EarningsGrowth Chk_Above200DMA Chk_RSI Chk_AnalystUpside Chk_MarginOfSafety".split()}}
tables = {
 "Prices": {"Symbol": T, "Date": DT, "Open": D, "High": D, "Low": D, "Close": D, "Volume": I},
 "IndexPrices": {"Symbol": T, "Name": T, "Group": T, "Region": T, "Date": DT, "Close": D},
 "Indices": {"Symbol": T, "Name": T, "Group": T, "Region": T, **tech},
 "LastRefresh": {"LastRefresh": DT},
 "News": {"Symbol": T, "Topic": T, "Headline": T, "Source": T, "Link": T, "Published": DT, "Sentiment": D, "SentimentLabel": T},
 "Scorecard": {"Symbol": T, "Name": T, "Sector": T, **tech, **fund, "NewsSentiment": D, "NewsCount": I, "SectorPE": D, "HeatSize": D, **score},
 "Checks": {"Symbol": T, "Result": T, "Check": T, "Pillar": T, "Sort": I},
 "Validation": {"Symbol": T, "Name": T, "Status": T, "HistRows": I, "LastDate": DT, "High52": D, "High52Candles": D, "Low52": D, "Low52Candles": D, "FundStatus": T, "FundSource": T,
                "FundCoverage": D, "Type": T, "DaysSinceTrade": I, "Overall": T, "Issues": T},
}
loaded_files = {"Prices": "08_Prices", "IndexPrices": "09_IndexPrices", "Indices": "11_Indices", "LastRefresh": "12_LastRefresh", "News": "14_News", "Scorecard": "15_Scorecard", "Checks": "16_Checks", "Validation": "17_Validation"}
expr_files = {"ProjectFolder": "01_ProjectFolder", "Watchlist": "02_Watchlist", "IndexList": "03_IndexList", "fnFetchChart": "04_fnFetchChart", "fnTechnicals": "05_fnTechnicals",
              "StgStocks": "06_StgStocks", "StgIndices": "07_StgIndices", "Quotes": "10_Quotes", "Fundamentals": "13_Fundamentals"}
read = lambda f: open(os.path.join(ROOT, "powerquery", f + ".pq"), encoding="utf-8").read().rstrip() + "\n"
ind = lambda s, n: "".join(("\t" * n + l if l.strip() else l) + "\n" for l in s.rstrip("\n").split("\n"))

# ---- DAX parse -----------------------------------------------------------
dax = open(os.path.join(ROOT, "dax", "measures.dax"), encoding="utf-8").read()
blocks = []; cur = None
for line in dax.split("\n"):
    m = re.match(r"^([A-Z][A-Za-z0-9 %()<>+&./-]*?) =\s*(.*)$", line)
    if m and not line.startswith("//"):
        cur = [m.group(1), [m.group(2)] if m.group(2) else []]; blocks.append(cur)
    elif cur is not None and not line.startswith("// ----") and not line.startswith("// ===") :
        cur[1].append(line)
def clean(lines):
    out = [l for l in lines]
    while out and (not out[-1].strip() or out[-1].lstrip().startswith("//  ") or out[-1].lstrip().startswith("// ->")): out.pop()
    return "\n".join(out).strip("\n")
calc_cols = {"Rating Sort": I, "Risk Sort": I, "Cap Bucket": T}
host = lambda n: "Indices" if n.startswith(("Index ", "Indices ", "Global Risk", "Rebased 100 (Ind")) else "News" if n in ("Headlines", "Avg Sentiment", "Positive %", "Negative %", "News Mood") \
       else "Validation" if n in ("Symbols Checked", "Symbols Good", "Symbols Warning", "Symbols Failed", "Data Health %", "Fundamentals Coverage %", "Last Updated") else "Scorecard"
measures = {t: [] for t in tables}; ccols = []
for name, lines in blocks:
    body = clean(lines)
    if name in calc_cols: ccols.append((name, body)); continue
    measures[host(name)].append((name, body))

# ---- write tables --------------------------------------------------------
for t, cols in tables.items():
    s = f"table {q(t)}\n\tlineageTag: {g()}\n\n"
    for c, dt in cols.items():
        s += f"\tcolumn {q(c)}\n\t\tdataType: {dt}\n\t\tlineageTag: {g()}\n\t\tsummarizeBy: none\n\t\tsourceColumn: {c}\n"
        if t == "Scorecard" and c == "Rating": s += "\t\tsortByColumn: 'Rating Sort'\n"
        if t == "Scorecard" and c == "Risk": s += "\t\tsortByColumn: 'Risk Sort'\n"
        if t == "News" and c == "Link": s += "\t\tdataCategory: WebUrl\n"
        s += "\n"
    if t == "Scorecard":
        for c, body in ccols:
            s += f"\tcolumn {q(c)} =\n" + ind(body, 3) + f"\t\tdataType: {calc_cols[c]}\n\t\tlineageTag: {g()}\n\t\tsummarizeBy: none\n\n"
    for n, body in measures[t]:
        fmt = "\t\tformatString: 0.0%\n" if n.endswith("%") else ""
        s += f"\tmeasure {q(n)} =\n" + ind(body, 3) + fmt + f"\t\tlineageTag: {g()}\n\n"
    s += f"\tpartition {q(t)} = m\n\t\tmode: import\n\t\tsource =\n" + ind(read(loaded_files[t]), 4) + "\n\tannotation PBI_ResultType = Table\n"
    open(os.path.join(SM, "definition", "tables", t + ".tmdl"), "w", encoding="utf-8").write(s)

# ---- expressions, model, relationships ----------------------------------
ex = ""
for n, f in expr_files.items():
    body = read(f)
    if n == "ProjectFolder":
        ex += f"expression ProjectFolder = \"C:\\Users\\YOUR_NAME\\powerbi-stock-dashboard\" meta [IsParameterQuery = true, Type = \"Text\", IsParameterQueryRequired = true]\n\tlineageTag: {g()}\n\tqueryGroup: Setup\n\n\tannotation PBI_ResultType = Text\n\n"
    else:
        ex += f"expression {q(n)} =\n" + ind(body, 2) + f"\tlineageTag: {g()}\n\tqueryGroup: Staging\n\n\tannotation PBI_ResultType = {'Function' if n.startswith('fn') else 'Table'}\n\n"
open(os.path.join(SM, "definition", "expressions.tmdl"), "w", encoding="utf-8").write(ex)
model = "model Model\n\tculture: en-US\n\tdefaultPowerBIDataSourceVersion: powerBI_V3\n\tsourceQueryCulture: en-US\n\n"
model += "".join(f"ref table {q(t)}\n" for t in tables) + "\n" + "".join(f"ref expression {q(n)}\n" for n in expr_files) + "\n"
model += "annotation PBI_QueryOrder = " + json.dumps(list(expr_files) + list(tables)) + "\n"
open(os.path.join(SM, "definition", "model.tmdl"), "w", encoding="utf-8").write(model)
open(os.path.join(SM, "definition", "database.tmdl"), "w").write("database\n\tcompatibilityLevel: 1600\n")
rels = [("Prices", "Scorecard"), ("Checks", "Scorecard"), ("News", "Scorecard"), ("IndexPrices", "Indices")]
open(os.path.join(SM, "definition", "relationships.tmdl"), "w").write("".join(f"relationship {g()}\n\tfromColumn: {a}.Symbol\n\ttoColumn: {b}.Symbol\n\n" for a, b in rels))
json.dump({"version": "4.0", "settings": {}}, open(os.path.join(SM, "definition.pbism"), "w"), indent=2)

# ---- report (legacy layout format) --------------------------------------
pages = ["Market Pulse", "Stock Picks", "Value and 52-Week Lows", "Stock Deep Dive", "Global Markets and Macro", "News and Sentiment", "Data Validation"]
theme = json.load(open(os.path.join(ROOT, "theme", "market-dark.json")))
os.makedirs(os.path.join(RP, "StaticResources", "RegisteredResources"))
json.dump(theme, open(os.path.join(RP, "StaticResources", "RegisteredResources", "market-dark.json"), "w"), indent=2)
cfg = {"version": "5.59", "themeCollection": {"baseTheme": {"name": "CY24SU10", "version": "5.59", "type": 2},
       "customTheme": {"name": "market-dark.json", "version": "5.59", "type": 1}}, "activeSectionIndex": 0, "defaultDrillFilterOtherVisuals": True}
rep = {"config": json.dumps(cfg), "layoutOptimization": 0,
       "resourcePackages": [{"resourcePackage": {"name": "SharedResources", "type": 2, "items": [{"type": 202, "path": "BaseThemes/CY24SU10.json", "name": "CY24SU10"}], "disabled": False}},
                            {"resourcePackage": {"name": "RegisteredResources", "type": 1, "items": [{"type": 202, "path": "market-dark.json", "name": "market-dark.json"}], "disabled": False}}],
       "sections": [{"config": "{}", "displayName": p, "displayOption": 1, "filters": "[]", "height": 720.0, "name": f"ReportSection{i+1}", "visualContainers": [], "width": 1280.0} for i, p in enumerate(pages)]}
json.dump(rep, open(os.path.join(RP, "report.json"), "w"), indent=2)
json.dump({"version": "1.0", "datasetReference": {"byPath": {"path": "../StockDashboard.SemanticModel"}, "byConnection": None}}, open(os.path.join(RP, "definition.pbir"), "w"), indent=2)
json.dump({"version": "1.0", "artifacts": [{"report": {"path": "StockDashboard.Report"}}], "settings": {"enableAutoRecovery": True}}, open(os.path.join(OUT, "StockDashboard.pbip"), "w"), indent=2)
print("tables:", {t: len(measures[t]) for t in tables}, "calc cols:", [c for c, _ in ccols], "total measures:", sum(len(v) for v in measures.values()), "blocks:", len(blocks))
