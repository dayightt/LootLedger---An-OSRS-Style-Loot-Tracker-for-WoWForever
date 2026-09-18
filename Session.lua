-- Session: the live per-character tracking span and its archive.
--
-- The session lives in LootLedgerCharDB.session and survives /reload and
-- relog. Only logged-in time counts toward its clock: activeSeconds holds
-- the completed spans, lastResumeTime marks the start of the current one.

local _, LL = ...

local Session = {}
LL.Session = Session

local MAX_HISTORY = 100

local function newSession()
    local now = LL.Now()
    return {
        startTime = now,
        activeSeconds = 0,
        lastResumeTime = now,
        mobs = {},
        unattributed = { coin = 0, items = {}, unclaimed = {} },
    }
end

function Session.Get()
    return LL.CharDB.session
end

function Session.Start()
    LL.CharDB.session = newSession()
    LL.Fire("SESSION_CHANGED")
    LL.Fire("LEDGER_CHANGED")
    return LL.CharDB.session
end

function Session.Resume()
    local s = Session.Get()
    if not s then return Session.Start() end
    s.lastResumeTime = LL.Now()
    return s
end

function Session.Suspend()
    local s = Session.Get()
    if not s or not s.lastResumeTime then return end
    s.activeSeconds = (s.activeSeconds or 0) + math.max(0, LL.Now() - s.lastResumeTime)
    s.lastResumeTime = nil
end

function Session.GetActiveSeconds()
    local s = Session.Get()
    if not s then return 0 end
    local total = s.activeSeconds or 0
    if s.lastResumeTime then
        total = total + math.max(0, LL.Now() - s.lastResumeTime)
    end
    return total
end

-- Instance name when inside one, else the mob with the most kills.
function Session.LabelFor()
    local name, kind = GetInstanceInfo()
    name = LL.Plain(name)
    kind = LL.Plain(kind)
    if kind and kind ~= "none" and type(name) == "string" and name ~= "" then
        return name
    end
    local s = Session.Get()
    local best, bestKills = nil, 0
    if s then
        for npcID, rec in pairs(s.mobs) do
            if (rec.kills or 0) > bestKills and rec.name then
                best, bestKills = rec.name, rec.kills
            end
        end
    end
    return best or "Session"
end

local function topMobs(sections, n)
    local out = {}
    for i = 1, math.min(n, #sections) do
        local sec = sections[i]
        out[i] = { npcID = sec.npcID, name = sec.name, value = sec.value, kills = sec.kills }
    end
    return out
end

local function topItems(sections, n)
    local all = {}
    for _, sec in ipairs(sections) do
        for _, e in ipairs(sec.entries) do
            if e.kind == "item" and not e.unclaimed then
                local cur = all[e.itemKey]
                if not cur then
                    cur = { itemKey = e.itemKey, name = e.name, count = 0, value = 0 }
                    all[e.itemKey] = cur
                end
                cur.count = cur.count + e.count
                cur.value = cur.value + (e.value or 0)
            end
        end
    end
    local list = {}
    for _, v in pairs(all) do list[#list + 1] = v end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
end

function Session.BuildHistoryEntry(label)
    local s = Session.Get()
    local totals = LL.Ledger.Totals("session")
    local entry = {
        label = label or Session.LabelFor(),
        startTime = s.startTime,
        endTime = LL.Now(),
        activeSeconds = Session.GetActiveSeconds(),
        kills = totals.kills,
        coin = totals.coin,
        itemValue = 0,
        topMobs = {},
        topItems = {},
    }
    if LL.Report then
        local report = LL.Report.Build("session")
        entry.itemValue = report.totals.itemValue or 0
        -- Value-sorted view regardless of the user's current sort setting.
        local sections = {}
        for i, sec in ipairs(report.sections) do sections[i] = sec end
        table.sort(sections, function(a, b)
            if a.value ~= b.value then return a.value > b.value end
            return (a.kills or 0) > (b.kills or 0)
        end)
        entry.topMobs = topMobs(sections, 5)
        entry.topItems = topItems(sections, 10)
    else
        local sections = {}
        for npcID, rec in pairs(s.mobs) do
            sections[#sections + 1] = { npcID = npcID, name = rec.name, value = rec.coin or 0, kills = rec.kills or 0, entries = {} }
        end
        table.sort(sections, function(a, b)
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.value > b.value
        end)
        entry.topMobs = topMobs(sections, 5)
    end
    entry.total = entry.itemValue + entry.coin
    return entry
end

function Session.Restart(label)
    Session.Suspend()
    local entry = Session.BuildHistoryEntry(label)
    table.insert(LL.CharDB.history, 1, entry)
    while #LL.CharDB.history > MAX_HISTORY do
        table.remove(LL.CharDB.history)
    end
    Session.Start()
    LL.Fire("HISTORY_CHANGED")
end

function Session.ResetSession()
    Session.Start()
end

function Session.History()
    return LL.CharDB.history
end

function Session.DeleteHistory(index)
    table.remove(LL.CharDB.history, index)
    LL.Fire("HISTORY_CHANGED")
end

function Session.ClearHistory()
    LL.CharDB.history = {}
    LL.Fire("HISTORY_CHANGED")
end

LL.On("DB_READY", function()
    if not LL.CharDB.session then
        LL.CharDB.session = newSession()
    else
        LL.ApplyDefaults(LL.CharDB.session, { mobs = {}, unattributed = { coin = 0, items = {}, unclaimed = {} } })
    end
end)

-- Folds the running span into activeSeconds without changing the total,
-- so a reload that skips PLAYER_LOGOUT loses at most one heartbeat.
function Session.Heartbeat()
    local s = Session.Get()
    if not s or not s.lastResumeTime then return end
    local now = LL.Now()
    s.activeSeconds = (s.activeSeconds or 0) + math.max(0, now - s.lastResumeTime)
    s.lastResumeTime = now
end

LL.RegisterEvent("PLAYER_LOGIN", function()
    Session.Resume()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(30, Session.Heartbeat)
    end
end)

LL.RegisterEvent("PLAYER_LOGOUT", function()
    Session.Suspend()
end)
