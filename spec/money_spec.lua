local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Money.lua")
local Money = ns.Money

describe("Money", function()
  it("splits copper into gold, silver and copper", function()
    assert.same({ 12, 3, 4 }, { Money.split(120304) })
  end)

  it("formats amounts and drops leading zero parts", function()
    assert.equal("12g 3s 4c", Money.format(120304))
    assert.equal("5s 0c", Money.format(500))
    assert.equal("7c", Money.format(7))
    assert.equal("0c", Money.format(0))
    assert.equal("1g 0s 0c", Money.format(10000))
  end)
end)
