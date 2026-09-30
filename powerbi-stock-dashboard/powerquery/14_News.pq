// Query name : News               (LOAD: ON)
// Live headlines from Google News RSS (last 3 days): market-wide topics from config\news_topics.csv
// plus the latest headlines for every watchlist stock, each with a simple keyword sentiment score (-1 .. +1).
let
    Root      = Text.TrimEnd(ProjectFolder, {"\", "/"}),
    TopicsRaw = Table.PromoteHeaders(Csv.Document(File.Contents(Root & "\config\news_topics.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]), [PromoteAllScalars = true]),
    TopicQ    = Table.AddColumn(Table.AddColumn(Table.SelectColumns(TopicsRaw, {"Topic", "Query"}), "Symbol", each null, type nullable text), "MaxItems", each 8, Int64.Type),
    StockQ    = Table.AddColumn(
                    Table.AddColumn(Table.AddColumn(Table.SelectColumns(Watchlist, {"Symbol", "Name"}), "Topic", each "Stock", type text),
                        "Query", each [Name] & " share price stock", type text),
                    "MaxItems", each 4, Int64.Type),
    AllQ      = Table.Combine({Table.SelectColumns(TopicQ, {"Symbol", "Topic", "Query", "MaxItems"}), Table.SelectColumns(StockQ, {"Symbol", "Topic", "Query", "MaxItems"})}),

    // ---------- helpers ----------
    Decode = (t as text) as text =>
        Text.Replace(Text.Replace(Text.Replace(Text.Replace(Text.Replace(Text.Replace(Text.Replace(t, "<![CDATA[", ""), "]]>", ""), "&#39;", "'"), "&apos;", "'"), "&quot;", """"), "&lt;", "<"), "&amp;", "&"),
    Tag = (chunk as text, name as text) as text =>
        try Decode(Text.BetweenDelimiters(chunk, "<" & name & ">", "</" & name & ">")) otherwise "",
    PosWords = {"surge", "rally", "gain", "jump", "soar", "record high", "beats", "upgrade", "buy", "strong", "rise", "rising", "bullish", "outperform", "rebound", "boost", "wins ", "order", "profit up", "growth", "approval", "dividend", "bonus"},
    NegWords = {"fall", "plunge", "slump", "crash", "loss", "downgrade", "sell", "weak", "miss ", "misses", "missed", "fraud", "probe", "penalty", "bearish", "cut", "decline", "slide", "tumble", "default", "lawsuit", "raid", "war ", "tariff", "recession", "layoff", "ban ", "bans ", "fined", "slowdown", "concern"},
    Score = (headline as text) as number =>
        let
            padded = " " & Text.Lower(headline) & " ",
            pos    = List.Count(List.Select(PosWords, (w) => Text.Contains(padded, " " & w))),
            neg    = List.Count(List.Select(NegWords, (w) => Text.Contains(padded, " " & w)))
        in
            if pos + neg = 0 then 0 else (pos - neg) / (pos + neg),

    ParseItem = (chunk as text) as list =>
        let
            rawTitle = Tag(chunk, "title"),
            src      = try Decode(Text.BetweenDelimiters(Text.AfterDelimiter(chunk, "<source"), ">", "</source>")) otherwise "",
            headline = if src <> "" and Text.EndsWith(rawTitle, " - " & src) then Text.Start(rawTitle, Text.Length(rawTitle) - Text.Length(src) - 3) else rawTitle,
            pubText  = Tag(chunk, "pubDate"),
            pub      = try DateTime.FromText(Text.BetweenDelimiters(pubText, ", ", " GMT"), [Format = "d MMM yyyy HH:mm:ss", Culture = "en-US"]) + #duration(0, 5, 30, 0) otherwise null
        in
            {headline, src, Tag(chunk, "link"), pub},

    GetItems = (searchText as text, maxItems as number) as table =>
        let
            Body   = try Text.FromBinary(Web.Contents("https://news.google.com", [
                        RelativePath = "rss/search",
                        Query = [q = searchText & " when:3d", hl = "en-IN", gl = "IN", ceid = "IN:en"],
                        Headers = [#"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"]
                     ]), TextEncoding.Utf8) otherwise "",
            Chunks = List.Skip(Text.Split(Body, "<item>"), 1),
            Rows   = List.Transform(Chunks, each ParseItem(_)),
            T0     = Table.FromRows(Rows, {"Headline", "Source", "Link", "Published"}),
            T1     = Table.Distinct(Table.SelectRows(T0, each [Headline] <> ""), {"Headline"}),
            T2     = Table.Sort(T1, {{"Published", Order.Descending}})
        in
            Table.FirstN(T2, maxItems),

    // ---------- run ----------
    WithItems = Table.AddColumn(AllQ, "Items", each GetItems([Query], [MaxItems]), type table),
    Expanded  = Table.ExpandTableColumn(Table.RemoveColumns(WithItems, {"Query", "MaxItems"}), "Items", {"Headline", "Source", "Link", "Published"}),
    Typed     = Table.TransformColumnTypes(Expanded, {{"Symbol", type text}, {"Topic", type text}, {"Headline", type text}, {"Source", type text}, {"Link", type text}, {"Published", type datetime}}),
    Scored    = Table.AddColumn(Typed, "Sentiment", each if [Headline] = null then null else Score([Headline]), type number),
    Labeled   = Table.AddColumn(Scored, "SentimentLabel", each if [Sentiment] = null then null else if [Sentiment] > 0.15 then "Positive" else if [Sentiment] < -0.15 then "Negative" else "Neutral", type text),
    Clean     = Table.SelectRows(Labeled, each [Headline] <> null)
in
    Clean
