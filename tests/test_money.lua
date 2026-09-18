local stub = require("wow_stub")

local function parse(LL, text) return LL.Tracker.ParseMoneyMessage(text) end

T.test("solo loot amounts", function()
    local LL = stub.LoadAddon()
    T.eq(parse(LL, "You loot 16 Copper"), 16)
    T.eq(parse(LL, "You loot 3 Silver, 16 Copper"), 316)
    T.eq(parse(LL, "You loot 1 Gold, 3 Silver, 16 Copper"), 10316)
    T.eq(parse(LL, "You loot 2 Gold"), 20000)
    T.eq(parse(LL, "You loot 1 Gold, 50 Copper"), 10050)
end)

T.test("group share and guild bank variants", function()
    local LL = stub.LoadAddon()
    T.eq(parse(LL, "Your share of the loot is 20 Copper."), 20)
    T.eq(parse(LL, "Your share of the loot is 1 Silver, 5 Copper."), 105)
    T.eq(parse(LL, "You loot 90 Copper (10 Copper deposited to guild bank)"), 90)
    T.eq(parse(LL, "Your share of the loot is 45 Copper. (5 Copper deposited to guild bank)"), 45)
end)

T.test("other players' loot and unrelated text are ignored", function()
    local LL = stub.LoadAddon()
    T.isnil(parse(LL, "Bob loots 16 Copper."))
    T.isnil(parse(LL, "Received 5 Silver."))
    T.isnil(parse(LL, "You loot nothing"))
    T.isnil(parse(LL, nil))
    T.noerror(function() T.isnil(parse(LL, stub.MakeSecret("You loot 16 Copper"))) end)
end)

T.test("amount words come from the client's strings", function()
    local LL = stub.LoadAddon()
    _G.YOU_LOOT_MONEY = "Ihr erhaltet %s"
    _G.GOLD_AMOUNT = "%d Gold"
    _G.SILVER_AMOUNT = "%d Silber"
    _G.COPPER_AMOUNT = "%d Kupfer"
    LL.Tracker.CompilePatterns()
    T.eq(parse(LL, "Ihr erhaltet 2 Silber, 7 Kupfer"), 207)
    T.isnil(parse(LL, "You loot 16 Copper"))
end)

T.test("ParseMoneyMessage reports group splits", function()
    local LL = stub.LoadAddon()
    local copper, split = LL.Tracker.ParseMoneyMessage("Your share of the loot is 20 Copper.")
    T.eq(copper, 20); T.truthy(split)
    copper, split = LL.Tracker.ParseMoneyMessage("You loot 16 Copper")
    T.eq(copper, 16); T.falsy(split)
end)
