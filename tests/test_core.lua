local stub = require("wow_stub")

T.test("Plain passes ordinary values through and drops secrets", function()
    local LL = stub.LoadAddon()
    T.eq(LL.Plain("abc"), "abc")
    T.eq(LL.Plain(42), 42)
    T.eq(LL.Plain(false), false)
    T.isnil(LL.Plain(nil))
    T.isnil(LL.Plain(stub.MakeSecret("hidden")))
    local t = { a = 1 }
    T.eq(LL.PlainTable(t), t)
    T.isnil(LL.PlainTable(stub.MakeSecretTable()))
    T.isnil(LL.PlainTable("not a table"))
end)

T.test("Plain works when the client has no issecretvalue at all", function()
    local LL = stub.LoadAddon()
    local saved = _G.issecretvalue
    _G.issecretvalue = nil
    T.eq(LL.Plain("abc"), "abc")
    _G.issecretvalue = saved
end)

T.test("event bus fires handlers in registration order with arguments", function()
    local LL = stub.LoadAddon()
    local calls = {}
    LL.On("LEDGER_CHANGED", function(a, b) calls[#calls + 1] = "first:" .. tostring(a) .. ":" .. tostring(b) end)
    LL.On("LEDGER_CHANGED", function(a) calls[#calls + 1] = "second:" .. tostring(a) end)
    LL.On("SESSION_CHANGED", function() calls[#calls + 1] = "wrong" end)
    LL.Fire("LEDGER_CHANGED", 1, 2)
    T.deq(calls, { "first:1:2", "second:1" })
    LL.Fire("NOBODY_LISTENS")
end)

T.test("ApplyDefaults deep-merges without clobbering existing values", function()
    local LL = stub.LoadAddon()
    local defaults = { a = 1, nested = { x = 10, y = 20, deep = { z = 30 } }, list = { 1, 2 } }
    local target = { a = 5, nested = { x = 11, deep = {} } }
    LL.ApplyDefaults(target, defaults)
    T.eq(target.a, 5)
    T.eq(target.nested.x, 11)
    T.eq(target.nested.y, 20)
    T.eq(target.nested.deep.z, 30)
    T.deq(target.list, { 1, 2 })
    -- Defaults must be copied, not shared by reference.
    target.list[1] = 99
    T.eq(defaults.list[1], 1)
end)

T.test("InitDB creates both databases with version and defaults", function()
    local LL = stub.LoadAddon()
    T.truthy(LL.DB, "account DB")
    T.truthy(LL.CharDB, "character DB")
    T.eq(LL.DB, _G.LootLedgerDB)
    T.eq(LL.CharDB, _G.LootLedgerCharDB)
    T.eq(LL.DB.version, LL.DB_VERSION)
    T.eq(LL.CharDB.version, LL.DB_VERSION)
    T.deq(LL.DB.mobs, {})
    T.deq(LL.DB.filters, {})
    T.deq(LL.DB.npcNames, {})
    T.eq(LL.DB.settings.viewMode, "session")
    T.eq(LL.DB.settings.sortMode, "recent")
    T.eq(LL.DB.settings.showUnclaimed, true)
    T.eq(LL.DB.settings.showPortraits, true)
    T.eq(LL.DB.settings.minimapButton, false)
    T.deq(LL.CharDB.history, {})
end)

T.test("InitDB keeps existing data and fills in new default fields", function()
    local LL = stub.LoadAddon({ before = function()
        _G.LootLedgerDB = { version = 1, mobs = { [5] = { name = "Kept", kills = 3 } }, settings = { sortMode = "value" } }
        _G.LootLedgerCharDB = { version = 1, history = { { label = "old" } } }
    end })
    T.eq(LL.DB.mobs[5].name, "Kept")
    T.eq(LL.DB.settings.sortMode, "value")
    T.eq(LL.DB.settings.viewMode, "session")
    T.eq(LL.CharDB.history[1].label, "old")
end)

T.test("InitDB migrates an unversioned table forward", function()
    local LL = stub.LoadAddon({ before = function()
        _G.LootLedgerDB = { mobs = {} }
    end })
    T.eq(LL.DB.version, LL.DB_VERSION)
    T.truthy(LL.DB.settings)
end)

T.test("FormatMoney uses the client's coin string when available", function()
    local LL = stub.LoadAddon()
    T.eq(LL.FormatMoney(12345), "<coin:12345>")
end)

T.test("FormatMoney falls back to g/s/c text", function()
    local LL = stub.LoadAddon()
    local saved = _G.C_CurrencyInfo
    _G.C_CurrencyInfo = nil
    T.eq(LL.FormatMoney(0), "0c")
    T.eq(LL.FormatMoney(7), "7c")
    T.eq(LL.FormatMoney(1600), "16s")
    T.eq(LL.FormatMoney(1607), "16s 7c")
    T.eq(LL.FormatMoney(123456), "12g 34s 56c")
    T.eq(LL.FormatMoney(100000), "10g")
    _G.C_CurrencyInfo = saved
end)

T.test("FormatMoneyShort compacts to the largest unit", function()
    local LL = stub.LoadAddon()
    T.eq(LL.FormatMoneyShort(9), "9c")
    T.eq(LL.FormatMoneyShort(3150), "31s")
    T.eq(LL.FormatMoneyShort(42000), "4.2g")
    T.eq(LL.FormatMoneyShort(40000), "4g")
    T.eq(LL.FormatMoneyShort(1234567), "123.5g")
    T.eq(LL.FormatMoneyShort(0), "0c")
end)

T.test("FormatDuration", function()
    local LL = stub.LoadAddon()
    T.eq(LL.FormatDuration(0), "0m 00s")
    T.eq(LL.FormatDuration(45), "0m 45s")
    T.eq(LL.FormatDuration(725), "12m 05s")
    T.eq(LL.FormatDuration(4320), "1h 12m")
    T.eq(LL.FormatDuration(3600 * 30 + 60), "30h 01m")
end)

T.test("Print prefixes with the addon colour", function()
    local LL = stub.LoadAddon()
    LL.Print("hello")
    T.eq(stub.LastChat(), "|cffa335eeLootLedger:|r hello")
end)

T.test("RegisterEvent dispatches through one frame and never touches the combat log", function()
    local LL = stub.LoadAddon()
    local got
    LL.RegisterEvent("PLAYER_MONEY", function(event, a) got = event .. ":" .. tostring(a) end)
    stub.FireEvent("PLAYER_MONEY", 7)
    T.eq(got, "PLAYER_MONEY:7")
    T.eq(stub.forbidden, 0)
    T.falsy(stub.AnyFrameRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
end)

T.test("saved variables that arrive after ADDON_LOADED are adopted at login", function()
    local LL = stub.LoadAddon()
    -- Fresh tables were created at ADDON_LOADED; something got recorded already.
    LL.Ledger.RecordKill(7, "Early Mob")
    local interimAccount, interimChar = LL.DB, LL.CharDB
    -- The client now restores the real saved tables, replacing the globals.
    _G.LootLedgerDB = { version = 1, mobs = { [5] = { name = "Saved Mob", kills = 3, coin = 0, items = {}, unclaimed = {} } }, npcNames = { [5] = "Saved Mob" } }
    _G.LootLedgerCharDB = { version = 1, session = { startTime = 1699990000, activeSeconds = 300, mobs = {}, unattributed = { coin = 0, items = {} } }, history = { { label = "old" } } }
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(LL.DB, _G.LootLedgerDB, "account table adopted")
    T.eq(LL.CharDB, _G.LootLedgerCharDB, "character table adopted")
    T.eq(LL.DB.mobs[5].kills, 3, "saved data kept")
    T.eq(LL.DB.mobs[7].name, "Early Mob", "interim data carried over")
    T.eq(LL.DB.settings.viewMode, "session", "defaults applied to the adopted table")
    T.eq(LL.Session.Get().startTime, 1699990000, "saved session resumed")
    T.eq(#LL.CharDB.history, 1)
    T.truthy(LL.loadedFromDisk.late)
    -- Recording now lands in the adopted table, which is what gets saved.
    LL.Ledger.RecordKill(5, "Saved Mob")
    T.eq(_G.LootLedgerDB.mobs[5].kills, 4)
    T.isnil(interimAccount.mobs[5])
end)

T.test("AdoptDB is a no-op when nothing was replaced", function()
    local LL = stub.LoadAddon()
    local db = LL.DB
    stub.FireEvent("PLAYER_LOGIN")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(LL.DB, db)
    T.falsy(LL.loadedFromDisk.late)
end)
