-- Headless test runner. From the addon folder:
--   luajit tests/run.lua            run everything
--   luajit tests/run.lua tracker    run only files whose name contains "tracker"

package.path = "./?.lua;./tests/?.lua;" .. package.path

local stub = require("wow_stub")

-- Non-UI files, in .toc order. UI files need real widgets and are verified in-game.
local CORE_FILES = {
    "Core.lua", "Items.lua", "Guid.lua", "Session.lua", "Ledger.lua", "Tracker.lua",
    "Pricing.lua", "Pricing_Auctionator.lua", "Pricing_Auctioneer.lua", "Report.lua",
}

local TEST_FILES = {
    "test_core", "test_items", "test_guid", "test_session", "test_ledger",
    "test_chat", "test_money", "test_tracker", "test_pricing", "test_report", "test_replay",
}

-- Loads the addon into a fresh namespace against a reset stub, exactly the
-- way the client does: each file receives (addonName, namespaceTable).
function stub.LoadAddon(opts)
    stub.Reset()
    if opts and opts.before then opts.before() end
    local LL = {}
    for _, file in ipairs(CORE_FILES) do
        local fh = io.open(file)
        if fh then
            fh:close()
            local chunk, err = loadfile(file)
            if not chunk then error(err) end
            chunk("LootLedger", LL)
        end
    end
    -- Mirror the client: SavedVariables exist by ADDON_LOADED time.
    stub.FireEvent("ADDON_LOADED", "LootLedger")
    return LL
end

-- ---------------------------------------------------------------------
-- Tiny assertion library
-- ---------------------------------------------------------------------

local T = {}
_G.T = T

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "eq", fmt(expected), fmt(actual)), 2)
    end
end

function T.near(actual, expected, tolerance, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(string.format("%s: expected ~%s, got %s", msg or "near", fmt(expected), fmt(actual)), 2)
    end
end

function T.truthy(v, msg)
    if not v then error(string.format("%s: expected truthy, got %s", msg or "truthy", fmt(v)), 2) end
end

function T.falsy(v, msg)
    if v then error(string.format("%s: expected falsy, got %s", msg or "falsy", fmt(v)), 2) end
end

function T.isnil(v, msg)
    if v ~= nil then error(string.format("%s: expected nil, got %s", msg or "isnil", fmt(v)), 2) end
end

function T.errors(fn, msg)
    local ok = pcall(fn)
    if ok then error(string.format("%s: expected an error", msg or "errors"), 2) end
end

function T.noerror(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error(string.format("%s: unexpected error: %s", msg or "noerror", tostring(err)), 2) end
end

local function deepEq(a, b, path)
    if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. fmt(a) .. " vs " .. fmt(b) end
        return true
    end
    for k, v in pairs(a) do
        local ok, why = deepEq(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing in actual" end
    end
    return true
end

function T.deq(actual, expected, msg)
    local ok, why = deepEq(actual, expected, msg or "deq")
    if not ok then error(why, 2) end
end

function T.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------
-- Test registration and execution
-- ---------------------------------------------------------------------

local tests = {}
function T.test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local filter = arg and arg[1]
local passed, failed = 0, 0
local failures = {}

for _, file in ipairs(TEST_FILES) do
    if not filter or string.find(file, filter, 1, true) then
        local path = "tests/" .. file .. ".lua"
        local fh = io.open(path)
        if fh then
            fh:close()
            tests = {}
            local chunk, err = loadfile(path)
            if not chunk then
                failed = failed + 1
                failures[#failures + 1] = path .. ": " .. err
            else
                local ok, loadErr = pcall(chunk)
                if not ok then
                    failed = failed + 1
                    failures[#failures + 1] = path .. ": " .. tostring(loadErr)
                end
                for _, t in ipairs(tests) do
                    local ok2, terr = xpcall(t.fn, debug.traceback)
                    if ok2 then
                        passed = passed + 1
                    else
                        failed = failed + 1
                        failures[#failures + 1] = file .. " / " .. t.name .. "\n" .. tostring(terr)
                        io.write("FAIL ", file, " / ", t.name, "\n")
                    end
                end
                io.write(string.format("%-14s %d tests\n", file, #tests))
            end
        end
    end
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
for _, f in ipairs(failures) do io.write("\n--- ", f, "\n") end
os.exit(failed == 0 and 0 or 1)
