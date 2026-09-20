local stub = require("wow_stub")

local WATER = "|cnIQ1:|Hitem:159::::::::6:1485:::::::::|h[Refreshing Spring Water]|h|r"
local BREAD = "|cnIQ1:|Hitem:4540::::::::6:1485:::::::::|h[Tough Hunk of Bread]|h|r"
local EGG = "|cnIQ0:|Hitem:4757::::::::6:1485:::::::::|h[Cracked Egg Shells]|h|r"

local function load()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    LL.DB.settings.showUnclaimed = true
    stub.SetItems({
        [159] = { name = "Refreshing Spring Water", quality = 1, sellPrice = 13, icon = 132794 },
        [4540] = { name = "Tough Hunk of Bread", quality = 1, sellPrice = 25, icon = 133964 },
        [4757] = { name = "Cracked Egg Shells", quality = 0, sellPrice = 5, icon = 132835 },
    })
    return LL
end

local function seed(LL)
    LL.Ledger.RecordKill(257532, "Windshaper Novice Seer")
    LL.Ledger.RecordItem(257532, "159:0", "Refreshing Spring Water", WATER, 3)   -- 39
    LL.Ledger.RecordItem(257532, "4540:0", "Tough Hunk of Bread", BREAD, 1)      -- 25
    LL.Ledger.RecordCoin(257532, 31)
    LL.Ledger.RecordUnclaimed(257532, "4757:0", "Cracked Egg Shells", EGG, 2)
end

T.test("sections carry priced entries sorted by value with coin among them", function()
    local LL = load()
    seed(LL)
    local report = LL.Report.Build("session")
    T.eq(#report.sections, 1)
    local sec = report.sections[1]
    T.eq(sec.npcID, 257532)
    T.eq(sec.name, "Windshaper Novice Seer")
    T.eq(sec.kills, 1)
    T.eq(sec.coin, 31)
    T.eq(sec.itemValue, 64)
    T.eq(sec.value, 95)
    T.eq(#sec.entries, 4)
    T.eq(sec.entries[1].itemKey, "159:0"); T.eq(sec.entries[1].value, 39); T.eq(sec.entries[1].unitPrice, 13); T.eq(sec.entries[1].priceLabel, "vendor")
    T.eq(sec.entries[2].kind, "coin"); T.eq(sec.entries[2].value, 31); T.eq(sec.entries[2].count, 31)
    T.eq(sec.entries[3].itemKey, "4540:0"); T.eq(sec.entries[3].value, 25)
    T.eq(sec.entries[4].itemKey, "4757:0"); T.truthy(sec.entries[4].unclaimed); T.eq(sec.entries[4].value, 0); T.eq(sec.entries[4].count, 2)
    T.eq(sec.entries[1].icon, 132794)
    T.eq(sec.entries[1].count, 3)
    T.eq(sec.entries[1].link, WATER)
end)

T.test("unclaimed entries can be hidden", function()
    local LL = load()
    seed(LL)
    LL.DB.settings.showUnclaimed = false
    local sec = LL.Report.Build("session").sections[1]
    T.eq(#sec.entries, 3)
    for _, e in ipairs(sec.entries) do T.falsy(e.unclaimed) end
end)

T.test("filtered items vanish from sections and totals", function()
    local LL = load()
    seed(LL)
    LL.Ledger.Filter("159:0", "Refreshing Spring Water", WATER)
    local report = LL.Report.Build("session")
    local sec = report.sections[1]
    T.eq(#sec.entries, 3)
    T.eq(sec.itemValue, 25)
    T.eq(report.totals.itemValue, 25)
    T.eq(report.totals.total, 56)
end)

T.test("sections sort by recency or by value", function()
    local LL = load()
    LL.Ledger.RecordKill(1, "Old Rich")
    LL.Ledger.RecordCoin(1, 5000)
    stub.Advance(10)
    LL.Ledger.RecordKill(2, "New Poor")
    LL.Ledger.RecordCoin(2, 1)
    LL.DB.settings.sortMode = "recent"
    local r = LL.Report.Build("session")
    T.eq(r.sections[1].npcID, 2); T.eq(r.sections[2].npcID, 1)
    LL.DB.settings.sortMode = "value"
    r = LL.Report.Build("session")
    T.eq(r.sections[1].npcID, 1); T.eq(r.sections[2].npcID, 2)
end)

T.test("totals and rates", function()
    local LL = load()
    seed(LL)
    stub.Advance(30)
    local r = LL.Report.Build("session")
    T.eq(r.totals.kills, 1)
    T.eq(r.totals.coin, 31)
    T.eq(r.totals.itemValue, 64)
    T.eq(r.totals.total, 95)
    T.eq(r.totals.activeSeconds, 30)
    T.isnil(r.totals.goldPerHour, "rates need a minute")
    T.isnil(r.totals.killsPerHour)
    stub.Advance(1770) -- 30 minutes total
    r = LL.Report.Build("session")
    T.eq(r.totals.activeSeconds, 1800)
    T.eq(r.totals.goldPerHour, 190)
    T.eq(r.totals.killsPerHour, 2)
    local all = LL.Report.Build("alltime")
    T.eq(all.totals.total, 95)
    T.isnil(all.totals.activeSeconds)
    T.isnil(all.totals.goldPerHour)
end)

T.test("unpriced items are flagged and count as zero", function()
    local LL = load()
    LL.Ledger.RecordKill(257532, "Seer")
    LL.Ledger.RecordItem(257532, "999:0", "Mystery", "|Hitem:999::::::::6:1485:::::::::|h[Mystery]|h", 1)
    LL.Ledger.RecordItem(257532, "159:0", "Water", WATER, 1)
    local r = LL.Report.Build("session")
    T.truthy(r.anyUnpriced)
    T.eq(r.sections[1].itemValue, 13)
    local mystery = r.sections[1].entries[2]
    T.eq(mystery.itemKey, "999:0"); T.isnil(mystery.unitPrice); T.eq(mystery.value, 0)
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    r = LL.Report.Build("session")
    T.truthy(r.anyUnpriced)
end)

T.test("mobs without a resolved name get a placeholder", function()
    local LL = load()
    LL.Ledger.RecordKill(4242, nil)
    local r = LL.Report.Build("session")
    T.eq(r.sections[1].name, "Unknown (#4242)")
    T.truthy(r.sections[1].unnamed)
end)

T.test("unattributed loot shows as a final Other section only when present", function()
    local LL = load()
    seed(LL)
    T.eq(#LL.Report.Build("session").sections, 1)
    LL.Ledger.RecordItem(nil, "4540:0", "Tough Hunk of Bread", BREAD, 2)
    LL.Ledger.RecordCoin(nil, 100)
    LL.DB.settings.sortMode = "value"
    local r = LL.Report.Build("session")
    T.eq(#r.sections, 2)
    local other = r.sections[2]
    T.truthy(other.isOther)
    T.isnil(other.npcID)
    T.eq(other.kills, 0)
    T.eq(other.value, 150)
    T.eq(r.totals.total, 245)
    T.eq(r.totals.itemValue, 114)
end)

T.test("collapsed state is passed through", function()
    local LL = load()
    seed(LL)
    LL.DB.settings.collapsed[257532] = true
    T.truthy(LL.Report.Build("session").sections[1].collapsed)
end)
