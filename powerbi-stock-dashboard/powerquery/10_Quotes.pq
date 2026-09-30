// Query name : Quotes             (staging; Enable load: OFF)
// Live price + technicals for every stock that downloaded successfully.
let
    Ok      = Table.SelectRows(StgStocks, each [Status] = "OK"),
    Calc    = Table.AddColumn(Ok, "T", each fnTechnicals([Chart]), type record),
    Slim    = Table.RemoveColumns(Calc, {"Chart", "Status"}),
    Names   = Record.FieldNames(fnTechnicals(Ok{0}[Chart])),
    Expand  = Table.ExpandRecordColumn(Slim, "T", Names, Names),
    Types   = Table.TransformColumnTypes(Expand, {
                {"Price", type number}, {"PrevClose", type number}, {"DayChange", type number}, {"DayChangePct", type number},
                {"High52", type number}, {"Low52", type number}, {"High52Candles", type number}, {"Low52Candles", type number},
                {"PctFromLow", type number}, {"PctFromHigh", type number}, {"Range52Pos", type number},
                {"Sma50", type number}, {"Sma200", type number}, {"Above50", type logical}, {"Above200", type logical}, {"Trend", type text},
                {"Rsi14", type number}, {"Ret1M", type number}, {"Ret3M", type number}, {"Ret6M", type number}, {"Ret1Y", type number}, {"RetYtd", type number},
                {"Volatility", type number}, {"Volume", type number}, {"AvgVolume20", type number}, {"VolumeRatio", type number},
                {"Currency", type text}, {"Exchange", type text}, {"LongName", type text}, {"LastTradeTime", type datetime}, {"LastDate", type date}, {"HistRows", Int64.Type}})
in
    Types
