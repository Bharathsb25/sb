// Query name : Validation         (LOAD: ON)  - data-health report for every stock and index in your config files.
// Answers: did the ticker download? is the data fresh? do the two 52-week sources agree? how complete are the fundamentals?
let
    TodayIst = Date.From(DateTimeZone.SwitchZone(DateTimeZone.UtcNow(), 5, 30)),
    Cols     = {"Symbol", "HistRows", "LastDate", "High52", "High52Candles", "Low52", "Low52Candles", "FundStatus", "FundSource", "FundCoverage"},

    Build = (stg as table, ok as table, typeName as text) as table =>
        let
            A = Table.SelectColumns(stg, {"Symbol", "Name", "Status"}),
            B = Table.SelectColumns(ok, Cols, MissingField.UseNull),
            J = Table.ExpandTableColumn(Table.NestedJoin(A, {"Symbol"}, B, {"Symbol"}, "B", JoinKind.LeftOuter), "B", List.RemoveItems(Cols, {"Symbol"})),
            T = Table.AddColumn(J, "Type", each typeName, type text)
        in
            T,

    Stocks   = Build(StgStocks, Scorecard, "Stock"),
    Idx      = Build(StgIndices, Indices, "Index / Macro"),
    All      = Table.Combine({Stocks, Idx}),

    Scored   = Table.AddColumn(All, "V", each
                let
                    days    = if [LastDate] = null then null else Duration.Days(TodayIst - [LastDate]),
                    stale   = days <> null and days > 5,
                    hiDiff  = if [High52] = null or [High52Candles] = null or [High52Candles] = 0 then null else Number.Abs([High52] / [High52Candles] - 1),
                    loDiff  = if [Low52] = null or [Low52Candles] = null or [Low52Candles] = 0 then null else Number.Abs([Low52] / [Low52Candles] - 1),
                    mism    = (hiDiff <> null and hiDiff > 0.05) or (loDiff <> null and loDiff > 0.05),
                    lowHist = [HistRows] <> null and [HistRows] < 200,
                    fundBad = [Type] = "Stock" and ([FundCoverage] = null or [FundCoverage] < 0.5),
                    issues  = List.Select({
                                  if [Status] <> "OK" then [Status] else null,
                                  if stale then "Stale price (" & Text.From(days) & " days old)" else null,
                                  if mism then "52W high/low differ >5% between sources" else null,
                                  if lowHist then "Short history (<200 sessions) - SMA200 unavailable" else null,
                                  if fundBad then "Fundamentals incomplete - valuation/analyst scores limited" else null
                              }, each _ <> null),
                    overall = if [Status] <> "OK" then "Failed" else if List.Count(issues) > 0 then "Warning" else "Good"
                in
                    [DaysSinceTrade = days, Overall = overall, Issues = Text.Combine(issues, "; ")]),
    OutNames = {"DaysSinceTrade", "Overall", "Issues"},
    Expanded = Table.ExpandRecordColumn(Scored, "V", OutNames, OutNames),
    Typed    = Table.TransformColumnTypes(Expanded, {{"Status", type text}, {"HistRows", Int64.Type}, {"LastDate", type date}, {"FundCoverage", type number}, {"DaysSinceTrade", Int64.Type}, {"Overall", type text}, {"Issues", type text}, {"FundStatus", type text}, {"FundSource", type text}})
in
    Typed
