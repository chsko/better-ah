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
    assert.equal("Not scanned yet. Next scan when sniping stops.",
      AutoScan.status({ open = true, now = now, held = true }))
    assert.equal("Scanned 4 min ago. Next scan in 11 min.",
      AutoScan.status({ open = true, lastScan = now - 4 * 60, now = now, held = true }), "not due yet: as usual")
    assert.equal("Scan failed: no answer from the auction house. Trying again in 2 min.",
      AutoScan.status({ open = true, now = now, failures = 1, failedAt = now,
        why = "no answer from the auction house" }))
  end)

  it("never asks within 15 minutes of any addon's full scan request (#114)", function()
    assert.equal(14 * 60, AutoScan.wait(now - 3600, now, 0, nil, now - 60), "another addon asked a minute ago")
    assert.equal(15 * 60 - 10, AutoScan.wait(now - 3600, now, 1, now, now - 10), "a retry waits out the window")
    assert.equal(0, AutoScan.wait(now - 3600, now, 0, nil, now - 15 * 60))
    assert.equal(11 * 60, AutoScan.wait(now - 4 * 60, now, 0, nil, now - 5 * 60), "our own interval when longer")
    assert.equal(10 * 60, AutoScan.wait(now - 3600, now, 0, nil, now - 60, now - 5 * 60),
      "15 minutes from the last answer, not from an unanswered request")
    assert.equal(14 * 60, AutoScan.wait(now - 3600, now, 1, now - 60, now - 60, now - 5 * 60),
      "after our own failure, also 15 minutes from the last request")
  end)

  it("says when another addon's scan holds the next one back", function()
    assert.equal("Scanned 1 h ago. Another addon ran a full scan 3 min ago. Next scan in 12 min.",
      AutoScan.status({ open = true, lastScan = now - 3600, now = now, askedAt = now - 3 * 60, askedBy = "other" }))
    assert.equal("Scanned just now. Next scan in 15 min.",
      AutoScan.status({ open = true, lastScan = now, now = now, askedAt = now, askedBy = "us" }))
  end)
end)
