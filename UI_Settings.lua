-- Settings: a canvas category in the game's Settings panel (Options ->
-- AddOns -> LootLedger) holding the toggles and the filtered-items list.

local _, LL = ...

local W = LL.Widgets
local UI = LL.UI

local canvas, category
local rows = {}
local ROW_HEIGHT = 24

local function settings() return LL.DB.settings end

local function refreshFilters()
    if not canvas then return end
    local list = LL.Ledger.Filters()
    local y = 0
    for i, entry in ipairs(list) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, canvas.filterChild)
            row:SetHeight(ROW_HEIGHT)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", 2, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = W.CreateLabel(row, "GameFontHighlight", nil, "LEFT")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.remove = W.CreateButton(row, "Remove", 70, 20)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.name:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row.icon:SetTexture(LL.Items.Icon(entry.link or entry.itemKey) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(entry.name or entry.itemKey)
        row.remove:SetScript("OnClick", function() LL.Ledger.Unfilter(entry.itemKey) end)
        row:Show()
        y = y + ROW_HEIGHT
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    canvas.filterChild:SetHeight(math.max(y, 1))
    canvas.filterEmpty:SetShown(#list == 0)
    canvas.clearButton:SetEnabled(#list > 0)
end

local function refreshToggles()
    if not canvas then return end
    canvas.minimapCheck:SetChecked(settings().minimapButton == true)
    canvas.unclaimedCheck:SetChecked(settings().showUnclaimed ~= false)
    canvas.portraitCheck:SetChecked(settings().showPortraits ~= false)
    canvas.skinCheck:SetChecked(settings().skin == "blizzard")
end

local function buildCanvas()
    canvas = CreateFrame("Frame")
    canvas:SetSize(620, 500)

    local title = W.CreateLabel(canvas, "GameFontNormalLarge", "LootLedger", "LEFT")
    title:SetPoint("TOPLEFT", 16, -16)
    local version = W.CreateLabel(canvas, "GameFontHighlightSmall", "v" .. tostring(LL.VERSION), "LEFT")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local desc = W.CreateLabel(canvas, "GameFontHighlight",
        "Tracks every corpse you loot, values the drops, and reports your gold per hour.", "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local open = W.CreateButton(canvas, "Open Loot Ledger", 140, 22, function() UI.Show() end)
    open:SetPoint("TOPRIGHT", -16, -14)

    canvas.minimapCheck = W.CreateCheckbox(canvas, "Show minimap button",
        "The addon is always available from the minimap's addon menu; this adds a classic button around the minimap too.",
        function(checked)
            settings().minimapButton = checked
            UI.SetMinimapButtonShown(checked)
            LL.Fire("SETTINGS_CHANGED")
        end)
    canvas.minimapCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -14)

    canvas.unclaimedCheck = W.CreateCheckbox(canvas, "Show loot other players picked up",
        "Items that dropped from a mob but went to someone else are shown dimmed and never counted toward your totals.",
        function(checked)
            settings().showUnclaimed = checked
            LL.Fire("SETTINGS_CHANGED")
        end)
    canvas.unclaimedCheck:SetPoint("TOPLEFT", canvas.minimapCheck, "BOTTOMLEFT", 0, -4)

    canvas.portraitCheck = W.CreateCheckbox(canvas, "Show mob portraits",
        "A small 3D headshot of each mob next to its name.",
        function(checked)
            settings().showPortraits = checked
            LL.Fire("SETTINGS_CHANGED")
        end)
    canvas.portraitCheck:SetPoint("TOPLEFT", canvas.unclaimedCheck, "BOTTOMLEFT", 0, -4)

    canvas.skinCheck = W.CreateCheckbox(canvas, "Use the classic Blizzard window style",
        "Off: flat dark panels with a purple accent. On: the game's own portrait-frame look.",
        function(checked)
            settings().skin = checked and "blizzard" or "modern"
            LL.Fire("SETTINGS_CHANGED")
            if UI.Rebuild then UI.Rebuild() end
        end)
    canvas.skinCheck:SetPoint("TOPLEFT", canvas.portraitCheck, "BOTTOMLEFT", 0, -4)

    local filterTitle = W.CreateLabel(canvas, "GameFontNormal", "Filtered items", "LEFT")
    filterTitle:SetPoint("TOPLEFT", canvas.skinCheck, "BOTTOMLEFT", 4, -16)
    local filterDesc = W.CreateLabel(canvas, "GameFontHighlightSmall",
        "Right-click an item in the ledger to filter it. Filtered items are never tracked and are hidden from history.", "LEFT")
    filterDesc:SetPoint("TOPLEFT", filterTitle, "BOTTOMLEFT", 0, -4)
    filterDesc:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
    filterDesc:SetWordWrap(true)

    canvas.clearButton = W.CreateButton(canvas, "Clear all", 90, 22, function()
        W.Confirm("CLEAR_FILTERS", "Remove every item filter?", function()
            for _, entry in ipairs(LL.Ledger.Filters()) do LL.Ledger.Unfilter(entry.itemKey) end
        end)
    end)
    canvas.clearButton:SetPoint("BOTTOMRIGHT", -16, 16)

    local inset = CreateFrame("Frame", nil, canvas, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", filterDesc, "BOTTOMLEFT", 0, -8)
    inset:SetPoint("BOTTOMRIGHT", canvas.clearButton, "TOPRIGHT", 0, 8)
    inset:SetPoint("LEFT", canvas, "LEFT", 16, 0)

    local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self) child:SetWidth(self:GetWidth()) end)
    canvas.filterChild = child

    canvas.filterEmpty = W.CreateLabel(inset, "GameFontDisable", "Nothing filtered.", "CENTER")
    canvas.filterEmpty:SetPoint("TOP", 0, -12)

    canvas:SetScript("OnShow", function()
        refreshToggles()
        refreshFilters()
    end)
end

local registerError
local fallbackWindow

local function register()
    if category then return true end
    if not canvas then
        local ok, err = pcall(buildCanvas)
        if not ok then
            registerError = "canvas: " .. tostring(err)
            canvas = nil
            return false
        end
    end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        registerError = "Settings.RegisterCanvasLayoutCategory is missing"
        return false
    end
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "LootLedger")
    if not ok or not cat then
        registerError = "register: " .. tostring(cat)
        return false
    end
    category = cat
    if Settings.RegisterAddOnCategory then
        local okAdd, errAdd = pcall(Settings.RegisterAddOnCategory, category)
        if not okAdd then registerError = "addon category: " .. tostring(errAdd) end
    end
    return true
