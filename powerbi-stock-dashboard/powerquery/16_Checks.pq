// Query name : Checks             (LOAD: ON)  - thesis checklist in long form (one row per stock x test) for the Deep-Dive matrix.
let
    Src   = Table.SelectColumns(Scorecard, {"Symbol", "Chk_Valuation", "Chk_ROE", "Chk_Debt", "Chk_EarningsGrowth", "Chk_Above200DMA", "Chk_RSI", "Chk_AnalystUpside", "Chk_MarginOfSafety"}),
    Unpiv = Table.UnpivotOtherColumns(Src, {"Symbol"}, "CheckKey", "Result"),
    Names = #table(type table [CheckKey = text, Check = text, Pillar = text, Sort = Int64.Type], {
                {"Chk_Valuation", "P/E below sector median", "Valuation", 1},
                {"Chk_ROE", "ROE >= 15%", "Quality", 2},
                {"Chk_Debt", "Debt/Equity <= 1x", "Quality", 3},
                {"Chk_EarningsGrowth", "Earnings growing", "Growth", 4},
                {"Chk_Above200DMA", "Price above 200-DMA", "Momentum", 5},
                {"Chk_RSI", "RSI between 30 and 70", "Momentum", 6},
                {"Chk_AnalystUpside", "Analyst upside >= 10%", "Analyst", 7},
                {"Chk_MarginOfSafety", ">= 15% below 52W high", "Value", 8}}),
    Join  = Table.ExpandTableColumn(Table.NestedJoin(Unpiv, {"CheckKey"}, Names, {"CheckKey"}, "N", JoinKind.LeftOuter), "N", {"Check", "Pillar", "Sort"}),
    Out   = Table.RemoveColumns(Join, {"CheckKey"})
in
    Out
