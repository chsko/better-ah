local helper = require("spec.helper")

local function load()
  local ns = helper.load("BetterAH/Core/SelfTest.lua")
  helper.load("BetterAH/Core/Probes.lua", ns)
  return ns
end

describe("SelfTest", function()
  it("runs every registered check and reports its status and detail", function()
    local ns = load()
    local suite = ns.SelfTest.new()
    suite:add("always passes", function() return "pass", "fine" end)
    suite:add("always fails", function() return "fail", "broken" end)
    local results = suite:run({})
    assert.same({
      { name = "always passes", status = "pass", detail = "fine" },
      { name = "always fails", status = "fail", detail = "broken" },
    }, results)
  end)

  it("reports a check that throws as a failure instead of stopping the run", function()
    local ns = load()
    local suite = ns.SelfTest.new()
    suite:add("throws", function() error("boom", 0) end)
    suite:add("after", function() return "pass" end)
    local results = suite:run({})
    assert.equal("fail", results[1].status)
    assert.matches("boom", results[1].detail)
    assert.equal("pass", results[2].status)
  end)

  it("formats results as one line per check plus a summary", function()
    local ns = load()
    local lines = ns.SelfTest.format({
      { name = "a", status = "pass", detail = "ok" },
      { name = "b", status = "info", detail = "1.15" },
      { name = "c", status = "fail", detail = "missing" },
    })
    assert.same({
      "[PASS] a: ok",
      "[INFO] b: 1.15",
      "[FAIL] c: missing",
      "Better AH self-test: 1 passed, 1 failed, 1 info",
    }, lines)
  end)
end)

describe("Probes", function()
  local function fakeEnv()
    return {
      GetBuildInfo = function() return "1.16.0", "60001", "Nov 1 2026", 16001 end,
      GetRealmName = function() return "Stonehoof" end,
      UnitFactionGroup = function() return "Horde", "Horde" end,
      QueryAuctionItems = function() end,
      GetNumAuctionItems = function() end,
      C_AuctionHouse = { SendBrowseQuery = function() end },
      C_GameRules = { IsHardcoreActive = function() return false end },
    }
  end

  local function byName(results)
    local t = {}
    for _, r in ipairs(results) do t[r.name] = r end
    return t
  end

  it("reports the interface version and build", function()
    local ns = load()
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))
    assert.equal("info", r["Interface version"].status)
    assert.equal("16001 (build 1.16.0.60001)", r["Interface version"].detail)
  end)

  it("reports the market key parts it can see", function()
    local ns = load()
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))
    assert.equal("Stonehoof", r["Realm"].detail)
    assert.equal("Horde", r["Faction"].detail)
    assert.matches("C_GameRules.IsHardcoreActive=false", r["Ruleset hints"].detail)
  end)

  it("lists which legacy and C_AuctionHouse functions exist", function()
    local ns = load()
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))
    assert.matches("found: QueryAuctionItems, GetNumAuctionItems", r["Legacy AH API"].detail)
    assert.matches("missing: .*GetAuctionItemInfo", r["Legacy AH API"].detail)
    assert.matches("found: SendBrowseQuery", r["C_AuctionHouse API"].detail)
    assert.matches("ReplicateItems", r["C_AuctionHouse API"].detail)
  end)

  it("fails the AH check when neither API is present", function()
    local ns = load()
    local env = fakeEnv()
    env.QueryAuctionItems, env.GetNumAuctionItems, env.C_AuctionHouse = nil, nil, nil
    local r = byName(ns.Probes.suite():run(env, { db = {} }))
    assert.equal("fail", r["Auction house API available"].status)
  end)

  it("passes the saved variables check only when the database loaded", function()
    local ns = load()
    assert.equal("pass", byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))["Saved variables"].status)
    assert.equal("fail", byName(ns.Probes.suite():run(fakeEnv(), {}))["Saved variables"].status)
  end)

  it("lets later code add checks to the shared suite", function()
    local ns = load()
    ns.Probes.suite():add("Extra", function() return "pass", "added later" end)
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))
    assert.equal("added later", r["Extra"].detail)
  end)
end)
