local helper = require("spec.helper")

describe("DisenchantWatch (#256)", function()
  local green = "|cff1eff00|Hitem:4251:0:0:0:0:0:-34:0|h[Hillman's Shoulders]|h|r"
  local dust = "|cffffffff|Hitem:10940::::::::60|h[Strange Dust]|h|r"

  local function setup()
    local ns = helper.load("BetterAH/Core/Purchases.lua")
    for _, f in ipairs({ "Disenchant", "SnipeProfit", "DisenchantTracker" }) do
      helper.load("BetterAH/Core/" .. f .. ".lua", ns)
    end
    local hooks, frame = {}, nil
    local env = { clock = 100, loot = {}, server = 5000, locked = {} }
    env.GetTime = function() return env.clock end
    env.GetServerTime = function() return env.server end
    env.C_Container = {
      UseContainerItem = function() end,
      PickupContainerItem = function() end,
      GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 3 then return { hyperlink = green, itemID = 4251, isLocked = env.locked[3] } end
        if bag == 0 and slot == 4 then return { hyperlink = dust, itemID = 10940, isLocked = env.locked[4] } end
      end,
    }
    env.hooksecurefunc = function(tbl, name, fn)
      hooks[name] = fn
      local old = tbl[name]
      tbl[name] = function(...) old(...); fn(...) end
    end
    env.GetNumLootItems = function() return #env.loot end
    env.GetLootSlotLink = function(i) return env.loot[i].link end
    env.GetLootSlotInfo = function(i) return "icon", "name", env.loot[i].count end
    env.CreateFrame = function()
      frame = { events = {} }
      function frame:RegisterEvent(e) self.events[e] = true end
      function frame:SetScript(_, fn) self.onEvent = fn end
      return frame
    end
    ns.snipeProfit = ns.SnipeProfit.new({})
    ns.purchases = ns.Purchases.new({})
    helper.load("BetterAH/Game/DisenchantWatch.lua", ns)
    local watch = ns.DisenchantWatch.install(env, ns)
    local function fire(event, ...) frame.onEvent(frame, event, ...) end
    return env, ns, watch, fire, hooks
  end

  it("records a disenchant: item clicked, cast started and finished, loot read", function()
    local env, ns, _, fire = setup()
    ns.snipeProfit:bought(4251, green, 9000, 10, { name = "Armor", min = 21, max = 25 })
    env.C_Container.UseContainerItem(0, 3) -- the hook runs after the click, targeting already over
    fire("UNIT_SPELLCAST_START", "player", "cast-1", 13262)
    env.clock = 100.5
    fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 13262) -- a second press: another action in progress
    env.clock = 103
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    env.loot = { { link = dust, count = 3 } }
    env.clock = 103.2
    fire("LOOT_READY")
    fire("LOOT_OPENED")
    local g = ns.snipeProfit.store.greens[1]
    assert.same({ [10940] = 3 }, g.de.mats)
    assert.equal(5000, g.de.t)
    assert.equal(1, #ns.snipeProfit.store.greens, "LOOT_OPENED after LOOT_READY adds nothing")
  end)

  it("names the item locked in the bags when the cast starts", function()
    local env, ns, _, fire = setup()
    env.locked[3] = true
    fire("UNIT_SPELLCAST_START", "player", "cast-1", 13262)
    env.locked[3] = nil
    env.clock = 103
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    env.loot = { { link = dust, count = 3 } }
    fire("LOOT_READY")
    assert.equal(4251, ns.snipeProfit.store.greens[1].item)
  end)

  it("names no locked item when several are locked", function()
    local env, _, watch = setup()
    env.locked[3], env.locked[4] = true, true
    assert.is_nil(watch:lockedItem())
  end)

  it("records nothing when no item is known", function()
    local env, ns, _, fire = setup()
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    env.loot = { { link = dust, count = 3 } }
    fire("LOOT_READY")
    assert.same({}, ns.snipeProfit.store.greens)
  end)

  it("uses the loot source's item when the game gives one", function()
    local env, ns, _, fire = setup()
    env.GetLootSourceInfo = function() return "Item-6841-0-4000000ABC" end
    env.C_Item = { GetItemLinkByGUID = function(guid) return guid == "Item-6841-0-4000000ABC" and green end }
    ns.purchases:bought(4251, green, 1, 7700, 1)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    env.loot = { { link = dust, count = 2 } }
    fire("LOOT_READY")
    local g = ns.snipeProfit.store.greens[1]
    assert.equal(4251, g.item)
    assert.is_nil(g.target, "not sniped")
    assert.equal(7700, g.c, "priced from the Purchases record")
  end)

  it("ignores another player's casts and ordinary loot", function()
    local env, ns, _, fire = setup()
    fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-1", 13262)
    env.loot = { { link = dust, count = 3 } }
    fire("LOOT_READY")
    assert.same({}, ns.snipeProfit.store.greens)
  end)

  it("names the calls this client lacks", function()
    local _, ns = setup()
    local missing = ns.DisenchantWatch.missing({ C_Container = {}, GetNumLootItems = function() end })
    assert.same({ "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo",
      "C_Container.UseContainerItem", "C_Container.PickupContainerItem", "C_Container.GetContainerItemInfo",
      "C_Container.GetContainerNumSlots", "C_Item.GetItemLinkByGUID" }, missing)
  end)
end)
