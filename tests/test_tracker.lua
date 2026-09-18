local stub = require("wow_stub")

local SEER = "Creature-0-4621-2991-336-257532-00012C894C"
local SEER_B = "Creature-0-4621-2991-336-257532-00002C8916"
local STRIDER = "Creature-0-4621-2991-336-251661-00032C88A3"
local CHEST = "GameObject-0-4621-2991-336-1234-00000ABCDE"
local WATER = "|cnIQ1:|Hitem:159::::::::6:1485:::::::::|h[Refreshing Spring Water]|h|r"
local BREAD = "|cnIQ1:|Hitem:4540::::::::6:1485:::::::::|h[Tough Hunk of Bread]|h|r"
local EGG = "|cnIQ0:|Hitem:4757::::::::6:1485:::::::::|h[Cracked Egg Shells]|h|r"

local function load()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    stub.SetUnits({ target = { guid = SEER, name = "Windshaper Novice Seer", dead = true } })
    return LL
end

local function seerWindow()
    stub.SetLootWindow({
        { type = 2, name = "16 Copper", sources = { { SEER, 16 } } },
        { type = 1, link = WATER, name = "Refreshing Spring Water", qty = 1, quality = 1, sources = { { SEER, 1 } } },
    })
end

T.test("LOOT_READY snapshots the window and records one kill per corpse", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    local snap = LL.Tracker._state.snapshot
    T.truthy(snap)
    T.eq(snap.slots[1].kind, "coin"); T.eq(snap.slots[1].copper, 16); T.eq(snap.slots[1].npcID, 257532)
    T.eq(snap.slots[2].kind, "item"); T.eq(snap.slots[2].itemKey, "159:0"); T.eq(snap.slots[2].qty, 1)
    T.eq(LL.DB.mobs[257532].kills, 1)
    T.eq(LL.DB.mobs[257532].name, "Windshaper Novice Seer")
    -- The client fires READY again and OPENED in between; neither may double count.
    stub.FireEvent("LOOT_OPENED", true, false)
    stub.FireEvent("LOOT_READY", true)
    T.eq(LL.DB.mobs[257532].kills, 1)
    T.eq(LL.Tracker._state.lastCorpse.npcID, 257532)
end)

T.test("LOOT_OPENED alone still snapshots when READY was missed", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_OPENED", true, false)
    T.truthy(LL.Tracker._state.snapshot)
    T.eq(LL.DB.mobs[257532].kills, 1)
end)

T.test("several corpses in one window are several kills; objects are none", function()
    local LL = load()
    stub.SetUnits({})
    stub.SetLootWindow({
        { type = 1, link = WATER, name = "Water", qty = 1, sources = { { SEER, 1 } } },
        { type = 1, link = BREAD, name = "Bread", qty = 1, sources = { { STRIDER, 1 } } },
        { type = 1, link = EGG, name = "Egg", qty = 2, sources = { { SEER, 1 }, { STRIDER, 1 } } },
        { type = 1, link = EGG, name = "Egg", qty = 1, sources = { { CHEST, 1 } } },
    })
    stub.FireEvent("LOOT_READY", true)
    T.eq(LL.DB.mobs[257532].kills, 1)
    T.eq(LL.DB.mobs[251661].kills, 1)
    T.isnil(LL.DB.mobs[257532].name, "no name source available")
    T.eq(LL.Ledger.Totals("session").kills, 2)
    T.isnil(LL.Tracker._state.snapshot.slots[4].npcID)
end)

T.test("reopening the same corpse is not a new kill until the dedupe window passes", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    T.eq(LL.DB.mobs[257532].kills, 1)
    stub.CloseLoot()
    stub.Advance(601)
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    T.eq(LL.DB.mobs[257532].kills, 2)
end)

