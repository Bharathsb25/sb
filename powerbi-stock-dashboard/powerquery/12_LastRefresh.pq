// Query name : LastRefresh        (LOAD: ON)
let
    NowIst = DateTime.From(DateTimeZone.SwitchZone(DateTimeZone.UtcNow(), 5, 30)),
    Out    = #table(type table [LastRefresh = datetime], {{NowIst}})
in
    Out
