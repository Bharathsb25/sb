// Query name : Watchlist          (Enable load: OFF)
// Edit config\watchlist.csv in Excel/Notepad to add or remove stocks. Yahoo symbols:
//   NSE = SYMBOL.NS   BSE = SYMBOL.BO   US = plain (AAPL)   Others: see finance.yahoo.com
let
    Path   = Text.TrimEnd(ProjectFolder, {"\", "/"}) & "\config\watchlist.csv",
    Raw    = Csv.Document(File.Contents(Path), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Header = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
    Typed  = Table.TransformColumnTypes(Header, {{"Symbol", type text}, {"Name", type text}, {"Sector", type text}}),
    Clean  = Table.Distinct(Table.SelectRows(Typed, each [Symbol] <> null and Text.Trim([Symbol]) <> ""), {"Symbol"})
in
    Clean
