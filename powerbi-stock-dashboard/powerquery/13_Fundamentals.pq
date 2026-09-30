// Query name : Fundamentals       (staging; Enable load: OFF)
// Valuation, quality, growth and ANALYST TARGET data.
// 1) Tries live Yahoo data through Python (needs:  pip install yfinance pandas  and Power BI > Options > Python scripting).
// 2) If Python is unavailable it falls back to output\fundamentals.csv (create it with:  python python\fetch_fundamentals.py --csv).
// 3) If neither works it returns an empty table - the dashboard still loads with price/technical data only.
let
    Root     = Text.TrimEnd(ProjectFolder, {"\", "/"}),
    Columns  = {"Symbol", "FundStatus", "FetchedAt", "FSector", "Industry", "RecKey", "MarketCap", "PE", "ForwardPE", "PB", "PEG", "EPS", "ForwardEPS", "BookValue",
                "ROE", "ROA", "ProfitMargin", "OperatingMargin", "RevenueGrowth", "EarningsGrowth", "DebtToEquityPct", "CurrentRatio", "FreeCashFlow", "TotalRevenue",
                "Beta", "DividendRate", "PayoutRatio", "TargetMean", "TargetMedian", "TargetHigh", "TargetLow", "AnalystCount", "RecMean", "InsiderHolding",
                "InstitutionHolding", "DividendYield", "VotesStrongBuy", "VotesBuy", "VotesHold", "VotesSell", "VotesStrongSell"},
    TextCols = {"Symbol", "FundStatus", "FetchedAt", "FSector", "Industry", "RecKey"},
    NumCols  = List.Difference(Columns, TextCols),

    Script   = () => Text.FromBinary(File.Contents(Root & "\python\fetch_fundamentals.py"), TextEncoding.Utf8),
    FromPy   = () => Python.Execute(Script(), [dataset = Watchlist]){[Name = "fundamentals"]}[Value],
    FromCsv  = () => Table.PromoteHeaders(Csv.Document(File.Contents(Root & "\output\fundamentals.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]), [PromoteAllScalars = true]),

    TryPy    = try FromPy(),
    TryCsv   = try FromCsv(),
    Picked   = if not TryPy[HasError] then [Data = TryPy[Value], Src = "Python (live)"]
               else if not TryCsv[HasError] then [Data = TryCsv[Value], Src = "CSV cache"]
               else [Data = #table(Columns, {}), Src = "Unavailable"],

    Aligned  = Table.SelectColumns(Picked[Data], Columns, MissingField.UseNull),
    AsText   = Table.TransformColumns(Aligned, List.Transform(TextCols, each {_, (v) => if v = null then null else Text.From(v), type nullable text})),
    AsNum    = Table.TransformColumns(AsText, List.Transform(NumCols, each {_, (v) => try (let n = Number.From(v) in if n = null or Number.IsNaN(n) then null else n) otherwise null, type nullable number})),
    WithSrc  = Table.AddColumn(AsNum, "FundSource", each Picked[Src], type text)
in
    WithSrc
