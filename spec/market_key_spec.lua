local helper = require("spec.helper")

describe("MarketKey", function()
  local MarketKey = helper.load("BetterAH/Core/MarketKey.lua").MarketKey

  it("round-trips realm, ruleset and faction", function()
    local key = MarketKey.build({ realm = "Firemaw", ruleset = "1", faction = "Horde" })
    assert.same({ realm = "Firemaw", ruleset = "1", faction = "Horde" }, MarketKey.parse(key))
  end)

  it("allows an empty realm, as Forever reports one", function()
    local key = MarketKey.build({ realm = "", ruleset = "1", faction = "Horde" })
    assert.same({ realm = "", ruleset = "1", faction = "Horde" }, MarketKey.parse(key))
    assert.equal("ruleset 1, Horde", MarketKey.describe(key))
  end)

  it("gives different markets different keys", function()
    local a = MarketKey.build({ realm = "", ruleset = "1", faction = "Horde" })
    assert.are_not.equal(a, MarketKey.build({ realm = "", ruleset = "2", faction = "Horde" }))
    assert.are_not.equal(a, MarketKey.build({ realm = "", ruleset = "1", faction = "Alliance" }))
    assert.are_not.equal(a, MarketKey.build({ realm = "Firemaw", ruleset = "1", faction = "Horde" }))
  end)

  it("needs a ruleset and a faction", function()
    assert.has_error(function() MarketKey.build({ realm = "Firemaw", faction = "Horde" }) end)
    assert.has_error(function() MarketKey.build({ realm = "Firemaw", ruleset = "1" }) end)
  end)

  it("rejects the separator inside a part", function()
    assert.has_error(function() MarketKey.build({ realm = "a|b", ruleset = "1", faction = "Horde" }) end)
  end)

  it("does not parse strings that are not market keys", function()
    assert.is_nil(MarketKey.parse("Firemaw"))
    assert.is_nil(MarketKey.parse(nil))
  end)

  it("describes a market with a realm", function()
    assert.equal("Firemaw, ruleset 1, Horde", MarketKey.describe("Firemaw|1|Horde"))
  end)
end)
