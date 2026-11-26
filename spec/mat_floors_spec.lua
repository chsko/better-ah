local helper = require("spec.helper")

describe("MatFloors", function()
  local ns = helper.load("BetterAH/Core/Disenchant.lua")
  helper.load("BetterAH/Core/MatFloors.lua", ns)
  local M = ns.MatFloors
  local STRANGE, LESSER_MAGIC, GREATER_MAGIC = 10940, 10938, 10939
  local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082

  local function values(t)
    return function(id) return t[id] end
  end
  local function target(kind, amount, enabled)
    return { enabled = enabled ~= false, band = 21, profit = { kind = kind, amount = amount } }
  end

  it("fills in the default rule", function()
    assert.same({ kind = "breakeven", percent = 80, convert = true }, M.rule(nil))
    assert.same({ kind = "percent", percent = 70, convert = false },
      M.rule({ kind = "percent", percent = 70, convert = false }))
    assert.equal(80, M.rule({ percent = -5 }).percent)
  end)

  it("knows the 24 materials by item key", function()
    assert.equal("Strange Dust", M.material("i:10940").name)
    assert.is_nil(M.material("i:2589"))
    assert.is_nil(M.material("Linen"))
  end)

  describe("break-even", function()
    it("is one less the smallest profit share among sniped targets", function()
      local share, profit = M.breakEven({ target("percent", 20), target("percent", 10), target("percent", 5, false) })
      assert.near(0.9, share, 1e-9)
      assert.near(0.1, profit, 1e-9)
    end)

    it("turns a profit in gold into a share of the band's worth", function()
      local t = target("gold", 2000)
      assert.near(0.8, (M.breakEven({ t }, function() return 10000 end)), 1e-9)
      assert.is_nil(M.breakEven({ t }, function() return nil end), "no worth, nothing to go by")
    end)

    it("is nil without a sniped target", function()
      assert.is_nil(M.breakEven({}))
      assert.is_nil(M.breakEven({ target("percent", 20, false) }))
    end)
  end)

  describe("floor", function()
    local rule = M.rule(nil)

    it("is the break-even share of market value", function()
      local f = M.floor("i:" .. STRANGE, rule, values({ [STRANGE] = 1802 }), { target("percent", 20) })
      assert.equal(1442, f.floor) -- 1802 * 0.8 = 1441.6, rounded up
      assert.equal("breakeven", f.source)
      assert.near(0.2, f.profit, 1e-9)
      assert.is_nil(f.convert)
    end)

    it("doesn't round a copper too high from float error", function()
      local f = M.floor("i:" .. STRANGE, rule, values({ [STRANGE] = 150 }), { target("percent", 18) })
      assert.equal(123, f.floor)
    end)

    it("falls back to the percent without a target", function()
      local f = M.floor("i:" .. STRANGE, rule, values({ [STRANGE] = 1000 }), {})
      assert.equal(800, f.floor)
      assert.equal("percent", f.source)
      local seventy = M.rule({ kind = "percent", percent = 70 })
      local f70 = M.floor("i:" .. STRANGE, seventy, values({ [STRANGE] = 1000 }), { target("percent", 20) })
      assert.equal(700, f70.floor)
    end)

    it("keeps a lesser essence at a third of the greater's floor", function()
      local v = values({ [LESSER_MAGIC] = 900, [GREATER_MAGIC] = 2800 })
      local f = M.floor("i:" .. LESSER_MAGIC, rule, v, { target("percent", 20) })
      assert.equal(720, f.base)
      assert.equal(747, f.floor) -- 2240 / 3, rounded up
      assert.same({ id = GREATER_MAGIC, ratio = 1 / 3, floor = 2240 }, f.convert)
    end)

    it("keeps a greater essence at three lessers' floors", function()
      local v = values({ [LESSER_ASTRAL] = 2000, [GREATER_ASTRAL] = 5200 })
      local f = M.floor("i:" .. GREATER_ASTRAL, rule, v, { target("percent", 20) })
      assert.equal(4800, f.floor)
      assert.equal(LESSER_ASTRAL, f.convert.id)
    end)

    it("leaves the essence rule out when convert is off", function()
      local v = values({ [LESSER_MAGIC] = 900, [GREATER_MAGIC] = 2800 })
      local f = M.floor("i:" .. LESSER_MAGIC, M.rule({ convert = false }), v, { target("percent", 20) })
      assert.equal(720, f.floor)
      assert.is_nil(f.convert)
    end)

    it("uses the other essence when this one has no market value", function()
      local f = M.floor("i:" .. LESSER_MAGIC, rule, values({ [GREATER_MAGIC] = 3000 }), { target("percent", 20) })
      assert.equal(800, f.floor)
      assert.is_nil(f.base)
    end)

    it("is nil for other items or with nothing known", function()
      assert.is_nil(M.floor("i:2589", rule, values({}), {}))
      assert.is_nil(M.floor("i:" .. STRANGE, rule, values({}), {}))
    end)
  end)
end)
