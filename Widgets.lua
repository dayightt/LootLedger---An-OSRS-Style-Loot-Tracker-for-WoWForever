-- Widgets: every piece of chrome the windows are built from, in two skins.
--
-- "modern" (default): flat near-black panels, 1px borders, a narrow sans
-- face and a single purple accent - no gold, no parchment.
-- "blizzard": the client's own PortraitFrame / inset / tab templates.
-- Nothing here ships textures or fonts; both skins use what the client
-- already has.

local _, LL = ...

local Widgets = {}
LL.Widgets = Widgets

Widgets.ICON_SIZE = 36
Widgets.ICON_GAP = 4
Widgets.HEADER_HEIGHT = 44
Widgets.ROW_HEIGHT = Widgets.ICON_SIZE + Widgets.ICON_GAP
Widgets.SKULL_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
Widgets.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
Widgets.LOGO = "Interface\\AddOns\\LootLedger\\textures\\logo.png"

local WHITE8 = "Interface\\Buttons\\WHITE8X8"

Widgets.THEME = {
    font = "Fonts\\ARIALN.TTF",
    bg = { 0.055, 0.06, 0.07, 0.94 },
    titleBar = { 0, 0, 0, 0.35 },
    well = { 0.03, 0.033, 0.04, 0.9 },
    border = { 0.19, 0.20, 0.23, 1 },
    borderSoft = { 0.14, 0.15, 0.17, 1 },
    button = { 0.11, 0.12, 0.14, 1 },
    buttonHover = { 0.15, 0.17, 0.19, 1 },
    accent = { 0.64, 0.21, 0.93 },
    accentHex = "|cffa335ee",
    text = { 0.92, 0.93, 0.95 },
    muted = { 0.56, 0.58, 0.62 },
    dim = { 0.40, 0.42, 0.46 },
}
local T = Widgets.THEME

function Widgets.IsModern()
    local s = LL.DB and LL.DB.settings
    return not (s and s.skin == "blizzard")
end

local function backdrop(frame, bgColor, borderColor, edge)
    frame:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = edge or 1 })
    frame:SetBackdropColor(unpack(bgColor))
    frame:SetBackdropBorderColor(unpack(borderColor))
end
Widgets.Backdrop = backdrop

-- ---------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------

-- Roles map onto Blizzard font templates in the classic skin and onto
-- ARIALN sizes/colours in the modern one. Callers pass either.
local ROLES = {
    GameFontNormal = { size = 13, color = "text" },
    GameFontHighlight = { size = 13, color = "text" },
    GameFontHighlightSmall = { size = 11, color = "muted" },
    GameFontNormalSmall = { size = 11, color = "muted" },
    GameFontNormalLarge = { size = 16, color = "accent" },
    GameFontDisable = { size = 12, color = "dim" },
    NumberFontNormal = { size = 12, color = "text", flags = "OUTLINE" },
}

function Widgets.CreateLabel(parent, template, text, justify)
    template = template or "GameFontHighlight"
    local fs
    if Widgets.IsModern() then
        local role = ROLES[template] or ROLES.GameFontHighlight
        fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(T.font, role.size, role.flags or "")
        fs:SetTextColor(unpack(T[role.color]))
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
    else
        fs = parent:CreateFontString(nil, "OVERLAY", template)
    end
    if text then fs:SetText(text) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

function Widgets.SetTitle(frame, text)
    if frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    end
end

function Widgets.SetPortrait(frame, texture)
    if frame.TitleIcon then
        frame.TitleIcon:SetTexture(texture)
        -- Blizzard icons carry a baked-in border worth cropping; our own
        -- logo does not.
        if texture == Widgets.LOGO then
            frame.TitleIcon:SetTexCoord(0, 1, 0, 1)
        else
            frame.TitleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        frame.TitleIcon:Show()
    elseif frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(texture)
    elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
        frame.PortraitContainer.portrait:SetTexture(texture)
    elseif frame.portrait then
        frame.portrait:SetTexture(texture)
    end
end

-- ---------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------

Widgets.TITLE_HEIGHT = 30

local function makeMovable(frame)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.OnPositionChanged then self:OnPositionChanged() end
    end)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
end