end

-- Same canvas in a plain window, for when the game's panel can't host it.
local function openFallback(reason)
    if not canvas then
        local ok, err = pcall(buildCanvas)
        if not ok then
            LL.Print("Settings could not be built: " .. tostring(err))
            return
        end
    end
    if not fallbackWindow then
        fallbackWindow = W.CreateWindow("LootLedgerSettingsFrame", "LootLedger Settings", 640, 520)
        W.SetPortrait(fallbackWindow, "Interface\\Icons\\INV_Misc_Gear_01")
        tinsert(UISpecialFrames, "LootLedgerSettingsFrame")
        canvas:SetParent(fallbackWindow)
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", 4, -28)
        canvas:SetPoint("BOTTOMRIGHT", -4, 4)
        canvas:Show()
        if reason then LL.Print("|cffaaaaaaUsing a standalone settings window (" .. tostring(reason) .. ").|r") end
    end
    fallbackWindow:Show()
end

function UI.OpenSettings()
    if fallbackWindow then
        openFallback()
        return
    end
    if register() and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID or category
        local ok, err = pcall(Settings.OpenToCategory, id)
        if ok then return end
        registerError = "open: " .. tostring(err)
    end
    openFallback(registerError)
end

function UI.SettingsStatus()
    return category and "registered in the Settings panel" or ("not registered: " .. tostring(registerError))
end

LL.On("DB_READY", function() register() end)
LL.On("FILTERS_CHANGED", function()
    if canvas and canvas:IsShown() then refreshFilters() end
end)