T.test("clearing a slot queues it once; receipts pop the queue and credit the mob", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(1)
    stub.ClearLootSlot(1)
    stub.ClearLootSlot(2)
    local st = LL.Tracker._state
    T.eq(#st.pendingCoin, 1); T.eq(st.pendingCoin[1].copper, 16); T.eq(st.pendingCoin[1].npcID, 257532)
    T.eq(#st.pendingItems, 1); T.eq(st.pendingItems[1].itemKey, "159:0")
    stub.CloseLoot()
    T.isnil(st.snapshot)
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty", "", "", "Shooty", "", 0, 0, "", 0, 1, "Player-4613-00792BD7")
    T.eq(LL.DB.mobs[257532].items["159:0"].count, 1)
    T.eq(LL.DB.mobs[257532].items["159:0"].link, WATER)
    T.eq(#st.pendingItems, 0)
    stub.FireEvent("PLAYER_MONEY")
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 16 Copper")
    T.eq(LL.DB.mobs[257532].coin, 16)
    T.eq(#st.pendingCoin, 0)
    T.eq(LL.Session.Get().mobs[257532].coin, 16)
end)

T.test("a receipt with nothing pending is counted without a mob", function()
    local LL = load()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER .. "x3", "Shooty")
    T.eq(LL.DB.unattributed.items["159:0"].count, 3)
    T.eq(LL.Ledger.Totals("session").itemCount, 3)
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 5 Copper")
    T.eq(LL.DB.unattributed.coin, 5)
end)

T.test("roll wins fall back to the most recent corpse for five minutes", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    stub.Advance(100)
    stub.FireEvent("CHAT_MSG_LOOT", "|HlootHistory:3|h[Loot]|h: You won: " .. BREAD, "Shooty")
    T.eq(LL.DB.mobs[257532].items["4540:0"].count, 1)
    stub.Advance(400)
    stub.FireEvent("CHAT_MSG_LOOT", "|HlootHistory:4|h[Loot]|h: You (Greed - 50) Won: " .. BREAD, "Shooty")
    T.eq(LL.DB.mobs[257532].items["4540:0"].count, 1, "too old")
    T.eq(LL.DB.unattributed.items["4540:0"].count, 1)
end)

T.test("plain receipts do not use the corpse fallback", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. BREAD, "Shooty")
    T.isnil(LL.DB.mobs[257532].items["4540:0"])
    T.eq(LL.DB.unattributed.items["4540:0"].count, 1)
end)

T.test("other players' pickups become unclaimed entries on the mob", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(2)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. WATER .. ".", "Bob")
    T.eq(LL.DB.mobs[257532].unclaimed["159:0"].count, 1)
    T.isnil(LL.DB.mobs[257532].items["159:0"])
    stub.FireEvent("CHAT_MSG_LOOT", "|HlootHistory:9|h[Loot]|h: Bob won: " .. BREAD, "Bob")
    T.eq(LL.DB.mobs[257532].unclaimed["4540:0"].count, 1, "roll fallback applies to others too")
    T.eq(LL.Ledger.Totals("session").itemCount, 0)
end)

T.test("group coin credits your share, not the corpse total", function()
    local LL = load()
    stub.SetLootWindow({ { type = 2, name = "1 Silver", sources = { { SEER, 100 } } } })
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(1)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_MONEY", "Your share of the loot is 20 Copper.")
    T.eq(LL.DB.mobs[257532].coin, 20)
end)

T.test("pending entries expire", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(2)
    stub.CloseLoot()
    stub.Advance(16)
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty")
    T.isnil(LL.DB.mobs[257532].items["159:0"])
    T.eq(LL.DB.unattributed.items["159:0"].count, 1)
end)

T.test("receipts are matched by item, not by order", function()
    local LL = load()
    stub.SetLootWindow({
        { type = 1, link = WATER, name = "Water", qty = 1, sources = { { SEER, 1 } } },
        { type = 1, link = BREAD, name = "Bread", qty = 1, sources = { { STRIDER, 1 } } },
    })
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(1)
    stub.ClearLootSlot(2)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. BREAD, "Shooty")
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty")
    T.eq(LL.DB.mobs[251661].items["4540:0"].count, 1)
    T.eq(LL.DB.mobs[257532].items["159:0"].count, 1)
end)

T.test("secret loot sources lose attribution but never error", function()
    local LL = load()
    stub.SetLootWindow({
        { type = 1, link = WATER, name = "Water", qty = 1, sources = { { stub.MakeSecret(SEER), 1 } } },
    })
    T.noerror(function() stub.FireEvent("LOOT_READY", true) end)
    T.eq(T.count(LL.DB.mobs), 0)
    stub.ClearLootSlot(1)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty")
    T.eq(LL.DB.unattributed.items["159:0"].count, 1)
    T.noerror(function()
        stub.FireEvent("CHAT_MSG_LOOT", stub.MakeSecret("You receive loot: " .. WATER), "Shooty")
        stub.FireEvent("CHAT_MSG_MONEY", stub.MakeSecret("You loot 5 Copper"))
    end)
    T.eq(LL.DB.unattributed.items["159:0"].count, 1)
    T.eq(LL.DB.unattributed.coin, 0)
end)

T.test("filtered items and quest rewards are not recorded", function()
    local LL = load()
    LL.Ledger.Filter("159:0", "Refreshing Spring Water", WATER)
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(2)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty")
    stub.FireEvent("CHAT_MSG_LOOT", "You receive item: " .. BREAD, "Shooty")
    T.isnil(LL.DB.mobs[257532].items["159:0"])
    T.isnil(LL.DB.unattributed.items["4540:0"])
    T.eq(LL.Ledger.Totals("session").itemCount, 0)
end)

T.test("a coin slot without a source amount falls back to parsing its label", function()
    local LL = load()
    stub.SetLootWindow({ { type = 2, name = "3 Silver, 7 Copper", sources = { { SEER, nil } } } })
    stub.FireEvent("LOOT_READY", true)
    T.eq(LL.Tracker._state.snapshot.slots[1].copper, 307)
end)

T.test("target and mouseover changes teach the name cache", function()
    local LL = load()
    stub.SetUnits({ target = { guid = STRIDER, name = "Galestrider" }, mouseover = { guid = SEER_B, name = "Windshaper Novice Seer" } })
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.eq(LL.DB.npcNames[251661], "Galestrider")
    T.eq(LL.DB.npcNames[257532], "Windshaper Novice Seer")
end)

