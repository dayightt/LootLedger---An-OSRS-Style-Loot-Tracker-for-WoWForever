-- History window: every past session archived by Restart Session.

local _, LL = ...

local W = LL.Widgets
local UI = LL.UI

local window
local rows = {}
local ROW_HEIGHT = 40
local GREY = "|cffaaaaaa"

local function dateText(t)
    if not t then return "" end
    return date("%b %d, %H:%M", t)
end

local function gph(entry)
    if not entry.activeSeconds or entry.activeSeconds < 60 then return "--" end
    return LL.FormatMoneyShort((entry.total or 0) / (entry.activeSeconds / 3600))
end

function UI.PrintHistoryEntry(entry)
    LL.Print(string.format("Session |cffffffff%s|r - %s, %d %s, %s (%s/hr)",
        tostring(entry.label), LL.FormatDuration(entry.activeSeconds or 0), entry.kills or 0,
        (entry.kills or 0) == 1 and "kill" or "kills", LL.FormatMoney(entry.total or 0), gph(entry)))
    LL.Print(string.format("  Coin %s  |cff777777·|r  Items %s  |cff777777·|r  %s to %s",
        LL.FormatMoney(entry.coin or 0), LL.FormatMoney(entry.itemValue or 0), dateText(entry.startTime), dateText(entry.endTime)))
    if entry.topMobs and #entry.topMobs > 0 then
        local parts = {}
        for _, m in ipairs(entry.topMobs) do
            parts[#parts + 1] = string.format("%s (%d, %s)", tostring(m.name or ("#" .. tostring(m.npcID))), m.kills or 0, LL.FormatMoneyShort(m.value or 0))
        end
        LL.Print("  Top mobs: " .. table.concat(parts, ", "))
    end
    if entry.topItems and #entry.topItems > 0 then
        local parts = {}
        for _, it in ipairs(entry.topItems) do
            parts[#parts + 1] = string.format("%dx %s (%s)", it.count or 0, tostring(it.name), LL.FormatMoneyShort(it.value or 0))
        end
        LL.Print("  Top items: " .. table.concat(parts, ", "))
    end
end

local function refresh()
    if not window or not window:IsShown() then return end
    local history = LL.Session.History()
    local y = 0
    for i, entry in ipairs(history) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, window.child)
            row:SetHeight(ROW_HEIGHT)
            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.06)
            local line = row:CreateTexture(nil, "BACKGROUND")
            line:SetPoint("BOTTOMLEFT", 2, 0)
            line:SetPoint("BOTTOMRIGHT", -2, 0)
            line:SetHeight(1)
            line:SetColorTexture(1, 1, 1, 0.08)
            row.label = W.CreateLabel(row, "GameFontNormal", nil, "LEFT")
            row.label:SetPoint("TOPLEFT", 8, -6)
            row.sub = W.CreateLabel(row, "GameFontHighlightSmall", nil, "LEFT")
            row.sub:SetPoint("BOTTOMLEFT", 8, 6)
            row.delete = W.CreateIconButton(row, "Interface\\Buttons\\UI-StopButton", "Delete this entry", nil, 16)
            row.delete:SetPoint("RIGHT", -6, 0)
            row.label:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
            row.sub:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row.label:SetText(tostring(entry.label))
        row.sub:SetText(string.format("%s%s  ·  %s  ·  %s/hr  ·  %s|r",
            GREY, LL.FormatDuration(entry.activeSeconds or 0), LL.FormatMoney(entry.total or 0), gph(entry), dateText(entry.endTime)))
        row:SetScript("OnClick", function() UI.PrintHistoryEntry(entry) end)
        row.delete:SetScript("OnClick", function() LL.Session.DeleteHistory(i) end)
        row:Show()
        y = y + ROW_HEIGHT
    end
    for i = #history + 1, #rows do rows[i]:Hide() end
    window.child:SetHeight(math.max(y, 1))
    window.empty:SetShown(#history == 0)
    window.clearButton:SetEnabled(#history > 0)
end

local function createWindow()
    window = W.CreateWindow("LootLedgerHistoryFrame", "Session History", 400, 380)
    W.SetPortrait(window, "Interface\\Icons\\INV_Misc_Note_01")
    tinsert(UISpecialFrames, "LootLedgerHistoryFrame")
    local top = W.ContentTop()

    local hint = W.CreateLabel(window, "GameFontHighlightSmall", GREY .. "Click a session for its full breakdown in chat.|r", "LEFT")
    hint:SetPoint("TOPLEFT", 14, -(top + 4))

    window.clearButton = W.CreateButton(window, "Clear All", 90, 22, function()
        W.Confirm("CLEAR_HISTORY", "Delete every archived session for this character?", function() LL.Session.ClearHistory() end)
    end)
    window.clearButton:SetPoint("BOTTOMRIGHT", -10, 10)

    local inset = W.CreateInset(window)
    inset:SetPoint("TOPLEFT", 8, -(top + 24))
    inset:SetPoint("BOTTOMRIGHT", -8, 38)

    local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self) child:SetWidth(self:GetWidth()) end)
    window.child = child

    window.empty = W.CreateLabel(inset, "GameFontDisable", "No archived sessions yet. Restart Session adds one.", "CENTER")
    window.empty:SetPoint("TOP", 0, -16)

    window:SetScript("OnShow", refresh)
end

function UI.OpenHistory()
    if not window then createWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end

function UI.RebuildHistory()
    if window then window:Hide() end
    window = nil
    rows = {}
end

LL.On("HISTORY_CHANGED", refresh)
