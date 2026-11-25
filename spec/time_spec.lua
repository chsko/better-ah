local helper = require("spec.helper")

describe("Time.ago", function()
  local Time = helper.load("BetterAH/Core/Time.lua").Time

  it("labels how long ago something happened", function()
    assert.equal("never", Time.ago(nil, 10))
    assert.equal("just now", Time.ago(100, 159))
    assert.equal("5 min ago", Time.ago(0, 300))
    assert.equal("2 h ago", Time.ago(0, 7300))
    assert.equal("1 day ago", Time.ago(0, 86400))
    assert.equal("3 days ago", Time.ago(0, 3 * 86400))
    assert.equal("just now", Time.ago(200, 100), "clock skew never shows a negative time")
  end)
end)
