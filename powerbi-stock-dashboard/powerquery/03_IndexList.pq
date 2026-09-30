// Query name : IndexList          (Enable load: OFF)
// Edit config\indices.csv to add/remove global indices, commodities, FX, bonds, crypto.
let
    Path   = Text.TrimEnd(ProjectFolder, {"\", "/"}) & "\config\indices.csv",
    Raw    = Csv.Document(File.Contents(Path), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Header = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
    Typed  = Table.TransformColumnTypes(Header, {{"Symbol", type text}, {"Name", type text}, {"Group", type text}, {"Region", type text}}),
    Clean  = Table.Distinct(Table.SelectRows(Typed, each [Symbol] <> null and Text.Trim([Symbol]) <> ""), {"Symbol"})
in
    Clean
