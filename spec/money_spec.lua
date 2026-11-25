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

  it("reads typed amounts in gold, silver and copper", function()
    assert.equal(120304, Money.parse("12g 3s 4c"))
    assert.equal(300, Money.parse("3s"))
    assert.equal(10500, Money.parse("1G5s"))
    assert.equal(1234, Money.parse(" 1234 "))
    assert.equal(0, Money.parse("0"))
    for _, bad in ipairs({ "", "abc", "5x", "3s 2g", "1.5g", "g", "-5" }) do
      assert.is_nil(Money.parse(bad), bad)
    end
  end)

  it("shortens money to gold and silver once there is gold", function()
    assert.equal("4g 12s", Money.short(41230))
    assert.equal("14s 95c", Money.short(1495))
    assert.equal("0c", Money.short(0))
  end)
end)
