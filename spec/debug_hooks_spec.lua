local helper = require("spec.helper")
local fake = require("spec.fake_client")

describe("DebugHooks (#99)", function()
  local function setup(on)
    local env = fake.new()
    local ns = helper.load("BetterAH/Core/Money.lua")
    helper.load("BetterAH/Core/DebugLog.lua", ns)
    helper.load("BetterAH/Core/Posting.lua", ns)
    helper.load("BetterAH/Game/PostingAPI.lua", ns)
    helper.load("BetterAH/Game/SnipeAPI.lua", ns)
    helper.load("BetterAH/Game/DebugHooks.lua", ns)
    ns.PostingAPI.install(env, ns)
    local api = ns.SnipeAPI.install(env, ns)
    ns.DebugHooks.install(env, ns)
    ns.DebugHooks.load(env)
    ns.debugLog:setOn(on)
    return env, api, ns
  end

  for _, on in ipairs({ false, true }) do
    it("leaves a buy as it was with the log " .. (on and "on" or "off"), function()
      local env, api, ns = setup(on)
      env.openAuctionHouse()
      local calls = {}
      api:buy(7, 900, function(...) calls[#calls + 1] = { ... } end, "the Buy button")
      assert.same({ { auctionID = 7, amount = 900 } }, env.bids, "PlaceBid runs inside the buy call")
      env.runTimers()
      assert.same({ { true } }, calls, "done once, with the same arguments")
      local text = table.concat(ns.debugLog.saved.lines, "\n")
      if on then
        assert.matches("%[buy%] send auction 7 for 900 copper %(from the Buy button%)", text)
        assert.matches("%[buy%] auction 7: bought", text)
      else
        assert.equal(0, ns.debugLog:count())
      end
    end)
  end

  it("logs how many of a search's units are yours and the cheapest that isn't (#132)", function()
    local env, _, ns = setup(true)
    env.openAuctionHouse()
    env.listings[11082] = { { unitPrice = 1444, quantity = 54, numOwnerItems = 54 },
      { unitPrice = 1447, quantity = 25 } }
    local got
    ns.postingAPI:search({ item = "i:11082", itemID = 11082, name = "Greater Astral Essence", commodity = true,
      itemKey = { itemID = 11082 } }, function(listings) got = listings end)
    env.runTimers()
    assert.equal(2, #got)
    assert.matches("[search] Greater Astral Essence -> 2 listings, search marks 54 yours, cheapest other 1447",
      table.concat(ns.debugLog.saved.lines, "\n"), 1, true)
  end)

  it("logs blocks only for this addon", function()
    local _, _, ns = setup(true)
    ns.DebugHooks.onEvent("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
    ns.DebugHooks.onEvent("ADDON_ACTION_BLOCKED", "BetterAH", "PlaceBid()")
    local text = table.concat(ns.debugLog.saved.lines, "\n")
    assert.is_nil(text:find("Foo", 1, true))
    assert.matches("%[blocked%] ADDON_ACTION_BLOCKED PlaceBid%(%)", text)
  end)

  it("logs the stack of a block, which names the line that made the call (#112)", function()
    local _, _, ns = setup(true)
    local saved = _G.debugstack
    _G.debugstack = function() return "BetterAH/Game/BrowseAPI.lua:201: in quoteCommodity\nOnClick" end
    ns.DebugHooks.onEvent("ADDON_ACTION_BLOCKED", "BetterAH", "UNKNOWN()")
    _G.debugstack = saved
    local text = table.concat(ns.debugLog.saved.lines, "\n")
    assert.truthy(text:find("UNKNOWN() / BetterAH/Game/BrowseAPI.lua:201: in quoteCommodity / OnClick", 1, true))
  end)

  it("logs Lua errors naming the addon and still hands them on", function()
    local env, _, ns = setup(false)
    local handed = {}
    local handler = function(m) handed[#handed + 1] = m end
    env.geterrorhandler = function() return handler end
    env.seterrorhandler = function(fn) handler = fn end
    ns.DebugHooks.setOn(env, true)
    handler("Interface/AddOns/BetterAH/UI/PostView.lua:10: boom")
    handler("Interface/AddOns/Other/x.lua:1: not ours")
    assert.equal(2, #handed)
    local text = table.concat(ns.debugLog.saved.lines, "\n")
    assert.matches("%[error%] Interface/AddOns/BetterAH/UI/PostView.lua:10: boom", text)
    assert.is_nil(text:find("not ours", 1, true))
  end)

  it("says so when another addon keeps the error handler", function()
    local env, _, ns = setup(false)
    env.geterrorhandler = function() return print end
    env.seterrorhandler = function() end
    ns.DebugHooks.setOn(env, true)
    assert.matches("Lua errors can't be logged", table.concat(ns.debugLog.saved.lines, "\n"))
  end)

  for _, on in ipairs({ false, true }) do
    it("passes a listening full scan through with the log " .. (on and "on" or "off") .. " (#114)", function()
      local env, _, ns = setup(on)
      helper.load("BetterAH/Core/MarketKey.lua", ns)
      helper.load("BetterAH/Game/AuctionAPI.lua", ns)
      local api = ns.AuctionAPI.install(env, ns)
      ns.DebugHooks.install(env, ns)
      env.hooksecurefunc = function(t, name, fn)
        local orig = t[name]
        t[name] = function(...) orig(...) fn(...) end
      end
      api:hookReplicate()
      env.openAuctionHouse()
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      env.C_AuctionHouse.ReplicateItems()
      env.runTimers()
      local got
      assert.is_true(api:scan(function(listings) got = listings end, { listen = true }))
      assert.equal(1, env.replicateCalls, "only the other addon's request")
      assert.equal(1, #got)
      local text = table.concat(ns.debugLog.saved.lines, "\n")
      if on then
        assert.matches("another addon asked for a full scan", text, 1, true)
        assert.matches("reading another addon's full scan", text, 1, true)
        assert.matches("a full scan answer came that we didn't ask for", text, 1, true)
      end
    end)
  end
end)
