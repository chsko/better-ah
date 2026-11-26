local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup()
  local env = fake.new()
  local ns = helper.load("BetterAH/Core/MarketKey.lua")
  helper.load("BetterAH/Core/MarketValue.lua", ns)
  helper.load("BetterAH/Core/PriceDB.lua", ns)
  helper.load("BetterAH/Core/SelfTest.lua", ns)
  helper.load("BetterAH/Core/Probes.lua", ns)
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  ns.prices = ns.PriceDB.new({})
  local api = ns.AuctionAPI.install(env, ns)
  env.openAuctionHouse()
  return env, api, ns
end

local function check(ns, env, name)
  for _, r in ipairs(ns.Probes.suite():run(env, { db = {} })) do
    if r.name == name then return r end
  end
end

describe("AuctionAPI", function()
  it("builds the market key from ruleset and faction when the realm name is empty", function()
    local env, _, ns = setup()
    assert.equal("/1/Horde", ns.AuctionAPI.currentMarket(env))
  end)

  it("keeps the same key whatever realm sources answer (ADR 0005)", function()
    local env, _, ns = setup()
    env.UnitGUID = function() return "Player-4701-0ABC1234" end
    env.GetNormalizedRealmName = function() return "Firemaw" end
    assert.equal("/1/Horde", ns.AuctionAPI.currentMarket(env))
    local r = check(ns, env, "Realm sources")
    assert.equal("GetNormalizedRealmName=Firemaw, GetRealmName=(empty), UnitGUID server id=4701", r.detail)
  end)

  it("gives each ruleset its own market", function()
    local env, _, ns = setup()
    env.gameMode = 2
    assert.equal("/2/Horde", ns.AuctionAPI.currentMarket(env))
  end)

  it("names Forever's rulesets from the game rules that are on, like TSM", function()
    local env, _, ns = setup()
    local active = {}
    env.Enum = { GameRule = { HardcoreRuleset = 101, PvPRuleset = 102, RPRuleset = 103 } }
    env.C_GameRules.IsGameRuleActive = function(rule) return active[rule] == true end
    assert.equal("/Normal/Horde", ns.AuctionAPI.currentMarket(env), "GetActiveGameMode is 1 on Normal and PvP")
    active[102] = true
    assert.equal("/PvP/Horde", ns.AuctionAPI.currentMarket(env))
    active[103] = true
    assert.equal("Roleplay PvP", ns.AuctionAPI.ruleset(env))
    active[102] = nil
    assert.equal("Roleplay", ns.AuctionAPI.ruleset(env))
    active[101] = true
    assert.equal("Hardcore", ns.AuctionAPI.ruleset(env))
    env.C_GameRules.IsGameRuleActive = function() error("not on this client") end
    assert.equal("1", ns.AuctionAPI.ruleset(env), "rules that can't be read fall back, never to Normal")
    env.C_GameRules.IsGameRuleActive = function() return nil end
    assert.equal("1", ns.AuctionAPI.ruleset(env), "nor a rule that answers nothing")
    env.C_GameRules.IsGameRuleActive = nil
    assert.equal("1", ns.AuctionAPI.ruleset(env))
    env.C_GameRules.IsGameRuleActive = function() return false end
    env.Enum = { GameRule = {} }
    assert.equal("1", ns.AuctionAPI.ruleset(env), "no ruleset rules in the enum")
  end)

  it("treats Gadgetzan, Booty Bay and Everlook as the neutral market", function()
    local env, _, ns = setup()
    for map, house in pairs({ [1446] = "Gadgetzan", [1434] = "Booty Bay", [1452] = "Everlook" }) do
      env.C_Map = { GetBestMapForUnit = function() return map end }
      assert.equal("/1/Neutral", ns.AuctionAPI.currentMarket(env))
      assert.equal("map " .. map .. ": " .. house, check(ns, env, "Neutral auction house").detail)
    end
    env.C_Map = { GetBestMapForUnit = function() return 1454 end }
    assert.equal("/1/Horde", ns.AuctionAPI.currentMarket(env), "Orgrimmar is the Horde market")
  end)

  it("has no market while the faction is unknown", function()
    local env, _, ns = setup()
    env.UnitFactionGroup = function() return nil end
    local key, why = ns.AuctionAPI.currentMarket(env)
    assert.is_nil(key)
    assert.equal("Your faction isn't known yet.", why)
  end)

  it("scans every replicate listing into the price database under the current market", function()
    local env, _, ns = setup()
    env.auctions = {
      { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 },
      { name = "Linen Cloth", count = 5, buyout = 400, itemID = 2589, owner = "Me" },
      { name = nil, count = 1, buyout = 999, itemID = 2592, hasAllInfo = false },
    }
    local result
    assert.is_true(ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end))
    env.now = env.now + 7
    env.runTimers()
    assert.same({ true, "Scanned 3 listings of 2 items in 7 seconds." }, result)
    local items = ns.prices:items("/1/Horde")
    assert.equal(2, #items)
    assert.same({ "Linen Cloth", 80, 25 }, { items[1].name, items[1].lowest, items[1].quantity })
    assert.equal("i:2592", items[2].item, "items without a name come last")
    assert.equal(env.now, ns.prices:lastScan("/1/Horde"))
  end)

  it("reports the scan in the self-test", function()
    local env, _, ns = setup()
    assert.equal("info", check(ns, env, "Full scan").status)
    env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
    ns.AuctionAPI.scanIntoPrices(ns, function() end)
    env.runTimers()
    local r = check(ns, env, "Full scan")
    assert.equal("pass", r.status)
    assert.equal("1 listings, 1 items, 0 without full info, 0 unreadable, 0s via event; "
      .. "first: Linen Cloth x20 for 4000",
      r.detail)
    assert.equal("pass", check(ns, env, "Market key").status)
    assert.equal("\"/1/Horde\" (ruleset 1, Horde)", check(ns, env, "Market key").detail)
    assert.equal("GetNormalizedRealmName=(empty), GetRealmName=(empty), UnitGUID server id=6841",
      check(ns, env, "Realm sources").detail)
    env.guid = nil
    assert.equal("GetNormalizedRealmName=(empty), GetRealmName=(empty), UnitGUID server id=(empty)",
      check(ns, env, "Realm sources").detail)
  end)

  it("refuses a second scan while one is running", function()
    local env, api, ns = setup()
    assert.is_true(ns.AuctionAPI.scanIntoPrices(ns, function() end))
    local ok, why = api:scan(function() end)
    assert.is_false(ok)
    assert.equal("A scan is already running.", why)
    assert.equal(1, env.replicateCalls)
  end)

  it("gives up with a reason when the auction house never answers", function()
    local env, api, ns = setup()
    env.replicateSilent = true
    local result
    env.auctions = {}
    ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end)
    env.runTimers(119)
    assert.is_nil(result, "still waiting just before the timeout")
    env.fire("UI_ERROR_MESSAGE", 51, "Too many requests")
    env.fire("UI_ERROR_MESSAGE", 51, "Something else")
    env.runTimers(1)
    assert.is_false(result[1])
    assert.matches("No reply from the auction house after 120 seconds", result[2])
    assert.matches("(replicate list: 0 listings before, 0 now; events: UI_ERROR_MESSAGE x2 (Too many requests); "
      .. "not in this client: none)", result[2], 1, true)
    assert.is_nil(api.pending)
    assert.equal("fail", check(ns, env, "Full scan").status)
    assert.is_true(api:scan(function() end), "a new scan can start after a timeout")
  end)

  it("reads the replicate list once it stops growing when the update event never comes", function()
    local env, _, ns = setup()
    env.replicateSilent = true
    env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
    local result
    ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end)
    env.runTimers(2)
    assert.is_nil(result, "two polls can't tell the list has stopped growing")
    env.runTimers(1)
    assert.same({ true, "Scanned 1 listings of 1 items in 3 seconds." }, result)
    assert.matches("via polling", ns.lastScanReport.detail)
  end)

  it("never takes a replicate list left over from an earlier scan as a new one", function()
    local env, _, ns = setup()
    env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
    ns.AuctionAPI.scanIntoPrices(ns, function() end)
    env.runTimers()
    local first = ns.prices:lastScan("/1/Horde")
    env.replicateSilent = true
    local result
    ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end)
    env.runTimers(120)
    assert.is_false(result[1])
    assert.matches("1 listings before, 1 now", result[2], 1, true)
    assert.equal(first, ns.prices:lastScan("/1/Horde"), "the old list was not stored again")
  end)

  it("names trace events this client doesn't have", function()
    local env, _, ns = setup()
    env.replicateSilent = true
    local register = env.CreateFrame("Frame").RegisterEvent
    for _, f in ipairs(env.frames) do
      f.RegisterEvent = function(frame, event)
        if event == "AUCTION_HOUSE_BROWSE_FAILURE" then error("unknown event") end
        return register(frame, event)
      end
    end
    local result
    ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end)
    env.runTimers(120)
    assert.matches("not in this client: AUCTION_HOUSE_BROWSE_FAILURE)", result[2], 1, true)
  end)

  it("ignores a late reply after a timeout", function()
    local env, _, ns = setup()
    env.replicateSilent = true
    local calls = 0
    ns.AuctionAPI.scanIntoPrices(ns, function() calls = calls + 1 end)
    env.runTimers(120)
    env.fire("REPLICATE_ITEM_LIST_UPDATE")
    assert.equal(1, calls)
  end)

  it("needs the auction house open to scan", function()
    local env, api = setup()
    env.CloseAuctionHouse()
    local ok, why = api:scan(function() end)
    assert.is_false(ok)
    assert.equal("Open the auction house to scan.", why)
    assert.equal(0, env.replicateCalls)
  end)

  it("fails a scan at once when the auction house closes mid-scan", function()
    local env, api, ns = setup()
    local result
    ns.AuctionAPI.scanIntoPrices(ns, function(ok, message) result = { ok, message } end)
    env.CloseAuctionHouse()
    assert.same({ false, "Scan failed. The auction house closed before the scan finished." }, result)
    assert.is_nil(api.pending)
  end)

  it("asks the client to load items that came back without full info", function()
    local env, api, ns = setup()
    local requested = {}
    env.C_Item = {
      RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
      GetItemNameByID = function(id) return id == 2592 and "Wool Cloth" or nil end,
    }
    env.auctions = { { count = 1, buyout = 5, itemID = 2592, hasAllInfo = false } }
    ns.AuctionAPI.scanIntoPrices(ns, function() end)
    env.runTimers()
    assert.same({ 2592 }, requested)
    assert.equal("Wool Cloth", api:itemName("i:2592"))
    assert.is_nil(api:itemName("i:1"))
  end)

  it("stores the names it can look up for listings that came without one", function()
    local env, _, ns = setup()
    env.C_Item = { GetItemNameByID = function(id) return id == 2592 and "Wool Cloth" or nil end }
    env.auctions = {
      { count = 1, buyout = 5, itemID = 2592, hasAllInfo = false },
      { count = 1, buyout = 5, itemID = 7, hasAllInfo = false },
    }
    ns.AuctionAPI.scanIntoPrices(ns, function() end)
    env.runTimers()
    local key = ns.AuctionAPI.currentMarket(env)
    local names = {}
    for _, it in ipairs(ns.prices:items(key)) do names[#names + 1] = it.name or it.item end
    assert.same({ "Wool Cloth", "i:7" }, names)
  end)

  it("says so when the client has no full scan", function()
    local env, api = setup()
    env.C_AuctionHouse.ReplicateItems = nil
    local ok, why = api:scan(function() end)
    assert.is_false(ok)
    assert.equal("This client can't do a full scan (C_AuctionHouse.ReplicateItems is missing).", why)
  end)

  describe("the 15-minute full scan limit (#114)", function()
    -- hooksecurefunc as the client does it: the original runs first, then the hook, with the same arguments.
    local function hooked()
      local env, api, ns = setup()
      env.hooksecurefunc = function(t, name, fn)
        local orig = t[name]
        t[name] = function(...) orig(...) fn(...) end
      end
      api:hookReplicate()
      return env, api, ns
    end

    it("notes our own requests, other addons' ones, and the server's answers", function()
      local env, api = hooked()
      local told = 0
      api.onOtherScan = function() told = told + 1 end
      assert.is_true(api:scan(function() end))
      assert.same({ env.now, "us" }, { api:lastAsk() })
      assert.equal(0, told, "our own request isn't another addon's")
      env.runTimers()
      assert.equal(env.now, select(3, api:lastAsk()), "answered")
      env.now = env.now + 60
      env.C_AuctionHouse.ReplicateItems()
      assert.equal(1, told)
      assert.same({ env.now, "other", env.now - 60 }, { api:lastAsk() })
    end)

    it("offers another addon's answer when it comes, once, and keeps the event watched after our scan", function()
      local env, api = hooked()
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      api:scan(function() end)
      env.runTimers()
      local offered = 0
      api.onOtherAnswer = function() offered = offered + 1 end
      env.now = env.now + 20 * 60
      env.C_AuctionHouse.ReplicateItems()
      env.runTimers()
      assert.equal(1, offered)
      assert.equal(env.now, select(3, api:lastAsk()))
      env.fire("REPLICATE_ITEM_LIST_UPDATE")
      assert.equal(1, offered, "a repeat event for the same answer")
      local calls, got = env.replicateCalls, nil
      assert.is_true(api:scan(function(listings) got = listings end, { listen = true }))
      assert.equal(calls, env.replicateCalls, "reading it asks for nothing")
      assert.equal(1, #got)
      assert.is_nil(api.pending)
    end)

    it("keeps the last request in saved variables, and a newer one noted before they loaded", function()
      local env, api = setup()
      api:scan(function() end)
      local saved = { askedAt = env.now - 3600, askedBy = "other", answeredAt = env.now - 3600 }
      api:useStore(saved)
      assert.same({ askedAt = env.now, askedBy = "us", answeredAt = env.now - 3600 }, saved)
      local newer = { askedAt = env.now + 5, askedBy = "other" }
      api:useStore(newer)
      assert.same({ env.now + 5, "other", env.now - 3600 }, { api:lastAsk() })
    end)
  end)
end)
