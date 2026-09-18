local stub = require("wow_stub")

local WATER = "|cnIQ1:|Hitem:159::::::::6:1485:::::::::|h[Refreshing Spring Water]|h|r"
local EGG = "|cnIQ0:|Hitem:4757::::::::6:1485:::::::::|h[Cracked Egg Shells]|h|r"

local function provider(id, label, price, available, priority)
    local p = { id = id, label = label, priority = priority or 10, calls = 0 }
    p.IsAvailable = function() return available ~= false end
    p.GetPrice = function(itemKey, link, itemID) p.calls = p.calls + 1; return type(price) == "function" and price() or price end
    return p
end

T.test("vendor price comes from item info", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    local price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 13); T.eq(label, "vendor")
    price, label = LL.Pricing.GetBestPrice("159:0")
    T.eq(price, 13, "key alone works")
end)

T.test("unknown items have no price yet", function()
    local LL = stub.LoadAddon()
    local price, label = LL.Pricing.GetBestPrice("999:0")
    T.isnil(price); T.isnil(label)
end)

T.test("the highest available provider wins, ties go to priority", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    LL.Pricing.Register(provider("a", "A", 20, true, 5))
    LL.Pricing.Register(provider("b", "B", 30, true, 1))
    LL.Pricing.Refresh()
    local price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 30); T.eq(label, "B")
    LL.Pricing.Register(provider("c", "C", 30, true, 9))
    LL.Pricing.Refresh()
    LL.Pricing.Flush()
    price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 30); T.eq(label, "C", "tie broken by priority")
end)

T.test("grey items are vendor-only", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [4757] = { name = "Cracked Egg Shells", quality = 0, sellPrice = 5 } })
    local p = provider("a", "A", 500)
    LL.Pricing.Register(p)
    LL.Pricing.Refresh()
    local price, label = LL.Pricing.GetBestPrice("4757:0", EGG)
    T.eq(price, 5); T.eq(label, "vendor")
    T.eq(p.calls, 0, "provider not consulted")
end)

T.test("unavailable providers are never called", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    local p = provider("a", "A", 500, false)
    LL.Pricing.Register(p)
    LL.Pricing.Refresh()
    local price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 13); T.eq(label, "vendor")
    T.eq(p.calls, 0)
end)

T.test("a provider returning nil or garbage is ignored", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    LL.Pricing.Register(provider("a", "A", nil))
    LL.Pricing.Register(provider("b", "B", "not a number"))
    LL.Pricing.Register({ id = "c", label = "C", IsAvailable = function() return true end, GetPrice = function() error("boom") end })
    LL.Pricing.Refresh()
    local price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 13); T.eq(label, "vendor")
end)

T.test("results are memoised until Flush, which announces the change", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    local value = 20
    local p = provider("a", "A", function() return value end)
    LL.Pricing.Register(p)
    LL.Pricing.Refresh()
    T.eq((LL.Pricing.GetBestPrice("159:0", WATER)), 20)
    value = 50
    T.eq((LL.Pricing.GetBestPrice("159:0", WATER)), 20, "memoised")
    T.eq(p.calls, 1)
    local fired = 0
    LL.On("PRICES_CHANGED", function() fired = fired + 1 end)
    LL.Pricing.Flush()
    T.eq(fired, 1)
    T.eq((LL.Pricing.GetBestPrice("159:0", WATER)), 50)
end)

T.test("an item load result flushes the memo so vendor prices appear", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13, loaded = false } })
    T.isnil((LL.Pricing.GetBestPrice("159:0", WATER)))
    local fired = 0
    LL.On("PRICES_CHANGED", function() fired = fired + 1 end)
    stub.LoadItem(159)
    T.eq(fired, 1)
    T.eq((LL.Pricing.GetBestPrice("159:0", WATER)), 13)
end)

T.test("Explain lists every provider", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    LL.Pricing.Register(provider("a", "A", 20, true))
    LL.Pricing.Register(provider("b", "B", 5, false))
    LL.Pricing.Refresh()
    local rows = LL.Pricing.Explain("159:0", WATER)
    local byId = {}
    for _, r in ipairs(rows) do byId[r.id] = r end
    T.eq(byId.vendor.price, 13); T.truthy(byId.vendor.available)
    T.eq(byId.a.price, 20); T.truthy(byId.a.available)
    T.isnil(byId.b.price); T.falsy(byId.b.available)
end)

T.test("Auctionator adapter registers when the addon and its API exist", function()
    local LL = stub.LoadAddon({ before = function()
        stub.SetAddOnLoaded("Auctionator", true)
        _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(caller, link) return 4200 end } } }
    end })
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    stub.FireEvent("PLAYER_LOGIN")
    local price, label = LL.Pricing.GetBestPrice("159:0", WATER)
    T.eq(price, 4200); T.eq(label, "AH")
    _G.Auctionator = nil
end)

T.test("Auctionator adapter stays out of the way when the addon is absent", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [159] = { name = "Water", quality = 1, sellPrice = 13 } })
    stub.FireEvent("PLAYER_LOGIN")
    local rows = LL.Pricing.Explain("159:0", WATER)
    local seen = {}
    for _, r in ipairs(rows) do seen[r.id] = r end
    T.truthy(seen.auctionator); T.falsy(seen.auctionator.available)
    T.truthy(seen.auctioneer); T.falsy(seen.auctioneer.available)
    T.eq((LL.Pricing.GetBestPrice("159:0", WATER)), 13)
end)

T.test("a zero vendor price is a known price, not a missing one", function()
    local LL = stub.LoadAddon()
    stub.SetItems({ [263428] = { name = "Dowsing Rod", quality = 1, sellPrice = 0 } })
    local price, label = LL.Pricing.GetBestPrice("263428:0")
    T.eq(price, 0); T.eq(label, "vendor")
    LL.Ledger.RecordKill(1, "Mob")
    LL.Ledger.RecordItem(1, "263428:0", "Dowsing Rod", "|Hitem:263428::::::::6:1485:::::::::|h[Dowsing Rod]|h", 1)
    local r = LL.Report.Build("session")
    T.falsy(r.anyUnpriced)
    T.eq(r.sections[1].entries[1].unitPrice, 0)
end)
