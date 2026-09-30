// Query name : fnFetchChart       (a FUNCTION - Power BI shows it with an fx icon; Enable load: OFF)
// Downloads 1 year of daily candles + live quote metadata for ONE Yahoo Finance symbol.
// Never throws: on any failure it returns [Status = "Error: ...", Meta = null, Hist = null]
// so one bad ticker cannot break the whole refresh (it is reported on the Data Validation page instead).
(symbol as text) as record =>
let
    Fetch = () =>
        let
            Response = Json.Document(
                Web.Contents(
                    "https://query1.finance.yahoo.com",
                    [
                        RelativePath = "v8/finance/chart/" & Uri.EscapeDataString(symbol),
                        Query = [range = "1y", interval = "1d", includePrePost = "false"],
                        Headers = [#"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"],
                        ManualStatusHandling = {400, 401, 403, 404, 429, 500, 502, 503}
                    ]
                )
            ),
            Result   = Response[chart][result]{0},
            MetaRec  = Result[meta],
            Offset   = Record.FieldOrDefault(MetaRec, "gmtoffset", 0),
            Stamps   = Result[timestamp],
            Q        = Result[indicators][quote]{0},
            Epoch    = #datetime(1970, 1, 1, 0, 0, 0),
            Dates    = List.Transform(Stamps, each Date.From(Epoch + #duration(0, 0, 0, _ + Offset))),
            Hist0    = Table.FromColumns({Dates, Q[open], Q[high], Q[low], Q[close], Q[volume]}, {"Date", "Open", "High", "Low", "Close", "Volume"}),
            Hist1    = Table.SelectRows(Hist0, each [Close] <> null),
            HistTbl  = Table.TransformColumnTypes(Hist1, {{"Date", type date}, {"Open", type number}, {"High", type number}, {"Low", type number}, {"Close", type number}, {"Volume", type number}})
        in
            [Status = if Table.RowCount(HistTbl) = 0 then "Error: no price rows returned" else "OK", Meta = MetaRec, Hist = HistTbl],
    Attempt = try Fetch(),
    Out     = if Attempt[HasError]
              then [Status = "Error: " & Attempt[Error][Message], Meta = null, Hist = null]
              else Attempt[Value]
in
    Out
