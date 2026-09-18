-- Main window: the loot ledger itself, plus the compact strip it
-- collapses into. Everything shown comes from Report.Build; this file
-- only lays it out.

local _, LL = ...

local W = LL.Widgets
local UI = LL.UI or {}
LL.UI = UI

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 440, 520
local MIN_WIDTH, MIN_HEIGHT = 340, 260
local LIST_TOP = 84
local GREY = "|cffaaaaaa"
local SEP = "  |cff777777·|r  "

local window, strip, list
local lastReport, lastScope
local iconsPerRow = 8
local refreshScheduled = false
local ticker

local function settings() return LL.DB.settings end

-- ---------------------------------------------------------------------
-- Element data
-- ---------------------------------------------------------------------

local function buildElements(report)
    local elements = {}
    for _, sec in ipairs(report.sections) do
        elements[#elements + 1] = { kind = "header", section = sec, height = W.HEADER_HEIGHT }
        if not sec.collapsed then
            local entries = sec.entries
            for i = 1, #entries, iconsPerRow do
                local row = { kind = "row", section = sec, entries = {}, height = W.ROW_HEIGHT }
                for j = i, math.min(i + iconsPerRow - 1, #entries) do
                    row.entries[#row.entries + 1] = entries[j]
                end
                elements[#elements + 1] = row
            end
        end
    end
    return elements
end

local function collapseKey(sec)
    return sec.isOther and "other" or sec.npcID
end

-- ---------------------------------------------------------------------
-- Header element
-- ---------------------------------------------------------------------

local function onHeaderClick(frame, button)
    local sec = frame.section
    if not sec then return end
    if button == "RightButton" then
        local entries = {}
        if sec.isOther then
            entries[1] = { text = "Clear other loot", func = function()
                W.Confirm("RESET_OTHER", "Clear all loot that had no mob behind it?", function() LL.Ledger.ResetOther() end)
            end }
        else
            entries[1] = { text = "Reset this mob", func = function()
                W.Confirm("RESET_MOB", string.format("Reset everything recorded for %s?", sec.name), function() LL.Ledger.ResetMob(sec.npcID) end)
            end }
        end
        W.ContextMenu(frame, sec.name, entries)
        return
    end
    local key = collapseKey(sec)
    if settings().collapsed[key] then settings().collapsed[key] = nil else settings().collapsed[key] = true end
    UI.Refresh()
end

local function buildHeader(frame)
    frame.built = true
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", onHeaderClick)

    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    local line = frame:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT", 2, 0)
    line:SetPoint("BOTTOMRIGHT", -2, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)

    frame.portrait = W.CreatePortrait(frame, W.ICON_SIZE)
    frame.portrait:SetPoint("LEFT", 4, 0)

    frame.arrow = frame:CreateTexture(nil, "ARTWORK")
    frame.arrow:SetSize(16, 16)

    frame.name = W.CreateLabel(frame, "GameFontNormal", nil, "LEFT")
    frame.kills = W.CreateLabel(frame, "GameFontHighlightSmall", nil, "LEFT")
    frame.value = W.CreateLabel(frame, "GameFontHighlight", nil, "RIGHT")
    frame.value:SetPoint("RIGHT", -8, 0)
end

local function initHeader(frame, data)
    if not frame.built then buildHeader(frame) end
    local sec = data.section
    frame.section = sec
    frame:SetHeight(W.HEADER_HEIGHT)

    local showPortrait = settings().showPortraits ~= false
    if showPortrait then
        frame.portrait:Show()
        if sec.isOther then
            frame.portrait:ShowFallback()
            frame.portrait.fallback:SetTexture(W.COIN_ICON)
        elseif sec.npcID then
            frame.portrait.fallback:SetTexture(W.SKULL_ICON)
            frame.portrait:SetCreatureID(sec.npcID)
        else
            frame.portrait:ShowFallback()
        end
    else
        frame.portrait:Hide()
    end
    local left = showPortrait and (4 + W.ICON_SIZE + 6) or 6

    frame.arrow:ClearAllPoints()
    frame.arrow:SetPoint("LEFT", left, 0)
    frame.arrow:SetTexture(sec.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

    frame.name:ClearAllPoints()
    frame.name:SetPoint("TOPLEFT", left + 20, -7)
    frame.name:SetPoint("RIGHT", frame.value, "LEFT", -8, 0)
    frame.name:SetText((sec.unnamed and GREY or "") .. sec.name .. (sec.unnamed and "|r" or ""))

    frame.kills:ClearAllPoints()
    frame.kills:SetPoint("BOTTOMLEFT", left + 20, 7)
    if sec.isOther then
        frame.kills:SetText(GREY .. "chests, nodes and loot with no corpse|r")
    else
        frame.kills:SetText(string.format("%s%d %s|r", GREY, sec.kills, sec.kills == 1 and "kill" or "kills"))
    end
    frame.value:SetText(LL.FormatMoney(sec.value))
end

-- ---------------------------------------------------------------------
-- Icon row element
-- ---------------------------------------------------------------------

local function showEntryTooltip(button)
    local entry = button.entry
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.kind == "coin" then
        GameTooltip:SetText("Coin", 1, 1, 1)
        GameTooltip:AddLine(LL.FormatMoney(entry.value), 1, 1, 1)
    else
        local shown = false
        if entry.link then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, entry.link) end
        if not shown then
            local itemID = LL.Items.SplitKey(entry.itemKey)
            if itemID and GameTooltip.SetItemByID then shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
        end
        if not shown then GameTooltip:SetText(entry.name or entry.itemKey, 1, 1, 1) end
        GameTooltip:AddLine(" ")
        if entry.unclaimed then
            GameTooltip:AddDoubleLine("Looted by others", "x" .. entry.count, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(GREY .. "Not counted toward your total|r")
        else
            GameTooltip:AddDoubleLine("Looted", "x" .. entry.count, 1, 1, 1, 1, 1, 1)
            if entry.unitPrice then
                GameTooltip:AddDoubleLine("Unit price", LL.FormatMoney(entry.unitPrice) .. " " .. GREY .. "(" .. tostring(entry.priceLabel) .. ")|r", 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("Total", LL.FormatMoney(entry.value), 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddLine(GREY .. "No price known yet|r")
            end
        end
        GameTooltip:AddLine(GREY .. "Right-click to filter this item|r")
    end
    GameTooltip:Show()
end

local function onEntryClick(button, mouseButton)
    local entry = button.entry
    if not entry or mouseButton ~= "RightButton" or entry.kind ~= "item" then return end
    W.ContextMenu(button, entry.name, {
        { text = "Filter this item", func = function()
            W.Confirm("FILTER_ITEM", string.format("Stop tracking %s and hide it everywhere?", entry.name or entry.itemKey), function()
                LL.Ledger.Filter(entry.itemKey, entry.name, entry.link)
            end)
        end },
    })
end

local function acquireEntryButton(row, index)
    local button = row.buttons[index]
    if button then return button end
    button = W.CreateItemButton(row)
    button:SetScript("OnEnter", showEntryTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", onEntryClick)
    row.buttons[index] = button
    return button
end

local function initRow(frame, data)
    if not frame.built then
        frame.built = true
        frame.buttons = {}
    end
    frame:SetHeight(W.ROW_HEIGHT)
    local x = 8
    for i, entry in ipairs(data.entries) do
        local button = acquireEntryButton(frame, i)
        button:ClearAllPoints()
        button:SetPoint("LEFT", x, 0)
        button.entry = entry
        local icon = entry.icon
        if type(icon) ~= "number" and type(icon) ~= "string" then icon = "Interface\\Icons\\INV_Misc_QuestionMark" end
        if entry.kind == "coin" then
            W.FillItemButton(button, W.COIN_ICON, 1, 1, nil, false)
            W.SetItemButtonCountText(button, LL.FormatMoneyShort(entry.value))
        else
            W.FillItemButton(button, icon, entry.count, entry.quality, entry.link, entry.unclaimed)
        end
        button:Show()
        x = x + W.ICON_SIZE + W.ICON_GAP
    end
    for i = #data.entries + 1, #frame.buttons do
        frame.buttons[i]:Hide()
        frame.buttons[i].entry = nil
    end
end

-- ---------------------------------------------------------------------
-- The list: ScrollBox when available, a plain ScrollFrame otherwise.
-- ---------------------------------------------------------------------

local function createScrollBoxList(parent)
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, elementData) return elementData.height end)
    view:SetElementFactory(function(factory, elementData)
        if elementData.kind == "header" then
            factory("Button", initHeader)
        else
            factory("Frame", initRow)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local obj = { scrollBox = scrollBox, scrollBar = scrollBar }
    function obj:SetElements(elements)
        local provider = CreateDataProvider(elements)
        self.scrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    end
    function obj:GetWidth() return self.scrollBox:GetWidth() end
    return obj
end

local function createScrollFrameList(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(1, 1)
    scrollFrame:SetScrollChild(child)
    local pools = { header = {}, row = {} }

    local obj = { scrollFrame = scrollFrame, child = child }
    function obj:SetElements(elements)
        local used = { header = 0, row = 0 }
        local y = 0
        child:SetWidth(scrollFrame:GetWidth())
        for _, data in ipairs(elements) do
            local pool = pools[data.kind]
            used[data.kind] = used[data.kind] + 1
            local frame = pool[used[data.kind]]
            if not frame then
                frame = CreateFrame(data.kind == "header" and "Button" or "Frame", nil, child)
                pool[used[data.kind]] = frame
            end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", 0, -y)
            frame:SetPoint("TOPRIGHT", 0, -y)
            if data.kind == "header" then initHeader(frame, data) else initRow(frame, data) end
            frame:Show()
            y = y + data.height
        end
        for kind, pool in pairs(pools) do
            for i = used[kind] + 1, #pool do pool[i]:Hide() end
        end
        child:SetHeight(math.max(y, 1))
    end
    function obj:GetWidth() return self.scrollFrame:GetWidth() end
    return obj
end

local function createList(parent)
    local ok, result = pcall(createScrollBoxList, parent)
    if ok and result then return result, "scrollbox" end
    LL.Print(GREY .. "ScrollBox unavailable (" .. tostring(result) .. "), using the classic list.|r")
    return createScrollFrameList(parent), "scrollframe"
end

-- ---------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------

local function createTabs(frame, labels, onSelect)
    local tabs = {}
    local usingTemplate = true
    for i, label in ipairs(labels) do
        local ok, tab = pcall(CreateFrame, "Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        if not ok or not tab then
            usingTemplate = false
            tab = W.CreateButton(frame, label, 100, 22)
        end
        tab:SetID(i)
        tab:SetText(label)
        tab:SetScript("OnClick", function() onSelect(i) end)
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, usingTemplate and 2 or -2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", usingTemplate and -12 or 4, 0)
        end
        tabs[i] = tab
    end
    frame.Tabs = tabs
    if usingTemplate and PanelTemplates_SetNumTabs then
        pcall(PanelTemplates_SetNumTabs, frame, #labels)
        for _, tab in ipairs(tabs) do
            if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        end
    end
    local obj = { tabs = tabs }
    function obj:Select(index)
        if usingTemplate and PanelTemplates_SetTab then
            pcall(PanelTemplates_SetTab, frame, index)
        else
            for i, tab in ipairs(tabs) do tab:SetEnabled(i ~= index) end
        end
    end
    return obj
end

-- ---------------------------------------------------------------------
-- Summary and strip text
-- ---------------------------------------------------------------------

local function rateText(total, kills, seconds)
    if not seconds or seconds < 60 then return "--", "--" end
    local hours = seconds / 3600
    return LL.FormatMoney(total / hours), string.format("%.0f", kills / hours)
end

local function sessionSummary(report)
    local t = report.totals
    local seconds = LL.Session.GetActiveSeconds()
    local gph, kph = rateText(t.total, t.kills, seconds)
    return string.format("%s%s%s /hr%s%s kills/hr%s%s",
        LL.FormatDuration(seconds), SEP, gph, SEP, kph, SEP, LL.FormatMoney(t.total))
end

local function allTimeSummary(report)
    local t = report.totals
    return string.format("%d %s%s%d items%s%s", t.kills, t.kills == 1 and "kill" or "kills", SEP, t.itemCount, SEP, LL.FormatMoney(t.total))
end

local function stripText(report)
    local t = report.totals
    local seconds = LL.Session.GetActiveSeconds()
    local gph, kph = rateText(t.total, t.kills, seconds)
    return string.format("%s%s%s/hr%s%s kills/hr%s%s", LL.FormatDuration(seconds), SEP, gph, SEP, kph, SEP, LL.FormatMoney(t.total))
end

local function updateSummary()
    if not window or not window:IsShown() or not lastReport then return end
    if lastScope == "session" then
        window.summary:SetText(sessionSummary(lastReport))
        window.restartButton:Show()
        if lastReport.anyUnpriced then
            window.note:SetText(GREY .. "some items have no price yet|r")
        else
            window.note:SetText("")
        end
    else
        window.summary:SetText(allTimeSummary(lastReport))
        window.restartButton:Hide()
        window.note:SetText(lastReport.anyUnpriced and (GREY .. "some items have no price yet|r") or "")
    end
end

local function updateStrip()
    if not strip or not strip:IsShown() then return end
    local report = LL.Report.Build("session")
    strip.text:SetText(stripText(report))
    strip:SetWidth(strip.text:GetStringWidth() + 44)
end

-- ---------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------

local function computeIconsPerRow()
    if not list then return iconsPerRow end
    local width = list:GetWidth() or 0
    return math.max(1, math.floor((width - 12) / (W.ICON_SIZE + W.ICON_GAP)))
end

local function doRefresh()
    refreshScheduled = false
    if window and window:IsShown() then
        iconsPerRow = computeIconsPerRow()
        lastScope = settings().viewMode == "alltime" and "alltime" or "session"
        lastReport = LL.Report.Build(lastScope)
        list:SetElements(buildElements(lastReport))
        updateSummary()
        window.tabs:Select(lastScope == "session" and 1 or 2)
        window.sortButton.tooltipText = settings().sortMode == "value" and "Sorted by value" or "Sorted by recent activity"
        window.sortButton.tooltipBody = "Click to switch"
        W.SetIcon(window.sortButton, settings().sortMode == "value" and "Interface\\Icons\\INV_Misc_Coin_01" or "Interface\\Icons\\INV_Misc_PocketWatch_01")
    end
    updateStrip()
end

function UI.Refresh()
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, doRefresh)
end

local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        local anyShown = (window and window:IsShown()) or (strip and strip:IsShown())
        if not anyShown then
            ticker:Cancel()
            ticker = nil
            return
        end
        updateSummary()
        updateStrip()
    end)
end

-- ---------------------------------------------------------------------
-- Window construction
-- ---------------------------------------------------------------------

local function savePosition(frame, key)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    settings()[key] = { point = point, relPoint = relPoint, x = x, y = y, width = frame:GetWidth(), height = frame:GetHeight() }
end

local function restorePosition(frame, key, defaultWidth, defaultHeight)
    local saved = settings()[key]
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
        if defaultWidth and saved.width then frame:SetSize(saved.width, saved.height or defaultHeight) end
    else
        frame:SetPoint("CENTER")
        if defaultWidth then frame:SetSize(defaultWidth, defaultHeight) end
    end
end

local function setViewMode(mode)
    settings().viewMode = mode
    UI.Refresh()
end

local function createWindow()
    window = W.CreateWindow("LootLedgerFrame", "Loot Ledger", DEFAULT_WIDTH, DEFAULT_HEIGHT)
    W.SetPortrait(window, W.COIN_ICON)
    -- Escape closes the full window; the compact strip is not registered
    -- and stays put.
    tinsert(UISpecialFrames, "LootLedgerFrame")
    window.OnPositionChanged = function(self) savePosition(self, "window") end
    W.AddResizeGrip(window, MIN_WIDTH, MIN_HEIGHT, function()
        savePosition(window, "window")
        UI.Refresh()
    end)
    window.OnSizeChangedThrottled = function()
        if computeIconsPerRow() ~= iconsPerRow then UI.Refresh() end
    end
    restorePosition(window, "window", DEFAULT_WIDTH, DEFAULT_HEIGHT)

    -- Toolbar (right-aligned icon buttons).
    local toolbar = CreateFrame("Frame", nil, window)
    toolbar:SetPoint("TOPRIGHT", -8, -30)
    toolbar:SetSize(160, 22)
    local x = 0
    local function tool(texture, tooltip, onClick)
        local b = W.CreateIconButton(toolbar, texture, tooltip, onClick, 20)
        b:SetPoint("RIGHT", -x, 0)
        x = x + 24
        return b
    end
    window.collapseButton = tool("Interface\\Buttons\\UI-Panel-CollapseButton-Up", "Collapse to a compact strip", function() UI.SetCompact(true) end)
    window.resetButton = tool("Interface\\Buttons\\CancelButton-Up", "Reset All", function()
        W.Confirm("RESET_ALL", "Wipe every mob, the session and the history for this character?", function() LL.Ledger.ResetAll() end)
    end)
    window.resetButton.tooltipBody = "Wipes all-time records, this character's session and its history."
    window.settingsButton = tool("Interface\\Icons\\INV_Misc_Gear_01", "Settings", function() UI.OpenSettings() end)
    window.historyButton = tool("Interface\\Icons\\INV_Misc_Note_01", "Session history", function() UI.OpenHistory() end)
    window.sortButton = tool("Interface\\Icons\\INV_Misc_PocketWatch_01", "Sort", function()
        settings().sortMode = settings().sortMode == "value" and "recent" or "value"
        UI.Refresh()
    end)
    for _, b in ipairs({ window.collapseButton, window.resetButton, window.settingsButton, window.historyButton, window.sortButton }) do
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    window.collapseButton.icon:SetTexCoord(0, 1, 0, 1)
    window.resetButton.icon:SetTexCoord(0, 1, 0, 1)

    -- Summary line and Restart Session.
    window.summary = W.CreateLabel(window, "GameFontHighlight", "", "LEFT")
    window.summary:SetPoint("TOPLEFT", 64, -34)
    window.summary:SetPoint("RIGHT", toolbar, "LEFT", -4, 0)
    window.note = W.CreateLabel(window, "GameFontHighlightSmall", "", "LEFT")
    window.note:SetPoint("TOPLEFT", 64, -56)
    window.restartButton = W.CreateButton(window, "Restart Session", 110, 20, function()
        W.Confirm("RESTART", "Archive this session to the history and start a new one?", function() LL.Session.Restart() end)
    end)
    window.restartButton:SetPoint("TOPRIGHT", -10, -54)

    -- List inset.
    local inset = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 8, -LIST_TOP)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    window.inset = inset
    list = createList(inset)

    window.tabs = createTabs(window, { "This Session", "All Time" }, function(index)
        setViewMode(index == 1 and "session" or "alltime")
    end)

    window:SetScript("OnShow", function()
        UI.Refresh()
        startTicker()
    end)
end

local function createStrip()
    strip = CreateFrame("Frame", "LootLedgerStrip", UIParent, "BackdropTemplate")
    strip:SetSize(300, 24)
    strip:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    strip:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    strip:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function(self) self:StartMoving() end)
    strip:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self, "strip")
    end)
    strip:SetFrameStrata("MEDIUM")
    strip.text = W.CreateLabel(strip, "GameFontHighlightSmall", "", "LEFT")
    strip.text:SetPoint("LEFT", 8, 0)
    strip.expand = W.CreateIconButton(strip, "Interface\\Buttons\\UI-Panel-ExpandButton-Up", "Expand", function() UI.SetCompact(false) end, 18)
    strip.expand:SetPoint("RIGHT", -4, 0)
    strip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then UI.SetCompact(false) end
    end)
    strip:SetScript("OnShow", function()
        updateStrip()
        startTicker()
    end)
    strip:Hide()
end

-- ---------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------

function UI.SetCompact(compact)
    settings().compact = compact and true or false
    if compact then
        if window then window:Hide() end
        if not strip then createStrip() end
        if not settings().strip and window then
            strip:ClearAllPoints()
            strip:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
        else
            restorePosition(strip, "strip")
        end
        strip:Show()
    else
        if strip then strip:Hide() end
        if not window then createWindow() end
        window:Show()
    end
end

function UI.Show()
    if settings().compact then
        UI.SetCompact(true)
    else
        if not window then createWindow() end
        window:Show()
    end
end

function UI.Hide()
    if window then window:Hide() end
    if strip then strip:Hide() end
end

function UI.IsShown()
    return (window and window:IsShown()) or (strip and strip:IsShown()) or false
end

function UI.Toggle()
    if UI.IsShown() then UI.Hide() else UI.Show() end
end

for _, event in ipairs({ "LEDGER_CHANGED", "SESSION_CHANGED", "PRICES_CHANGED", "FILTERS_CHANGED", "SETTINGS_CHANGED", "HISTORY_CHANGED" }) do
    LL.On(event, UI.Refresh)
end
