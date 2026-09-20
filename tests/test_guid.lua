local stub = require("wow_stub")

local SEER = "Creature-0-4621-2991-336-257532-00012C894C"
local SEER2 = "Creature-0-4621-2991-336-257532-00002C8916"
local CHEST = "GameObject-0-4621-2991-336-1234-00000ABCDE"
local PLAYER = "Player-4613-00792BD7"

T.test("Parse splits kind and numeric id", function()
    local LL = stub.LoadAddon()
    local kind, id = LL.Guid.Parse(SEER)
    T.eq(kind, "Creature")
    T.eq(id, 257532)
    kind, id = LL.Guid.Parse(CHEST)
    T.eq(kind, "GameObject")
    T.eq(id, 1234)
    kind, id = LL.Guid.Parse(PLAYER)
    T.eq(kind, "Player")
    T.isnil(id)
    T.isnil(LL.Guid.Parse(nil))
    T.isnil(LL.Guid.Parse(""))
    T.isnil(LL.Guid.Parse(stub.MakeSecret(SEER)))
end)

T.test("NpcID only for creatures and vehicles", function()
    local LL = stub.LoadAddon()
    T.eq(LL.Guid.NpcID(SEER), 257532)
    T.eq(LL.Guid.NpcID("Vehicle-0-4621-2991-336-777-00012C894C"), 777)
    T.isnil(LL.Guid.NpcID(CHEST))
    T.isnil(LL.Guid.NpcID(PLAYER))
    T.isnil(LL.Guid.NpcID(nil))
end)

T.test("ResolveName prefers the cache and does not call unit APIs", function()
    local LL = stub.LoadAddon()
    LL.DB.npcNames[257532] = "Cached Seer"
    stub.SetUnits({ target = { guid = SEER, name = "Live Seer" } })
    T.eq(LL.Guid.ResolveName(SEER, 257532), "Cached Seer")
    T.eq(LL.Guid.CachedName(257532), "Cached Seer")
end)

T.test("ResolveName uses UnitTokenFromGUID + UnitName and caches", function()
    local LL = stub.LoadAddon()
    stub.SetUnits({ target = { guid = SEER, name = "Windshaper Novice Seer" } })
    T.eq(LL.Guid.ResolveName(SEER, 257532), "Windshaper Novice Seer")
    T.eq(LL.DB.npcNames[257532], "Windshaper Novice Seer")
    -- A different spawn of the same npc resolves from cache alone.
    stub.SetUnits({})
    T.eq(LL.Guid.ResolveName(SEER2, 257532), "Windshaper Novice Seer")
end)

T.test("ResolveName falls back to the unit tooltip", function()
    local LL = stub.LoadAddon()
    stub.tooltipNames[SEER] = "Tooltip Seer"
    T.eq(LL.Guid.ResolveName(SEER, 257532), "Tooltip Seer")
    T.eq(LL.DB.npcNames[257532], "Tooltip Seer")
end)

T.test("ResolveName returns nil when nothing knows the unit", function()
    local LL = stub.LoadAddon()
    T.isnil(LL.Guid.ResolveName(SEER, 257532))
    T.isnil(LL.DB.npcNames[257532])
end)

T.test("ResolveName survives secret names and tokens", function()
    local LL = stub.LoadAddon()
    stub.SetUnits({ target = { guid = SEER, name = stub.MakeSecret("hidden") } })
    T.noerror(function() T.isnil(LL.Guid.ResolveName(SEER, 257532)) end)
    local savedToken = _G.UnitTokenFromGUID
    _G.UnitTokenFromGUID = function() return stub.MakeSecret("target") end
    T.noerror(function() T.isnil(LL.Guid.ResolveName(SEER, 257532)) end)
    _G.UnitTokenFromGUID = savedToken
    local savedTip = C_TooltipInfo.GetHyperlink
    C_TooltipInfo.GetHyperlink = function() return stub.MakeSecretTable() end
    T.noerror(function() T.isnil(LL.Guid.ResolveName(SEER, 257532)) end)
    C_TooltipInfo.GetHyperlink = function() error("boom") end
    T.noerror(function() T.isnil(LL.Guid.ResolveName(SEER, 257532)) end)
    C_TooltipInfo.GetHyperlink = savedTip
end)

T.test("LearnUnit caches creatures and ignores players and secrets", function()
    local LL = stub.LoadAddon()
    stub.SetUnits({
        target = { guid = SEER, name = "Windshaper Novice Seer" },
        mouseover = { guid = PLAYER, name = "Someone", isPlayer = true },
    })
    LL.Guid.LearnUnit("target")
    LL.Guid.LearnUnit("mouseover")
    LL.Guid.LearnUnit("focus")
    T.eq(LL.DB.npcNames[257532], "Windshaper Novice Seer")
    T.eq(T.count(LL.DB.npcNames), 1)
    stub.SetUnits({ target = { guid = stub.MakeSecret(SEER), name = "x" } })
    T.noerror(function() LL.Guid.LearnUnit("target") end)
    T.eq(T.count(LL.DB.npcNames), 1)
end)

T.test("Learning a name fires LEDGER_CHANGED only when a mob record was waiting for it", function()
    local LL = stub.LoadAddon()
    local fired = 0
    LL.On("LEDGER_CHANGED", function() fired = fired + 1 end)
    stub.SetUnits({ target = { guid = SEER, name = "Windshaper Novice Seer" } })
    LL.Guid.LearnUnit("target")
    T.eq(fired, 0, "no record yet")
    LL.DB.mobs[257532] = { kills = 1, coin = 0, items = {}, unclaimed = {} }
    LL.DB.npcNames[257532] = nil
    LL.Guid.LearnUnit("target")
    T.eq(LL.DB.mobs[257532].name, "Windshaper Novice Seer")
    T.eq(fired, 1)
    LL.Guid.LearnUnit("target")
    T.eq(fired, 1, "already named")
end)

T.test("unnamed mobs are retried from their last GUID once a name is available", function()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    -- Looted while the name was unreadable.
    T.isnil(LL.Guid.ResolveName(SEER, 257532))
    LL.Ledger.RecordKill(257532, nil)
    T.isnil(LL.DB.mobs[257532].name)
    -- Later the unit is visible with a readable name.
    stub.SetUnits({ target = { guid = SEER, name = "Windshaper Novice Seer" } })
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(LL.DB.mobs[257532].name, "Windshaper Novice Seer")
    T.eq(LL.Session.Get().mobs[257532].name, "Windshaper Novice Seer")
end)

T.test("nameplates teach names too", function()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    LL.Ledger.RecordKill(257532, nil)
    stub.SetUnits({ nameplate3 = { guid = SEER2, name = "Windshaper Novice Seer" } })
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
    T.eq(LL.DB.mobs[257532].name, "Windshaper Novice Seer")
end)

T.test("a typed name overrides a learned one everywhere", function()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    LL.Ledger.RecordKill(257532, "Windshaper Novice Seer")
    local fired = 0
    LL.On("LEDGER_CHANGED", function() fired = fired + 1 end)
    LL.Guid.SetName(257532, "  Seer  ")
    T.eq(LL.DB.mobs[257532].name, "Seer")
    T.eq(LL.Session.Get().mobs[257532].name, "Seer")
    T.eq(LL.DB.npcNames[257532], "Seer")
    T.eq(fired, 1)
    LL.Guid.SetName(257532, "   ")
    T.eq(LL.DB.mobs[257532].name, "Seer", "blank ignored")
end)
