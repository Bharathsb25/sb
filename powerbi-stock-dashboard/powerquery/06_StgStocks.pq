// Query name : StgStocks          (staging; Enable load: OFF)
// One row per watchlist stock with the raw Yahoo response attached. Everything else reads from here,
// so each ticker is downloaded once per refresh.
let
    Src     = Watchlist,
    Fetched = Table.AddColumn(Src, "Chart", each fnFetchChart([Symbol]), type record),
    Out     = Table.AddColumn(Fetched, "Status", each [Chart][Status], type text)
in
    Out
