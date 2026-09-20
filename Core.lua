-- Core: namespace, output, secret-value guards, event bus, saved variables,
-- and the small formatting helpers every other file uses.

local ADDON_NAME, LL = ...

LL.ADDON_NAME = ADDON_NAME
LL.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
LL.ACCENT = "|cffa335ee"
LL.DB_VERSION = 1

-- ---------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------

function LL.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(LL.ACCENT .. "LootLedger:|r " .. tostring(msg))
end

-- ---------------------------------------------------------------------
-- Secret values. Any value that came from an event payload or a unit /
-- loot / chat API goes through here before it is compared, formatted,
-- or used as a table key. A secret becomes nil, so the worst case is
-- missing data rather than an error.
-- ---------------------------------------------------------------------

function LL.Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function LL.PlainTable(t)
    if type(t) ~= "table" then return nil end
    if issecrettable and issecrettable(t) then return nil end
    return t
end

-- ---------------------------------------------------------------------
-- Clock indirection (tests replace these)
-- ---------------------------------------------------------------------

function LL.Now() return time() end
function LL.Clock() return GetTime() end

-- ---------------------------------------------------------------------
-- Internal event bus
-- ---------------------------------------------------------------------

local listeners = {}

function LL.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function LL.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-- ---------------------------------------------------------------------
-- Client events: one hidden frame, handlers registered by name.
-- ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

function LL.RegisterEvent(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], fn)
end

-- ---------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------

local function copyDeep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = copyDeep(val) end
    return out
end

-- Fills missing keys in tbl from defaults, recursing into tables that
-- exist on both sides. Never overwrites a value that is already set.
function LL.ApplyDefaults(tbl, defaults)
    for k, dv in pairs(defaults) do
        local tv = tbl[k]
        if tv == nil then
            tbl[k] = copyDeep(dv)
        elseif type(tv) == "table" and type(dv) == "table" then
            LL.ApplyDefaults(tv, dv)
        end
    end
    return tbl
end

LL.DEFAULTS = {
    version = LL.DB_VERSION,
    mobs = {},
    unattributed = { coin = 0, items = {}, unclaimed = {} },
    npcNames = {},
    filters = {},
    settings = {
        viewMode = "session",
        sortMode = "recent",
        compact = false,
        showUnclaimed = false,
        showPortraits = true,
        skin = "modern",
        minimapButton = false,
        minimapAngle = 220,
        window = {},
        collapsed = {},
    },
}

LL.CHAR_DEFAULTS = {
    version = LL.DB_VERSION,
    session = nil, -- created by Session.Start on first login
    history = {},
}

-- Forward migrations keyed by the version they upgrade FROM. An
-- unversioned table counts as version 0.
local MIGRATIONS = {
    [0] = function(db) end, -- v1 is the first shipped layout; defaults do the work
}

local function migrate(db)
    local v = tonumber(db.version) or 0
    while v < LL.DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
        db.version = v
    end
end

function LL.InitDB()
    LootLedgerDB = type(LootLedgerDB) == "table" and LootLedgerDB or {}
    LootLedgerCharDB = type(LootLedgerCharDB) == "table" and LootLedgerCharDB or {}
    migrate(LootLedgerDB)
    migrate(LootLedgerCharDB)
    LL.ApplyDefaults(LootLedgerDB, LL.DEFAULTS)
    LL.ApplyDefaults(LootLedgerCharDB, LL.CHAR_DEFAULTS)
    LL.DB = LootLedgerDB
    LL.CharDB = LootLedgerCharDB
    return LL.DB, LL.CharDB
end

-- If the client restores the saved tables after our first init, the
-- globals get replaced under us. Adopt whatever is there now, carrying
-- over anything recorded into the interim tables.
local function mergeInterim(target, interim)
    if target == interim or type(interim) ~= "table" then return end
    for npcID, rec in pairs(interim.mobs or {}) do
        if not target.mobs[npcID] then target.mobs[npcID] = rec end
    end
    for npcID, name in pairs(interim.npcNames or {}) do
        target.npcNames[npcID] = target.npcNames[npcID] or name
    end
end

function LL.AdoptDB(reason)
    local accountReplaced = type(LootLedgerDB) == "table" and LootLedgerDB ~= LL.DB
    local charReplaced = type(LootLedgerCharDB) == "table" and LootLedgerCharDB ~= LL.CharDB
    if not accountReplaced and not charReplaced then return false end
    local interimDB, interimChar = LL.DB, LL.CharDB
    LL.InitDB()
    if accountReplaced then mergeInterim(LL.DB, interimDB) end
    if charReplaced and interimChar and interimChar.session and not LL.CharDB.session then
        LL.CharDB.session = interimChar.session
    end
    LL.loadedFromDisk = { account = true, character = true, late = reason }
    LL.Fire("DB_READY")
    return true
end

LL.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local hadAccountData = type(LootLedgerDB) == "table" and LootLedgerDB.version ~= nil
    local hadCharData = type(LootLedgerCharDB) == "table" and LootLedgerCharDB.version ~= nil
    LL.InitDB()
    LL.loadedFromDisk = { account = hadAccountData, character = hadCharData }
    LL.Fire("DB_READY")
end)

LL.RegisterEvent("PLAYER_LOGIN", function() LL.AdoptDB("PLAYER_LOGIN") end)
LL.RegisterEvent("PLAYER_ENTERING_WORLD", function() LL.AdoptDB("PLAYER_ENTERING_WORLD") end)

-- One line at login: what came back from disk. If the client was closed
-- without a clean logout, nothing is written and this is where you see it.
LL.RegisterEvent("PLAYER_LOGIN", function()
    local mobs = 0
    for _ in pairs(LL.DB.mobs) do mobs = mobs + 1 end
    local session = LL.CharDB.session
    local since = session and session.startTime and date("%b %d %H:%M", session.startTime) or "now"
    local fresh = LL.loadedFromDisk and not LL.loadedFromDisk.account
    local late = LL.loadedFromDisk and LL.loadedFromDisk.late
    LL.Print(string.format("v%s - %d %s on record%s%s, session running since %s. /ll to open.",
        tostring(LL.VERSION), mobs, mobs == 1 and "mob" or "mobs",
        fresh and " (no saved data found, starting fresh)" or "",
        late and (" (saved data arrived at " .. late .. ")") or "", since))
end)

-- ---------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------

function LL.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then copper = 0 end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

function LL.FormatMoneyShort(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10000 then
        local g = copper / 10000
        local s = string.format("%.1f", g)
        s = s:gsub("%.0$", "")
        return s .. "g"
    elseif copper >= 100 then
        return math.floor(copper / 100) .. "s"
    end
    return copper .. "c"
end

function LL.FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    end
    return string.format("%dm %02ds", m, s)
end
