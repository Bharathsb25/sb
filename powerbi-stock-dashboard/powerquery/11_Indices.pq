// Query name : Indices            (LOAD: ON)  - latest level, change, 52W range, trend for every global index / commodity / FX / bond.
let
    Ok     = Table.SelectRows(StgIndices, each [Status] = "OK"),
    Calc   = Table.AddColumn(Ok, "T", each fnTechnicals([Chart]), type record),
    Slim   = Table.RemoveColumns(Calc, {"Chart", "Status"}),
    Names  = Record.FieldNames(fnTechnicals(Ok{0}[Chart])),
    Expand = Table.ExpandRecordColumn(Slim, "T", Names, Names),
    Types  = Table.TransformColumnTypes(Expand, {
                {"Price", type number}, {"PrevClose", type number}, {"DayChange", type number}, {"DayChangePct", type number},
                {"High52", type number}, {"Low52", type number}, {"PctFromLow", type number}, {"PctFromHigh", type number}, {"Range52Pos", type number},
                {"Sma50", type number}, {"Sma200", type number}, {"Trend", type text}, {"Rsi14", type number},
                {"Ret1M", type number}, {"Ret3M", type number}, {"Ret6M", type number}, {"Ret1Y", type number}, {"RetYtd", type number},
                {"Volatility", type number}, {"LastTradeTime", type datetime}, {"LastDate", type date}})
in
    Types
