-- Minimal fake of the WoW client API surface LootLedger touches, so the
-- non-UI files run under a plain Lua 5.1 interpreter. Everything is driven
-- by fixtures the tests set through the `stub` table.

local stub = {}

-- ---------------------------------------------------------------------
-- Secret values. The client tags values; here a secret is a wrapper table
-- that errors on any operation except identity checks, which is close
-- enough to catch code that forgets to guard.
-- ---------------------------------------------------------------------

local SecretMT = {}
local function secretError() error("attempt to use a secret value", 2) end
SecretMT.__index = secretError
SecretMT.__newindex = secretError
SecretMT.__concat = secretError
SecretMT.__len = secretError
SecretMT.__lt = secretError
SecretMT.__le = secretError
SecretMT.__add = secretError
SecretMT.__call = secretError
SecretMT.__tostring = function() return "<secret>" end

function stub.MakeSecret(v)
    return setmetatable({ __secret = true, __value = v }, SecretMT)
end

function stub.MakeSecretTable()
    return setmetatable({ __secrettable = true }, SecretMT)
end

_G.issecretvalue = function(v)
    return type(v) == "table" and rawget(v, "__secret") == true
end
_G.issecrettable = function(t)
    return type(t) == "table" and rawget(t, "__secrettable") == true
end

-- ---------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------

local wallClock = 1700000000
local upClock = 1000.0

function stub.SetTime(wall, up)
    wallClock = wall or wallClock
    upClock = up or upClock
end
function stub.Advance(seconds)
    wallClock = wallClock + seconds
    upClock = upClock + seconds
end

_G.time = function() return wallClock end
_G.GetTime = function() return upClock end
_G.date = function(fmt, t) return os.date(fmt, t or wallClock) end

-- ---------------------------------------------------------------------
-- Lua helpers the client provides globally
-- ---------------------------------------------------------------------

_G.format = string.format
_G.strmatch = string.match
_G.strfind = string.find
_G.gsub = string.gsub
_G.strlen = string.len
_G.strsub = string.sub
_G.strlower = string.lower
_G.strupper = string.upper
_G.strrep = string.rep
_G.tinsert = table.insert
_G.tremove = table.remove
_G.floor = math.floor
_G.ceil = math.ceil
_G.max = math.max
_G.min = math.min
_G.abs = math.abs

_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