local function createModernWindow(name, title, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    backdrop(frame, T.bg, T.border)

    local bar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(Widgets.TITLE_HEIGHT - 1)
    bar:SetColorTexture(unpack(T.titleBar))

    -- The accent rule under the title bar, fading out to the right.
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 1, -Widgets.TITLE_HEIGHT)
    rule:SetPoint("TOPRIGHT", -1, -Widgets.TITLE_HEIGHT)
    rule:SetHeight(1)
    rule:SetColorTexture(1, 1, 1, 1)
    rule:SetGradient("HORIZONTAL", CreateColor(T.accent[1], T.accent[2], T.accent[3], 0.9), CreateColor(T.accent[1], T.accent[2], T.accent[3], 0.08))
    frame.AccentRule = rule

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 8, -5)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.TitleIcon = icon

    local titleText = frame:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(T.font, 15, "")
    titleText:SetTextColor(unpack(T.accent))
    titleText:SetShadowColor(0, 0, 0, 0.8)
    titleText:SetShadowOffset(1, -1)
    titleText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    titleText:SetText(title)
    frame.TitleText = titleText

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -5, -4)
    local x = close:CreateFontString(nil, "OVERLAY")
    x:SetFont(T.font, 18, "")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    x:SetTextColor(unpack(T.muted))
    close.text = x
    close:SetScript("OnEnter", function() x:SetTextColor(unpack(T.accent)) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(T.muted)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.CloseButton = close

    makeMovable(frame)
    frame:Hide()
    return frame
end

local function createBlizzardWindow(name, title, width, height, template)
    local frame = CreateFrame("Frame", name, UIParent, template or "PortraitFrameTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    makeMovable(frame)
    Widgets.SetTitle(frame, title)
    -- The template's close button routes through HideUIPanel, which the
    -- client blocks for addon frames during combat. Hide directly instead.
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
    frame:Hide()
    return frame
end

-- A standard window: title bar, close button, movable, clamped.
function Widgets.CreateWindow(name, title, width, height, template)
    if Widgets.IsModern() then
        return createModernWindow(name, title, width, height)
    end
    return createBlizzardWindow(name, title, width, height, template)
end

-- Where content may start below the title area.
function Widgets.ContentTop()
    return Widgets.IsModern() and (Widgets.TITLE_HEIGHT + 6) or 30
end

-- The recessed panel that holds a list.
function Widgets.CreateInset(parent)
    if Widgets.IsModern() then
        local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        backdrop(inset, T.well, T.borderSoft)
        return inset
    end
    return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

-- Bottom-right grip that resizes the frame.
function Widgets.AddResizeGrip(frame, minWidth, minHeight, onResized)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight)
    elseif frame.SetMinResize then
        frame:SetMinResize(minWidth, minHeight)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    if Widgets.IsModern() then
        grip:GetNormalTexture():SetVertexColor(0.5, 0.5, 0.55)
        grip:GetNormalTexture():SetAlpha(0.6)
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if onResized then onResized() end
    end)
    frame:HookScript("OnSizeChanged", function()
        if frame.OnSizeChangedThrottled then frame:OnSizeChangedThrottled() end
    end)
    return grip
end

-- ---------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------

