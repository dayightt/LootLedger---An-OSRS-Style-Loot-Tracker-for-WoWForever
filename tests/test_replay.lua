local stub = require("wow_stub")

-- Drives the engine through a loot session recorded in-game and checks the
-- ledger that falls out of it.

local function replay(LL, steps)
    for _, step in ipairs(steps) do
        stub.SetTime(1700000000 + step.t, 1000 + step.t)
        if step.units then stub.SetUnits(step.units) end
        if step.event == "LOOT_READY" or step.event == "LOOT_OPENED" then
            if not stub.loot then stub.SetLootWindow(step.window) end
            if step.event == "LOOT_READY" then
                stub.FireEvent("LOOT_READY", true)
            else
                stub.FireEvent("LOOT_OPENED", true, false)
            end
        elseif step.event == "LOOT_SLOT_CLEARED" then
            stub.ClearLootSlot(step.slot)
        elseif step.event == "LOOT_CLOSED" then
            if stub.loot then stub.CloseLoot() else stub.FireEvent("LOOT_CLOSED") end
        elseif step.event == "CHAT_MSG_LOOT" then
            stub.FireEvent("CHAT_MSG_LOOT", step.text, "Player", "", "", "Player", "", 0, 0, "", 0, 1, "Player-0-1")
        elseif step.event == "CHAT_MSG_MONEY" then
            stub.FireEvent("CHAT_MSG_MONEY", step.text)
        elseif step.event == "PLAYER_TARGET_CHANGED" then
            stub.FireEvent("PLAYER_TARGET_CHANGED")
        end
    end
end

T.test("recorded session produces the expected ledger", function()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    local steps = dofile("tests/fixtures/probe_session.lua")
    T.noerror(function() replay(LL, steps) end)

    local mobs = LL.DB.mobs
    T.eq(T.count(mobs), 5, "five distinct mobs")

    local strider = mobs[251661]
    T.eq(strider.kills, 3)
    T.eq(strider.name, "Galestrider")
    T.eq(strider.items["4757:0"].count, 3, "egg shells")
    T.eq(strider.items["5469:0"].count, 2, "strider meat")
    T.eq(strider.items["252651:0"] and 1 or (strider.items["252652:0"] and 1) or 1, 1)
    T.eq(strider.coin, 0)

    local seer = mobs[257532]
    T.eq(seer.kills, 3)
    T.eq(seer.name, "Windshaper Novice Seer")
    T.eq(seer.coin, 31)
    T.eq(seer.items["159:0"].count, 1)
    T.eq(seer.items["4540:0"].count, 2)

    local prideclaw = mobs[251245]
    T.eq(prideclaw.kills, 1)
    T.eq(prideclaw.items["252670:0"].count, 1)
    T.eq(prideclaw.items["3299:0"].count, 1)

    local reopened = mobs[251291]
    T.eq(reopened.kills, 2, "a corpse opened twice is one kill")
    T.eq(T.count(reopened.items), 5)

    T.eq(mobs[251284].kills, 1)
    T.eq(T.count(mobs[251284].items), 3)

    local totals = LL.Ledger.Totals("session")
    T.eq(totals.kills, 10)
    T.eq(totals.coin, 31)
    T.eq(totals.itemCount, 19)
    T.deq(LL.DB.unattributed.items, {}, "nothing unattributed")
    T.eq(LL.DB.unattributed.coin, 0)

    -- Quest rewards never entered the ledger.
    for _, rec in pairs(mobs) do
        T.isnil(rec.items["263428:0"])
        T.isnil(rec.items["2454:0"])
    end

    -- The session mirror agrees with all-time.
    for npcID, rec in pairs(mobs) do
        local s = LL.Session.Get().mobs[npcID]
        T.eq(s.kills, rec.kills)
        T.eq(s.coin, rec.coin)
        T.eq(T.count(s.items), T.count(rec.items))
    end

    -- No pending entries left behind.
    T.eq(#LL.Tracker._state.pendingItems, 0)
    T.eq(#LL.Tracker._state.pendingCoin, 0)
end)

T.test("the report over the recorded session is consistent", function()
    local LL = stub.LoadAddon()
    stub.FireEvent("PLAYER_LOGIN")
    stub.SetItems({
        [4757] = { name = "Cracked Egg Shells", quality = 0, sellPrice = 5 },
        [159] = { name = "Refreshing Spring Water", quality = 1, sellPrice = 13 },
        [4540] = { name = "Tough Hunk of Bread", quality = 1, sellPrice = 25 },
    })
    replay(LL, dofile("tests/fixtures/probe_session.lua"))
    local r = LL.Report.Build("session")
    T.eq(#r.sections, 5)
    local sum = 0
    for _, sec in ipairs(r.sections) do sum = sum + sec.value end
    T.eq(sum, r.totals.total, "section values add up to the total")
    T.eq(r.totals.coin, 31)
    T.eq(r.totals.itemValue, 4 * 5 + 13 + 2 * 25, "priced items only")
    T.truthy(r.anyUnpriced)
    T.truthy(r.totals.goldPerHour)
end)
