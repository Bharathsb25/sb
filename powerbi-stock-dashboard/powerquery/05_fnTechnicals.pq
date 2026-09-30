// Query name : fnTechnicals       (FUNCTION; Enable load: OFF)
// Input : the record returned by fnFetchChart (Status = "OK").
// Output: one flat record of price, 52-week range, trend, momentum, risk and liquidity metrics.
(chart as record) as record =>
let
    H        = chart[Hist],
    Meta     = chart[Meta],
    C        = H[Close],
    N        = List.Count(C),
    LastP    = List.Last(C),
    PrevP    = if N > 1 then C{N - 2} else null,

    AvgLast  = (l as list, k as number) as nullable number => if List.Count(l) >= k then List.Average(List.LastN(l, k)) else null,
    Ret      = (l as list, k as number) as nullable number => if List.Count(l) > k then List.Last(l) / l{List.Count(l) - 1 - k} - 1 else null,

    // RSI(14) with Wilder smoothing
    RsiFn = (l as list) as nullable number =>
        if List.Count(l) < 16 then null else
        let
            Idx    = List.Positions(List.RemoveFirstN(l, 1)),
            Diffs  = List.Transform(Idx, each l{_ + 1} - l{_}),
            Gains  = List.Transform(Diffs, each if _ > 0 then _ else 0),
            Losses = List.Transform(Diffs, each if _ < 0 then -_ else 0),
            G0     = List.Average(List.FirstN(Gains, 14)),
            L0     = List.Average(List.FirstN(Losses, 14)),
            Rest   = List.Zip({List.Skip(Gains, 14), List.Skip(Losses, 14)}),
            Final  = List.Accumulate(Rest, {G0, L0}, (s, x) => {(s{0} * 13 + x{0}) / 14, (s{1} * 13 + x{1}) / 14})
        in
            if Final{1} = 0 then 100 else 100 - 100 / (1 + Final{0} / Final{1}),

    // Annualised volatility of daily returns
    Vol = (l as list) as nullable number =>
        if List.Count(l) < 30 then null else
        let
            R = List.Transform(List.Positions(List.RemoveFirstN(l, 1)), each l{_ + 1} / l{_} - 1)
        in
            List.StandardDeviation(R) * Number.Sqrt(252),

    // 52-week range: prefer Yahoo's own figure, fall back to the 1y candles
    Hi52H    = List.Max(H[High]),
    Lo52H    = List.Min(H[Low]),
    Hi52     = let v = Record.FieldOrDefault(Meta, "fiftyTwoWeekHigh", null) in if v = null then Hi52H else v,
    Lo52     = let v = Record.FieldOrDefault(Meta, "fiftyTwoWeekLow", null) in if v = null then Lo52H else v,

    Sma50V    = AvgLast(C, 50),
    Sma200V   = AvgLast(C, 200),
    LastDateV = List.Max(H[Date]),
    YStart   = Date.StartOfYear(LastDateV),
    Before   = Table.SelectRows(H, each [Date] < YStart),
    YtdBase  = if Table.RowCount(Before) > 0 then List.Last(Before[Close]) else null,

    Vols     = List.RemoveNulls(H[Volume]),
    VolN     = List.Count(Vols),
    AvgVol20 = if VolN > 21 then List.Average(List.Range(Vols, VolN - 21, 20)) else null,
    LastVol  = if VolN > 0 then List.Last(Vols) else null,

    TrendV    = if Sma50V = null or Sma200V = null then "n/a"
               else if LastP > Sma50V and Sma50V > Sma200V then "Uptrend"
               else if LastP < Sma50V and Sma50V < Sma200V then "Downtrend"
               else "Sideways / Mixed",
    Epoch    = #datetime(1970, 1, 1, 0, 0, 0),
    Offset   = Record.FieldOrDefault(Meta, "gmtoffset", 0),
    MktTime  = Record.FieldOrDefault(Meta, "regularMarketTime", null)
in
    [
        Price          = LastP,
        PrevClose      = PrevP,
        DayChange      = if PrevP = null then null else LastP - PrevP,
        DayChangePct   = if PrevP = null or PrevP = 0 then null else LastP / PrevP - 1,
        High52         = Hi52,
        Low52          = Lo52,
        High52Candles  = Hi52H,
        Low52Candles   = Lo52H,
        PctFromLow     = if Lo52 = null or Lo52 = 0 then null else LastP / Lo52 - 1,
        PctFromHigh    = if Hi52 = null or Hi52 = 0 then null else LastP / Hi52 - 1,
        Range52Pos     = if Hi52 = null or Lo52 = null or Hi52 = Lo52 then null else (LastP - Lo52) / (Hi52 - Lo52),
        Sma50          = Sma50V,
        Sma200         = Sma200V,
        Above50        = if Sma50V = null then null else LastP > Sma50V,
        Above200       = if Sma200V = null then null else LastP > Sma200V,
        Trend          = TrendV,
        Rsi14          = RsiFn(C),
        Ret1M          = Ret(C, 21),
        Ret3M          = Ret(C, 63),
        Ret6M          = Ret(C, 126),
        Ret1Y          = Ret(C, N - 1),
        RetYtd         = if YtdBase = null then null else LastP / YtdBase - 1,
        Volatility     = Vol(C),
        Volume         = LastVol,
        AvgVolume20    = AvgVol20,
        VolumeRatio    = if AvgVol20 = null or AvgVol20 = 0 or LastVol = null then null else LastVol / AvgVol20,
        Currency       = Record.FieldOrDefault(Meta, "currency", null),
        Exchange       = Record.FieldOrDefault(Meta, "fullExchangeName", Record.FieldOrDefault(Meta, "exchangeName", null)),
        LongName       = Record.FieldOrDefault(Meta, "longName", Record.FieldOrDefault(Meta, "shortName", null)),
        LastTradeTime  = if MktTime = null then null else Epoch + #duration(0, 0, 0, MktTime + Offset),
        LastDate       = LastDateV,
        HistRows       = N
    ]
