-- Report: the view model.
--
-- Turns a ledger scope plus pricing, filters and settings into what the
-- window shows: sorted mob sections with priced entries, totals and rates.
-- It is a pure function of that state, and both the window and the chat
-- output read from it, so the two can never disagree.

local _, LL = ...

local Report = {}
LL.Report = Report

local Items, Ledger, Pricing = LL.Items, LL.Ledger, LL.Pricing

local MIN_RATE_SECONDS = 60
local COIN_ICON = 133784 -- INV_Misc_Coin_02

local function itemEntry(itemKey, rec, unclaimed, state)
    local link = rec.link
    local unitPrice, label
    if not unclaimed then
        unitPrice, label = Pricing.GetBestPrice(itemKey, link)
        if not unitPrice then state.anyUnpriced = true end
    end
    local info = Items.Info(link or itemKey)
    return {
        kind = "item",
        itemKey = itemKey,
        link = link,
        name = rec.name or (info and info.name) or itemKey,
        count = rec.count or 0,
        unitPrice = unitPrice,
        priceLabel = label,
        value = unclaimed and 0 or ((unitPrice or 0) * (rec.count or 0)),
        unclaimed = unclaimed,
        icon = Items.Icon(link or itemKey) or (info and info.icon),
        quality = info and info.quality or 1,
    }
end

local function sortEntries(entries)
    table.sort(entries, function(a, b)
        local au, bu = a.unclaimed or false, b.unclaimed or false
        if au ~= bu then return not au end
        if au then
            if a.count ~= b.count then return a.count > b.count end
            return (a.name or "") < (b.name or "")
        end
        if a.value ~= b.value then return a.value > b.value end
        if a.kind ~= b.kind then return a.kind == "coin" end
        return (a.name or "") < (b.name or "")
    end)
end

local function buildEntries(items, unclaimedItems, coin, state, showUnclaimed)
    local entries = {}
    local itemValue = 0
    for itemKey, rec in pairs(items or {}) do
        if not Ledger.IsFiltered(itemKey) then
            local e = itemEntry(itemKey, rec, false, state)
            itemValue = itemValue + e.value
            entries[#entries + 1] = e
        end
    end
    if showUnclaimed then
        for itemKey, rec in pairs(unclaimedItems or {}) do
            if not Ledger.IsFiltered(itemKey) then
                entries[#entries + 1] = itemEntry(itemKey, rec, true, state)
            end
        end
    end
    if (coin or 0) > 0 then
        entries[#entries + 1] = {
            kind = "coin", name = "Coin", count = coin, value = coin, icon = COIN_ICON, quality = 1, unclaimed = false,
        }
    end
    sortEntries(entries)
    return entries, itemValue
end

function Report.Build(scope)
    scope = scope or "session"
    local settings = LL.DB.settings
    local showUnclaimed = settings.showUnclaimed == true
    local state = { anyUnpriced = false }
    local sections = {}

    for npcID, rec in pairs(Ledger.Mobs(scope)) do
        local entries, itemValue = buildEntries(rec.items, rec.unclaimed, rec.coin, state, showUnclaimed)
        sections[#sections + 1] = {
            npcID = npcID,
            name = rec.name or string.format("Unknown (#%d)", npcID),
            unnamed = rec.name == nil,
            kills = rec.kills or 0,
            coin = rec.coin or 0,
            itemValue = itemValue,
            value = itemValue + (rec.coin or 0),
            entries = entries,
            lastUpdate = rec.lastUpdate or 0,
            collapsed = settings.collapsed[npcID] == true,
        }
    end

    if settings.sortMode == "value" then
        table.sort(sections, function(a, b)
            if a.value ~= b.value then return a.value > b.value end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.name < b.name
        end)
    else
        table.sort(sections, function(a, b)
            if a.lastUpdate ~= b.lastUpdate then return a.lastUpdate > b.lastUpdate end
            return a.name < b.name
        end)
    end

    local totals = Ledger.Totals(scope)
    local itemValue = 0
    for _, sec in ipairs(sections) do itemValue = itemValue + sec.itemValue end

    local other = Ledger.Unattributed(scope)
    local otherEntries, otherValue = buildEntries(other.items, other.unclaimed, other.coin, state, showUnclaimed)
    if #otherEntries > 0 then
        itemValue = itemValue + otherValue
        sections[#sections + 1] = {
            npcID = nil,
            isOther = true,
            name = "Other loot",
            kills = 0,
            coin = other.coin or 0,
            itemValue = otherValue,
            value = otherValue + (other.coin or 0),
            entries = otherEntries,
            lastUpdate = 0,
            collapsed = settings.collapsed.other == true,
        }
    end

    local result = {
        sections = sections,
        anyUnpriced = state.anyUnpriced,
        totals = {
            kills = totals.kills,
            coin = totals.coin,
            itemCount = totals.itemCount,
            itemValue = itemValue,
            total = itemValue + totals.coin,
        },
    }

    if scope == "session" then
        local seconds = LL.Session.GetActiveSeconds()
        result.totals.activeSeconds = seconds
        if seconds >= MIN_RATE_SECONDS then
            local hours = seconds / 3600
            result.totals.goldPerHour = result.totals.total / hours
            result.totals.killsPerHour = totals.kills / hours
        end
    end

    return result
end
