local helper = require("spec.helper")

describe("AutoScan", function()
  local ns = helper.load("BetterAH/Core/Time.lua")
  helper.load("BetterAH/Core/AutoScan.lua", ns)
  local AutoScan = ns.AutoScan
  local now = 100000

  it("scans at once when there is no scan, else 15 minutes after the last", function()
    assert.equal(0, AutoScan.wait(nil, now))
    assert.equal(11 * 60, AutoScan.wait(now - 4 * 60, now))
    assert.equal(0, AutoScan.wait(now - 15 * 60, now))
    assert.equal(0, AutoScan.wait(now - 3600, now))
  end)

  it("tries a failed scan again after 2, then 5, then every 15 minutes", function()
    assert.equal(120, AutoScan.wait(now - 3600, now, 1, now))
    assert.equal(300, AutoScan.wait(now - 3600, now, 2, now))
    assert.equal(900, AutoScan.wait(now - 3600, now, 3, now))
    assert.equal(900, AutoScan.wait(now - 3600, now, 7, now))
    assert.equal(60, AutoScan.wait(nil, now, 1, now - 60))
  end)

  it("says what the scan is doing", function()
    assert.equal("Scanning the auction house...", AutoScan.status({ scanning = true }))
    assert.equal("Scanned 4 min ago. Next scan in 11 min.",
      AutoScan.status({ open = true, lastScan = now - 4 * 60, now = now }))
    assert.equal("Scanned 3 h ago. Open the auction house to scan.",
      AutoScan.status({ open = false, lastScan = now - 3 * 3600, now = now }))
    assert.equal("Not scanned yet. Next scan in a moment.", AutoScan.status({ open = true, now = now }))
    assert.equal("Scan failed: no answer from the auction house. Trying again in 2 min.",
      AutoScan.status({ open = true, now = now, failures = 1, failedAt = now,
        why = "no answer from the auction house" }))
  end)
end)
