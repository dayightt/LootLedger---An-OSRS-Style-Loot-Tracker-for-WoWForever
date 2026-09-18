-- Auctioneer price provider. Auctioneer has not shipped for this client
-- yet, so this adapter only carries the detection scaffold: fill in
-- MarketValue below once its price API is known and it starts reporting
-- itself available. Nothing else in the addon needs to change.

local _, LL = ...

-- Returns the market value in copper for a link, or nil. Replace the body
-- with the real call, e.g. AucAdvanced.API.GetMarketValue(link).
local function MarketValue(link)
    return nil
end

local function loaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctioneer") or false
end

LL.Pricing.Register({
    id = "auctioneer",
    label = "Auctioneer",
    priority = 10,
    IsAvailable = function()
        return loaded() and MarketValue("probe") ~= false and _G.AucAdvanced ~= nil
    end,
    GetPrice = function(itemKey, link, itemID)
        return MarketValue(link or LL.Items.ItemString(itemKey))
    end,
})
