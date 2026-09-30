// Query name : Scorecard          (LOAD: ON)  - THE main table: one row per stock with price, technicals, fundamentals,
// analyst targets, pillar scores, composite score, rating, thesis checklist, signals and an indicative trade plan.
// Scoring rules are documented in docs\METHODOLOGY.md. Edit the cut-offs / weights below to match your own style.
let
    // ---------- 1. join price data + fundamentals + news ----------
    FundCols = {"FundStatus", "FundSource", "FSector", "Industry", "RecKey", "MarketCap", "PE", "ForwardPE", "PB", "PEG", "EPS", "ROE", "ROA", "ProfitMargin", "OperatingMargin",
                "RevenueGrowth", "EarningsGrowth", "DebtToEquityPct", "CurrentRatio", "FreeCashFlow", "Beta", "DividendYield", "PayoutRatio",
                "TargetMean", "TargetMedian", "TargetHigh", "TargetLow", "AnalystCount", "RecMean", "VotesStrongBuy", "VotesBuy", "VotesHold", "VotesSell", "VotesStrongSell",
                "InsiderHolding", "InstitutionHolding"},
    J1       = Table.ExpandTableColumn(Table.NestedJoin(Quotes, {"Symbol"}, Fundamentals, {"Symbol"}, "F", JoinKind.LeftOuter), "F", FundCols),
    S1       = Table.AddColumn(J1, "SectorFinal", each if [FSector] <> null and [FSector] <> "" then [FSector] else [Sector], type text),
    S2       = Table.RenameColumns(Table.RemoveColumns(S1, {"Sector", "FSector"}), {{"SectorFinal", "Sector"}}),

    NewsAgg  = Table.Group(Table.SelectRows(News, each [Symbol] <> null and [Sentiment] <> null), {"Symbol"},
                    {{"NewsSentiment", each List.Average([Sentiment]), type number}, {"NewsCount", each Table.RowCount(_), Int64.Type}}),
    J2       = Table.ExpandTableColumn(Table.NestedJoin(S2, {"Symbol"}, NewsAgg, {"Symbol"}, "N", JoinKind.LeftOuter), "N", {"NewsSentiment", "NewsCount"}),

    // sector median P/E (positive earnings only; falls back to the whole-list median when a sector has < 3 names)
    PosPE    = Table.SelectRows(J2, each [PE] <> null and [PE] > 0),
    AllPE    = if Table.RowCount(PosPE) = 0 then null else List.Median(PosPE[PE]),
    PeBySec  = Table.Group(PosPE, {"Sector"}, {{"SectorPE0", each List.Median([PE]), type number}, {"SectorN", each Table.RowCount(_), Int64.Type}}),
    J3       = Table.ExpandTableColumn(Table.NestedJoin(J2, {"Sector"}, PeBySec, {"Sector"}, "P", JoinKind.LeftOuter), "P", {"SectorPE0", "SectorN"}),
    J4       = Table.AddColumn(J3, "SectorPE", each if [SectorN] <> null and [SectorN] >= 3 then [SectorPE0] else AllPE, type nullable number),
    Caps     = List.RemoveNulls(J4[MarketCap]),
    MedCap   = if List.Count(Caps) = 0 then 1 else List.Median(Caps),
    J5       = Table.AddColumn(J4, "HeatSize", each if [MarketCap] = null then MedCap else [MarketCap], type number),
    Base     = Table.RemoveColumns(J5, {"SectorPE0", "SectorN"}),

    // ---------- 2. scoring helpers ----------
    // Grade: score = scores{ number of cut-offs that x has reached }   (scores has one more item than cuts)
    Grade = (x as nullable number, cuts as list, scores as list) as nullable number =>
        if x = null then null else scores{List.Count(List.Select(cuts, each x >= _))},
    // Weighted mean that ignores missing (null) pillars/metrics
    WMean = (pairs as list) as nullable number =>
        let
            V = List.Select(pairs, each _{0} <> null),
            W = List.Sum(List.Transform(V, each _{1}))
        in
            if List.Count(V) = 0 then null else List.Sum(List.Transform(V, each _{0} * _{1})) / W,
    Sym   = (b as nullable logical, yes as number, no as number) as nullable number => if b = null then null else if b then yes else no,
    CK    = (b as nullable logical) as text => if b = null then "n/a" else if b then "Pass" else "Fail",

    ScoreRow = (r as record) as record =>
        let
            price   = r[Price],
            isFin   = r[Sector] = "Financial Services",
            pe      = r[PE],
            secPE   = r[SectorPE],
            peRel   = if pe = null or secPE = null or secPE = 0 then null else pe / secPE,
            de      = if r[DebtToEquityPct] = null then null else r[DebtToEquityPct] / 100,
            vol     = r[Volatility],
            enough  = r[AnalystCount] <> null and r[AnalystCount] >= 3,
            upside  = if r[TargetMean] = null or price = null or price = 0 then null else r[TargetMean] / price - 1,

            // pillar 1: valuation (25%)
            peScore  = if pe = null then null else if pe <= 0 then 10 else Grade(peRel, {0.8, 1.0, 1.25, 1.6}, {100, 80, 55, 30, 10}),
            pbScore  = if r[PB] = null then null else if r[PB] <= 0 then 10 else Grade(r[PB], {1.5, 3, 6, 10}, {100, 80, 55, 30, 10}),
            pegScore = if r[PEG] = null or r[PEG] <= 0 then null else Grade(r[PEG], {1, 1.5, 2, 3}, {100, 80, 55, 30, 10}),
            valuation = WMean({{peScore, 2}, {pbScore, 1}, {pegScore, 1}}),

            // pillar 2: quality / balance sheet (25%)
            roeScore = Grade(r[ROE], {0.05, 0.10, 0.15, 0.20}, {10, 30, 55, 80, 100}),
            pmScore  = Grade(r[ProfitMargin], {0.03, 0.08, 0.15, 0.25}, {10, 30, 55, 80, 100}),
            deScore  = if isFin then null else Grade(de, {0.3, 0.7, 1.2, 2.0}, {100, 80, 55, 30, 10}),
            crScore  = if isFin then null else Grade(r[CurrentRatio], {0.8, 1.2, 1.8}, {10, 40, 70, 90}),
            quality  = WMean({{roeScore, 2}, {pmScore, 1}, {deScore, 1}, {crScore, 0.5}}),

            // pillar 3: growth (15%)
            growth   = WMean({{Grade(r[RevenueGrowth], {0, 0.05, 0.10, 0.20}, {10, 30, 55, 80, 100}), 1},
                              {Grade(r[EarningsGrowth], {-0.10, 0, 0.10, 0.25}, {10, 30, 55, 80, 100}), 1.5}}),

            // pillar 4: momentum / trend (15%)  - works without fundamentals
            momentum = WMean({{Sym(r[Above200], 100, 25), 2},
                              {Sym(r[Above50], 100, 35), 1},
                              {Grade(r[Ret3M], {-0.10, 0, 0.05, 0.15}, {15, 35, 55, 80, 95}), 1.5},
                              {Grade(r[Rsi14], {30, 40, 50, 65, 75}, {60, 45, 65, 90, 60, 30}), 1}}),

            // pillar 5: analyst consensus (20%) - needs >= 3 analysts
            analyst  = if not enough then null
                       else WMean({{Grade(upside, {0, 0.08, 0.15, 0.25}, {10, 40, 65, 85, 100}), 2},
                                   {Grade(r[RecMean], {1.75, 2.25, 2.75, 3.5}, {100, 85, 60, 35, 10}), 1.5}}),

            pillars   = {{valuation, 25}, {quality, 25}, {growth, 15}, {momentum, 15}, {analyst, 20}},
            nPillars  = List.Count(List.Select(pillars, each _{0} <> null)),
            composite = if nPillars >= 3 then WMean(pillars) else null,

            // thesis checklist (8 yes/no tests)
            c1 = if pe = null or secPE = null then null else pe > 0 and pe < secPE,
            c2 = if r[ROE] = null then null else r[ROE] >= 0.15,
            c3 = if isFin or de = null then null else de <= 1,
            c4 = if r[EarningsGrowth] = null then null else r[EarningsGrowth] > 0,
            c5 = r[Above200],
            c6 = if r[Rsi14] = null then null else r[Rsi14] >= 30 and r[Rsi14] <= 70,
            c7 = if upside = null or not enough then null else upside >= 0.10,
            c8 = if r[PctFromHigh] = null then null else r[PctFromHigh] <= -0.15,
            checks    = {c1, c2, c3, c4, c5, c6, c7, c8},
            labels    = {"Valuation below sector P/E", "ROE >= 15%", "Debt/Equity <= 1x", "Earnings growing", "Above 200-DMA", "RSI between 30 and 70", "Analyst upside >= 10%", ">= 15% below 52W high"},
            passed    = List.Count(List.Select(checks, each _ = true)),
            evaluated = List.Count(List.Select(checks, each _ <> null)),
            passRate  = if evaluated = 0 then null else passed / evaluated,
            prSafe    = if passRate = null then 0 else passRate,
            failedTxt = Text.Combine(List.Transform(List.Select(List.Positions(checks), each checks{_} = false), each labels{_}), "; "),

            rating = if composite = null then "Insufficient data"
                     else if composite >= 72 and prSafe >= 0.75 then "Strong Buy"
                     else if composite >= 62 then "Buy"
                     else if composite >= 52 then "Accumulate"
                     else if composite >= 42 then "Hold / Watch"
                     else "Avoid",
            techRating = if momentum = null then "n/a" else if momentum >= 70 then "Bullish" else if momentum >= 50 then "Neutral" else "Bearish",
            risk = if vol = null then "n/a" else if vol >= 0.45 or (de <> null and de > 2) then "High" else if vol >= 0.30 then "Medium" else "Low",

            // signals
            fromLow  = r[PctFromLow],
            fromHigh = r[PctFromHigh],
            sigList  = List.Select({
                if valuation <> null and quality <> null and valuation >= 70 and quality >= 60 then "Value + Quality" else null,
                if fromLow <> null and fromLow <= 0.15 and quality <> null and quality >= 60 then "Quality near 52W low" else null,
                if fromLow <> null and fromLow <= 0.10 and (quality = null or quality < 60) then "Near 52W low (weak fundamentals)" else null,
                if fromHigh <> null and fromHigh <= -0.30 then "Deep discount to 52W high" else null,
                if fromHigh <> null and fromHigh >= -0.03 and r[VolumeRatio] <> null and r[VolumeRatio] >= 1.2 then "Breakout: near 52W high on volume" else null,
                if r[Rsi14] <> null and r[Rsi14] < 30 then "Oversold (RSI < 30)" else null,
                if r[Rsi14] <> null and r[Rsi14] > 70 then "Overbought (RSI > 70)" else null,
                if r[NewsSentiment] <> null and r[NewsSentiment] <= -0.25 then "Negative news flow" else null
            }, each _ <> null),

            // indicative trade plan: stop = clamp(0.3 x annual volatility, 6%, 15%) below price ~ 1.5 x 10-day sigma
            stopPct  = if vol = null then 0.10 else List.Min({0.15, List.Max({0.06, 0.30 * vol})}),
            stopLvl  = if price = null then null else price * (1 - stopPct),
            tgt      = r[TargetMean],
            rr       = if tgt = null or price = null or stopLvl = null or tgt <= price then null else (tgt - price) / (price - stopLvl),

            coverKeys = {r[PE], r[PB], r[ROE], r[ProfitMargin], r[DebtToEquityPct], r[RevenueGrowth], r[EarningsGrowth], r[TargetMean], r[RecMean], r[MarketCap]},
            coverage  = List.Count(List.Select(coverKeys, each _ <> null)) / List.Count(coverKeys)
        in
            [
                DebtToEquity     = de,
                PEvsSector       = peRel,
                UpsidePct        = upside,
                ValuationScore   = valuation,
                QualityScore     = quality,
                GrowthScore      = growth,
                MomentumScore    = momentum,
                AnalystScore     = analyst,
                Composite        = composite,
                Rating           = rating,
                TechRating       = techRating,
                Risk             = risk,
                ChecksPassed     = passed,
                ChecksEvaluated  = evaluated,
                PassRate         = passRate,
                ChecksText       = Text.From(passed) & "/" & Text.From(evaluated),
                FailedChecks     = failedTxt,
                Signals          = Text.Combine(sigList, " | "),
                StopPct          = stopPct,
                StopLoss         = stopLvl,
                RiskReward       = rr,
                FundCoverage     = coverage,
                Chk_Valuation    = CK(c1),
                Chk_ROE          = CK(c2),
                Chk_Debt         = CK(c3),
                Chk_EarningsGrowth = CK(c4),
                Chk_Above200DMA  = CK(c5),
                Chk_RSI          = CK(c6),
                Chk_AnalystUpside = CK(c7),
                Chk_MarginOfSafety = CK(c8)
            ],

    Scored   = Table.AddColumn(Base, "S", each ScoreRow(_), type record),
    OutNames = {"DebtToEquity", "PEvsSector", "UpsidePct", "ValuationScore", "QualityScore", "GrowthScore", "MomentumScore", "AnalystScore", "Composite", "Rating", "TechRating", "Risk",
                "ChecksPassed", "ChecksEvaluated", "PassRate", "ChecksText", "FailedChecks", "Signals", "StopPct", "StopLoss", "RiskReward", "FundCoverage",
                "Chk_Valuation", "Chk_ROE", "Chk_Debt", "Chk_EarningsGrowth", "Chk_Above200DMA", "Chk_RSI", "Chk_AnalystUpside", "Chk_MarginOfSafety"},
    Expanded = Table.ExpandRecordColumn(Scored, "S", OutNames, OutNames),
    Typed    = Table.TransformColumnTypes(Expanded, {
                {"DebtToEquity", type number}, {"PEvsSector", type number}, {"UpsidePct", type number}, {"ValuationScore", type number}, {"QualityScore", type number},
                {"GrowthScore", type number}, {"MomentumScore", type number}, {"AnalystScore", type number}, {"Composite", type number}, {"Rating", type text},
                {"TechRating", type text}, {"Risk", type text}, {"ChecksPassed", Int64.Type}, {"ChecksEvaluated", Int64.Type}, {"PassRate", type number},
                {"ChecksText", type text}, {"FailedChecks", type text}, {"Signals", type text}, {"StopPct", type number}, {"StopLoss", type number},
                {"RiskReward", type number}, {"FundCoverage", type number}, {"FundStatus", type text}, {"FundSource", type text}}, "en-US"),
    Sorted   = Table.Sort(Typed, {{"Composite", Order.Descending}, {"MomentumScore", Order.Descending}})
in
    Sorted
