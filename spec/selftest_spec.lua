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

  it("turns an unknown status into a failure and any detail into text", function()
    local ns = load()
    local suite = ns.SelfTest.new()
    suite:add("odd status", function() return 42, "x" end)
    suite:add("table detail", function() return "info", {} end)
    local results = suite:run({})
    assert.equal("fail", results[1].status)
    assert.matches("unknown status 42", results[1].detail)
    assert.equal("string", type(results[2].detail))
    assert.equal(4, #ns.SelfTest.format(results) + 1)
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

  it("passes the saved variables check only when the global is the addon's database", function()
    local ns = load()
    local env, db = fakeEnv(), { seen = true }
    env.BetterAHDB = db
    local r = byName(ns.Probes.suite():run(env, { db = db }))["Saved variables"]
    assert.equal("pass", r.status)
    assert.equal("BetterAHDB loaded (1 keys)", r.detail)
    assert.equal("fail", byName(ns.Probes.suite():run(fakeEnv(), {}))["Saved variables"].status)
    assert.equal("fail", byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))["Saved variables"].status)
  end)

  it("never calls an auction house function", function()
    local ns = load()
    local env = fakeEnv()
    local function trap() error("auction function was called", 0) end
    for _, name in ipairs({ "QueryAuctionItems", "PostAuction", "StartAuction", "CancelAuction", "PlaceAuctionBid" }) do
      env[name] = trap
    end
    env.C_AuctionHouse = { SendBrowseQuery = trap, PostItem = trap, CancelAuction = trap, PlaceBid = trap }
    for _, r in ipairs(ns.Probes.suite():run(env, { db = {} })) do
      assert.is_nil(r.detail:find("auction function was called", 1, true), r.name)
    end
  end)

  it("lists the client's auction duration labels", function()
    local ns = load()
    local env = fakeEnv()
    env.AUCTION_DURATION_ONE, env.AUCTION_DURATION_TWO = "12 Hours", "24 Hours"
    local r = byName(ns.Probes.suite():run(env, { db = {} }))["Auction durations"]
    assert.same({ "info", "1=12 Hours, 2=24 Hours, 3=(missing)" }, { r.status, r.detail })
  end)

  it("says which browse API exists when the AH check passes", function()
    local ns = load()
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))["Auction house API available"]
    assert.equal("pass", r.status)
    assert.equal("legacy QueryAuctionItems: yes; C_AuctionHouse.SendBrowseQuery: yes", r.detail)
  end)

  it("keeps the other ruleset hints when one of them throws", function()
    local ns = load()
    local env = fakeEnv()
    env.C_Seasons = { GetActiveSeason = function() error("needs an argument") end }
    local r = byName(ns.Probes.suite():run(env, { db = {} }))["Ruleset hints"]
    assert.equal("info", r.status)
    assert.matches("C_GameRules.IsHardcoreActive=false", r.detail)
    assert.matches("C_Seasons.GetActiveSeason=error", r.detail)
  end)

  it("reports the other ruleset candidates the client answers", function()
    local ns = load()
    local env = fakeEnv()
    env.C_GameRules.GetCurrentGameModeRecordID = function() return 12 end
    env.GetRealmID = function() return 6946 end
    local r = byName(ns.Probes.suite():run(env, { db = {} }))["Ruleset hints"]
    assert.matches("C_GameRules.GetCurrentGameModeRecordID=12", r.detail)
    assert.matches("GetRealmID=6946", r.detail)
  end)

  it("copes with a client that returns nothing", function()
    local ns = load()
    local env = { GetBuildInfo = function() end, GetRealmName = function() end, UnitFactionGroup = function() end }
    local r = byName(ns.Probes.suite():run(env, {}))
    assert.equal("nil (build nil.nil)", r["Interface version"].detail)
    assert.equal("nil", r["Faction"].detail)
    assert.equal("no ruleset API found", r["Ruleset hints"].detail)
    assert.equal("fail", r["Auction house API available"].status)
  end)

  it("lets later code add checks to the shared suite", function()
    local ns = load()
    ns.Probes.suite():add("Extra", function() return "pass", "added later" end)
    local r = byName(ns.Probes.suite():run(fakeEnv(), { db = {} }))
    assert.equal("added later", r["Extra"].detail)
  end)
end)

describe("Commands", function()
  local function setup()
    local printed = {}
    _G.SlashCmdList = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
    local ns = load()
    ns.db = {}
    helper.load("BetterAH/Core/Commands.lua", ns)
    ns.Probes.suite().checks = {}
    ns.Probes.suite():add("Only", function() return "pass", "ran" end)
    return printed, ns
  end

  after_each(function() _G.SlashCmdList, _G.DEFAULT_CHAT_FRAME, _G.SLASH_BETTERAH1 = nil, nil, nil end)

  it("registers /bah", function()
    setup()
    assert.equal("/bah", _G.SLASH_BETTERAH1)
    assert.is_function(_G.SlashCmdList.BETTERAH)
  end)

  it("runs the self-test regardless of case and spacing", function()
    local printed = setup()
    _G.SlashCmdList.BETTERAH("  SELFTEST ")
    assert.matches("%[PASS%] Only: ran", printed[1])
  end)

  it("escapes | in check details so chat prints them as written", function()
    local printed, ns = setup()
    ns.Probes.suite().checks = {}
    ns.Probes.suite():add("Key", function() return "pass", "/1/Horde or |1|Horde" end)
    _G.SlashCmdList.BETTERAH("selftest")
    assert.equal("|cfff2c94cBetter AH|r [PASS] Key: /1/Horde or ||1||Horde", printed[1])
  end)

  it("shows help for an empty or unknown command", function()
    local printed = setup()
    _G.SlashCmdList.BETTERAH("")
    _G.SlashCmdList.BETTERAH("dance")
    assert.matches("/bah selftest", printed[1])
    assert.matches("/bah selftest", printed[4])
  end)
end)