T.test("tracing echoes what the engine consumed", function()
    local LL = load()
    LL.Tracker.SetTracing(true)
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    T.truthy(#stub.chat > 0)
    T.truthy(string.find(stub.LastChat(), "257532", 1, true) or string.find(stub.chat[#stub.chat - 1], "257532", 1, true))
    LL.Tracker.SetTracing(false)
end)

T.test("the combat log is never registered", function()
    local LL = load()
    T.eq(stub.forbidden, 0)
    T.falsy(stub.AnyFrameRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
    T.falsy(stub.AnyFrameRegistered("COMBAT_LOG_EVENT"))
end)

T.test("a window closed without slot-cleared events still attributes its receipts", function()
    local LL = load()
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. WATER, "Shooty")
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 16 Copper")
    T.eq(LL.DB.mobs[257532].items["159:0"].count, 1)
    T.eq(LL.DB.mobs[257532].coin, 16)
end)

T.test("coin receipts prefer the pending slot with the same amount", function()
    local LL = load()
    stub.SetLootWindow({ { type = 2, name = "5 Copper", sources = { { STRIDER, 5 } } } })
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    stub.SetLootWindow({ { type = 2, name = "9 Copper", sources = { { SEER, 9 } } } })
    stub.FireEvent("LOOT_READY", true)
    stub.ClearLootSlot(1)
    stub.CloseLoot()
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 9 Copper")
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 5 Copper")
    T.eq(LL.DB.mobs[257532].coin, 9)
    T.eq(LL.DB.mobs[251661].coin, 5)
end)

T.test("a party member's pickup is attributed to the corpse they are targeting", function()
    local LL = load()
    stub.inGroup = true
    stub.SetUnits({
        party1 = { guid = "Player-1-AAA", name = "Kirbeer", isPlayer = true },
        party1target = { guid = STRIDER, name = "Galestrider", dead = true },
    })
    stub.FireEvent("CHAT_MSG_LOOT", "Kirbeer-Mortal receives loot: " .. WATER .. "x2.", "Kirbeer-Mortal")
    T.eq(LL.DB.mobs[251661].unclaimed["159:0"].count, 2)
    T.eq(LL.DB.mobs[251661].name, "Galestrider", "name learned from the target")
    T.eq(LL.DB.mobs[251661].kills, 0, "not our kill")
    T.eq(LL.Ledger.Totals("session").itemCount, 0)
end)

T.test("a party member's pickup with nothing to go on lands under Other loot", function()
    local LL = load()
    stub.inGroup = true
    stub.SetUnits({ party1 = { guid = "Player-1-AAA", name = "Kirbeer", isPlayer = true } })
    stub.FireEvent("CHAT_MSG_LOOT", "Kirbeer-Mortal receives loot: " .. WATER .. ".", "Kirbeer-Mortal")
    T.eq(LL.DB.unattributed.unclaimed["159:0"].count, 1)
    local r = LL.Report.Build("session")
    T.eq(#r.sections, 1)
    T.truthy(r.sections[1].isOther)
    T.truthy(r.sections[1].entries[1].unclaimed)
    T.eq(r.totals.total, 0)
end)

T.test("a party member's pickup falls back to the most recent corpse you opened", function()
    local LL = load()
    stub.inGroup = true
    seerWindow()
    stub.FireEvent("LOOT_READY", true)
    stub.CloseLoot()
    stub.SetUnits({ party1 = { guid = "Player-1-AAA", name = "Kirbeer", isPlayer = true } })
    stub.FireEvent("CHAT_MSG_LOOT", "Kirbeer receives loot: " .. BREAD .. ".", "Kirbeer")
    T.eq(LL.DB.mobs[257532].unclaimed["4540:0"].count, 1)
end)

T.test("a coin split is attributed to a group member's dead target", function()
    local LL = load()
    stub.inGroup = true
    stub.SetUnits({
        party2 = { guid = "Player-1-BBB", name = "Someone", isPlayer = true },
        party2target = { guid = STRIDER, name = "Galestrider", dead = true },
    })
    stub.FireEvent("CHAT_MSG_MONEY", "Your share of the loot is 12 Copper.")
    T.eq(LL.DB.mobs[251661].coin, 12)
    -- Solo-style loot text never uses the group guess.
    stub.FireEvent("CHAT_MSG_MONEY", "You loot 3 Copper")
    T.eq(LL.DB.unattributed.coin, 3)
end)

T.test("secret group targets are ignored without error", function()
    local LL = load()
    stub.inGroup = true
    stub.SetUnits({
        party1 = { guid = "Player-1-AAA", name = "Kirbeer", isPlayer = true },
        party1target = { guid = stub.MakeSecret(STRIDER), name = stub.MakeSecret("x"), dead = true },
    })
    T.noerror(function()
        stub.FireEvent("CHAT_MSG_LOOT", "Kirbeer receives loot: " .. WATER .. ".", "Kirbeer")
    end)
    T.eq(LL.DB.unattributed.unclaimed["159:0"].count, 1)
end)
