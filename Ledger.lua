-- Ledger: the per-mob drop records.
--
-- Two scopes share one shape: "alltime" is LootLedgerDB (account-wide),
-- "session" is LootLedgerCharDB.session. Every record call writes both.
-- Each scope holds mobs[npcID] plus an `unattributed` bucket for loot
-- that had no corpse behind it (chests, nodes, fishing, roll wins long
-- after the window closed). Totals are derived from those, so resetting
-- one mob never leaves the totals out of step with the sections.

local _, LL = ...

local Ledger = {}
LL.Ledger = Ledger

local function newMob(name)
    return { name = name, kills = 0, coin = 0, items = {}, unclaimed = {}, lastUpdate = 0 }
end

local function scopeTable(scope)
    if scope == "session" then return LL.CharDB.session end
    return LL.DB
end

local function scopes()
    return LL.DB, LL.CharDB.session
end

local function mobIn(container, npcID, name)
    local rec = container.mobs[npcID]
    if not rec then
        rec = newMob(name or (LL.Guid and LL.Guid.CachedName(npcID)) or nil)
        container.mobs[npcID] = rec
    elseif not rec.name and name then
        rec.name = name
    end
    rec.lastUpdate = LL.Now()
    return rec
end

local function addItem(list, itemKey, name, link, qty)
    local entry = list[itemKey]
    if not entry then
        entry = { name = name, link = link, count = 0 }
        list[itemKey] = entry
    end
    if not entry.link and link then entry.link = link end
    entry.count = entry.count + (qty or 1)
end

function Ledger.Mobs(scope)
    return scopeTable(scope).mobs
end

function Ledger.Unattributed(scope)
    return scopeTable(scope).unattributed
end

function Ledger.RecordKill(npcID, name)
    for _, container in ipairs({ scopes() }) do
        local rec = mobIn(container, npcID, name)
        rec.kills = rec.kills + 1
    end
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.RecordItem(npcID, itemKey, name, link, qty)
    if Ledger.IsFiltered(itemKey) then return false end
    for _, container in ipairs({ scopes() }) do
        if npcID then
            local rec = mobIn(container, npcID, nil)
            addItem(rec.items, itemKey, name, link, qty)
        else
            addItem(container.unattributed.items, itemKey, name, link, qty)
        end
    end
    LL.Fire("LEDGER_CHANGED")
    return true
end

function Ledger.RecordUnclaimed(npcID, itemKey, name, link, qty)
    if Ledger.IsFiltered(itemKey) then return false end
    for _, container in ipairs({ scopes() }) do
        if npcID then
            local rec = mobIn(container, npcID, nil)
            addItem(rec.unclaimed, itemKey, name, link, qty)
        else
            container.unattributed.unclaimed = container.unattributed.unclaimed or {}
            addItem(container.unattributed.unclaimed, itemKey, name, link, qty)
        end
    end
    LL.Fire("LEDGER_CHANGED")
    return true
end

function Ledger.RecordCoin(npcID, copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return false end
    for _, container in ipairs({ scopes() }) do
        if npcID then
            local rec = mobIn(container, npcID, nil)
            rec.coin = rec.coin + copper
        else
            container.unattributed.coin = (container.unattributed.coin or 0) + copper
        end
    end
    LL.Fire("LEDGER_CHANGED")
    return true
end

-- Fills in a name for records created before it was known. Never
-- overwrites a name that is already set.
function Ledger.SetName(npcID, name)
    if not name then return end
    local changed = false
    for _, container in ipairs({ scopes() }) do
        local rec = container.mobs[npcID]
        if rec and not rec.name then
            rec.name = name
            changed = true
        end
    end
    if changed then LL.Fire("LEDGER_CHANGED") end
end

-- Sets a mob's display name in both scopes, replacing any existing one.
function Ledger.Rename(npcID, name)
    for _, container in ipairs({ scopes() }) do
        local rec = container.mobs[npcID]
        if rec then rec.name = name end
    end
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.ResetMob(npcID)
    for _, container in ipairs({ scopes() }) do
        container.mobs[npcID] = nil
    end
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.ResetOther()
    for _, container in ipairs({ scopes() }) do
        container.unattributed = { coin = 0, items = {}, unclaimed = {} }
    end
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.ResetAll()
    LL.DB.mobs = {}
    LL.DB.unattributed = { coin = 0, items = {}, unclaimed = {} }
    LL.Session.ClearHistory()
    LL.Session.ResetSession()
    LL.Fire("LEDGER_CHANGED")
end

-- Derived totals for a scope: kills, coin, and the number of claimed items.
function Ledger.Totals(scope)
    local container = scopeTable(scope)
    local totals = { kills = 0, coin = container.unattributed.coin or 0, itemCount = 0 }
    for _, rec in pairs(container.mobs) do
        totals.kills = totals.kills + (rec.kills or 0)
        totals.coin = totals.coin + (rec.coin or 0)
        for _, entry in pairs(rec.items) do
            totals.itemCount = totals.itemCount + (entry.count or 0)
        end
    end
    for _, entry in pairs(container.unattributed.items) do
        totals.itemCount = totals.itemCount + (entry.count or 0)
    end
    return totals
end

-- ---------------------------------------------------------------------
-- Filters: items that are never tracked and never shown.
-- ---------------------------------------------------------------------

function Ledger.IsFiltered(itemKey)
    return LL.DB.filters[itemKey] ~= nil
end

function Ledger.Filter(itemKey, name, link)
    LL.DB.filters[itemKey] = { name = name, link = link }
    LL.Fire("FILTERS_CHANGED")
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.Unfilter(itemKey)
    LL.DB.filters[itemKey] = nil
    LL.Fire("FILTERS_CHANGED")
    LL.Fire("LEDGER_CHANGED")
end

function Ledger.Filters()
    local list = {}
    for itemKey, info in pairs(LL.DB.filters) do
        list[#list + 1] = { itemKey = itemKey, name = info.name, link = info.link }
    end
    table.sort(list, function(a, b) return (a.name or a.itemKey) < (b.name or b.itemKey) end)
    return list
end
