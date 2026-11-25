local helper = require("spec.helper")

local Scale = helper.load("BetterAH/Core/WindowScale.lua").WindowScale

describe("WindowScale", function()
  it("allows 0.7x to 1.5x on a screen with room for it", function()
    local min, max = Scale.limits(980, 470, 2560, 1440)
    assert.equal(0.7, min)
    assert.equal(1.5, max)
  end)

  it("caps the scale so the window fits the screen", function()
    local _, max = Scale.limits(980, 470, 1365, 768)
    assert.equal(1365 / 980, max)
    _, max = Scale.limits(980, 470, 2560, 600)
    assert.equal(600 / 470, max)
  end)

  it("still allows the minimum on a screen too small for it", function()
    local min, max = Scale.limits(980, 470, 500, 300)
    assert.equal(0.7, min)
    assert.equal(0.7, max)
  end)

  it("clamps a scale into the limits", function()
    assert.equal(0.7, Scale.clamp(0.2, 980, 470, 2560, 1440))
    assert.equal(1.5, Scale.clamp(3, 980, 470, 2560, 1440))
    assert.equal(1.2, Scale.clamp(1.2, 980, 470, 2560, 1440))
    assert.equal(1, Scale.clamp(0 / 0, 980, 470, 2560, 1440), "not a number gives the default")
    assert.equal(1, Scale.clamp(nil, 980, 470, 2560, 1440))
  end)

  it("loads the saved scale, or 1x when none is usable", function()
    assert.equal(1, Scale.load(nil))
    assert.equal(1, Scale.load({}))
    assert.equal(1, Scale.load({ scale = "big" }))
    assert.equal(1, Scale.load({ scale = 0 / 0 }))
    assert.equal(1.25, Scale.load({ scale = 1.25 }))
    assert.equal(0.7, Scale.load({ scale = 0.1 }))
    assert.equal(1.5, Scale.load({ scale = 9 }))
  end)

  describe("fromDrag", function()
    -- A 980 x 470 window at 1x with its top-left corner at (100, 700); the grip starts at its corner.
    local function drag(x, y) return Scale.fromDrag(1, 100, 700, 1080, 230, x, y, 980, 470) end

    it("keeps the scale when the cursor hasn't moved", function()
      assert.equal(1, drag(1080, 230))
    end)

    it("doubles the scale when the corner moves twice as far along the diagonal", function()
      assert.near(2, drag(100 + 1960, 700 - 940), 1e-9)
    end)

    it("halves it when the corner moves halfway back to the top-left", function()
      assert.near(0.5, drag(100 + 490, 700 - 235), 1e-9)
    end)

    it("follows a sideways or a vertical drag too", function()
      assert.is_true(drag(1280, 230) > 1)
      assert.is_true(drag(1080, 100) > 1)
      assert.is_true(drag(900, 230) < 1)
    end)

    it("starts from the scale the window had", function()
      assert.near(1.5, Scale.fromDrag(1.2, 100, 700, 1080, 230, 100 + 980 * 1.25, 700 - 470 * 1.25, 980, 470), 1e-9)
    end)

    it("keeps the scale when the drag starts at or behind the top-left corner", function()
      assert.equal(1, Scale.fromDrag(1, 100, 700, 100, 700, 500, 300, 980, 470))
    end)
  end)

  describe("place", function()
    it("keeps a corner that leaves the window on screen", function()
      assert.same({ 100, 700 }, { Scale.place(100, 700, 980, 470, 1365, 768) })
    end)

    it("moves the window back on screen", function()
      assert.same({ 1365 - 1200, 768 }, { Scale.place(400, 800, 1200, 600, 1365, 768) })
      assert.same({ 0, 600 }, { Scale.place(-50, 300, 1200, 600, 1365, 768) })
    end)
  end)
end)
