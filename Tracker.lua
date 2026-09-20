-- Tracker: the event engine.
--
-- A loot window is snapshotted the moment it is ready: every slot with its
-- link/quantity and, from GetLootSourceInfo, the corpse it came from. A
-- kill is a corpse you opened. Slots that get cleared go into short-lived
-- pending queues; the chat receipts that arrive after the window closes
-- ("You receive loot: ...", "You loot 16 Copper") pop those queues, which
-- is what ties each pickup to its mob. Crediting the chat amount rather
-- than the slot amount makes party splits come out right by itself.

local _, LL = ...

local Tracker = {}
LL.Tracker = Tracker

local Items, Guid, Ledger = LL.Items, LL.Guid, LL.Ledger

local CORPSE_TTL = 600      -- seconds a corpse GUID stays deduped
local DEATH_TTL = 60        -- seconds an experience-message name waits for its corpse
local PENDING_TTL = 15      -- seconds a cleared slot waits for its receipt
local ROLL_FALLBACK = 300   -- seconds a roll win may trail the corpse it came from
local MOUSEOVER_THROTTLE = 0.25

local state = {
    snapshot = nil,
    pendingItems = {},
    pendingCoin = {},
    recentCorpses = {},
    lastCorpse = nil,
    recentDeaths = {},
}
Tracker._state = state

local tracing = false
function Tracker.SetTracing(on) tracing = on and true or false end
function Tracker.IsTracing() return tracing end

local function trace(fmt, ...)
    if tracing then LL.Print("|cff888888[trace]|r " .. string.format(fmt, ...)) end
end

-- ---------------------------------------------------------------------
-- Chat patterns, compiled from the client's own format strings so the
-- engine works in any locale.
-- ---------------------------------------------------------------------

