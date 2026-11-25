local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/WindowModel.lua")
  for _, file in ipairs({ "Money", "Time", "MarketKey", "PriceDB", "SelfTest", "Probes" }) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  ns.prices = ns.PriceDB.new({})
  ns.AuctionAPI.install(env, ns)
  local w = ns.Window.install(env, ns)
  return env, w, ns
end

local function sidebarButton(w, id) return w.buttons[id] end

describe("Window", function()
  it("shows Better AH and conceals Blizzard's window when the auction house opens", function()
    local env, w = setup()
    env.openAuctionHouse()
    assert.is_true(env.BetterAHFrame:IsShown())
    assert.equal("BasicFrameTemplateWithInset", env.BetterAHFrame.template)
    assert.equal(0, env.AuctionFrame.alpha)
    assert.is_false(env.AuctionFrame.mouse)
    assert.is_true(env.AuctionFrame:IsShown(), "Blizzard's window must not be hidden, or the AH closes")
    assert.is_true(env.open)
    assert.equal("Post", w.heading:GetText())
  end)

  it("switches the main view from the sidebar", function()
    local env, w = setup()
    env.openAuctionHouse()
    sidebarButton(w, "disenchant"):Click()
    assert.equal("Disenchant snipe", w.heading:GetText())
    assert.is_true(sidebarButton(w, "disenchant").highlighted)
    assert.is_false(sidebarButton(w, "post").highlighted)
  end)

  it("toggles to Blizzard's window and back without closing the auction house", function()
    local env, w = setup()
    env.openAuctionHouse()
    w.toggleButton:Click()
    assert.is_false(env.BetterAHFrame:IsShown())
    assert.equal(1, env.AuctionFrame.alpha)
    assert.is_true(env.AuctionFrame.mouse)
    assert.is_true(env.open)
    w.returnButton:Click()
    assert.is_true(env.BetterAHFrame:IsShown())
    assert.equal(0, env.AuctionFrame.alpha)
    assert.is_true(env.open)
  end)

  it("closes the auction house when Better AH's close button is pressed", function()
    local env = setup()
    env.openAuctionHouse()
    env.BetterAHFrameCloseButton:Click()
    assert.is_false(env.open)
    assert.is_false(env.BetterAHFrame:IsShown())
    assert.equal(1, env.AuctionFrame.alpha, "Blizzard's window is restored for next time")
  end)

  it("closes the auction house from Blizzard's window too", function()
    local env, w = setup()
    env.openAuctionHouse()
    w.toggleButton:Click()
    env.AuctionFrame:Hide()
    assert.is_false(env.open)
    assert.is_false(env.BetterAHFrame:IsShown())
  end)

  it("hides Better AH and restores Blizzard's window when the auction house closes", function()
    local env = setup()
    env.openAuctionHouse()
    env.closed = 0
    env.CloseAuctionHouse() -- walking away from the auctioneer
    assert.is_false(env.BetterAHFrame:IsShown())
    assert.equal(1, env.AuctionFrame.alpha)
    assert.equal(1, env.AuctionFrame.scale)
    assert.is_true(env.AuctionFrame.mouse)
    assert.is_true(env.closed <= 2, "no close loop")
  end)

  it("closes with Escape like other game windows", function()
    local env = setup()
    env.openAuctionHouse()
    assert.same({ "BetterAHFrame" }, env.UISpecialFrames)
    env.pressEscape()
    assert.is_false(env.open)
    assert.is_false(env.BetterAHFrame:IsShown())
  end)

  it("stays hidden if the auction house closes before the deferred render runs", function()
    local env = setup()
    env.open = true
    env.AuctionFrame:Show()
    env.fire("AUCTION_HOUSE_SHOW")
    env.CloseAuctionHouse()
    env.runTimers()
    assert.is_false(env.BetterAHFrame ~= nil and env.BetterAHFrame:IsShown())
    assert.equal(1, env.AuctionFrame.alpha)
  end)

  it("restores Blizzard's own mouse setting", function()
    local env, w = setup()
    env.AuctionFrame.mouse = false
    env.openAuctionHouse()
    w.toggleButton:Click()
    assert.is_false(env.AuctionFrame.mouse)
  end)

  it("never creates a second window", function()
    local env, w = setup()
    w:build()
    env.openAuctionHouse()
    local count = 0
    for _, f in ipairs(env.frames) do if f.name == "BetterAHFrame" then count = count + 1 end end
    assert.equal(1, count)
    assert.equal(1, #env.UISpecialFrames)
  end)

  it("adds a self-test check that builds the window", function()
    local env, _, ns = setup()
    local results = ns.Probes.suite():run(env, { db = {} })
    local last = results[#results]
    assert.equal("Better AH window", last.name)
    assert.equal("pass", last.status)
    assert.equal("window created with 8 sidebar entries; close button BetterAHFrameCloseButton; inset InsetBg",
      last.detail)
  end)

  it("passes the window check with the modern template shape", function()
    local env, _, ns = setup({ template = "modern" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("pass", last.status)
    assert.equal("window created with 8 sidebar entries; close button CloseButton; inset Inset", last.detail)
  end)

  it("finds the inset by its global name when it has no parent key", function()
    local env, _, ns = setup({ template = "named" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("pass", last.status)
    assert.equal("window created with 8 sidebar entries; close button BetterAHFrameCloseButton; "
      .. "inset BetterAHFrameInsetBg",
      last.detail)
  end)

  it("ignores a global with the close button's name that belongs to another frame", function()
    local env, _, ns = setup({ template = "bare" })
    env.BetterAHFrameCloseButton = env.CreateFrame("Button", nil, env.UIParent)
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("fail", last.status)
  end)

  it("closes the window from the modern template's close button", function()
    local env = setup({ template = "modern" })
    env.openAuctionHouse()
    env.BetterAHFrame.CloseButton:Click()
    assert.is_false(env.BetterAHFrame:IsShown())
  end)

  it("fails the window check when the window has no close button", function()
    local env, _, ns = setup({ template = "bare" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("fail", last.status)
    assert.equal("window has no close button (looked for CloseButton and BetterAHFrameCloseButton); inset none",
      last.detail)
  end)

  describe("Prices and history", function()
    local function rowText(w, r)
      local out = {}
      for c, cell in ipairs(w.rows[r]) do out[c] = cell:GetText() end
      return out
    end

    it("asks for a first scan on a market never scanned", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      assert.is_true(w.pricesPanel:IsShown())
      assert.is_false(w.placeholder:IsShown())
      assert.equal("No scan of this market yet. Press Scan to record its prices.", w.scanStatus:GetText())
    end)

    it("scans from the Scan button and lists items with lowest buyout, quantity and seen time", function()
      local env, w = setup()
      env.auctions = {
        { name = "Wool Cloth", count = 10, buyout = 30500, itemID = 2592 },
        { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 },
      }
      env.openAuctionHouse()
      w:select("prices")
      w.scanButton:Click()
      assert.equal("Scanning the auction house. This can take a minute or two.", w.scanStatus:GetText())
      assert.is_false(w.scanButton:IsEnabled())
      env.runTimers()
      assert.equal("Scanned 2 listings of 2 items in 0 seconds.", w.scanStatus:GetText())
      assert.is_true(w.scanButton:IsEnabled())
      assert.same({ "Linen Cloth", "2s 0c", "20", "just now" }, rowText(w, 1))
      assert.same({ "Wool Cloth", "30s 50c", "10", "just now" }, rowText(w, 2))
      assert.same({ "", "", "", "" }, rowText(w, 3))
    end)

    it("shows the result when the auction house replies before the scan call returns", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      local replicate = env.C_AuctionHouse.ReplicateItems
      env.C_AuctionHouse.ReplicateItems = function()
        replicate()
        env.runTimers()
      end
      w.scanButton:Click()
      assert.equal("Scanned 0 listings of 0 items in 0 seconds.", w.scanStatus:GetText())
    end)

    it("says why a scan can't start", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      env.C_AuctionHouse.ReplicateItems = nil
      w.scanButton:Click()
      assert.equal("This client can't do a full scan (C_AuctionHouse.ReplicateItems is missing).",
        w.scanStatus:GetText())
      assert.is_true(w.scanButton:IsEnabled())
    end)

    it("drops the last scan message when the player is on another market", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      w.scanButton:Click()
      env.runTimers()
      env.C_Map = { GetBestMapForUnit = function() return 1446 end }
      w:renderPrices()
      assert.equal("No scan of this market yet. Press Scan to record its prices.", w.scanStatus:GetText())
    end)

    it("shows only the current market's items", function()
      local env, w, ns = setup()
      ns.prices:recordScan("|1|Alliance", env.now, { { item = "i:1", name = "Elsewhere", count = 1, buyout = 1 } })
      env.openAuctionHouse()
      w:select("prices")
      assert.same({ "", "", "", "" }, rowText(w, 1))
    end)

    it("shows the last scan time when coming back later", function()
      local env, w, ns = setup()
      ns.prices:recordScan("|1|Horde", env.now - 600, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      env.openAuctionHouse()
      w:select("prices")
      assert.equal("1 items. Last scan of ruleset 1, Horde: 10 min ago.", w.scanStatus:GetText())
      assert.same({ "Thing", "1c", "1", "10 min ago" }, rowText(w, 1))
    end)

    it("scrolls through more items than fit", function()
      local env, w, ns = setup()
      local listings = {}
      for i = 1, 20 do
        listings[i] = { item = "i:" .. i, name = string.format("Item %02d", i), count = 1, buyout = i }
      end
      ns.prices:recordScan("|1|Horde", env.now, listings)
      env.openAuctionHouse()
      w:select("prices")
      w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, -1)
      assert.equal("Item 04", rowText(w, 1)[1])
      for _ = 1, 10 do w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, -1) end
      assert.equal("Item 07", rowText(w, 1)[1], "stops at the last full page")
      assert.equal("Item 20", rowText(w, 14)[1])
    end)
  end)
end)
