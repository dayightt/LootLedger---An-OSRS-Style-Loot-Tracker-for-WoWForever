-- Auctionator price provider. Registers itself unconditionally; it only
-- reports itself available when Auctionator is loaded and exposes its
-- public v1 API, so nothing here runs otherwise.

local _, LL = ...

local function api()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator")) then return nil end
    local a = _G.Auctionator
    local v1 = a and a.API and a.API.v1
    if v1 and type(v1.GetAuctionPriceByItemLink) == "function" then return v1 end
    return nil
end

LL.Pricing.Register({
    id = "auctionator",
    label = "AH",
    priority = 20,
    IsAvailable = function() return api() ~= nil end,
    GetPrice = function(itemKey, link, itemID)
        local v1 = api()
        if not v1 then return nil end
        local query = link or LL.Items.ItemString(itemKey)
        return v1.GetAuctionPriceByItemLink(LL.ADDON_NAME, query)
    end,
})
