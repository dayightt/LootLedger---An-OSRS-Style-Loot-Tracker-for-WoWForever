-- Guid: creature identity from GUIDs, and turning a GUID into a name.
--
-- GUID layout: Creature-0-<server>-<instance>-<zone>-<npcID>-<spawnUID>.
-- The npcID (field 6) is the stable identity of a mob type; the spawn
-- UID changes every respawn. Mob records are keyed by npcID and names are
-- learned once and cached in LootLedgerDB.npcNames.

local _, LL = ...

local Guid = {}
LL.Guid = Guid

local ID_KINDS = { Creature = true, Vehicle = true, GameObject = true, Pet = true }

-- Returns kind ("Creature", "Player", "GameObject", ...) and, for kinds
-- that carry an entry id in field 6, that id as a number.
function Guid.Parse(guid)
    guid = LL.Plain(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local kind = string.match(guid, "^([%a]+)%-")
    if not kind then return nil end
    if ID_KINDS[kind] then
        local id = select(6, strsplit("-", guid))
        return kind, tonumber(id)
    end
    return kind, nil
end

function Guid.NpcID(guid)
    local kind, id = Guid.Parse(guid)
    if kind == "Creature" or kind == "Vehicle" then return id end
    return nil
end

function Guid.CachedName(npcID)
    local names = LL.DB and LL.DB.npcNames
    return names and names[npcID] or nil
end

-- Stores a learned name and fills in any mob record that was created
-- before the name was known.
local function remember(npcID, name)
    if not npcID or not name then return end
    LL.DB.npcNames[npcID] = name
    local rec = LL.DB.mobs[npcID]
    if rec and not rec.name then
        rec.name = name
        local session = LL.CharDB and LL.CharDB.session
        local srec = session and session.mobs and session.mobs[npcID]
        if srec and not srec.name then srec.name = name end
        LL.Fire("LEDGER_CHANGED")
    end
end

local function nameFromToken(guid)
    if not UnitTokenFromGUID then return nil end
    local token = LL.Plain(UnitTokenFromGUID(guid))
    if type(token) ~= "string" then return nil end
    local name = LL.Plain(UnitName(token))
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local function nameFromTooltip(guid)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. guid)
    if not ok then return nil end
    data = LL.PlainTable(data)
    if not data then return nil end
    local lines = LL.PlainTable(data.lines)
    local first = lines and LL.PlainTable(lines[1])
    local name = first and LL.Plain(first.leftText)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Cache -> live unit token -> unit tooltip -> nil. Any success is cached.
function Guid.ResolveName(guid, npcID)
    guid = LL.Plain(guid)
    npcID = npcID or Guid.NpcID(guid)
    local cached = Guid.CachedName(npcID)
    if cached then return cached end
    if type(guid) ~= "string" then return nil end
    local name = nameFromToken(guid) or nameFromTooltip(guid)
    if name then remember(npcID, name) end
    return name
end

-- Opportunistic learning from a unit token (target, mouseover, ...).
function Guid.LearnUnit(unit)
    local guid = LL.Plain(UnitGUID(unit))
    local npcID = Guid.NpcID(guid)
    if not npcID then return end
    if LL.Plain(UnitIsPlayer(unit)) then return end
    local name = LL.Plain(UnitName(unit))
    if type(name) ~= "string" or name == "" then return end
    if LL.DB.npcNames[npcID] == name then
        local rec = LL.DB.mobs[npcID]
        if rec and rec.name then return end
    end
    remember(npcID, name)
end
