// Query name : IndexPrices        (LOAD: ON)  - 1 year of closes per index / commodity / FX; powers rebased comparison charts.
let
    Ok       = Table.SelectRows(StgIndices, each [Status] = "OK"),
    WithHist = Table.AddColumn(Ok, "Hist", each [Chart][Hist], type table),
    Keep     = Table.SelectColumns(WithHist, {"Symbol", "Name", "Group", "Region", "Hist"}),
    Expanded = Table.ExpandTableColumn(Keep, "Hist", {"Date", "Close"}),
    Typed    = Table.TransformColumnTypes(Expanded, {{"Symbol", type text}, {"Name", type text}, {"Group", type text}, {"Region", type text}, {"Date", type date}, {"Close", type number}})
in
    Typed
