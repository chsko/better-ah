local helper = require("spec.helper")

local function model()
  return helper.load("BetterAH/Core/WindowModel.lua").WindowModel.new()
end

describe("WindowModel", function()
  it("lists the workflows in the sidebar, grouped like prototype B", function()
    local sections = model():sections()
    local flat = {}
    for _, section in ipairs(sections) do
      local ids = {}
      for _, entry in ipairs(section.entries) do ids[#ids + 1] = entry.id end
      flat[#flat + 1] = section.title .. ": " .. table.concat(ids, ",")
    end
    assert.same({
      "Sell: post,cancel",
      "Buy: disenchant,deals,shopping",
      "Make: crafting",
      "Data: prices,alts",
    }, flat)
  end)

  it("gives every entry a readable label", function()
    for _, section in ipairs(model():sections()) do
      for _, entry in ipairs(section.entries) do
        assert.is_string(entry.label)
        assert.is_true(#entry.label > 0)
      end
    end
  end)

  it("starts on the Post view and switches view on select", function()
    local m = model()
    assert.equal("post", m.view)
    assert.is_true(m:select("disenchant"))
    assert.equal("disenchant", m.view)
  end)

  it("ignores an unknown view", function()
    local m = model()
    assert.is_false(m:select("nope"))
    assert.equal("post", m.view)
  end)

  it("shows Better AH when the auction house opens", function()
    local m = model()
    assert.equal("closed", m.mode)
    m:auctionOpened()
    assert.equal("better", m.mode)
  end)

  it("toggles between Better AH and Blizzard's window while open", function()
    local m = model()
    m:auctionOpened()
    m:toggle()
    assert.equal("blizzard", m.mode)
    m:toggle()
    assert.equal("better", m.mode)
  end)

  it("does nothing on toggle while the auction house is closed", function()
    local m = model()
    m:toggle()
    assert.equal("closed", m.mode)
  end)

  it("returns to closed when the auction house closes, and reopens in Better AH", function()
    local m = model()
    m:auctionOpened()
    m:toggle()
    m:auctionClosed()
    assert.equal("closed", m.mode)
    m:auctionOpened()
    assert.equal("better", m.mode)
  end)

  it("keeps the selected view across closing and reopening", function()
    local m = model()
    m:select("crafting")
    m:auctionOpened()
    m:auctionClosed()
    m:auctionOpened()
    assert.equal("crafting", m.view)
  end)
end)
