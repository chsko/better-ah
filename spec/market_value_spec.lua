local helper = require("spec.helper")

describe("MarketValue", function()
  local MarketValue = helper.load("BetterAH/Core/MarketValue.lua").MarketValue
  local DAY = MarketValue.DAY

  local function stacks(n, count, unit)
    local out = {}
    for i = 1, n do out[i] = { count = count, buyout = count * unit } end
    return out
  end

  local function with(list, ...)
    for _, l in ipairs({ ... }) do list[#list + 1] = l end
    return list
  end

  describe("scanValue", function()
    it("averages the cheapest part of the listings", function()
      -- 10 units at 100..1000: the cheapest 15% (2 units) are always taken. 30% would be 3 units, but
      -- 300 is 1.5x 200, a jump of more than 20%, so it stops at 2.
      local listings = {}
      for i = 1, 10 do listings[i] = { count = 1, buyout = i * 100 } end
      local value, info = MarketValue.scanValue(listings)
      assert.equal(150, value)
      assert.same({ units = 10, used = 2, dropped = 0, lowest = 100 }, info)
    end)

    it("takes up to 30% while prices stay close", function()
      local value, info = MarketValue.scanValue(stacks(10, 10, 1000))
      assert.equal(1000, value)
      assert.equal(30, info.used)
    end)

    it("leaves out a troll listing far below the rest, in big and small markets", function()
      local value, info = MarketValue.scanValue(with(stacks(10, 10, 100000), { count = 1, buyout = 1 }))
      assert.equal(100000, value)
      assert.same({ units = 101, used = 30, dropped = 1, lowest = 1 }, info)
      for n = 2, 13 do
        assert.equal(9000, (MarketValue.scanValue(with(stacks(n, 1, 9000), { count = 1, buyout = 1 }))), n)
      end
    end)

    it("leaves out a cheap stack that would fill the whole window", function()
      local value, info = MarketValue.scanValue(with(stacks(100, 1, 10000), { count = 20, buyout = 20 }))
      assert.equal(10000, value)
      assert.equal(20, info.dropped)
    end)

    it("keeps genuinely cheaper listings that aren't far below the median", function()
      local value, info = MarketValue.scanValue(with(stacks(9, 1, 1000), { count = 1, buyout = 600 }))
      assert.equal(867, value, "the cheapest 3 of 10: 600, 1000 and 1000")
      assert.equal(0, info.dropped)
    end)

    it("is not moved by absurdly high listings", function()
      local value = MarketValue.scanValue(with(stacks(10, 10, 5000), { count = 20, buyout = 20 * 9999999 }))
      assert.equal(5000, value)
    end)

    it("uses per-unit prices, so a big stack counts as many units", function()
      local value, info = MarketValue.scanValue({ { count = 20, buyout = 2000 }, { count = 1, buyout = 500 } })
      assert.equal(100, value)
      assert.equal(21, info.units)
    end)

    it("prices a market of one or two units from the cheapest, since it can't tell a troll", function()
      assert.equal(4321, (MarketValue.scanValue({ { count = 1, buyout = 4321 } })))
      local value, info = MarketValue.scanValue({ { count = 1, buyout = 1 }, { count = 1, buyout = 9000 } })
      assert.equal(1, value)
      assert.equal(0, info.dropped)
    end)

    it("skips bid-only listings and returns nil when nothing has a buyout", function()
      assert.is_nil(MarketValue.scanValue({ { count = 5, buyout = 0 }, { count = 2 } }))
      assert.is_nil(MarketValue.scanValue({}))
      assert.equal(700, (MarketValue.scanValue({ { count = 5, buyout = 0 }, { count = 1, buyout = 700 } })))
    end)

    it("never values an item at 0 copper", function()
      assert.equal(1, (MarketValue.scanValue({ { count = 20, buyout = 1 } })))
    end)

    it("rounds to whole copper", function()
      local value = MarketValue.scanValue(stacks(9, 3, 3333.3333))
      assert.equal(3333, value)
      assert.equal(math.floor(value), value)
    end)
  end)

  describe("smooth", function()
    local now = 100 * DAY + 3600

    it("weights recent days more over the last 14 days", function()
      -- today 1400 (weight 14), 13 days ago 0 (weight 1): (1400*14 + 0*1) / 15
      local value, info = MarketValue.smooth({ { day = 100, value = 1400 }, { day = 87, value = 0 } }, now)
      assert.equal(1307, value)
      assert.same({ days = 2, oldest = 13 }, info)
    end)

    it("follows a real price move within two weeks", function()
      local points = {}
      for d = 0, 13 do points[#points + 1] = { day = 100 - d, value = d < 7 and 2000 or 1000 } end
      local value = MarketValue.smooth(points, now)
      assert.is_true(value > 1500 and value < 2000, tostring(value))
    end)

    it("forgets days older than 14 days", function()
      assert.is_nil(MarketValue.smooth({ { day = 86, value = 5 } }, now))
      assert.equal(10, (MarketValue.smooth({ { day = 86, value = 5 }, { day = 99, value = 10 } }, now)))
    end)

    it("ignores points from the future", function()
      assert.equal(10, (MarketValue.smooth({ { day = 101, value = 99 }, { day = 100, value = 10 } }, now)))
    end)
  end)
end)
