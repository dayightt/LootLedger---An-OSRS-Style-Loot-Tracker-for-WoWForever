-- Pricing: what an item is worth.
--
-- A provider is a small table:
--   { id = "auctionator", label = "AH", priority = 20,
--     IsAvailable = function() ... end,
--     GetPrice = function(itemKey, link, itemID) return copper or nil end }
-- The vendor sell price is always in; every available provider is asked
-- and the highest answer wins (ties go to the higher priority). Grey items
-- are vendor-only. Answers are memoised per item until Flush.

local _, LL = ...

local Pricing = {}
LL.Pricing = Pricing

local Items = LL.Items

local providers = {}
local availability = {}
local memo = {}

local VENDOR = {
    id = "vendor",
    label = "vendor",
    priority = 0,
    IsAvailable = function() return true end,
    GetPrice = function(itemKey, link)
        local info = Items.Info(link or itemKey)
        return info and info.sellPrice or nil
    end,
}

function Pricing.Register(provider)
    for i, p in ipairs(providers) do
        if p.id == provider.id then
            providers[i] = provider
            availability[provider.id] = nil
            return
        end
    end
    providers[#providers + 1] = provider
end

function Pricing.Providers()
    return providers
end

local function isAvailable(provider)
    local cached = availability[provider.id]
    if cached ~= nil then return cached end
    local ok, result = pcall(provider.IsAvailable)
    local available = ok and result == true
    availability[provider.id] = available
    return available
end

function Pricing.Refresh()
    availability = {}
    Pricing.Flush()
end

function Pricing.Flush()
    memo = {}
    LL.Fire("PRICES_CHANGED")
end

-- A provider answers with copper, or nil when it has no data. Zero is a
-- real answer (a vendor that pays nothing), not a missing one.
local function ask(provider, itemKey, link, itemID)
    local ok, price = pcall(provider.GetPrice, itemKey, link, itemID)
    if ok and type(price) == "number" and price >= 0 then
        return math.floor(price)
    end
    return nil
end

local function isGrey(itemKey, link)
    local info = Items.Info(link or itemKey)
    return info ~= nil and info.quality == 0
end

-- Returns copper, providerLabel - or nil while nothing knows the item.
function Pricing.GetBestPrice(itemKey, link)
    local cached = memo[itemKey]
    if cached then return cached.price, cached.label end
    local itemID = Items.SplitKey(itemKey)
    local bestPrice, bestLabel, bestPriority = nil, nil, -1

    local function consider(provider)
        if not isAvailable(provider) then return end
        local price = ask(provider, itemKey, link, itemID)
        if not price then return end
        local priority = provider.priority or 0
        if not bestPrice or price > bestPrice or (price == bestPrice and priority > bestPriority) then
            bestPrice, bestLabel, bestPriority = price, provider.label, priority
        end
    end

    consider(VENDOR)
    if not isGrey(itemKey, link) then
        for _, provider in ipairs(providers) do consider(provider) end
    end

    if bestPrice then
        memo[itemKey] = { price = bestPrice, label = bestLabel }
    end
    return bestPrice, bestLabel
end

-- Every provider's answer, for /ll debugprice.
function Pricing.Explain(itemKey, link)
    local itemID = Items.SplitKey(itemKey)
    local rows = {}
    local function row(provider)
        local available = isAvailable(provider)
        rows[#rows + 1] = {
            id = provider.id,
            label = provider.label,
            available = available,
            price = available and ask(provider, itemKey, link, itemID) or nil,
        }
    end
    row(VENDOR)
    for _, provider in ipairs(providers) do row(provider) end
    return rows
end

LL.RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
    Pricing.Flush()
end)

LL.RegisterEvent("PLAYER_LOGIN", function()
    Pricing.Refresh()
end)
