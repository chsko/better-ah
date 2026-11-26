local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/DebugLog.lua")
local DebugLog = ns.DebugLog

describe("DebugLog (#99)", function()
  local function clock() return "12:34:56.789" end

  it("keeps nothing while off, except marks", function()
    local saved = {}
    local log = DebugLog.new(saved, clock)
    log:begin("Char-Realm")
    log:add("ui", "click %s", "Buy")
    assert.same({}, saved.lines)
    log:mark("it broke")
    assert.same({ "#1 12:34:56.789 [session] Char-Realm", "#1 12:34:56.789 [MARK] it broke" }, saved.lines)
  end)

  it("writes the session header before the first line, and numbers sessions", function()
    local saved = { on = true }
    local log = DebugLog.new(saved, clock)
    log:begin("first")
    log:add("ui", "click %q", "Buy")
    log:begin("second")
    log:add("view", "post")
    assert.same({
      "#1 12:34:56.789 [session] first",
      "#1 12:34:56.789 [ui] click \"Buy\"",
      "#2 12:34:56.789 [session] second",
      "#2 12:34:56.789 [view] post",
    }, saved.lines)
  end)

  it("folds the same line again into a count", function()
    local saved = { on = true }
    local log = DebugLog.new(saved, clock)
    log:add("browse", "%d results", 3)
    log:add("browse", "%d results", 3)
    log:add("browse", "%d results", 3)
    log:add("browse", "%d results", 4)
    assert.same({
      "#0 12:34:56.789 [browse] 3 results (x3, last 12:34:56.789)",
      "#0 12:34:56.789 [browse] 4 results",
    }, saved.lines)
  end)

  it("keeps only the newest lines", function()
    local saved = { on = true }
    local log = DebugLog.new(saved, clock)
    for i = 1, DebugLog.MAX + DebugLog.SLACK + 1 do log:add("n", "%d", i) end
    assert.equal(DebugLog.MAX, #saved.lines)
    assert.matches("%[n%] " .. (DebugLog.MAX + DebugLog.SLACK + 1) .. "$", saved.lines[#saved.lines])
    assert.matches("%[n%] " .. (DebugLog.SLACK + 2) .. "$", saved.lines[1])
    log:add("n", "next")
    assert.equal(DebugLog.MAX + 1, #saved.lines)
  end)

  it("never throws on bad arguments, and describes tables", function()
    local saved = { on = true }
    local log = DebugLog.new(saved, clock)
    log:add("x", "%d items", "many")
    log:add("q", "%s", { searchString = "Arcane", sorts = { 1 }, n = 2 })
    log:add("t", "two\nlines")
    assert.equal("#0 12:34:56.789 [x] %d items many", saved.lines[1])
    assert.equal("#0 12:34:56.789 [q] {n=2, searchString=Arcane, sorts={...}}", saved.lines[2])
    assert.equal("#0 12:34:56.789 [t] two / lines", saved.lines[3])
  end)

  it("doesn't format anything while off", function()
    local log = DebugLog.new({}, function() error("clock called") end)
    local called = false
    log:add("x", "%s", setmetatable({}, { __tostring = function() called = true return "" end }))
    assert.is_false(called)
  end)

  it("stamps local time with milliseconds", function()
    local fakeDate = function(fmt) assert.equal("%H:%M:%S", fmt) return "08:09:10" end
    assert.equal("08:09:10.250", DebugLog.stamp(fakeDate, 1234.25))
  end)

  it("clears the lines", function()
    local saved = { on = true }
    local log = DebugLog.new(saved, clock)
    log:add("x", "a")
    log:clear()
    assert.equal(0, log:count())
  end)
end)
