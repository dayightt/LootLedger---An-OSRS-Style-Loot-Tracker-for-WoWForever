-- Items: link parsing, item keys, and cached item information.
--
-- An item is identified by "itemID:suffixID". Random-suffix items
-- ("... of the Whale") share an itemID with every other roll of the same
-- base item but are different auctionable goods with different values, so
-- the suffix is part of the identity. suffixID is 0 for ordinary items.

local _, LL = ...

local Items = {}
LL.Items = Items

-- Modern link layout: item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:...
local LINK_WITH_COLOR = "(|c[^|]*|Hitem:[^|]+|h%[[^%]]*%]|h|r)"
local LINK_BARE = "(|Hitem:[^|]+|h%[[^%]]*%]|h)"

-- Returns itemID, suffixID, name, link for the first item link in text.
function Items.ParseLink(text)
    if type(text) ~= "string" then return nil end
    local link = string.match(text, LINK_WITH_COLOR) or string.match(text, LINK_BARE)
    if not link then return nil end
    local itemString = string.match(link, "|H(item:[^|]+)|h")
    local name = string.match(link, "|h%[([^%]]*)%]|h")
    local fields = { strsplit(":", itemString) }
    local itemID = tonumber(fields[2])
    if not itemID then return nil end
    local suffixID = tonumber(fields[8]) or 0
    return itemID, suffixID, name, link
end

function Items.Key(itemID, suffixID)
    return tostring(itemID) .. ":" .. tostring(suffixID or 0)
end

function Items.SplitKey(key)
    local id, suffix = string.match(key, "^(%-?%d+):(%-?%d+)$")
    return tonumber(id), tonumber(suffix)
end

function Items.ItemString(key)
    local id, suffix = Items.SplitKey(key)
    return string.format("item:%d:0:0:0:0:0:%d", id, suffix or 0)
end

local function toQuery(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    if string.find(v, "|Hitem:", 1, true) or string.find(v, "^item:") then return v end
    local id = Items.SplitKey(v)
    if id then return Items.ItemString(v) end
    return tonumber(v)
end

-- Synchronous; never waits on the item cache.
function Items.Icon(v)
    local query = toQuery(v)
    if not query then return nil end
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(query)
    return icon
end

local infoCache = {}
local loadRequested = {}

-- Returns { name, link, quality, sellPrice, icon } or nil while the item
-- is still being fetched. A fetch is requested once per itemID; the
-- ITEM_DATA_LOAD_RESULT handler flushes the cache so the next call sees it.
function Items.Info(v)
    local query = toQuery(v)
    if not query then return nil end
    local cacheKey = tostring(query)
    local cached = infoCache[cacheKey]
    if cached then return cached end
    local name, link, quality, _, _, _, _, _, _, icon, sellPrice = C_Item.GetItemInfo(query)
    if not name then
        local id = type(query) == "number" and query or tonumber(string.match(tostring(query), "item:(%d+)"))
        if id and not loadRequested[id] and C_Item.RequestLoadItemDataByID then
            loadRequested[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
        return nil
    end
    local info = { name = name, link = link, quality = quality, sellPrice = sellPrice or 0, icon = icon }
    infoCache[cacheKey] = info
    return info
end

function Items.Flush()
    infoCache = {}
end

-- Pricing announces PRICES_CHANGED for this event; here we only drop the
-- stale cache so the next lookup sees the loaded data.
LL.RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
    itemID = LL.Plain(itemID)
    if itemID then loadRequested[itemID] = nil end
    Items.Flush()
end)