local function escape(s)
    return (string.gsub(s, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end

-- "%s" captures lazily, "%d" captures digits. Anchored both ends.
local function patternFromFormat(fmt)
    local p = escape(fmt)
    p = string.gsub(p, "%%%%s", "(.-)")
    p = string.gsub(p, "%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- Each entry: which global string, what it means, and which capture
-- (counting only %s/%d in order) holds the quantity / player name.
local LOOT_FORMATS = {
    { global = "LOOT_ITEM_SELF_MULTIPLE",         kind = "own",   qty = 2 },
    { global = "LOOT_ITEM_SELF",                  kind = "own" },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED",  kind = "own",   roll = true },
    { global = "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", kind = "own",   roll = true },
    { global = "LOOT_ROLL_YOU_WON",               kind = "own",   roll = true },
    { global = "LOOT_ITEM_MULTIPLE",              kind = "other", player = 1, qty = 3 },
    { global = "LOOT_ITEM",                       kind = "other", player = 1 },
    { global = "LOOT_ROLL_WON_NO_SPAM_NEED",      kind = "other", player = 2, roll = true },
    { global = "LOOT_ROLL_WON_NO_SPAM_GREED",     kind = "other", player = 2, roll = true },
    { global = "LOOT_ROLL_WON",                   kind = "other", player = 2, roll = true },
}

local MONEY_FORMATS = { "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }
local SPLIT_FORMATS = { LOOT_MONEY_SPLIT_GUILD = true, LOOT_MONEY_SPLIT = true }
local AMOUNT_FORMATS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }

local lootPatterns = {}
local moneyPatterns = {}
local amountPatterns = {}
local deathPatterns = {}

function Tracker.CompilePatterns()
    lootPatterns = {}
    for _, def in ipairs(LOOT_FORMATS) do
        local fmt = _G[def.global]
        if type(fmt) == "string" then
            lootPatterns[#lootPatterns + 1] = {
                pattern = patternFromFormat(fmt), kind = def.kind, qty = def.qty, player = def.player, roll = def.roll,
            }
        end
    end
    moneyPatterns = {}
    for _, name in ipairs(MONEY_FORMATS) do
        local fmt = _G[name]
        if type(fmt) == "string" then
            moneyPatterns[#moneyPatterns + 1] = { pattern = patternFromFormat(fmt), split = SPLIT_FORMATS[name] or false }
        end
    end
    amountPatterns = {}
    for name, mult in pairs(AMOUNT_FORMATS) do
        local fmt = _G[name]
        if type(fmt) == "string" then
            -- Unanchored: several amounts sit in one string.
            local p = escape(fmt)
            p = string.gsub(p, "%%%%d", "(%%d+)")
            amountPatterns[#amountPatterns + 1] = { pattern = p, mult = mult }
        end
    end
    -- "%s dies, you gain %d experience." and its group/rested variants.
    -- The mob name leads every one of them.
    deathPatterns = {}
    for key, fmt in pairs(_G) do
        if type(key) == "string" and type(fmt) == "string"
            and string.find(key, "^COMBATLOG_XPGAIN_") and string.find(fmt, "^%%s") then
            deathPatterns[#deathPatterns + 1] = patternFromFormat(fmt)
        end
    end
    table.sort(deathPatterns, function(a, b) return #a > #b end)
end

-- The mob named in an experience-gain line, or nil.
function Tracker.ParseDeathMessage(text)
    text = LL.Plain(text)
    if type(text) ~= "string" then return nil end
    for _, pattern in ipairs(deathPatterns) do
        local name = string.match(text, pattern)
        if name and name ~= "" then return name end
    end
    return nil
end

-- Returns kind ("own"/"other"), link, quantity, playerName, isRoll - or nil
-- for anything that is not a loot receipt.
function Tracker.ClassifyLootMessage(text)
    text = LL.Plain(text)
    if type(text) ~= "string" then return nil end
    for _, entry in ipairs(lootPatterns) do
        local captures = { string.match(text, entry.pattern) }
        if captures[1] then
            local _, _, _, link = Items.ParseLink(text)
            if not link then return nil end
            local qty = entry.qty and tonumber(captures[entry.qty]) or 1
            local player = entry.player and captures[entry.player] or nil
            return entry.kind, link, qty, player, entry.roll or false
        end
    end
    return nil
end

-- Copper looted by the player, or nil when the message is not about the
-- player's own loot.
function Tracker.ParseMoneyMessage(text)
    text = LL.Plain(text)
    if type(text) ~= "string" then return nil end
    local moneyText, split
    for _, entry in ipairs(moneyPatterns) do
        moneyText = string.match(text, entry.pattern)
        if moneyText then
            split = entry.split
            break
        end
    end
    if not moneyText then return nil end
    local copper = Tracker.ParseAmount(moneyText)
    if not copper then return nil end
    return copper, split
end

-- Sums every gold/silver/copper amount found in a money string.
function Tracker.ParseAmount(moneyText)
    local total, found = 0, false
    for _, entry in ipairs(amountPatterns) do
        local n = string.match(moneyText, entry.pattern)
        if n then
            total = total + tonumber(n) * entry.mult
            found = true
        end
    end
    if not found then return nil end
    return total
end

-- ---------------------------------------------------------------------
-- Pending queues
-- ---------------------------------------------------------------------

local function purge(list, now)
    local i = 1
    while i <= #list do
        if now - list[i].t > PENDING_TTL then
            table.remove(list, i)
        else
            i = i + 1
        end
    end
end

-- Oldest matching entry, confirmed (slot seen cleared) before tentative
-- (slot still full when the window closed).
local function popItem(itemKey, now)
    purge(state.pendingItems, now)
    local fallback
    for i, entry in ipairs(state.pendingItems) do
        if entry.itemKey == itemKey then
            if not entry.tentative then
                table.remove(state.pendingItems, i)
                return entry
            end
            fallback = fallback or i
        end
    end
    if fallback then return table.remove(state.pendingItems, fallback) end
    return nil
end

-- Exact amount first (solo loot), then oldest confirmed, then oldest.
local function popCoin(copper, now)
    purge(state.pendingCoin, now)
    local list = state.pendingCoin
    for i, entry in ipairs(list) do
        if entry.copper == copper then return table.remove(list, i) end
    end
    for i, entry in ipairs(list) do
        if not entry.tentative then return table.remove(list, i) end
    end
    return table.remove(list, 1)
end

local function purgeCorpses(now)
    for guid, t in pairs(state.recentCorpses) do
        if now - t > CORPSE_TTL then state.recentCorpses[guid] = nil end
    end
end

local function purgeDeaths(now)
    local list = state.recentDeaths
    while list[1] and now - list[1].t > DEATH_TTL do table.remove(list, 1) end
end

-- A name for a corpse the unit APIs would not name: the recent experience
-- messages, but only when they agree (one death, or all the same mob).
-- A mixed pull is ambiguous and must not poison the name cache.
function Tracker.NameFromRecentDeaths(now)
    purgeDeaths(now)
    local list = state.recentDeaths
    if #list == 0 then return nil end
    local name = list[1].name
    for i = 2, #list do
        if list[i].name ~= name then return nil end
    end
    table.remove(list, 1)
    return name
end

-- ---------------------------------------------------------------------
-- Loot window
-- ---------------------------------------------------------------------

local function readSlot(slot, now, newCorpses)
    local kind = LL.Plain(GetLootSlotType(slot))
    local icon, name, qty, currencyID, quality = GetLootSlotInfo(slot)
    name = LL.Plain(name)
    qty = LL.Plain(qty)
    quality = LL.Plain(quality)
    local s = { slot = slot, cleared = false, name = name, quality = quality }

    if kind == 2 then
        s.kind = "coin"
    elseif kind == 1 then
        s.kind = "item"
        local link = LL.Plain(GetLootSlotLink(slot))
        local itemID, suffixID, linkName = Items.ParseLink(link)
        if itemID then
            s.link = link
            s.itemKey = Items.Key(itemID, suffixID)
            s.name = linkName or name
        end
        s.qty = (type(qty) == "number" and qty > 0) and qty or 1
    else
        s.kind = "other"
    end

    local sources = { GetLootSourceInfo(slot) }
    local primaryGuid = LL.Plain(sources[1])
    local primaryQty = LL.Plain(sources[2])
    local npcID = Guid.NpcID(primaryGuid)
    if npcID then
        s.guid = primaryGuid
        s.npcID = npcID
    end
    if s.kind == "coin" then
        s.copper = tonumber(primaryQty) or (type(name) == "string" and Tracker.ParseAmount(name)) or 0
    end

    for i = 1, #sources, 2 do
        local guid = LL.Plain(sources[i])
        local id = Guid.NpcID(guid)
        if id and not state.recentCorpses[guid] then
            state.recentCorpses[guid] = now
            newCorpses[#newCorpses + 1] = { guid = guid, npcID = id }
        end
    end
    return s
end

function Tracker.OnLootReady()
    if state.snapshot then return end
    if not LL.DB then return end
    local num = LL.Plain(GetNumLootItems())
    if type(num) ~= "number" then return end
    local now = LL.Clock()
    purgeCorpses(now)

    local snap = { openedAt = now, slots = {} }
    local newCorpses = {}
    for slot = 1, num do
        local s = readSlot(slot, now, newCorpses)
        snap.slots[slot] = s
        if s.npcID then
            state.lastCorpse = { npcID = s.npcID, guid = s.guid, t = now }
        end
    end
    state.snapshot = snap

    for _, corpse in ipairs(newCorpses) do
        local name = Guid.ResolveName(corpse.guid, corpse.npcID)
        local how = "unit"
        if not name then
            name = Tracker.NameFromRecentDeaths(now)
            if name then
                Guid.Learn(corpse.npcID, name)
                how = "experience message"
            end
        end
        Ledger.RecordKill(corpse.npcID, name)
        trace("kill: %s (#%d) %s [%s]", tostring(name), corpse.npcID, corpse.guid, name and how or "unnamed")
    end
    trace("loot window: %d slot(s), %d new corpse(s)", num, #newCorpses)
    for _, s in ipairs(snap.slots) do
        trace("  slot %d %s %s x%s from #%s", s.slot, s.kind, tostring(s.name), tostring(s.qty or s.copper), tostring(s.npcID))
    end
end

local function queueSlot(s, now, tentative)
    if s.kind == "item" and s.itemKey then
        table.insert(state.pendingItems, { itemKey = s.itemKey, qty = s.qty, npcID = s.npcID, t = now, tentative = tentative })
        trace("pending item%s: %s x%d (#%s)", tentative and " (tentative)" or "", s.name or s.itemKey, s.qty or 1, tostring(s.npcID))
    elseif s.kind == "coin" and (s.copper or 0) > 0 then
        table.insert(state.pendingCoin, { copper = s.copper, npcID = s.npcID, t = now, tentative = tentative })
        trace("pending coin%s: %d (#%s)", tentative and " (tentative)" or "", s.copper, tostring(s.npcID))
    end
end

function Tracker.OnSlotCleared(slot)
    slot = LL.Plain(slot)
    local snap = state.snapshot
    local s = snap and type(slot) == "number" and snap.slots[slot]
    if not s or s.cleared then return end
    s.cleared = true
    queueSlot(s, LL.Clock(), false)
end

-- The client sometimes closes an auto-looted window without reporting any
-- slot as cleared. Whatever was still in it is queued tentatively so the
-- receipts that follow can still find their corpse; unused entries expire.
function Tracker.OnLootClosed()
    local snap = state.snapshot
    state.snapshot = nil
    if not snap then return end
    local now = LL.Clock()
    for _, s in ipairs(snap.slots) do
        if not s.cleared then
            s.cleared = true
            queueSlot(s, now, true)
        end
    end
end

-- ---------------------------------------------------------------------
-- Chat receipts
-- ---------------------------------------------------------------------

-- Group members: the client targets whatever you loot, so a member's
-- target at the moment their receipt arrives is the corpse it came from.
local function groupUnits()
    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 40
        local units = {}
        for i = 1, n do units[#units + 1] = "raid" .. i end
        return units
    elseif IsInGroup and IsInGroup() then
        return { "party1", "party2", "party3", "party4" }
    end
    return {}
end

local function baseName(name)
    if type(name) ~= "string" then return nil end
    return string.match(name, "^([^%-]+)") or name
end

-- Returns npcID, guid of a dead creature a group member is targeting.
-- With playerName only that member is considered.
function Tracker.GuessCorpseFromGroup(playerName)
    local wanted = baseName(playerName)
    for _, unit in ipairs(groupUnits()) do
        local name = baseName(LL.Plain(UnitName(unit)))
        if name and (not wanted or name == wanted) then
            local target = unit .. "target"
            local guid = LL.Plain(UnitGUID(target))
            local npcID = Guid.NpcID(guid)
            if npcID and LL.Plain(UnitIsDead(target)) == true then
                return npcID, guid
            end
        end
    end
    return nil
end

local function recentCorpse(now, window)
    local last = state.lastCorpse
    if last and (now - last.t) <= window then return last.npcID end
    return nil
end

local function attribute(itemKey, isRoll, now, kind, playerName)
    local pending = popItem(itemKey, now)
    if pending then return pending.npcID, "window" end
    if kind == "other" then
        local npcID, guid = Tracker.GuessCorpseFromGroup(playerName)
        if npcID then
            if guid then
                Guid.ResolveName(guid, npcID)
                state.lastCorpse = { npcID = npcID, guid = guid, t = now }
            end
            return npcID, "looter target"
        end
    end
    if isRoll or kind == "other" then
        local npcID = recentCorpse(now, ROLL_FALLBACK)
        if npcID then return npcID, "recent corpse" end
    end
    return nil, "none"
end

function Tracker.OnChatLoot(text, playerName)
    local kind, link, qty, player, isRoll = Tracker.ClassifyLootMessage(text)
    if not kind then return end
    local itemID, suffixID, name = Items.ParseLink(link)
    if not itemID then return end
    local itemKey = Items.Key(itemID, suffixID)
    if Ledger.IsFiltered(itemKey) then
        trace("ignored filtered item %s", name or itemKey)
        return
    end
    if kind == "other" and LL.DB.settings.showUnclaimed ~= true then
        -- Other players' pickups are only recorded when the user asked to
        -- see them. Decided before touching the pending queue, so an
        -- ignored message can never consume the slot your own receipt needs.
        return
    end
    local now = LL.Clock()
    local npcID, how = attribute(itemKey, isRoll, now, kind, player or playerName)
    if kind == "own" then
        Ledger.RecordItem(npcID, itemKey, name, link, qty)
        trace("you: %s x%d -> #%s (%s)", name or itemKey, qty, tostring(npcID), how)
    else
        Ledger.RecordUnclaimed(npcID, itemKey, name, link, qty)
        trace("%s: %s x%d -> #%s (%s)", tostring(player), name or itemKey, qty, tostring(npcID), how)
    end
end

local COIN_GROUP_FALLBACK = 120

function Tracker.OnChatMoney(text)
    local copper, isSplit = Tracker.ParseMoneyMessage(text)
    if not copper or copper <= 0 then return end
    local now = LL.Clock()
    local pending = popCoin(copper, now)
    local npcID, how = pending and pending.npcID or nil, "window"
    if not npcID and isSplit then
        npcID = Tracker.GuessCorpseFromGroup(nil)
        how = "group member target"
        if not npcID then
            npcID = recentCorpse(now, COIN_GROUP_FALLBACK)
            how = "recent corpse"
        end
    end
    Ledger.RecordCoin(npcID, copper)
    trace("coin: %d -> #%s (%s)", copper, tostring(npcID), npcID and how or "none")
end

-- ---------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------

Tracker.CompilePatterns()

LL.RegisterEvent("LOOT_READY", function() Tracker.OnLootReady() end)
LL.RegisterEvent("LOOT_OPENED", function() Tracker.OnLootReady() end)
LL.RegisterEvent("LOOT_SLOT_CLEARED", function(_, slot) Tracker.OnSlotCleared(slot) end)
LL.RegisterEvent("LOOT_CLOSED", function() Tracker.OnLootClosed() end)
LL.RegisterEvent("CHAT_MSG_LOOT", function(_, text, playerName) Tracker.OnChatLoot(text, playerName) end)
LL.RegisterEvent("CHAT_MSG_MONEY", function(_, text) Tracker.OnChatMoney(text) end)

LL.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, text)
    local name = Tracker.ParseDeathMessage(text)
    if name then
        table.insert(state.recentDeaths, { name = name, t = LL.Clock() })
        trace("death: %s", name)
    end
end)
LL.RegisterEvent("PLAYER_TARGET_CHANGED", function() Guid.LearnUnit("target") end)
LL.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
    unit = LL.Plain(unit)
    if type(unit) == "string" then Guid.LearnUnit(unit) end
end)
-- Leaving combat is the moment withheld names tend to become readable.
LL.RegisterEvent("PLAYER_REGEN_ENABLED", function() Guid.RetryUnnamed() end)

local lastMouseover = 0
LL.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
    local now = LL.Clock()
    if now - lastMouseover < MOUSEOVER_THROTTLE then return end
    lastMouseover = now
    Guid.LearnUnit("mouseover")
end)

-- Global strings can be replaced by localisation addons that load after us.
LL.RegisterEvent("PLAYER_LOGIN", function() Tracker.CompilePatterns() end)
