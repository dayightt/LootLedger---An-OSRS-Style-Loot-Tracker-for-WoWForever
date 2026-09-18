-- Slash commands: /ll and /lootledger.

local _, LL = ...

local W = LL.Widgets
local UI = LL.UI
local GREY = "|cffaaaaaa"

local function printReport(scope)
    local report = LL.Report.Build(scope)
    local t = report.totals
    if #report.sections == 0 then
        LL.Print(scope == "session" and "Nothing looted this session yet." or "Nothing recorded yet.")
        return
    end
    LL.Print(scope == "session" and "This session:" or "All time:")
    for _, sec in ipairs(report.sections) do
        LL.Print(string.format("|cffffffff%s|r - %d %s - %s", sec.name, sec.kills, sec.kills == 1 and "kill" or "kills", LL.FormatMoney(sec.value)))
        for _, e in ipairs(sec.entries) do
            if e.kind == "coin" then
                LL.Print("    Coin " .. LL.FormatMoney(e.value))
            elseif e.unclaimed then
                LL.Print(string.format("    %s%dx %s (others)|r", GREY, e.count, e.name))
            elseif e.unitPrice then
                LL.Print(string.format("    %dx %s - %s each (%s) = %s", e.count, e.link or e.name, LL.FormatMoney(e.unitPrice), e.priceLabel, LL.FormatMoney(e.value)))
            else
                LL.Print(string.format("    %dx %s - no price yet", e.count, e.link or e.name))
            end
        end
    end
    if scope == "session" then
        local seconds = LL.Session.GetActiveSeconds()
        local rate = seconds >= 60 and LL.FormatMoney(t.total / (seconds / 3600)) or "--"
        LL.Print(string.format("Total %s in %s (%s/hr, %d kills)", LL.FormatMoney(t.total), LL.FormatDuration(seconds), rate, t.kills))
    else
        LL.Print(string.format("Total %s (%d kills, %d items)", LL.FormatMoney(t.total), t.kills, t.itemCount))
    end
    if report.anyUnpriced then LL.Print(GREY .. "Some items have no price yet.|r") end
end

local function printStatus()
    local report = LL.Report.Build("session")
    local t = report.totals
    local seconds = LL.Session.GetActiveSeconds()
    local rate = seconds >= 60 and LL.FormatMoney(t.total / (seconds / 3600)) or "--"
    LL.Print(string.format("%s - %s/hr - %d kills - %s total", LL.FormatDuration(seconds), rate, t.kills, LL.FormatMoney(t.total)))
end

local function printDebug()
    LL.Print("Build " .. tostring((select(1, GetBuildInfo()))) .. ", addon v" .. tostring(LL.VERSION))
    LL.Print("  settings: " .. UI.SettingsStatus())
    local mobs = 0
    for _ in pairs(LL.DB.mobs) do mobs = mobs + 1 end
    local loaded = LL.loadedFromDisk or {}
    LL.Print(string.format("  database: %d mobs all-time, account data %s, character data %s",
        mobs, loaded.account and "loaded from disk" or "started fresh this login", loaded.character and "loaded from disk" or "started fresh this login"))
    for _, row in ipairs(LL.Pricing.Explain("6948:0")) do
        LL.Print(string.format("  provider %s (%s): %s", row.id, row.label, row.available and "available" or "not available"))
    end
    local on = not LL.Tracker.IsTracing()
    LL.Tracker.SetTracing(on)
    LL.Print("Event tracing " .. (on and "ON - every loot event the engine consumes is echoed here. /ll debug again to stop." or "off."))
end

local function printPrice(arg)
    local itemID, suffixID = LL.Items.ParseLink(arg)
    local link
    if itemID then
        link = select(4, LL.Items.ParseLink(arg))
    else
        itemID = tonumber(arg)
        suffixID = 0
    end
    if not itemID then
        LL.Print("Usage: /ll debugprice <itemID or item link>")
        return
    end
    local itemKey = LL.Items.Key(itemID, suffixID)
    local info = LL.Items.Info(link or itemKey)
    LL.Print(string.format("%s (%s)%s", info and info.name or ("item " .. itemKey), itemKey, info and "" or " - not cached yet, try again in a moment"))
    for _, row in ipairs(LL.Pricing.Explain(itemKey, link)) do
        LL.Print(string.format("  %s: %s", row.label, row.price and LL.FormatMoney(row.price) or (row.available and "no data" or "not available")))
    end
    local best, label = LL.Pricing.GetBestPrice(itemKey, link)
    LL.Print("  best: " .. (best and (LL.FormatMoney(best) .. " (" .. label .. ")") or "none"))
end

local function printFilters()
    local list = LL.Ledger.Filters()
    if #list == 0 then
        LL.Print("No filtered items. Right-click an item in the ledger to filter it.")
        return
    end
    LL.Print("Filtered items:")
    for _, entry in ipairs(list) do
        LL.Print("  " .. (entry.link or entry.name or entry.itemKey))
    end
end

local function printHelp()
    LL.Print("Commands:")
    LL.Print("  /ll - toggle the ledger window")
    LL.Print("  /ll loot - print this session's loot")
    LL.Print("  /ll alltime - print the all-time ledger")
    LL.Print("  /ll status - one-line session status")
    LL.Print("  /ll restart - archive this session and start a new one")
    LL.Print("  /ll reset - wipe everything (asks first)")
    LL.Print("  /ll history - open the session history")
    LL.Print("  /ll settings - open the settings panel")
    LL.Print("  /ll filter - list filtered items")
    LL.Print("  /ll debug - provider status and event tracing")
    LL.Print("  /ll debugprice <itemID|link> - how an item is priced")
end

SLASH_LOOTLEDGER1 = "/ll"
SLASH_LOOTLEDGER2 = "/lootledger"
SlashCmdList["LOOTLEDGER"] = function(msg)
    msg = msg or ""
    local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" then
        UI.Toggle()
    elseif cmd == "loot" then
        printReport("session")
    elseif cmd == "alltime" or cmd == "all" then
        printReport("alltime")
    elseif cmd == "status" then
        printStatus()
    elseif cmd == "restart" then
        W.Confirm("RESTART", "Archive this session to the history and start a new one?", function() LL.Session.Restart() end)
    elseif cmd == "reset" then
        W.Confirm("RESET_ALL", "Wipe every mob, the session and the history for this character?", function() LL.Ledger.ResetAll() end)
    elseif cmd == "history" then
        UI.OpenHistory()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        UI.OpenSettings()
    elseif cmd == "filter" or cmd == "filters" then
        printFilters()
    elseif cmd == "debug" then
        printDebug()
    elseif cmd == "debugprice" then
        printPrice(rest)
    elseif cmd == "compact" then
        UI.SetCompact(not LL.DB.settings.compact)
    else
        printHelp()
    end
end
