local helper = require("spec.helper")
local fake = require("spec.fake_client")

describe("DebugHooks (#99)", function()
  local function setup(on)
    local env = fake.new()
    local ns = helper.load("BetterAH/Core/Money.lua")
    helper.load("BetterAH/Core/DebugLog.lua", ns)
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
end)
