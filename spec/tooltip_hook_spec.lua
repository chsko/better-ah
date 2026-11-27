local helper = require("spec.helper")

-- The hook's own job: read the item from the client, hand it to TooltipPrices and draw the answer.
-- The real tooltip and its refresh on Shift need the client (see #119).
describe("TooltipHook", function()
  local ns, env, tip, lines

  local link = "|cff1eff00|Hitem:4251:0:0:0:0:0:-34:0|h[Hillman's Shoulders]|h|r"

  before_each(function()
    ns = helper.load("BetterAH/Core/Money.lua")
    for _, f in ipairs({ "MarketValue", "PriceDB", "Disenchant", "Purchases", "TooltipPrices", "CharacterRecords" }) do
      helper.load("BetterAH/Core/" .. f .. ".lua", ns)
    end
    helper.load("BetterAH/Game/TooltipHook.lua", ns)
    ns.AuctionAPI = { currentMarket = function() return "/Normal/Horde" end }
    ns.prices = ns.PriceDB.new({})
    ns.purchases = ns.Purchases.new({})
    ns.tooltipSettings = {}
    lines = {}
    tip = {
      item = link,
      GetItem = function(self) return "Hillman's Shoulders", self.item end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " | " .. right end,
      Show = function() end,
    }
    env = {
      GameTooltip = tip, now = 86400 * 100, shift = false, count = 1,
      GetServerTime = function() return env.now end,
      IsShiftKeyDown = function() return env.shift end,
      -- Like the Forever client (#153): no global GetItemInfo, GetItemCount or GetCoinTextureString.
      C_Item = {
        GetItemCount = function() return env.count end,
        -- name, link, quality, item level, required level, class, subclass, max stack, equip slot, icon, sell, classID
        GetItemInfo = function() return "Hillman's Shoulders", link, 2, 26, 21, "Armor", "Leather", 1,
          "INVTYPE_SHOULDER", 0, 500, 4 end,
      },
    }
  end)

  it("adds the block to the main tooltip with market value, disenchant value, paid and profit", function()
    ns.prices:importPrices("/Normal/Horde", env.now, { ["i:4251"] = { value = 42000 }, ["i:11083"] = { value = 3000 },
      ["i:11082"] = { value = 9000 }, ["i:11084"] = { value = 8000 } })
    ns.purchases:bought(4251, link, 1, 21000, env.now)
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.equal(" ", lines[1])
    assert.equal("Better AH", lines[2])
    assert.equal("Market value | 4g 20s 0c", lines[3])
    assert.matches("^Disenchant value | ", lines[4])
    assert.equal("You paid | 2g 10s 0c", lines[5])
    assert.equal("Profit if sold | +1g 89s 0c", lines[6])
    assert.matches("^Profit if disenchanted | ", lines[7])
  end)

  it("says when an item has no price, and leaves comparison tooltips alone", function()
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.equal(ns.TooltipPrices.NO_PRICE, lines[3])
    lines = {}
    local other = setmetatable({}, { __index = tip })
    ns.TooltipHook.new(env, ns):onItem(other)
    assert.same({}, lines)
  end)

  it("adds nothing when the setting is off", function()
    ns.tooltipSettings.show = false
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.same({}, lines)
  end)

  it("skips a quest item with no price: it can never be on the auction house", function()
    env.C_Item.GetItemInfo = function()
      return "Quest Thing", link, 1, 10, 1, "Quest", "Quest", 1, "", 0, 0, 12, 0, 4
    end
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.same({}, lines)
  end)

  it("skips a soulbound item with no price", function()
    env.C_Item.GetItemInfo = function()
      return "Bound Thing", link, 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_CHEST", 0, 0, 4, 1, 1
    end
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.same({}, lines)
  end)

  it("draws the full block once an item that wasn't cached has loaded", function()
    ns.prices:importPrices("/Normal/Horde", env.now, { ["i:4251"] = { value = 42000 }, ["i:11083"] = { value = 3000 } })
    local info = env.C_Item.GetItemInfo
    env.C_Item.GetItemInfo = function() end
    local hook = ns.TooltipHook.new(env, ns)
    hook:onItem(tip)
    assert.is_nil(lines[4])
    lines, env.C_Item.GetItemInfo = {}, info
    hook:onItem(tip)
    assert.matches("^Disenchant value | ", lines[4])
  end)

  it("never breaks the tooltip when something in it throws", function()
    ns.prices = { marketValue = function() error("bad data") end }
    assert.has_no.errors(function() ns.TooltipHook.new(env, ns):onItem(tip) end)
    assert.same({}, lines)
  end)

  it("draws money with the coin icons from C_CurrencyInfo", function()
    ns.prices:importPrices("/Normal/Horde", env.now, { ["i:4251"] = { value = 42000 } })
    env.C_CurrencyInfo = { GetCoinTextureString = function(c) return "coins:" .. c end }
    env.GetCoinTextureString = function() return "old global" end
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.equal("Market value | coins:42000", lines[3])
  end)

  it("still reads a client that has only the old globals", function()
    ns.prices:importPrices("/Normal/Horde", env.now, { ["i:4251"] = { value = 42000 }, ["i:11083"] = { value = 3000 } })
    env.GetItemInfo, env.C_Item = env.C_Item.GetItemInfo, nil
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.matches("^Disenchant value | ", lines[4])
  end)

  it("shows the bag totals on the main tooltip while Shift is held", function()
    ns.prices:importPrices("/Normal/Horde", env.now, { ["i:4251"] = { value = 42000 } })
    env.shift, env.count = true, 3
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.equal("Better AH |cff9d9d9d(3 in bags)|r", lines[2])
    assert.equal("Market value | 12g 60s 0c", lines[3])
  end)
end)

describe("TooltipHook, an item not in the bags", function()
  it("shows no paid price or profit on someone else's copy", function()
    local ns = helper.load("BetterAH/Core/Money.lua")
    for _, f in ipairs({ "MarketValue", "PriceDB", "Disenchant", "Purchases", "TooltipPrices" }) do
      helper.load("BetterAH/Core/" .. f .. ".lua", ns)
    end
    helper.load("BetterAH/Game/TooltipHook.lua", ns)
    ns.AuctionAPI = { currentMarket = function() return "/Normal/Horde" end }
    ns.prices, ns.purchases, ns.tooltipSettings = ns.PriceDB.new({}), ns.Purchases.new({}), {}
    ns.prices:importPrices("/Normal/Horde", 100, { ["i:2589"] = { value = 100 } })
    ns.purchases:bought(2589, nil, 5, 300, 100)
    local lines = {}
    local tip = { GetItem = function() return "Linen Cloth", "item:2589" end, Show = function() end,
      AddLine = function(_, t) lines[#lines + 1] = t end,
      AddDoubleLine = function(_, l) lines[#lines + 1] = l end }
    local env = { GameTooltip = tip, GetServerTime = function() return 100 end,
      C_Item = { GetItemCount = function() return 0 end,
        GetItemInfo = function() return "Linen Cloth", "item:2589", 1, 5, 0, "Trade Goods", "Cloth", 20 end } }
    ns.TooltipHook.new(env, ns):onItem(tip)
    assert.same({ " ", "Better AH |cff9d9d9d(each)|r", "Market value" }, lines)
  end)
end)