local function createModernButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 80, height or 22)
    backdrop(button, T.button, T.border)
    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetFont(T.font, 12, "")
    label:SetTextColor(unpack(T.text))
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    button.Label = label
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(unpack(T.buttonHover))
            self:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(T.button))
        self:SetBackdropBorderColor(unpack(T.border))
    end)
    button:SetScript("OnMouseDown", function(self) if self:IsEnabled() then label:SetPoint("CENTER", 1, -1) end end)
    button:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)
    button:SetScript("OnEnable", function() label:SetTextColor(unpack(T.text)) end)
    button:SetScript("OnDisable", function() label:SetTextColor(unpack(T.dim)) end)
    button.SetText = function(self, t) label:SetText(t) end
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Standard push button.
function Widgets.CreateButton(parent, text, width, height, onClick)
    if Widgets.IsModern() then
        return createModernButton(parent, text, width, height, onClick)
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, height or 22)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Small square button showing an icon, with a tooltip.
function Widgets.CreateIconButton(parent, texture, tooltip, onClick, size)
    size = size or 20
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    button.icon = icon
    Widgets.SetIcon(button, texture)
    if Widgets.IsModern() then
        icon:SetAlpha(0.75)
        button:HookScript("OnEnter", function() icon:SetAlpha(1) end)
        button:HookScript("OnLeave", function() icon:SetAlpha(0.75) end)
    else
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)
    end
    button.tooltipText = tooltip
    button:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 1, 1)
        if self.tooltipBody then GameTooltip:AddLine(self.tooltipBody, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Accepts an atlas name or a texture path.
function Widgets.SetIcon(button, texture)
    local icon = button.icon
    if type(texture) == "string" and not string.find(texture, "\\", 1, true) and icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(texture) then
        icon:SetAtlas(texture)
    else
        icon:SetTexture(texture)
    end
end

-- ---------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------

-- Returns { tabs = {...}, Select = function(self, index) }. Modern tabs sit
-- inside the frame at `anchor`; classic tabs hang off the bottom edge.
function Widgets.CreateTabs(frame, labels, onSelect, anchorX, anchorY)
    local tabs = {}
    local obj = { tabs = tabs }

    if Widgets.IsModern() then
        for i, label in ipairs(labels) do
            local tab = CreateFrame("Button", nil, frame)
            local text = tab:CreateFontString(nil, "OVERLAY")
            text:SetFont(T.font, 13, "")
            text:SetPoint("CENTER", 0, 1)
            text:SetText(label)
            tab.text = text
            tab:SetSize(text:GetStringWidth() + 18, 24)
            local underline = tab:CreateTexture(nil, "ARTWORK")
            underline:SetPoint("BOTTOMLEFT", 4, 0)
            underline:SetPoint("BOTTOMRIGHT", -4, 0)
            underline:SetHeight(2)
            underline:SetColorTexture(unpack(T.accent))
            tab.underline = underline
            tab:SetScript("OnClick", function() onSelect(i) end)
            tab:SetScript("OnEnter", function() if not tab.active then text:SetTextColor(unpack(T.text)) end end)
            tab:SetScript("OnLeave", function() if not tab.active then text:SetTextColor(unpack(T.muted)) end end)
            if i == 1 then
                tab:SetPoint("TOPLEFT", frame, "TOPLEFT", anchorX or 8, anchorY or -(Widgets.TITLE_HEIGHT + 4))
            else
                tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 2, 0)
            end
            tabs[i] = tab
        end
        function obj:Select(index)
            for i, tab in ipairs(tabs) do
                tab.active = (i == index)
                tab.underline:SetShown(tab.active)
                tab.text:SetTextColor(unpack(tab.active and T.text or T.muted))
            end
        end
        return obj
    end

    local usingTemplate = true
    for i, label in ipairs(labels) do
        local ok, tab = pcall(CreateFrame, "Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        if not ok or not tab then
            usingTemplate = false
            tab = Widgets.CreateButton(frame, label, 100, 22)
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
-- Checkboxes
-- ---------------------------------------------------------------------

function Widgets.CreateCheckbox(parent, label, tooltip, onChanged)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    end
    text:SetText(label)
    check.Label = text
    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        if onChanged then onChanged(self:GetChecked() and true or false) end
    end)
    check:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return check
end

-- ---------------------------------------------------------------------
-- Item icons
-- ---------------------------------------------------------------------

-- Item icon slot from the client's ItemButton template, falling back to a
-- plain button with the same pieces if the template is unavailable.
function Widgets.CreateItemButton(parent)
    local ok, button = pcall(CreateFrame, "ItemButton", nil, parent, "ItemButtonTemplate")
    if not ok or not button then
        button = CreateFrame("Button", nil, parent)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        button.icon = icon
        local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -2, 2)
        button.Count = count
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetBlendMode("ADD")
        border:Hide()
        button.IconBorder = border
        button.plainFallback = true
    end
    button:SetSize(Widgets.ICON_SIZE, Widgets.ICON_SIZE)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if Widgets.IsModern() then
        -- Drop the template's slot art; a 1px frame around the icon instead.
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal then normal:SetAlpha(0) end
        local frame = CreateFrame("Frame", nil, button, "BackdropTemplate")
        frame:SetPoint("TOPLEFT", -1, 1)
        frame:SetPoint("BOTTOMRIGHT", 1, -1)
        frame:SetFrameLevel(button:GetFrameLevel())
        backdrop(frame, { 0, 0, 0, 0 }, T.border)
        button.Frame = frame
        if button.icon then button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        if button.Count then
            button.Count:SetFont(T.font, 12, "OUTLINE")
            button.Count:ClearAllPoints()
            button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
        end
    end
    return button
end

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function Widgets.QualityColor(quality)
    local c = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
    return c[1], c[2], c[3]
end

function Widgets.QualityHex(quality)
    local r, g, b = Widgets.QualityColor(quality)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Fills an item button: icon, count, quality border, dimmed state.
