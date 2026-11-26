local helper = require("spec.helper")

describe("ValueHistory", function()
  local ns = helper.load("BetterAH/Core/MarketValue.lua")
  helper.load("BetterAH/Core/Disenchant.lua", ns)
  helper.load("BetterAH/Core/ValueHistory.lua", ns)
  local VH, D = ns.ValueHistory, ns.Disenchant
  local band = { min = 26, max = 30 } -- armor: Soul Dust 75% 1-2, Greater Astral 20% 1-2, Large Glimmering 5%

  describe("snapshots", function()
    it("keeps the newest ten per market and measures against the one before the latest", function()
      local store = {}
      assert.is_nil(VH.baseline(store, "m"))
      for i = 1, 12 do
        VH.record(store, "m", i * 100, function(id) return id == 11083 and i * 10 or nil end, D.MATERIALS)
      end
      assert.equal(10, #store.m)
      assert.equal(300, store.m[1].time)
      local base = VH.baseline(store, "m")
      assert.equal(1100, base.time)
      assert.equal(110, VH.priceLookup(base)(11083))
      assert.is_nil(VH.priceLookup(base)(10940), "only priced materials are kept")
      assert.is_nil(VH.baseline(store, "other"))
    end)

    it("has no baseline after the first scan", function()
      local store = {}
      VH.record(store, "m", 1, function() return 5 end, D.MATERIALS)
      assert.is_nil(VH.baseline(store, "m"))
      assert.is_nil(VH.priceLookup(nil)(11083))
    end)
  end)

  describe("priceOn", function()
    local history = { { day = 10, value = 100 }, { day = 12, value = 120 } }
    it("takes that day's point or the latest earlier one within 14 days", function()
      assert.equal(100, VH.priceOn(history, 10))
      assert.equal(100, VH.priceOn(history, 11))
      assert.equal(120, VH.priceOn(history, 12))
      assert.equal(120, VH.priceOn(history, 25))
      assert.is_nil(VH.priceOn(history, 26), "too old")
      assert.is_nil(VH.priceOn(history, 9), "before any point")
      assert.is_nil(VH.priceOn({}, 9))
    end)
  end)

  describe("bandSeries", function()
    it("works out each day's after-cut value from the materials' daily prices", function()
      local histories = {
        [11083] = { { day = 98, value = 400 }, { day = 100, value = 500 } },
        [11082] = { { day = 98, value = 1000 } },
        [11084] = { { day = 99, value = 200 } },
      }
      local series = VH.bandSeries(band, "armor", function(id) return histories[id] end, {}, 100, 5)
      -- Day 98 lacks the shard, which is priced today, so it is left out; days 96-97 have nothing.
      assert.same({ 99, 100 }, { series[1].day, series[2].day })
      local value99 = D.value({ quality = 2, class = "armor", level = 26 }, function(id)
        return ({ [11083] = 400, [11082] = 1000, [11084] = 200 })[id]
      end, {})
      assert.equal(D.net(value99), series[1].net)
      assert.is_true(series[2].net > series[1].net, "dust went up")
    end)

    it("follows the Salvager option", function()
      local h = { [11083] = { { day = 5, value = 500 } }, [11082] = { { day = 5, value = 1000 } } }
      local without = VH.bandSeries(band, "armor", function(id) return h[id] end, {}, 5, 1)
      local with = VH.bandSeries(band, "armor", function(id) return h[id] end, { salvager = true }, 5, 1)
      assert.is_true(with[1].net > without[1].net)
    end)

    it("is empty without prices", function()
      assert.same({}, VH.bandSeries(band, "weapon", function() return nil end, {}, 100, 30))
    end)
  end)

  describe("trend and layout", function()
    it("fits a straight line and gives its change over the series", function()
      local at, change = VH.trend({ { day = 1, net = 100 }, { day = 2, net = 110 }, { day = 3, net = 120 } })
      assert.equal(20, change)
      assert.equal(130, math.floor(at(4) + 0.5))
      local _, down = VH.trend({ { day = 1, net = 300 }, { day = 3, net = 100 } })
      assert.equal(-200, down)
      assert.is_nil(VH.trend({ { day = 1, net = 5 } }))
      assert.is_nil(VH.trend({}))
    end)

    it("places points across the range with today at the right edge", function()
      local l = VH.layout({ { day = 71, net = 100 }, { day = 100, net = 200 } }, 100, 30)
      assert.equal(100, l.low)
      assert.equal(200, l.high)
      assert.same({ x = 0, y = 0 }, l.points[1])
      assert.same({ x = 1, y = 1 }, l.points[2])
      assert.near(0, l.trend[1].y, 1e-9)
      assert.near(1, l.trend[2].y, 1e-9)
      assert.equal(0, l.trend[1].x)
      assert.is_nil(VH.layout({}, 100, 30))
    end)

    it("widens the axis to the trend line's ends, so the line keeps its slope", function()
      local series = { { day = 1, net = 0 }, { day = 2, net = 0 }, { day = 3, net = 0 }, { day = 4, net = 10 } }
      local l = VH.layout(series, 4, 4)
      assert.equal(-2, l.low, "the fit is -2 on the first day")
      assert.near(0, l.trend[1].y, 1e-9)
    end)

    it("centres a flat series and draws no trend for one point", function()
      local l = VH.layout({ { day = 100, net = 50 } }, 100, 7)
      assert.same({ x = 1, y = 0.5 }, l.points[1])
      assert.is_nil(l.trend)
    end)
  end)
end)

describe("DisenchantView changes", function()
  local ns = helper.load("BetterAH/Core/Money.lua")
  for _, f in ipairs({ "MarketValue", "Disenchant", "Targets", "ValueHistory" }) do
    helper.load("BetterAH/Core/" .. f .. ".lua", ns)
  end
  helper.load("BetterAH/UI/DisenchantView.lua", ns)
  local D = ns.DisenchantView
  local function row(list) for _, r in ipairs(list) do if r.band.min == 26 then return r end end end
  local now = { [11083] = 500, [11082] = 1000, [11084] = 2000 }

  it("gives a band's change only when both scans priced the same materials", function()
    local price = function(id) return now[id] end
    local same = row(D.rows(price, {}, nil, function(id) return ({ [11083] = 400, [11082] = 1000,
      [11084] = 2000 })[id] end))
    assert.is_true(same.armor.change > 0)
    assert.equal(100, same.armor.breakdown[1].change)
    assert.equal(0, same.armor.breakdown[2].change)
    local newMat = row(D.rows(price, {}, nil, function(id) return ({ [11083] = 500, [11084] = 2000 })[id] end))
    assert.is_nil(newMat.armor.change, "the essence got a price, nothing moved")
    assert.is_nil(newMat.armor.breakdown[2].change)
    assert.is_nil(row(D.rows(price, {})).armor.change, "no earlier scan")
  end)

  it("writes changes in green or red, and the trend over the days it covers", function()
    assert.equal("|cff1eff00+38c|r", D.changeText(38))
    assert.equal("|cffff4a3a-1g 2s|r", D.changeText(-10200, true))
    assert.is_nil(D.changeText(0))
    assert.is_nil(D.changeText(nil))
    assert.equal("", D.trendText(nil, 0, 0))
    assert.equal("One day of prices so far: no trend yet.", D.trendText(nil, 1, 0))
    assert.equal("Trend flat over 1 day", D.trendText(0, 2, 1))
    assert.equal("Trend |cffff4a3a-5c|r over 12 days", D.trendText(-5, 9, 12))
  end)
end)
