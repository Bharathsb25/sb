// Query name : StgIndices         (staging; Enable load: OFF)
let
    Src     = IndexList,
    Fetched = Table.AddColumn(Src, "Chart", each fnFetchChart([Symbol]), type record),
    Out     = Table.AddColumn(Fetched, "Status", each [Chart][Status], type text)
in
    Out
