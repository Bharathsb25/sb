// Query name : Prices             (LOAD: ON)  - 1 year of daily candles per stock; powers the price charts.
let
    Ok       = Table.SelectRows(StgStocks, each [Status] = "OK"),
    WithHist = Table.AddColumn(Ok, "Hist", each [Chart][Hist], type table),
    Keep     = Table.SelectColumns(WithHist, {"Symbol", "Hist"}),
    Expanded = Table.ExpandTableColumn(Keep, "Hist", {"Date", "Open", "High", "Low", "Close", "Volume"}),
    Typed    = Table.TransformColumnTypes(Expanded, {{"Symbol", type text}, {"Date", type date}, {"Open", type number}, {"High", type number}, {"Low", type number}, {"Close", type number}, {"Volume", Int64.Type}})
in
    Typed
