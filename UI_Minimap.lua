-- Minimap: the addon-compartment entry (always) and an optional classic
-- button around the minimap ring.

local _, LL = ...

local W = LL.Widgets
local UI = LL.UI

local button

local function settings() return LL.DB.settings end

-- Tooltip lines shared by the compartment entry and the button.
function UI.AddSummaryTooltip(tooltip)
    tooltip:SetText("LootLedger", 1, 1, 1)
    local report = LL.Report.Build("session")
    local t = report.totals
    local seconds = LL.Session.GetActiveSeconds()
    tooltip:AddDoubleLine("Session", LL.FormatDuration(seconds), 0.8, 0.8, 0.8, 1, 1, 1)
    if seconds >= 60 then
        tooltip:AddDoubleLine("Gold per hour", LL.FormatMoney(t.total / (seconds / 3600)), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tooltip:AddDoubleLine("Kills", tostring(t.kills), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("Total", LL.FormatMoney(t.total), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffaaaaaaLeft-click: toggle the ledger. Right-click: settings.|r")
end

local function updatePosition()
    if not button then return end
    local angle = math.rad(settings().minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    settings().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    updatePosition()
end

local function createButton()
    button = CreateFrame("Button", "LootLedgerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(W.COIN_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then UI.OpenSettings() else UI.Toggle() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        UI.AddSummaryTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updatePosition()
end

function UI.SetMinimapButtonShown(shown)
    if shown then
        if not button then createButton() end
        updatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

-- Addon compartment (the addon list on the minimap).
function LootLedger_OnCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then UI.OpenSettings() else UI.Toggle() end
end

function LootLedger_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    UI.AddSummaryTooltip(GameTooltip)
    GameTooltip:Show()
end

function LootLedger_OnCompartmentLeave()
    GameTooltip:Hide()
end

LL.RegisterEvent("PLAYER_LOGIN", function()
    if settings().minimapButton then UI.SetMinimapButtonShown(true) end
end)
