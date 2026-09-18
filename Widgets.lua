-- Widgets: small helpers around the client's own frame templates so every
-- window looks like part of the default UI. Nothing here draws custom
-- textures; it only arranges what Blizzard ships.

local _, LL = ...

local Widgets = {}
LL.Widgets = Widgets

Widgets.ICON_SIZE = 36
Widgets.ICON_GAP = 4
Widgets.HEADER_HEIGHT = 44
Widgets.ROW_HEIGHT = Widgets.ICON_SIZE + Widgets.ICON_GAP
Widgets.SKULL_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
Widgets.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

-- Some templates expose SetTitle, older ones only the font string.
function Widgets.SetTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    end
end

function Widgets.SetPortrait(frame, texture)
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(texture)
    elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
        frame.PortraitContainer.portrait:SetTexture(texture)
    elseif frame.portrait then
        frame.portrait:SetTexture(texture)
    end
end

-- A standard windowed frame: title bar, close button, movable, clamped.
function Widgets.CreateWindow(name, title, width, height, template)
    local frame = CreateFrame("Frame", name, UIParent, template or "PortraitFrameTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
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
    Widgets.SetTitle(frame, title)
    -- The template's close button routes through HideUIPanel, which the
    -- client blocks for addon frames during combat. Hide directly instead.
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
    frame:Hide()
    return frame
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
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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

-- Standard gold button.
function Widgets.CreateButton(parent, text, width, height, onClick)
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
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.2)
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

function Widgets.CreateLabel(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

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
    if SetItemButtonQuality then
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

-- 3D headshot of a creature by npcID, with an icon fallback.
function Widgets.CreatePortrait(parent, size)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(size, size)
    holder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    holder:SetBackdropColor(0, 0, 0, 0.6)
    holder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

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