_G.strtrim = function(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

_G.strsplit = function(delim, s, pieces)
    local out = {}
    local start = 1
    local dlen = #delim
    while true do
        local i = string.find(s, delim, start, true)
        if not i or (pieces and #out == pieces - 1) then
            out[#out + 1] = string.sub(s, start)
            break
        end
        out[#out + 1] = string.sub(s, start, i - 1)
        start = i + dlen
    end
    return unpack(out)
end

_G.strjoin = function(delim, ...)
    return table.concat({ ... }, delim)
end

_G.tostringall = function(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, n)
end

_G.securecallfunction = function(fn, ...) return fn(...) end
_G.securecall = _G.securecallfunction

-- ---------------------------------------------------------------------
-- Chat / output
-- ---------------------------------------------------------------------

stub.chat = {}
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg) stub.chat[#stub.chat + 1] = msg end,
}
function stub.LastChat() return stub.chat[#stub.chat] end

-- ---------------------------------------------------------------------
-- Frames and events
-- ---------------------------------------------------------------------

local frames = {}
local FrameMT = {}
FrameMT.__index = function(t, k)
    -- Any widget method we didn't model is a harmless no-op.
    local fn = function() end
    rawset(t, k, fn)
    return fn
end

local function newFrame(frameType, name, parent, template)
    local f = setmetatable({
        __type = frameType, __name = name, __parent = parent, __template = template,
        __events = {}, __scripts = {}, __shown = true, __children = {},
    }, FrameMT)
    f.RegisterEvent = function(self, event)
        if event == "COMBAT_LOG_EVENT" or event == "COMBAT_LOG_EVENT_UNFILTERED" then
            stub.forbidden = (stub.forbidden or 0) + 1
            return false
        end
        self.__events[event] = true
        return true
    end
    f.UnregisterEvent = function(self, event) self.__events[event] = nil end
    f.UnregisterAllEvents = function(self) self.__events = {} end
    f.IsEventRegistered = function(self, event) return self.__events[event] == true end
    f.SetScript = function(self, handler, fn) self.__scripts[handler] = fn end
    f.GetScript = function(self, handler) return self.__scripts[handler] end
    f.Show = function(self) self.__shown = true end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.IsVisible = function(self) return self.__shown end
    f.GetName = function(self) return self.__name end
    f.GetParent = function(self) return self.__parent end
    f.SetParent = function(self, p) self.__parent = p end
    f.CreateFontString = function(self) return newFrame("FontString", nil, self) end
    f.CreateTexture = function(self) return newFrame("Texture", nil, self) end
    f.GetText = function(self) return self.__text end
    f.SetText = function(self, t) self.__text = t end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

_G.CreateFrame = function(frameType, name, parent, template)
    return newFrame(frameType, name, parent, template)
end

_G.UIParent = newFrame("Frame", "UIParent")
_G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
_G.GameTooltipTextLeft1 = newFrame("FontString", "GameTooltipTextLeft1")

function stub.FireEvent(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            f.__scripts.OnEvent(f, event, ...)
        end
    end
end

function stub.AnyFrameRegistered(event)
    for _, f in ipairs(frames) do
        if f.__events[event] then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------

local timers = {}
_G.C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = upClock + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { cancelled = false }
        t.Cancel = function() t.cancelled = true end
        t.IsCancelled = function() return t.cancelled end
        stub.tickers[#stub.tickers + 1] = { interval = interval, fn = fn, ticker = t }
        return t
    end,
}
stub.tickers = {}

-- Runs every pending C_Timer.After callback regardless of delay.
function stub.RunTimers()
    local pending = timers
    timers = {}
    for _, t in ipairs(pending) do t.fn() end
    return #pending
end

function stub.RunTickers()
    for _, entry in ipairs(stub.tickers) do
        if not entry.ticker.cancelled then entry.fn(entry.ticker) end
    end
end

-- ---------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------

-- stub.SetItems({ [itemID] = { name=, quality=, sellPrice=, icon=, loaded=true|false } })
stub.items = {}
stub.itemLoadRequests = {}

function stub.SetItems(items)
    stub.items = items
    stub.itemLoadRequests = {}
end

local function itemIDFrom(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local id = string.match(v, "item:(%d+)")
        if id then return tonumber(id) end
        return tonumber(v)
    end
    return nil
end
stub.ItemIDFrom = itemIDFrom

_G.C_Item = {
    GetItemInfo = function(v)
        local id = itemIDFrom(v)
        local it = id and stub.items[id]
        if not it or it.loaded == false then return nil end
        local link = string.format("|cnIQ%d:|Hitem:%d::::::::6:1485:::::::::|h[%s]|h|r", it.quality or 1, id, it.name)
        return it.name, link, it.quality or 1, 1, 1, "Miscellaneous", "Junk", 20, "INVTYPE_NON_EQUIP_IGNORE",
            it.icon or 134400, it.sellPrice or 0, 15, 0, 1, 0, nil, false, ""
    end,
    GetItemInfoInstant = function(v)
        local id = itemIDFrom(v)
        local it = id and stub.items[id]
        if not it then return nil end
        return id, "Miscellaneous", "Junk", "INVTYPE_NON_EQUIP_IGNORE", it.icon or 134400, 15, 0
    end,
    RequestLoadItemDataByID = function(id)
        stub.itemLoadRequests[id] = (stub.itemLoadRequests[id] or 0) + 1
    end,
    IsItemDataCachedByID = function(id)
        local it = stub.items[id]
        return it ~= nil and it.loaded ~= false
    end,
}

-- Marks an item loaded and fires the client event.
function stub.LoadItem(id)
    local it = stub.items[id]
    if it then it.loaded = true end
    stub.FireEvent("ITEM_DATA_LOAD_RESULT", id, it ~= nil)
end

-- ---------------------------------------------------------------------
-- Loot window
-- ---------------------------------------------------------------------

-- stub.SetLootWindow({ { type=1, link=, name=, qty=, quality=, icon=, sources={ {guid, qty}, ... } }, { type=2, name="16 Copper", sources={ {guid, 16} } } })
stub.loot = nil

function stub.SetLootWindow(slots)
    stub.loot = slots
    for _, s in ipairs(slots) do s.cleared = false end
end

_G.GetNumLootItems = function()
    return stub.loot and #stub.loot or 0
end
_G.GetLootSlotType = function(slot)
    local s = stub.loot and stub.loot[slot]
    return s and s.type or 0
end
_G.GetLootSlotInfo = function(slot)
    local s = stub.loot and stub.loot[slot]
    if not s or s.cleared then return nil end
    return s.icon or 134400, s.name, s.type == 2 and 0 or (s.qty or 1), s.currencyID, s.quality or 1, s.locked or false, s.isQuestItem or false, nil, nil, s.type == 2
end
_G.GetLootSlotLink = function(slot)
    local s = stub.loot and stub.loot[slot]
    if not s or s.type ~= 1 then return nil end
    if s.cleared then return "|cnIQ1:|Hitem:::::::::6:1485:::::::::|h[]|h|r" end
    return s.link
end
_G.GetLootSourceInfo = function(slot)
    local s = stub.loot and stub.loot[slot]
    if not s or not s.sources then return nil end
    local out = {}
    for _, pair in ipairs(s.sources) do
        out[#out + 1] = pair[1]
        out[#out + 1] = pair[2]
    end
    return unpack(out)
end
_G.IsFishingLoot = function() return stub.fishingLoot or false end
_G.CloseLoot = function() stub.CloseLoot() end

function stub.ClearLootSlot(slot)
    local s = stub.loot and stub.loot[slot]
    if s then s.cleared = true end
    stub.FireEvent("LOOT_SLOT_CLEARED", slot)
end

function stub.CloseLoot()
    stub.loot = nil
    stub.FireEvent("LOOT_CLOSED")
end

_G.Enum = {
    LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
}

-- ---------------------------------------------------------------------
-- Units
-- ---------------------------------------------------------------------

-- stub.SetUnits({ target = { guid=, name=, isPlayer=, dead=, tapDenied= } })
stub.units = {}
stub.tooltipNames = {}   -- [guid] = name, for C_TooltipInfo.GetHyperlink("unit:guid")

function stub.SetUnits(units) stub.units = units end

local function unit(u) return stub.units[u] end
_G.UnitExists = function(u) return unit(u) ~= nil end
_G.UnitGUID = function(u) local x = unit(u); return x and x.guid end
_G.UnitName = function(u) local x = unit(u); return x and x.name end
_G.UnitIsPlayer = function(u) local x = unit(u); return x and x.isPlayer or false end
_G.UnitIsDead = function(u) local x = unit(u); return x and x.dead or false end
_G.UnitIsTapDenied = function(u) local x = unit(u); return x and x.tapDenied or false end
_G.UnitAffectingCombat = function() return stub.inCombat or false end
_G.InCombatLockdown = function() return stub.inCombat or false end
_G.UnitTokenFromGUID = function(guid)
    for token, x in pairs(stub.units) do
        if x.guid == guid then return token end
    end
    return nil
end

_G.C_TooltipInfo = {
    GetHyperlink = function(link)
        local guid = string.match(link, "^unit:(.+)$")
        if guid and stub.tooltipNames[guid] then
            return { guid = guid, lines = { { leftText = stub.tooltipNames[guid] } } }
        end
        return nil
    end,
}

-- ---------------------------------------------------------------------
-- Misc client APIs
-- ---------------------------------------------------------------------

stub.addons = {}
function stub.SetAddOnLoaded(name, loaded) stub.addons[name] = loaded end

_G.C_AddOns = {
    IsAddOnLoaded = function(name) return stub.addons[name] == true end,
    GetAddOnMetadata = function(name, field)
        if field == "Version" then return "test" end
        return nil
    end,
}

stub.instance = { name = "Zephras Isle", type = "none" }
_G.GetInstanceInfo = function()
    local i = stub.instance
    return i.name, i.type, 0, "", 5, 0, false, 2991, 0, nil, false
end
_G.IsInInstance = function()
    local t = stub.instance.type
    return t ~= "none", t
end

_G.GetMoney = function() return stub.money or 0 end

_G.C_CurrencyInfo = {
    GetCoinTextureString = function(copper)
        return string.format("<coin:%d>", copper)
    end,
}

_G.C_PartyInfo = { GetLootMethod = function() return 3 end }
_G.IsInGroup = function() return stub.inGroup or false end
_G.IsInRaid = function() return stub.inRaid or false end
_G.GetCVar = function() return "1" end
_G.SlashCmdList = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which, ...) stub.lastPopup = which; return { which = which } end
_G.hooksecurefunc = function() end

-- ---------------------------------------------------------------------
-- Global strings (enUS, captured from the client)
-- ---------------------------------------------------------------------

function stub.ResetStrings()
    _G.LOOT_ITEM_SELF = "You receive loot: %s"
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
    _G.LOOT_ITEM = "%s receives loot: %s."
    _G.LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
    _G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s"
    _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d"
    _G.LOOT_ITEM_PUSHED = "%s receives item: %s."
    _G.LOOT_ITEM_PUSHED_MULTIPLE = "%s receives item: %sx%d."
    _G.LOOT_ITEM_CREATED_SELF = "You create: %s."
    _G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
    _G.LOOT_ITEM_REFUND = "You are refunded: %s."
    _G.LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
    _G.LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s"
    _G.LOOT_ROLL_WON = "|HlootHistory:%d|h[Loot]|h: %s won: %s"
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: You (Need - %d, Main-Spec) Won: %s"
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: You (Greed - %d) Won: %s"
    _G.LOOT_ROLL_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Main-Spec) Won: %s"
    _G.LOOT_ROLL_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: %s (Greed - %d) Won: %s"
    _G.LOOT_ROLL_ALL_PASSED = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s"
    _G.LOOT_ROLL_PASSED_SELF = "|HlootHistory:%d|h[Loot]|h: You passed on: %s"
    _G.LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s"
    _G.LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s"
    _G.LOOT_ROLL_GREED = "|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s"
    _G.LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"
    _G.LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"
    _G.LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"
    _G.LOOT_ROLL_DISENCHANT_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Disenchant for: %s"
    _G.LOOT_DISENCHANT_CREDIT = "%s was disenchanted for loot by %s."
    _G.YOU_LOOT_MONEY = "You loot %s"
    _G.YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
    _G.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
    _G.LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)"
    _G.LOOT_MONEY = "%s loots %s."
    _G.GOLD_AMOUNT = "%d Gold"
    _G.SILVER_AMOUNT = "%d Silver"
    _G.COPPER_AMOUNT = "%d Copper"
    _G.CURRENCY_GAINED = "You receive currency: %s"
    _G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
    _G.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
    _G.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
    _G.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
    _G.COMBATLOG_XPGAIN_EXHAUSTION1_GROUP = "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)"
    _G.CURRENCY_GAINED_MULTIPLE = "You receive currency: %sx%d"
end
stub.ResetStrings()

-- ---------------------------------------------------------------------
-- Reset between tests
-- ---------------------------------------------------------------------

function stub.Reset()
    frames = {}
    _G.UIParent = newFrame("Frame", "UIParent")
    _G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
    timers = {}
    stub.tickers = {}
    stub.chat = {}
    stub.items = {}
    stub.itemLoadRequests = {}
    stub.loot = nil
    stub.units = {}
    stub.tooltipNames = {}
    stub.addons = {}
    stub.instance = { name = "Zephras Isle", type = "none" }
    stub.inCombat = false
    stub.inGroup = false
    stub.inRaid = false
    stub.money = 0
    stub.forbidden = 0
    stub.lastPopup = nil
    stub.fishingLoot = false
    wallClock = 1700000000
    upClock = 1000.0
    _G.LootLedgerDB = nil
    _G.LootLedgerCharDB = nil
    _G.SlashCmdList = {}
    _G.StaticPopupDialogs = {}
    _G.LootLedger_OnCompartmentClick = nil
    stub.ResetStrings()
end

return stub