function Widgets.FillItemButton(button, icon, count, quality, link, dimmed)
    if button.plainFallback then
        button.icon:SetTexture(icon)
        button.Count:SetText(count and count > 1 and tostring(count) or "")
        if quality and quality > 1 then
            button.IconBorder:SetVertexColor(Widgets.QualityColor(quality))
            button.IconBorder:Show()
        else
            button.IconBorder:Hide()
        end
        button.icon:SetDesaturated(dimmed and true or false)
        button:SetAlpha(dimmed and 0.45 or 1)
        return
    end
    if SetItemButtonTexture then SetItemButtonTexture(button, icon) elseif button.icon then button.icon:SetTexture(icon) end
    if SetItemButtonCount then SetItemButtonCount(button, count or 1) elseif button.Count then button.Count:SetText(count and count > 1 and tostring(count) or "") end
    if button.Frame and Widgets.IsModern() then
        -- Modern skin: the 1px frame carries the quality colour. The
        -- template's own quality overlays are never invoked here - without
        -- the slot art they size wrong - and any it owns stay hidden.
        if quality and quality > 1 then
            local r, g, b = Widgets.QualityColor(quality)
            button.Frame:SetBackdropBorderColor(r, g, b, 1)
        else
            button.Frame:SetBackdropBorderColor(unpack(T.border))
        end
        for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "ProfessionQualityOverlay", "ItemContextOverlay" }) do
            local tex = button[key]
            if tex and tex.Hide then tex:Hide() end
        end
    elseif SetItemButtonQuality then
        pcall(SetItemButtonQuality, button, quality, link)
    elseif button.IconBorder then
        if quality and quality > 1 then
            button.IconBorder:SetVertexColor(Widgets.QualityColor(quality))
            button.IconBorder:Show()
        else
            button.IconBorder:Hide()
        end
    end
    if SetItemButtonDesaturated then
        SetItemButtonDesaturated(button, dimmed and true or false)
    elseif button.icon then
        button.icon:SetDesaturated(dimmed and true or false)
    end
    button:SetAlpha(dimmed and 0.45 or 1)
end

-- Item count shown on the button; coin entries show the amount instead.
function Widgets.SetItemButtonCountText(button, text)
    if button.Count then
        button.Count:SetText(text or "")
        button.Count:Show()
    end
end

-- ---------------------------------------------------------------------
-- Mob portrait
-- ---------------------------------------------------------------------

-- 3D headshot of a creature by npcID, with an icon fallback.
function Widgets.CreatePortrait(parent, size)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(size, size)
    backdrop(holder, { 0, 0, 0, 0.6 }, Widgets.IsModern() and T.border or { 0.3, 0.3, 0.3, 1 })

    local fallback = holder:CreateTexture(nil, "ARTWORK")
    fallback:SetPoint("TOPLEFT", 1, -1)
    fallback:SetPoint("BOTTOMRIGHT", -1, 1)
    fallback:SetTexture(Widgets.SKULL_ICON)
    fallback:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    holder.fallback = fallback

    local ok, model = pcall(CreateFrame, "PlayerModel", nil, holder)
    if ok and model and model.SetCreature then
        model:SetPoint("TOPLEFT", 1, -1)
        model:SetPoint("BOTTOMRIGHT", -1, 1)
        if model.SetPortraitZoom then model:SetPortraitZoom(1) end
        if model.SetCamDistanceScale then model:SetCamDistanceScale(1) end
        model:EnableMouse(false)
        holder.model = model
    end

    function holder:SetCreatureID(npcID)
        if self.npcID == npcID then return end
        self.npcID = npcID
        if self.model and npcID then
            self.model:Show()
            self.fallback:Hide()
            local okSet = pcall(self.model.SetCreature, self.model, npcID)
            if okSet then
                if self.model.SetPortraitZoom then pcall(self.model.SetPortraitZoom, self.model, 1) end
                return
            end
            self.model:Hide()
        elseif self.model then
            self.model:Hide()
        end
        self.fallback:Show()
    end

    function holder:ShowFallback()
        self.npcID = nil
        if self.model then self.model:Hide() end
        self.fallback:Show()
    end

    return holder
end

-- ---------------------------------------------------------------------
-- Dialogs and menus
-- ---------------------------------------------------------------------

-- Confirmation popup with a stable id.
function Widgets.Confirm(id, text, onAccept)
    local which = "LOOTLEDGER_" .. id
    if not StaticPopupDialogs[which] then
        StaticPopupDialogs[which] = {
            text = "%s",
            button1 = YES or "Yes",
            button2 = NO or "No",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(self, data)
                if data and data.onAccept then data.onAccept() end
            end,
        }
    end
    StaticPopup_Show(which, text, nil, { onAccept = onAccept })
end

-- Right-click menu; falls back to running the first action if the
-- modern menu API is not present.
function Widgets.ContextMenu(owner, title, entries)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            if title then root:CreateTitle(title) end
            for _, entry in ipairs(entries) do
                root:CreateButton(entry.text, entry.func)
            end
        end)
        return
    end
    if entries[1] then entries[1].func() end
end

function Widgets.MoneyText(copper)
    return LL.FormatMoney(copper)
end
