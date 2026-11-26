local helper = require("spec.helper")

local function texture()
  local t = {}
  function t:SetSnapToPixelGrid(on) self.snap = on end
  function t:SetTexelSnappingBias(bias) self.bias = bias end
  return t
end

describe("Loading.unsnap", function()
  local ns = {}
  helper.load("BetterAH/UI/Loading.lua", ns)

  it("turns pixel snapping off on a frame's textures and its children's, so a spinner turns smoothly", function()
    local ring, sparks, inner = texture(), texture(), texture()
    local child = { GetRegions = function() return inner end }
    local frame = {
      GetRegions = function() return ring, "not a region", sparks end,
      GetChildren = function() return child end,
    }
    ns.Loading.unsnap(frame)
    for _, t in ipairs({ ring, sparks, inner }) do
      assert.is_false(t.snap)
      assert.equal(0, t.bias)
    end
  end)

  it("is done to every spinner", function()
    local ring = texture()
    local env = { CreateFrame = function()
      return { GetRegions = function() return ring end, SetSize = function() end, Hide = function() end }
    end }
    ns.Loading.spinner(env, {})
    assert.is_false(ring.snap)
  end)

  it("leaves a client without those calls alone", function()
    assert.has_no.errors(function() ns.Loading.unsnap({ GetRegions = function() return {} end }) end)
    assert.has_no.errors(function() ns.Loading.unsnap({}) end)
  end)
end)
