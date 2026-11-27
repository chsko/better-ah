local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/WindowModel.lua")
  helper.load("BetterAH/Core/BrowseFilters.lua", ns)
  helper.load("BetterAH/Core/Browse.lua", ns)
  helper.load("BetterAH/Core/SearchHistory.lua", ns)
  helper.load("BetterAH/Core/Buying.lua", ns)
  local core = { "Money", "Time", "MarketKey", "MarketValue", "Disenchant", "ValueHistory", "Targets", "Sniper",
    "PriceDB", "CharacterRecords", "MatFloors", "EssenceSwap", "Posting", "PostQueue", "SelfTest", "Probes",
    "Purchases", "TooltipPrices", "MyAuctions", "MyBids", "Ledger" }
  for _, file in ipairs(core) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Core/AutoScan.lua", ns)
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  helper.load("BetterAH/Game/PostingAPI.lua", ns)
  helper.load("BetterAH/Game/SnipeAPI.lua", ns)
  helper.load("BetterAH/UI/Loading.lua", ns)
  helper.load("BetterAH/UI/Dropdown.lua", ns)
  helper.load("BetterAH/UI/PostView.lua", ns)
  helper.load("BetterAH/UI/SnipeView.lua", ns)
  helper.load("BetterAH/UI/ValueChart.lua", ns)
  helper.load("BetterAH/UI/DisenchantView.lua", ns)
  helper.load("BetterAH/UI/SettingsView.lua", ns)
  helper.load("BetterAH/Game/BrowseAPI.lua", ns)
  helper.load("BetterAH/UI/BrowseItemView.lua", ns)
  helper.load("BetterAH/UI/BrowseHistory.lua", ns)
  helper.load("BetterAH/UI/BrowseFilterBar.lua", ns)
  helper.load("BetterAH/UI/BrowseView.lua", ns)
  helper.load("BetterAH/Game/MyAuctionsAPI.lua", ns)
  helper.load("BetterAH/UI/MyAuctionsView.lua", ns)
  helper.load("BetterAH/Game/MyBidsAPI.lua", ns)
  helper.load("BetterAH/UI/MyBidsView.lua", ns)
  helper.load("BetterAH/Game/LedgerAPI.lua", ns)
  helper.load("BetterAH/UI/LedgerView.lua", ns)
  helper.load("BetterAH/Core/DetailPane.lua", ns)
  helper.load("BetterAH/UI/Divider.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  ns.prices = ns.PriceDB.new({})
  -- Auto scan (#30) is off unless a spec turns it on, so scans start only where a spec starts one.
  ns.autoScan = false
  ns.characters = ns.CharacterRecords.new({})
  ns.posting = ns.Posting.Settings.new({})
  ns.purchases = ns.Purchases.new({})
  ns.searchHistory = ns.SearchHistory.new({})
  ns.browseSettings = {}
  ns.paneSettings = opts and opts.panes or {}
  ns.bidSettings = {}
  ns.tooltipSettings = {}
  ns.AuctionAPI.install(env, ns)
  ns.PostingAPI.install(env, ns)
  ns.SnipeAPI.install(env, ns)
  ns.BrowseAPI.install(env, ns)
  ns.MyAuctionsAPI.install(env, ns)
  ns.MyBidsAPI.install(env, ns)
  ns.ledger = ns.Ledger.new({})
  ns.LedgerAPI.install(env, ns)
  if opts and opts.tracker then
    helper.load("BetterAH/Game/CharacterTracker.lua", ns)
    ns.CharacterTracker.install(env, ns)
  end
  local w = ns.Window.install(env, ns)
  if opts and opts.debug then
    helper.load("BetterAH/Core/DebugLog.lua", ns)
    helper.load("BetterAH/Game/DebugHooks.lua", ns)
    ns.DebugHooks.install(env, ns)
    ns.DebugHooks.load(env)
  end
  return env, w, ns
end

local function sidebarButton(w, id) return w.buttons[id] end

describe("Window", function()
  it("shows Better AH and conceals Blizzard's window when the auction house opens", function()
    local env, w = setup()
    env.openAuctionHouse()
    assert.is_true(env.BetterAHFrame:IsShown())
    assert.equal("PortraitFrameTemplate", env.BetterAHFrame.template, "the same frame as Blizzard's auction house")
    assert.equal("Better AH", env.BetterAHFrame.title)
    assert.equal("Interface\\Icons\\INV_Misc_Coin_02", env.BetterAHFrame.portrait)
    assert.equal(2, w.textLayer:GetFrameLevel(), "texts draw above the panel art")
    assert.equal("auctionhouse-background-categories", w.sidebarPanel.Background.atlas)
    assert.equal("auctionhouse-background-index", w.mainPanel.Background.atlas)
    assert.equal(0, env.AuctionFrame.alpha)
    assert.is_false(env.AuctionFrame.mouse)
    assert.is_true(env.AuctionFrame:IsShown(), "Blizzard's window must not be hidden, or the AH closes")
    assert.is_true(env.open)
    assert.equal("Post", w.heading:GetText())
  end)

  it("conceals Blizzard's window before it is drawn, not a frame later", function()
    local env = setup()
    env.open = true
    env.AuctionFrame:Show()
    env.fire("AUCTION_HOUSE_SHOW")
    assert.equal(0, env.AuctionFrame.alpha, "concealed in the same frame, before any timer runs")
    env.runTimers()
    assert.is_true(env.BetterAHFrame:IsShown())
  end)

  it("conceals Blizzard's window when it shows before the open event, on later visits", function()
    local env = setup()
    env.openAuctionHouse()
    env.CloseAuctionHouse()
    assert.equal(1, env.AuctionFrame.alpha)
    env.open = true
    env.AuctionFrame:Show()
    assert.equal(0, env.AuctionFrame.alpha, "hidden as it shows, before our handler runs")
    env.fire("AUCTION_HOUSE_SHOW")
    env.runTimers()
    assert.is_true(env.BetterAHFrame:IsShown())
    assert.equal(0, env.AuctionFrame.alpha)
  end)

  it("conceals Blizzard's window when it shows after the open event, on later visits", function()
    local env = setup()
    env.openAuctionHouse()
    env.CloseAuctionHouse()
    assert.equal(1, env.AuctionFrame.alpha)
    env.open = true
    env.fire("AUCTION_HOUSE_SHOW")
    env.AuctionFrame:Show()
    assert.equal(0, env.AuctionFrame.alpha, "hidden as it shows")
    assert.is_false(env.AuctionFrame.mouse)
  end)

  it("leaves Blizzard's window alone when it shows while the player chose it", function()
    local env, w = setup()
    env.openAuctionHouse()
    w.toggleButton:Click()
    assert.equal("blizzard", w.model.mode)
    env.AuctionFrame.scripts.OnShow(env.AuctionFrame)
    assert.equal(1, env.AuctionFrame.alpha)
    assert.is_true(env.AuctionFrame.mouse)
  end)

  it("switches the main view from the sidebar", function()
    local env, w = setup()
    env.openAuctionHouse()
    sidebarButton(w, "disenchant"):Click()
    assert.equal("Disenchant snipe", w.heading:GetText())
    local selected, other = sidebarButton(w, "disenchant"), sidebarButton(w, "post")
    assert.is_true(selected.selectedTexture:IsShown())
    assert.equal("auctionhouse-nav-button-select", selected.selectedTexture.atlas)
    assert.equal("GameFontHighlightSmall", selected:GetFontString().font)
    assert.is_false(other.selectedTexture:IsShown())
    assert.equal("GameFontNormalSmall", other:GetFontString().font)
    sidebarButton(w, "deals"):Click()
    assert.equal("Listings below 70% of market value and your shopping list hits will be listed here.",
      w.placeholder:GetText())
  end)

  it("draws sidebar entries with Blizzard's category list art, not action buttons", function()
    local env, w = setup()
    env.openAuctionHouse()
    local b = sidebarButton(w, "post")
    assert.is_nil(b.template)
    assert.equal("Post", b:GetText())
    local atlases = {}
    for _, t in ipairs(b.textures) do atlases[t.layer] = t.atlas end
    assert.same({ BACKGROUND = "auctionhouse-nav-button", ARTWORK = "auctionhouse-nav-button-select",
      HIGHLIGHT = "auctionhouse-nav-button-highlight" }, atlases)
  end)

  it("describes every placeholder view", function()
    local env, w = setup()
    env.openAuctionHouse()
    for id in pairs(w.buttons) do
      w:select(id)
      if w.placeholder:IsShown() then assert.is_truthy((w.placeholder:GetText() or ""):find("%w"), id) end
    end
  end)

  it("explains both toggle buttons with tooltips", function()
    local env, w = setup()
    local tip = { lines = {} }
    function tip.SetOwner() end
    function tip.SetText(_, t) tip.title = t end
    function tip.AddLine(_, t) tip.lines[#tip.lines + 1] = t end
    function tip.Show() tip.shown = true end
    function tip.Hide() tip.shown = false end
    env.GameTooltip = tip
    env.openAuctionHouse()
    w.toggleButton.scripts.OnEnter(w.toggleButton)
    assert.equal("Blizzard UI", tip.title)
    assert.equal("Switch to Blizzard's auction house window. Use the Better AH button there to come back.",
      tip.lines[1])
    w.toggleButton.scripts.OnLeave(w.toggleButton)
    assert.is_false(tip.shown)
    w.toggleButton:Click()
    w.returnButton.scripts.OnEnter(w.returnButton)
    assert.equal("Better AH", tip.title)
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
    assert.equal("window created with 12 sidebar entries; close button CloseButton; auction house art found",
      last.detail)
  end)

  it("finds the close button by its global name when it has no parent key", function()
    local env, _, ns = setup({ template = "named" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("pass", last.status)
    assert.equal("window created with 12 sidebar entries; close button BetterAHFrameCloseButton; "
      .. "auction house art found", last.detail)
  end)

  it("fails the window check when the client lacks the auction house art", function()
    local env, _, ns = setup({ missingArt = { "auctionhouse-nav-button-select", "auctionhouse-background-index" } })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("fail", last.status)
    assert.equal("auction house art missing from this client: auctionhouse-background-index, "
      .. "auctionhouse-nav-button-select", last.detail)
  end)

  it("says when it can't check the art", function()
    local env, _, ns = setup({ noAtlasInfo = true })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("pass", last.status)
    assert.equal("window created with 12 sidebar entries; close button CloseButton; "
      .. "art not checked (no C_Texture.GetAtlasInfo)", last.detail)
  end)

  it("ignores a global with the close button's name that belongs to another frame", function()
    local env, _, ns = setup({ template = "bare" })
    env.BetterAHFrameCloseButton = env.CreateFrame("Button", nil, env.UIParent)
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("fail", last.status)
  end)

  it("closes the window from the template's close button", function()
    local env = setup()
    env.openAuctionHouse()
    env.BetterAHFrame.CloseButton:Click()
    assert.is_false(env.BetterAHFrame:IsShown())
    assert.is_false(env.open)
  end)

  it("fails the window check when the window has no close button", function()
    local env, _, ns = setup({ template = "bare" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("fail", last.status)
    assert.equal("window has no close button (looked for CloseButton and BetterAHFrameCloseButton)", last.detail)
  end)

  it("gives every list's scroll bar room from the rows and the panel's edge", function()
    local env, w = setup()
    env.openAuctionHouse()
    local lists = { w.rows, w.altsRows, w.postView.rows, w.disenchantView.targetRows }
    -- Lists start 10 px into the main panel, which is 564 px wide: 554 px to its edge. The bar is 8 px.
    for i, rows in ipairs(lists) do
      local bar = rows.scrollBar
      assert.is_not_nil(bar, "list " .. i)
      local x = bar.points.TOPLEFT.x
      assert.is_true(x >= rows.width + 8, "list " .. i .. ": room from the rows")
      assert.is_true(x + 8 <= 554 - 16, "list " .. i .. ": room from the panel's edge")
      local cells = rows[1]
      local lastCell = cells[#cells]
      assert.is_true(lastCell.points.LEFT.x + lastCell.width <= rows.width, "list " .. i .. ": columns fit the rows")
    end
    assert.equal(140, w.disenchantView.targetRows[1][2].width, "target names keep their room")
    assert.is_nil(w.disenchantView.rows.scrollBar, "the band table doesn't scroll")
    assert.equal(540, w.disenchantView.rows.width, "and keeps the full width")
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
      assert.equal("No scan of this market yet. One starts when the auction house is open.", w.scanStatus:GetText())
    end)

    it("scans and lists items with lowest buyout, quantity and seen time", function()
      local env, w = setup()
      env.auctions = {
        { name = "Wool Cloth", count = 10, buyout = 30500, itemID = 2592 },
        { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 },
      }
      env.openAuctionHouse()
      w:select("prices")
      w:startScan()
      assert.equal("Scanning the auction house (a minute or two).", w.scanStatus:GetText())
      local bar, spinner = w.scanLoading.barFrame, w.scanLoading.spinnerFrame
      assert.is_true(spinner:IsShown(), "a spinner: the auction house doesn't say how far along it is")
      assert.is_false(bar:IsShown(), "not a bar that sweeps over and over")
      env.runTimers()
      assert.equal("Scanned 2 listings of 2 items in 0 seconds.", w.scanStatus:GetText())
      assert.is_false(spinner:IsShown())
      assert.is_false(bar:IsShown())
      assert.same({ "Linen Cloth", "2s 0c", "2s 0c", "20", "just now" }, rowText(w, 1))
      assert.same({ "Wool Cloth", "30s 50c", "30s 50c", "10", "just now" }, rowText(w, 2))
      assert.same({ "", "", "", "", "" }, rowText(w, 3))
    end)

    it("scans by itself when the auction house opens and the last scan is old, and says so", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      ns.prices:recordScan("/1/Horde", env.now - 3600, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      local replicate, scans = env.C_AuctionHouse.ReplicateItems, 0
      env.C_AuctionHouse.ReplicateItems = function() scans = scans + 1 return replicate() end
      env.replicateSilent = true
      env.openAuctionHouse()
      assert.equal("Scanned 1 h ago. Next scan in a moment.", w.scanStateText:GetText())
      env.runTimers(2)
      assert.equal(1, scans)
      assert.equal("Scanning the auction house...", w.scanStateText:GetText())
      assert.is_true(w.scanSpinner:IsShown())
      -- Just left of the right-aligned text, not of the whole box.
      local at = w.scanSpinner.points.RIGHT
      assert.equal(w.scanStateText, at.rel)
      assert.equal(-(#"Scanning the auction house..." * 6) - 6, at.x)
      env.replicateSilent = false
      env.fire("REPLICATE_ITEM_LIST_UPDATE")
      env.runTimers(5)
      assert.equal("Scanned just now. Next scan in 15 min.", w.scanStateText:GetText())
      assert.is_false(w.scanSpinner:IsShown())
      assert.equal(-(#"Scanned just now. Next scan in 15 min." * 6) - 6, w.scanSpinner.points.RIGHT.x,
        "moves with the text")
      env.runTimers(14 * 60)
      assert.equal(1, scans, "not before 15 minutes")
      env.runTimers(60)
      assert.equal(2, scans, "again 15 minutes after the last one")
    end)

    it("doesn't scan when the last scan is fresh, and stops when the auction house closes", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      ns.prices:recordScan("/1/Horde", env.now - 4 * 60, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      local replicate, scans = env.C_AuctionHouse.ReplicateItems, 0
      env.C_AuctionHouse.ReplicateItems = function() scans = scans + 1 return replicate() end
      env.openAuctionHouse()
      env.runTimers(5)
      assert.equal(0, scans)
      assert.equal("Scanned 4 min ago. Next scan in 11 min.", w.scanStateText:GetText())
      env.CloseAuctionHouse()
      env.runTimers(20 * 60)
      assert.equal(0, scans, "nothing while the auction house is closed")
      w:renderScanState()
      assert.equal("Scanned 24 min ago. Open the auction house to scan.", w.scanStateText:GetText())
    end)

    it("tries a failed scan again after 2 minutes, then 5", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      local calls = 0
      env.C_AuctionHouse.ReplicateItems = nil
      local get = env.C_AuctionHouse
      setmetatable(get, { __index = function(_, k) if k == "ReplicateItems" then calls = calls + 1 end end })
      env.openAuctionHouse()
      env.runTimers(2)
      assert.equal("Scan failed: this client can't do a full scan (C_AuctionHouse.ReplicateItems is missing). "
        .. "Trying again in 2 min.", w.scanStateText:GetText())
      local before = calls
      env.runTimers(119)
      assert.equal(before, calls)
      env.runTimers(2)
      assert.is_true(calls > before, "tried again")
      assert.matches("Trying again in 5 min.", w.scanStateText:GetText(), 1, true)
    end)

    it("doesn't count closing the auction house mid-scan as a failure, and keeps the title short", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      env.replicateSilent = true
      env.openAuctionHouse()
      env.runTimers(2)
      env.CloseAuctionHouse()
      assert.is_nil(w.scanWhy)
      assert.equal(0, w.scanFailures or 0)
      assert.equal("no reply from the auction house after 120 seconds",
        ns.Window.shortReason("Scan failed. No reply from the auction house after 120 seconds. Full scans may be "
          .. "limited (replicate list: 0 listings before)."))
    end)

    it("shows the result when the auction house replies before the scan call returns", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      local replicate = env.C_AuctionHouse.ReplicateItems
      env.C_AuctionHouse.ReplicateItems = function()
        replicate()
        env.runTimers()
      end
      w:startScan()
      assert.equal("Scanned 1 listings of 1 items in 0 seconds.", w.scanStatus:GetText())
    end)

    it("says why a scan can't start", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      env.C_AuctionHouse.ReplicateItems = nil
      w:startScan()
      assert.equal("This client can't do a full scan (C_AuctionHouse.ReplicateItems is missing).",
        w.scanStatus:GetText())
    end)

    it("drops the last scan message when the player is on another market", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("prices")
      w:startScan()
      env.runTimers()
      env.C_Map = { GetBestMapForUnit = function() return 1446 end }
      w:renderPrices()
      assert.equal("No scan of this market yet. One starts when the auction house is open.", w.scanStatus:GetText())
    end)

    it("shows only the current market's items", function()
      local env, w, ns = setup()
      ns.prices:recordScan("/1/Alliance", env.now, { { item = "i:1", name = "Elsewhere", count = 1, buyout = 1 } })
      env.openAuctionHouse()
      w:select("prices")
      assert.same({ "", "", "", "", "" }, rowText(w, 1))
    end)

    it("shows the last scan time when coming back later", function()
      local env, w, ns = setup()
      ns.prices:recordScan("/1/Horde", env.now - 600, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      env.openAuctionHouse()
      w:select("prices")
      assert.equal("1 items. Last scan of ruleset 1, Horde: 10 min ago.", w.scanStatus:GetText())
      assert.same({ "Thing", "1c", "1c", "1", "10 min ago" }, rowText(w, 1))
    end)

    it("explains the selected item's market value in the detail panel", function()
      local env, w, ns = setup()
      local listings = { { item = "i:1", name = "Troll Target", count = 1, buyout = 1 } }
      for i = 2, 11 do listings[i] = { item = "i:1", name = "Troll Target", count = 10, buyout = 10 * 5000 } end
      ns.prices:recordScan("/1/Horde", env.now - 86400, { { item = "i:1", count = 1, buyout = 3000 } })
      ns.prices:recordScan("/1/Horde", env.now, listings)
      env.openAuctionHouse()
      w:select("prices")
      assert.equal("Select an item to see its market value and how it was worked out.", w.detailBody:GetText())
      w.rows[1].button:Click()
      assert.is_true(w.rows[1].button.selectedTexture:IsShown())
      assert.equal("Troll Target", w.detailTitle:GetText())
      assert.equal(table.concat({
        "Market value: 40s 37c",
        "Lowest buyout: 1c",
        "Quantity listed: 101",
        "",
        "Scan today: the average of the cheapest 30 of 100 listed, leaving out 1 priced far below the rest.",
        "Smoothed over 2 days of the last 14, with recent days counting most.",
        "",
        "Daily value (average of each day's scans and checks)",
        "Today: 50s 0c",
        "Yesterday: 30s 0c",
      }, "\n"), w.detailBody:GetText())
      assert.same({ "Troll Target", "1c", "40s 37c", "101", "just now" }, rowText(w, 1))
    end)

    it("shows a dash for items with no market value and says why in the detail", function()
      local env, w, ns = setup()
      ns.prices:recordScan("/1/Horde", env.now, { { item = "i:9", name = "Bid Only", count = 1, buyout = 0 } })
      env.openAuctionHouse()
      w:select("prices")
      assert.same({ "Bid Only", "bid only", "-", "1", "just now" }, rowText(w, 1))
      w.rows[1].button:Click()
      assert.matches("Market value: none yet", w.detailBody:GetText(), 1, true)
      assert.matches("No buyouts seen in the last 14 days", w.detailBody:GetText(), 1, true)
    end)

    it("clears the detail when the selected item is gone and ignores clicks on empty rows", function()
      local env, w, ns = setup()
      ns.prices:recordScan("/1/Horde", env.now, { { item = "i:1", name = "Thing", count = 1, buyout = 5 } })
      env.openAuctionHouse()
      w:select("prices")
      w.rows[2].button:Click()
      assert.is_nil(w.selected)
      w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, -1)
      w.rows[1].button:Click()
      assert.equal("i:1", w.selected)
      env.C_Map = { GetBestMapForUnit = function() return 1446 end }
      w:renderPrices()
      assert.is_nil(w.selected)
      assert.equal("", w.detailTitle:GetText())
      assert.is_false(w.rows[1].button:IsShown())
      w:select("post")
      assert.equal("", w.detailBody:GetText(), "other views clear the detail panel")
    end)

    it("tells an item scanned before price history existed to be scanned again", function()
      local _, _, ns = setup()
      local text = ns.Window.detailText({ item = "i:1", seen = 1, lowest = 195 }, nil, nil, {}, 1)
      assert.matches("Scanned before Better AH kept price history", text, 1, true)
    end)

    it("shows what a green item disenchants into, and what that's worth here", function()
      local env, w, ns = setup()
      ns.prices:importPrices("/1/Horde", env.now, { ["i:16204"] = { value = 200 }, ["i:16203"] = { value = 1000 } })
      ns.prices:recordScan("/1/Horde", env.now, { { item = "i:15000", name = "Green Robe", count = 1, buyout = 500 } })
      env.GetItemInfo = function(id)
        if id ~= 15000 then return nil end
        return "Green Robe", "link", 2, 58, 53, "Armor", "Cloth", 1, "INVTYPE_ROBE", 0, 100, 4
      end
      env.openAuctionHouse()
      w:select("prices")
      for r = 1, 14 do
        if w.rows[r][1]:GetText() == "Green Robe" then w.rows[r].button:Click() end
      end
      assert.matches(table.concat({
        "Disenchant value: 7s 0c (6s 65c after the 5% auction house cut)",
        "Illusion Dust (75%, 1-2): 3s 0c",
        "Greater Eternal Essence (20%, 1-2): 4s 0c",
        "Large Brilliant Shard (5%, 1): no price",
        "Materials without a price count as nothing. Scan to price them.",
        "Counts an Arcane Salvager (set in Disenchant snipe).",
      }, "\n"), w.detailBody:GetText(), 1, true)
      ns.disenchant = { salvager = false }
      w:renderPrices()
      assert.matches("Disenchant value: 5s 25c (4s 98c after the 5% auction house cut)\n"
        .. "Illusion Dust (75%, 1-2): 2s 25c", w.detailBody:GetText(), 1, true)
      assert.is_nil(w.detailBody:GetText():find("Salvager", 1, true))
      env.GetItemInfo = function() return nil end
      w:renderPrices()
      assert.is_nil(w.detailBody:GetText():find("Disenchant", 1, true), "item details not loaded: no section")
      assert.matches("Market value", w.detailBody:GetText(), 1, true)
    end)

    it("scans only the disenchant materials, without counting as a full scan", function()
      local env, w, ns = setup()
      env.listings[16204] = { { unitPrice = 150, quantity = 20, numOwnerItems = 20 },
        { unitPrice = 200, quantity = 50 }, { unitPrice = 210, quantity = 30 } }
      env.listings[16203] = { { unitPrice = 1000, quantity = 5 } }
      env.openAuctionHouse()
      w:select("prices")
      w.materialsButton:Click()
      assert.is_false(w.materialsButton:IsEnabled(), "one materials scan at a time")
      assert.matches("Scanning materials: 0 of 24.", w.scanStatus:GetText(), 1, true)
      local bar = w.scanLoading.barFrame
      assert.is_true(bar:IsShown())
      assert.same({ 0, 24 }, { bar:GetMinMaxValues() })
      assert.equal(0, bar:GetValue())
      assert.equal(bar, w.scanStatus.points.LEFT.rel, "the status line moves right of the bar")
      env.runTimers()
      assert.equal("Materials: 2 updated, 22 not listed by others.", w.scanStatus:GetText())
      assert.is_false(bar:IsShown())
      assert.equal(w.materialsButton, w.scanStatus.points.LEFT.rel)
      assert.is_true(w.materialsButton:IsEnabled())
      assert.equal(24, #env.searches)
      assert.equal(200, (ns.prices:marketValue("/1/Horde", "i:16204", env.now)), "your own listings don't count")
      assert.equal(1000, (ns.prices:marketValue("/1/Horde", "i:16203", env.now)))
      assert.is_nil(ns.prices:lastScan("/1/Horde"), "not a full scan")
      assert.equal("Illusion Dust", rowText(w, 2)[1])
    end)

    it("won't start a materials scan beside a full scan (#114)", function()
      local env, w = setup()
      env.replicateSilent = true
      env.openAuctionHouse()
      w:select("prices")
      w:startScan()
      w:scanMaterials()
      assert.is_nil(w.materialScan)
      assert.equal(0, #env.searches)
      assert.equal("A full scan is running. Scan materials when it is done.", w.scanStatus:GetText())
    end)

    it("reads another addon's full scan, then waits 15 minutes from it (#114)", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      env.hooksecurefunc = function(t, name, fn)
        local orig = t[name]
        t[name] = function(...) orig(...) fn(...) end
      end
      ns.auctionAPI:hookReplicate()
      ns.prices:recordScan("/1/Horde", env.now - 3600, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      env.openAuctionHouse()
      env.C_AuctionHouse.ReplicateItems() -- another addon, before our auto scan
      local calls = env.replicateCalls
      assert.equal("Scanned 1 h ago. Another addon ran a full scan just now. Next scan in 15 min.",
        w.scanStateText:GetText())
      env.runTimers(5)
      assert.equal(calls, env.replicateCalls, "we didn't ask as well")
      assert.equal(200, (ns.prices:marketValue("/1/Horde", "i:2589", env.now)))
      assert.equal("Scanned just now. Next scan in 15 min.", w.scanStateText:GetText())
      env.runTimers(15 * 60)
      assert.equal(calls + 1, env.replicateCalls, "ours, once the 15 minutes are up")
    end)

    it("doesn't ask while another addon's unanswered request holds the 15 minutes (#114)", function()
      local env, w, ns = setup()
      ns.autoScan = nil
      ns.auctionAPI:useStore({ askedAt = env.now - 60, askedBy = "other" })
      ns.prices:recordScan("/1/Horde", env.now - 3600, { { item = "i:1", name = "Thing", count = 1, buyout = 1 } })
      env.openAuctionHouse()
      env.runTimers(5)
      assert.equal(0, env.replicateCalls, "a reload or a new visit doesn't skip the wait")
      assert.equal("Scanned 1 h ago. Another addon ran a full scan 1 min ago. Next scan in 14 min.",
        w.scanStateText:GetText())
      env.runTimers(14 * 60)
      assert.equal(1, env.replicateCalls)
    end)


    it("takes a material the auction house answers as an item, and retries one with no answer", function()
      local env, w, ns = setup()
      env.listings[16204] = { item = true, level = 5, { buyoutAmount = 200, quantity = 5 } }
      env.listings[11083] = { { unitPrice = 446, quantity = 5 } }
      env.uncached[11083] = true -- not in the item cache: loaded before its search
      env.listings[16203] = { { unitPrice = 1000, quantity = 5 } }
      env.openAuctionHouse()
      w:select("prices")
      local send = env.C_AuctionHouse.SendSearchQuery
      local dropped = false
      env.C_AuctionHouse.SendSearchQuery = function(key, ...)
        if key.itemID == 16203 and not dropped then
          dropped = true -- the first lookup gets no answer
          return
        end
        return send(key, ...)
      end
      w.materialsButton:Click()
      env.runTimers(30)
      assert.equal("Materials: 3 updated, 21 not listed by others.", w.scanStatus:GetText())
      assert.equal(200, (ns.prices:marketValue("/1/Horde", "i:16204", env.now)), "answered as an item")
      assert.equal(446, (ns.prices:marketValue("/1/Horde", "i:11083", env.now)), "searched once its data loaded")
      assert.equal(1000, (ns.prices:marketValue("/1/Horde", "i:16203", env.now)), "answered on the retry")
    end)

    it("says when the auction house closes during a materials scan", function()
      local env, w, ns = setup()
      env.listings[16204] = { { unitPrice = 200, quantity = 50 } }
      env.openAuctionHouse()
      w:select("prices")
      w:scanMaterials()
      env.CloseAuctionHouse()
      assert.is_nil(w.materialScan, "the scan ends")
      assert.matches("24 failed (the auction house closed)", w.scanStatus:GetText(), 1, true)
      assert.is_nil(ns.prices:marketValue("/1/Horde", "i:16204", env.now))
    end)

    it("asks for the auction house before scanning materials", function()
      local env, w, ns = setup()
      env.openAuctionHouse()
      w:select("prices")
      ns.postingAPI.open = false
      w:scanMaterials()
      assert.equal("Open the auction house to scan materials.", w.scanStatus:GetText())
    end)

    it("explains an item known only from imported prices", function()
      local env, w, ns = setup()
      ns.prices:importPrices("/1/Horde", env.now, { ["i:5"] = { value = 777, name = "Imported" } })
      env.openAuctionHouse()
      w:select("prices")
      w.rows[1].button:Click()
      assert.equal(table.concat({
        "Market value: 7s 77c",
        "Lowest buyout: not scanned yet",
        "",
        "Includes imported prices from today.",
        "Smoothed over 1 day of the last 14, with recent days counting most.",
        "",
        "Daily value (average of each day's scans and checks)",
        "Today: 7s 77c",
      }, "\n"), w.detailBody:GetText())
      assert.same({ "Imported", "-", "7s 77c", "-", "never" }, rowText(w, 1))
    end)

    it("scrolls through more items than fit", function()
      local env, w, ns = setup()
      local listings = {}
      for i = 1, 20 do
        listings[i] = { item = "i:" .. i, name = string.format("Item %02d", i), count = 1, buyout = i }
      end
      ns.prices:recordScan("/1/Horde", env.now, listings)
      env.openAuctionHouse()
      w:select("prices")
      w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, -1)
      assert.equal("Item 04", rowText(w, 1)[1])
      for _ = 1, 10 do w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, -1) end
      assert.equal("Item 07", rowText(w, 1)[1], "stops at the last full page")
      assert.equal("Item 20", rowText(w, 14)[1])
      local bar = w.rows.scrollBar
      assert.is_true(bar:IsShown())
      assert.same({ 1, 14 / 20 }, { bar:GetScrollPercentage(), bar:GetVisibleExtentPercentage() },
        "the wheel moves the scroll bar too")
      bar:drag(0.5)
      assert.equal("Item 04", rowText(w, 1)[1], "dragging halfway shows the middle page")
      assert.equal(0.5, bar:GetScrollPercentage(), "the thumb stays where it was dragged")
      w.pricesPanel.scripts.OnMouseWheel(w.pricesPanel, 1)
      assert.equal("Item 01", rowText(w, 1)[1])
      assert.equal(0, bar:GetScrollPercentage())
      bar:drag(0.95)
      assert.equal("Item 07", rowText(w, 1)[1], "near the bottom rounds to the last page")
      bar:wheel(1)
      assert.equal("Item 04", rowText(w, 1)[1], "a wheel notch over the bar moves 3 rows, as over the list")
    end)
  end)

  describe("Alts and inventory", function()
    local function altRow(w, r)
      local out = {}
      for c, cell in ipairs(w.altsRows[r]) do out[c] = cell:GetText() end
      return out
    end

    it("says nothing is recorded before any character has been read", function()
      local env, w = setup()
      env.openAuctionHouse()
      w:select("alts")
      assert.is_true(w.altsPanel:IsShown())
      assert.is_false(w.pricesPanel:IsShown())
      assert.is_false(w.placeholder:IsShown())
      assert.equal("Nothing recorded yet. Your bags are read as you play, your bank when you open it.",
        w.altsStatus:GetText())
      assert.equal("", w.detailBody:GetText())
    end)

    it("lists every item with its total and how many characters have it", function()
      local env, w, ns = setup()
      ns.characters:setCharacter("Thrall-6841", { name = "Thrall" })
      ns.characters:setCharacter("Jaina-6946", { name = "Jaina" })
      ns.characters:setPlace("Thrall-6841", "bags", { { item = "i:2589", count = 25, name = "Linen Cloth" },
        { item = "i:2592", count = 3, name = "Wool Cloth" } }, 1)
      ns.characters:setPlace("Thrall-6841", "bank", { { item = "i:2589", count = 40 } }, 1)
      ns.characters:setPlace("Jaina-6946", "auctions", { { item = "i:2589", count = 10 } }, 1)
      env.openAuctionHouse()
      w:select("alts")
      assert.equal("2 items across 2 characters. Bank not read yet for Jaina: open it once to include it.",
        w.altsStatus:GetText())
      assert.same({ "Linen Cloth", "75", "2" }, altRow(w, 1))
      assert.is_false(w.altsRows.scrollBar:IsShown(), "no scroll bar when everything fits")
      assert.same({ "Wool Cloth", "3", "1" }, altRow(w, 2))
      assert.is_false(w.altsRows[3].button:IsShown())
      assert.equal("Select an item to see which characters have it, and where.", w.detailBody:GetText())

      w.altsRows[1].button:Click()
      assert.is_true(w.altsRows[1].button.selectedTexture:IsShown())
      assert.equal("Linen Cloth", w.detailTitle:GetText())
      assert.equal("Total: 75\n\nJaina: 10 on the auction house\nThrall: 65 (25 in bags, 40 in the bank)",
        w.detailBody:GetText())
    end)

    it("scrolls through more items than fit", function()
      local env, w, ns = setup()
      local items = {}
      for i = 1, 20 do items[i] = { item = "i:" .. i, count = i, name = string.format("Item %02d", i) } end
      ns.characters:setPlace("Me-1", "bags", items, 1)
      env.openAuctionHouse()
      w:select("alts")
      for _ = 1, 10 do w.altsPanel.scripts.OnMouseWheel(w.altsPanel, -1) end
      assert.equal("Item 07", altRow(w, 1)[1], "stops at the last full page")
      assert.is_true(w.altsRows.scrollBar:IsShown())
      assert.equal(1, w.altsRows.scrollBar:GetScrollPercentage())
      w.altsRows.scrollBar:drag(0)
      assert.equal("Item 01", altRow(w, 1)[1], "dragging the bar to the top")
      assert.equal("20 items across 1 character. Bank not read yet for Me-1: open it once to include it.",
        w.altsStatus:GetText())
      ns.characters:setPlace("Me-1", "bank", {}, 2)
      w:renderAlts()
      assert.equal("20 items across 1 character.", w.altsStatus:GetText())
    end)

    it("updates while open when the bags change", function()
      local env, w = setup({ tracker = true })
      env.containers = { [0] = { { itemID = 2589, count = 5, name = "Linen Cloth" } } }
      env.openAuctionHouse()
      w:select("alts")
      env.fire("BAG_UPDATE_DELAYED")
      assert.same({ "Linen Cloth", "5", "1" }, altRow(w, 1))
    end)
  end)

  describe("Disenchant", function()
    local function band(w, r)
      local out = {}
      for c, cell in ipairs(w.disenchantView.rows[r]) do out[c] = cell:GetText() end
      return out
    end
    -- Christian's prices from his spreadsheet: Soul Dust, Greater Astral Essence, Large Glimmering Shard.
    local function deSetup()
      local env, w, ns = setup()
      ns.prices:importPrices("/1/Horde", env.now, { ["i:11083"] = { value = 446 }, ["i:11082"] = { value = 1568 },
        ["i:11084"] = { value = 3978 } })
      env.openAuctionHouse()
      w:select("disenchant")
      return env, w, ns
    end

    it("lists every green band with what one is worth after the auction house cut", function()
      local env, w, ns = deSetup()
      assert.is_true(w.disenchantPanel:IsShown())
      assert.is_false(w.placeholder:IsShown())
      assert.is_false(w.pricesPanel:IsShown())
      assert.same({ "5-15", "1-10", "-", "-", "0 of 2 priced" }, band(w, 1))
      local cells = band(w, 4)
      assert.same({ "26-30", "21-25", "14s 20c", "3 of 4 priced" }, { cells[1], cells[2], cells[3], cells[5] })
      ns.prices:recordScan("/1/Horde", env.now, { { item = "i:10940", name = "Strange Dust", count = 5, buyout = 500 },
        { item = "i:10939", name = "Greater Magic Essence", count = 5, buyout = 5000 },
        { item = "i:10998", name = "Lesser Astral Essence", count = 5, buyout = 2000 },
        { item = "i:10978", name = "Small Glimmering Shard", count = 5, buyout = 2500 } }, true)
      w.disenchantView:render()
      assert.equal("today", band(w, 3)[5], "how old the oldest material price is")
      assert.matches("^%d+s %d+c %*$", cells[4], "weapons miss Greater Magic Essence: marked as too low")
      assert.equal("61+", band(w, 11)[1])
      assert.equal("56+", band(w, 11)[2])
      assert.is_false(w.disenchantView.rows[12].button:IsShown())
      assert.equal("Prices from ruleset 1, Horde.", w.disenchantView.status:GetText())
    end)

    it("counts the Arcane Salvager unless it is turned off, and remembers the choice", function()
      local _, w, ns = deSetup()
      local box = w.disenchantView.salvagerButton
      assert.is_true(box:GetChecked(), "on by default")
      box:Click()
      assert.is_false(box:GetChecked())
      assert.is_false(ns.disenchant.salvager, "saved")
      assert.equal("11s 12c", band(w, 4)[3])
      box:Click()
      assert.is_true(ns.disenchant.salvager)
      assert.equal("14s 20c", band(w, 4)[3])
    end)

    it("explains a band's materials in the detail panel", function()
      local _, w, ns = deSetup()
      assert.equal("Select a band to see what each material adds.", w.detailBody:GetText())
      w.disenchantView.rows[4].button:Click()
      assert.is_true(w.disenchantView.rows[4].button.selectedTexture:IsShown())
      assert.equal("Greens of item level 26-30", w.detailTitle:GetText())
      local v = w.disenchantView
      assert.is_true(v.bandDetail:IsShown())
      assert.equal("Usually required level 21-25", v.bandRequired:GetText())
      local armor, weapon = v.classBoxes.armor, v.classBoxes.weapon
      assert.equal("14s 20c", armor.value:GetText(), "after the cut, big")
      assert.equal("14s 95c\nbefore the cut", armor.before:GetText())
      assert.matches("^%d+s %d+c%*$", weapon.value:GetText(), "a material without a price")
      assert.is_true(armor.selected)
      assert.equal("What armor gives", v.materialsTitle:GetText())
      local line = v.materialLines[1]
      assert.equal("Lg. Glimmering Shard", v.materialLines[3][1]:GetText(), "shortened to fit")
      assert.equal("Large Glimmering Shard", v.materialLines[3].name)
      assert.same({ "Soul Dust", "75%", "1-2", "6s 69c" },
        { line[1]:GetText(), line[2]:GetText(), line[3]:GetText(), line[4]:GetText() })
      assert.is_true(line.share > 0.4 and line.share < 0.5, "Soul Dust is under half of 14s 95c")
      assert.is_true(v.materialLines[3].track:IsShown())
      assert.equal(3, #v.materialLines, "a green gives at most three materials")
      assert.equal(math.floor(276 * line.share + 0.5), line.fill:GetWidth(), "the bar shows the share")
      assert.equal("", v.materialsNote:GetText())
      assert.equal("Counts the Arcane Salvager's 50% chance of one extra dust or essence.", v.salvagerNote:GetText())
      assert.equal("", w.detailBody:GetText())
      weapon:Click()
      assert.is_true(weapon.selected)
      assert.equal("What weapons give", v.materialsTitle:GetText())
      assert.equal("none", v.materialLines[2][4]:GetText(), "Greater Magic Essence has no price")
      assert.matches("has no price yet", v.materialsNote:GetText(), 1, true)
      assert.equal("Greater Magic Ess.", v.materialLines[2][1]:GetText(), "short enough for its column")
      v.tabButtons.snipe:Click()
      assert.is_false(v.bandDetail:IsShown())
      assert.is_false(v.salvagerNote:IsShown())
      v.tabButtons.values:Click()
      assert.is_true(weapon.selected, "the class stays chosen")
      w:select("prices")
      assert.is_false(v.bandDetail:IsShown())
      w:select("disenchant")
      assert.equal("Greens of item level 26-30", w.detailTitle:GetText(), "the selection stays")
      v.makeButton:Click()
      v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
      assert.same({ onehand = true, twohand = true, ranged = true }, ns.disenchant.targets[1].types,
        "a target for the weapons shown")
    end)

    it("redraws when a full scan finishes, and keeps the detail panel its own", function()
      local env, w = setup()
      env.auctions = { { name = "Soul Dust", count = 10, buyout = 5000, itemID = 11083 } }
      env.openAuctionHouse()
      w:select("prices")
      w:startScan()
      w:select("disenchant")
      assert.is_false(w.disenchantView.materialsButton:IsEnabled(), "no materials scan during a full scan")
      w.disenchantView.rows[4].button:Click()
      env.runTimers()
      assert.is_true(w.disenchantView.materialsButton:IsEnabled())
      assert.equal("Greens of item level 26-30", w.detailTitle:GetText())
      assert.matches("^%d+s %d+c %*$", band(w, 4)[3], "the scanned Soul Dust counts")
    end)

    it("drops the materials scan message once a full scan starts", function()
      local env, w = deSetup()
      w.disenchantView.materialsButton:Click()
      env.runTimers()
      assert.matches("Materials: ", w.disenchantView.status:GetText(), 1, true)
      env.auctions = { { name = "Linen Cloth", count = 20, buyout = 4000, itemID = 2589 } }
      w:startScan()
      env.runTimers()
      assert.equal("Full scan just now.", w.disenchantView.status:GetText())
    end)

    local function typeIn(box, text)
      box:SetFocus()
      box:SetText(text)
      box.scripts.OnEnterPressed(box)
    end

    local function target(w, r)
      local out = {}
      for c, cell in ipairs(w.disenchantView.targetRows[r]) do out[c] = cell:GetText() end
      return out
    end

    it("opens on Values, with Targets and Snipe beside it", function()
      local _, w = deSetup()
      local v = w.disenchantView
      assert.is_true(v.valuesPanel:IsShown())
      assert.is_false(v.targetsPanel:IsShown())
      assert.is_true(v.tabButtons.values.selectedTexture:IsShown())
      assert.is_true(v.tabButtons.snipe:IsEnabled())
      v.tabButtons.targets:Click()
      assert.is_true(v.targetsPanel:IsShown())
      assert.is_false(v.valuesPanel:IsShown())
      assert.is_true(v.targetsEmpty:IsShown())
      assert.is_false(v.targetRows[1].button:IsShown())
      assert.is_true(v.salvagerButton:IsShown(), "the Salvager counts on every tab")
    end)

    it("adds a target and shows its max price from the band's worth", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      v.newButton:Click()
      assert.same({ "", "Armor, req. 21-25", "Armor", "14s 20c", "10%", "12s 78c" }, target(w, 1))
      assert.is_false(v.targetRows[1].check:GetChecked(), "a new target starts unticked (#206)")
      assert.equal(1, #ns.disenchant.targets, "saved")
      assert.is_true(v.editor:IsShown())
      assert.equal("Armor, req. 21-25", w.detailTitle:GetText())
      assert.equal("12s 78c", v.maxText:GetText())
      assert.equal("Worth 14s 20c after the cut", v.worthText:GetText())
      v.targetRows[1].check:Click()
      assert.is_true(ns.disenchant.targets[1].enabled, "ticked: sniped")
      v.targetRows[1].check:Click()
      assert.is_false(ns.disenchant.targets[1].enabled, "kept but not sniped")
    end)

    it("prices a target's materials at the latest scan's cheapest when it is under market value (#250)", function()
      local env, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      v.newButton:Click()
      assert.equal("14s 20c", target(w, 1)[4], "market value alone before a scan lists the dust cheaper")
      -- One Soul Dust listed at 1s: under its market value, which the rest of the listings keep near 4s 46c.
      local listings = { { item = "i:11083", name = "Soul Dust", count = 1, buyout = 100 } }
      for _ = 1, 9 do listings[#listings + 1] = { item = "i:11083", name = "Soul Dust", count = 1, buyout = 446 } end
      ns.prices:recordScan("/1/Horde", env.now, listings, true)
      v:render()
      assert.same({ "Armor, req. 21-25", "Armor", "9s 27c", "10%", "8s 34c" },
        { target(w, 1)[2], target(w, 1)[3], target(w, 1)[4], target(w, 1)[5], target(w, 1)[6] })
      assert.equal("Worth 9s 27c after the cut", v.worthText:GetText())
      v.tabButtons.values:Click()
      assert.equal("13s 39c", band(w, 4)[3], "Values keeps market value")
    end)

    it("edits a target's types, band and profit", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      v.newButton:Click()
      v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
      v.typeBoxes.plate:Click()
      v.typeBoxes.mail:Click()
      assert.equal("Cloth, Leather, req. 21-25", target(w, 1)[2])
      v.goldButton:Click()
      assert.same({ kind = "gold", amount = 142 }, ns.disenchant.targets[1].profit, "the max price stays put")
      typeIn(v.profitInput, "3s")
      assert.equal("11s 20c", v.maxText:GetText())
      assert.equal("3s 0c", target(w, 1)[5])
      typeIn(v.profitInput, "lots")
      assert.equal("Type an amount like 3s or 1g 5s.", v.editorStatus:GetText())
      v.percentButton:Click()
      assert.same({ kind = "percent", amount = 21 }, ns.disenchant.targets[1].profit)
      typeIn(v.profitInput, "150")
      assert.equal("Type a percent from 0 to 99, like 20.", v.editorStatus:GetText())
      local bands = fake.menuLabels(v.bandDrop)
      local at
      for i, label in ipairs(bands) do if label == v.bandDrop:GetText() then at = i end end
      assert.equal("Req. 21-25, ilvl 26-30", bands[at])
      v.bandDrop:Click()
      fake.pick(v.bandDrop, bands[at + 1])
      assert.equal(31, ns.disenchant.targets[1].band)
      assert.equal(bands[at + 1], v.bandDrop:GetText())
      assert.equal("Cloth, Leather, req. 26-30", w.detailTitle:GetText())
      assert.matches("%*$", target(w, 1)[4], "only Soul Dust is priced for that band")
      assert.equal("A material has no price yet, so this is too low. Scan materials on Values.",
        v.editorStatus:GetText())
      v.deleteButton:Click()
      assert.equal(0, #ns.disenchant.targets)
      assert.is_false(v.editor:IsShown())
    end)

    it("saves what was typed to the target it was typed for, and drops it on Escape", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      v.newButton:Click()
      v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
      v.newButton:Click()
      v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
      v.selectTarget(v, 1)
      v.profitInput:SetFocus()
      v.profitInput:SetText("30")
      v.render(v) -- a materials scan step while typing
      assert.equal("30", v.profitInput:GetText(), "the box keeps what is being typed")
      v.targetRows[2].button:Click()
      v.profitInput:ClearFocus() -- the click takes the focus
      assert.same({ kind = "percent", amount = 30 }, ns.disenchant.targets[1].profit)
      assert.same({ kind = "percent", amount = 10 }, ns.disenchant.targets[2].profit)
      v.profitInput:SetFocus()
      v.profitInput:SetText("50")
      v.profitInput.scripts.OnEscapePressed(v.profitInput)
      assert.same({ kind = "percent", amount = 10 }, ns.disenchant.targets[2].profit, "Escape drops it")
      assert.equal("10", v.profitInput:GetText())
    end)

    it("scrolls through more targets than fit", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      for _ = 1, 16 do v.newButton:Click() end
      assert.is_true(v.targetRows.scrollBar:IsShown())
      assert.equal(13, #v.targetRows, "a row fewer, to clear Start sniping (#212)")
      v.targetRows.scrollBar:drag(1)
      assert.equal(3, v.targetOffset)
      v.targetRows[13].button:Click()
      assert.equal(16, v.target)
      v.targetRows[13].check:Click()
      assert.is_true(ns.disenchant.targets[16].enabled)
      v.deleteButton:Click()
      assert.equal(15, #ns.disenchant.targets)
    end)

    it("makes a target from a band on Values", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      assert.is_false(v.makeButton:IsShown())
      v.rows[3].button:Click()
      assert.is_true(v.makeButton:IsShown())
      v.makeButton:Click()
      v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
      assert.equal("targets", v.tab)
      assert.equal(21, ns.disenchant.targets[1].band)
      assert.equal("Armor, req. 16-20", w.detailTitle:GetText())
      w:select("prices")
      assert.is_false(v.editor:IsShown(), "no editor over other views")
      assert.is_false(v.makeButton:IsShown())
      assert.is_false(v.bandDetail:IsShown())
    end)

    it("scans materials from the view and shows the new values", function()
      local env, w = deSetup()
      env.listings[11083] = { { unitPrice = 500, quantity = 50 } }
      w.disenchantView.materialsButton:Click()
      assert.is_false(w.disenchantView.materialsButton:IsEnabled())
      assert.equal("Scanning materials: 0 of 24.", w.disenchantView.status:GetText())
      assert.is_true(w.disenchantView.loading.barFrame:IsShown())
      env.runTimers()
      assert.is_false(w.disenchantView.loading.barFrame:IsShown())
      assert.equal("Materials scan just now.", w.disenchantView.status:GetText(), "a clean result is one short line")
      assert.is_true(w.disenchantView.materialsButton:IsEnabled())
      assert.are_not.equal("14s 20c", band(w, 4)[3], "the new Soul Dust price counts")
    end)

    it("a full scan updates the values and the status line names it (#143)", function()
      local env, w, ns = deSetup()
      local v = w.disenchantView
      env.auctions = { { name = "Soul Dust", count = 50, buyout = 25000, itemID = 11083 } }
      w:startScan()
      env.runTimers()
      assert.equal(1, #ns.disenchant.snapshots["/1/Horde"])
      assert.equal("full", ns.disenchant.snapshots["/1/Horde"][1].kind)
      w:select("disenchant")
      assert.equal("Full scan just now.", v.status:GetText())
      v.materialsButton:Click()
      env.runTimers()
      assert.equal("Materials: 0 updated, 24 not listed by others. Full scan just now.",
        v.status:GetText(), "a materials scan that found nothing leaves the full scan's prices")
      env.now = env.now + 2 * 3600
      w.addon.auctionAPI.store.answeredAt = nil
      w:startScan()
      env.auctions[2] = { name = "Soul Dust", count = 10, buyout = 6000, itemID = 11083 } -- a fresh list
      env.runTimers()
      w:select("disenchant")
      assert.equal("Full scan just now. Changes since 2 h ago.", v.status:GetText())
    end)

    it("marks what the last scan changed in green or red (#106)", function()
      local env, w, ns = deSetup()
      local v = w.disenchantView
      env.listings[11083] = { { unitPrice = 500, quantity = 50 } }
      v.materialsButton:Click()
      env.runTimers()
      assert.is_nil(band(w, 4)[3]:find("|c", 1, true), "nothing to compare the first scan with")
      assert.is_nil(v.status:GetText():find("Changes since", 1, true))
      env.listings[11083] = { { unitPrice = 900, quantity = 50 } }
      v.materialsButton:Click()
      env.runTimers()
      assert.equal(2, #ns.disenchant.snapshots["/1/Horde"])
      assert.matches("|cff1eff00+", band(w, 4)[3], 1, true)
      assert.equal("Materials scan just now. Changes since a moment ago.", v.status:GetText())
      w.materialStatus, w.materialQuiet = "Materials: 23 updated, 0 not listed by others, 1 failed (x).", false
      v:render()
      assert.equal("Materials: 23 updated, 0 not listed by others, 1 failed (x). Changes since a moment ago.",
        v.status:GetText(), "a failure stays, without naming the materials scan twice")
      w.materialStatus = w.MATERIALS_WAIT
      v:render()
      assert.equal(w.MATERIALS_WAIT, v.status:GetText(), "the wait message stands alone")
      w.materialStatus, w.materialQuiet = nil, true
      v.rows[4].button:Click()
      assert.matches("^|cff1eff00%+", v.classBoxes.armor.change:GetText())
      assert.matches("^|cff1eff00%+", v.materialLines[1][5]:GetText(), "Soul Dust went up")
      assert.equal("same", v.materialLines[2][5]:GetText(), "Greater Astral Essence didn't move")
      env.listings[11083] = { { unitPrice = 100, quantity = 50 } }
      v.materialsButton:Click()
      assert.equal("Scanning materials: 0 of 24.", v.status:GetText(), "a running scan stands alone")
      env.runTimers()
      assert.matches("^|cffff4a3a%-", v.materialLines[1][5]:GetText(), "and down again, in red")
    end)

    it("charts the chosen class's daily value with a trend line (#106)", function()
      local env, w, ns = deSetup()
      local v = w.disenchantView
      v.rows[4].button:Click()
      assert.equal(1, #v.chartSeries)
      assert.equal("One day of prices so far: no trend yet.", v.trendText:GetText())
      assert.equal("Armor: daily value", v.chartTitle:GetText())
      ns.prices:importPrices("/1/Horde", env.now - 2 * 86400, { ["i:11083"] = { value = 300 },
        ["i:11082"] = { value = 1200 }, ["i:11084"] = { value = 3000 } })
      v:render()
      assert.equal(3, #v.chartSeries, "yesterday carries the day before's prices")
      assert.matches("^Trend |cff1eff00%+.* over 2 days$", v.trendText:GetText(), "the days it covers")
      local shown = 0
      for _, dot in ipairs(v.chart.pools.dot) do if dot:IsShown() then shown = shown + 1 end end
      assert.is_true(shown > 2, "drawn as dots without CreateLine")
      v.chartButtons[7]:Click()
      assert.equal(7, ns.disenchant.chartDays)
      assert.equal(3, #v.chartSeries, "all within a week")
      v.classBoxes.weapon:Click()
      assert.equal("Weapons: daily value", v.chartTitle:GetText())
    end)

    describe("Snipe", function()
      -- An Armor target for 26-30 (worth 14s 20c, 10% profit: max 12s 78c), and one cheap bracer on the
      -- auction house among results that aren't buys.
      local function snipeSetup()
        local env, w, ns = deSetup()
        local v = w.disenchantView
        v.tabButtons.targets:Click()
        v.newButton:Click()
        v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
        env.browseResults = {
          { itemKey = { itemID = 5001, itemLevel = 28 }, minPrice = 900, totalQuantity = 2 },
          { itemKey = { itemID = 5002, itemLevel = 28 }, minPrice = 5000, totalQuantity = 1 },
          { itemKey = { itemID = 5003, itemLevel = 35 }, minPrice = 100, totalQuantity = 1 },
        }
        env.listings[5001] = { item = true, level = 28,
          { buyoutAmount = 900, auctionID = 77, itemLink = "[Ridgeback Bracers]" },
          { buyoutAmount = 1200, auctionID = 78, itemLink = "[Ridgeback Bracers]" },
          { buyoutAmount = 1300, auctionID = 79, itemLink = "[Ridgeback Bracers]" } }
        -- Item details: two leather pieces. Others aren't loaded.
        local names = { [5001] = "Ridgeback Bracers", [5002] = "Ridgeback Boots", [5003] = "Ridgeback Belt" }
        env.GetItemInfo = function(id)
          if not names[id] or env.uncached[id] then return nil end
          return names[id], "link", 2, id == 5003 and 35 or 28, 23, "Armor", "Leather", 1, "INVTYPE_WRIST", 0, 100, 4, 2
        end
        v.tabButtons.snipe:Click()
        return env, w, ns, v.snipe
      end

      it("starts from Targets and lists the buys it finds, most profit first", function()
        local env, w, ns = snipeSetup()
        local v = w.disenchantView
        v.tabButtons.targets:Click()
        assert.equal("Start sniping 1 target", v.startButton:GetText())
        v.startButton:Click()
        local s = v.snipe
        assert.is_true(v.snipePanel:IsShown())
        assert.is_true(s.running)
        assert.equal(21, env.browses[1].minLevel)
        assert.equal(25, env.browses[1].maxLevel)
        env.runTimers()
        assert.equal(1, #env.searches, "only the cheap bracer in the band is looked up")
        assert.equal("[Ridgeback Bracers]", s.cardName:GetText())
        assert.equal("Next buy: Armor, req. 21-25  ·  1 at this price", s.cardLabel:GetText())
        assert.equal("Buy for 9s 0c", s.buyButton:GetText())
        assert.equal("+5s 20c", s.cols[3].value:GetText())
        local function near(i)
          local row = s.nearRows[i]
          return { row[1]:GetText(), row[2]:GetText(), row[3]:GetText(), row[4]:GetText(), row[5]:GetText() }
        end
        assert.same({ "Ridgeback Bracers", "Armor, req. 21-25", "9s 0c", "12s 78c", "|cff1eff003s 78c under|r" },
          near(1), "the cheapest bracer, under the max")
        assert.is_true(s.nearRows[1].bg:IsShown(), "buyable: tinted")
        assert.equal("2", s.nearRows[1][6]:GetText(), "how many are listed")
        assert.same({ "Ridgeback Boots", "Armor, req. 21-25", "50s 0c", "12s 78c", "|cffff9d3a37s 22c over|r" },
          near(2), "over the max, and by how much")
        assert.is_false(s.nearRows[2].bg:IsShown())
        assert.equal("", near(3)[1], "the item level 35 result is out of the band")
        assert.equal(1, #env.sounds)
        assert.matches("^Sniping 1 target", s.status:GetText())
        assert.equal("This session", w.detailTitle:GetText())
        assert.is_true(s.settingsBox:IsShown())
        assert.is_not_nil(ns.disenchant.session, "the session is saved")
      end)

      it("buys with the button or a mouse wheel turn and counts the spend", function()
        local env, _, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        s.buyButton:Click()
        assert.equal("Buying...", s.buyButton:GetText())
        assert.is_false(s.buyButton:IsEnabled())
        env.runTimers()
        assert.same({ auctionID = 77, amount = 900 }, env.bids[1])
        assert.equal("Spent this session: 9s 0c", s.spentText:GetText())
        assert.matches("Bought %[Ridgeback Bracers%] for 9s 0c", s.logText:GetText())
        assert.equal("Buy for 12s 0c", s.buyButton:GetText())
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        env.runTimers()
        assert.same({ auctionID = 78, amount = 1200 }, env.bids[2])
        assert.equal("Spent this session: 21s 0c", s.spentText:GetText())
        assert.equal("2 bought, worth 28s 40c disenchanted: +7s 40c expected profit", s.summary:GetText())
        assert.equal(2100, ns.disenchant.session.spent)
        env.runTimers(1)
        assert.equal(2, #env.browses, "the next round starts after a rest")
        assert.equal("Nothing under your max prices yet", s.cardName:GetText(), "bought auctions don't come back")
      end)

      it("sends PlaceBid before redrawing, from the button and the wheel (#130)", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        local placeBid, seen = env.C_AuctionHouse.PlaceBid, {}
        env.C_AuctionHouse.PlaceBid = function(...)
          seen[#seen + 1] = { text = s.buyButton:GetText(), enabled = s.buyButton:IsEnabled() }
          return placeBid(...)
        end
        s.buyButton:Click()
        assert.same({ text = "Buy for 9s 0c", enabled = true }, seen[1], "the view is not redrawn before the call")
        assert.equal("Buying...", s.buyButton:GetText(), "redrawn after it")
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        assert.equal(1, #seen, "a second notch while the buy is in flight doesn't buy again")
        env.runTimers()
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        assert.same({ text = "Buy for 12s 0c", enabled = true }, seen[2])
        assert.equal("Buying...", s.buyButton:GetText())
      end)

      it("keeps a find the game blocks inside PlaceBid, and the next notch tries it again (#130)", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        local placeBid = env.C_AuctionHouse.PlaceBid
        env.C_AuctionHouse.PlaceBid = function() env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "PlaceBid()") end
        s.buyButton:Click()
        assert.matches("Not bought %[Ridgeback Bracers%]: the game blocked PlaceBid%(%) from the Buy button%. "
          .. "It's still next%.", s.logText:GetText())
        assert.equal("Buy for 9s 0c", s.buyButton:GetText())
        assert.is_true(s.buyButton:IsEnabled())
        env.C_AuctionHouse.PlaceBid = placeBid
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        env.runTimers()
        assert.same({ auctionID = 77, amount = 900 }, env.bids[1], "the same auction, bought")
      end)

      it("drops the rest of a search when one auction is already gone, and looks again (#130)", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.equal(1, #env.searches)
        env.bidFails, env.bidError = true, 4
        s.buyButton:Click()
        env.runTimers()
        assert.equal(1, #env.bids, "the other bracer from the same search isn't tried")
        assert.matches("Missed %[Ridgeback Bracers%]: already gone %(sold to someone else, or taken down%)%. "
          .. "Dropped 1 more from the same search; looking again", s.logText:GetText())
        assert.equal("Nothing under your max prices yet", s.cardName:GetText())
        env.bidFails, env.bidError = false, nil
        env.runTimers(1)
        env.runTimers()
        assert.equal(2, #env.searches, "the item is looked up again on the next check")
        assert.equal("[Ridgeback Bracers]", s.cardName:GetText(), "what is still listed comes back")
        assert.equal("Buy for 12s 0c", s.buyButton:GetText(), "but not the auction that was gone")
      end)

      it("lists the 20 closest in five rows with a scroll bar, and blinks rows that change (#201)", function()
        local env, _, ns, s = snipeSetup()
        local clock = 100
        env.GetTime = function() return clock end
        env.GetItemInfo = function(id)
          return "Piece " .. id, "link", 2, 28, 23, "Armor", "Leather", 1, "INVTYPE_WRIST", 0, 100, 4, 2
        end
        env.browseResults = {}
        for i = 1, 25 do
          env.browseResults[i] = { itemKey = { itemID = 6000 + i, itemLevel = 28 }, minPrice = 1300 + i,
            totalQuantity = 1 }
        end
        s.startButton:Click()
        env.runTimers()
        assert.equal(20, #s.nearList, "the 20 closest are kept")
        assert.equal(5, #s.nearRows, "the list keeps its five-row height")
        assert.equal("Piece 6001", s.nearRows[1][1]:GetText())
        assert.is_true(s.nearBar:IsShown(), "more than fit: the bar shows")
        local barAt = s.nearBar.points.TOPLEFT
        local rowWidth = 540 - ns.SnipeView.NEAR_BAR_ROOM
        assert.equal(rowWidth + ns.SnipeView.NEAR_BAR_GAP, barAt.x, "inside the panel, right of the rows")
        local cols = {}
        for _, col in ipairs(ns.SnipeView.NEAR_COLUMNS) do cols[#cols + 1] = col end
        table.sort(cols, function(x, y) return x[2] < y[2] end)
        for i, col in ipairs(cols) do
          assert.is_true(col[2] + col[3] <= rowWidth, col[1] .. " stays clear of the bar")
          local after = cols[i + 1]
          if after then assert.is_true(col[2] + col[3] <= after[2], col[1] .. " doesn't overlap the next") end
        end
        s.nearBar:drag(1)
        assert.equal(15, s.nearOffset)
        assert.equal("Piece 6016", s.nearRows[1][1]:GetText())
        assert.equal("Piece 6020", s.nearRows[5][1]:GetText())
        s.nearBar:wheel(1)
        assert.equal("Piece 6015", s.nearRows[1][1]:GetText(), "wheeling over the bar scrolls a row")
        for _, row in ipairs(s.nearRows) do assert.is_false(row.flash:IsShown(), "the first list doesn't blink") end
        -- The next check: one listing got cheaper. Only its row blinks, and it scrolls with the list.
        env.browseResults[16].minPrice = 1290
        env.runTimers(2)
        assert.equal(6016, s.nearList[1].itemKey.itemID, "now the closest")
        s:scrollNear(0)
        assert.is_true(s.nearRows[1].flash:IsShown(), "the changed row blinks")
        assert.is_false(s.nearRows[2].flash:IsShown())
        assert.is_true(s.flashDriver:IsShown())
        s:scrollNear(1)
        for _, row in ipairs(s.nearRows) do assert.is_false(row.flash:IsShown(), "the blink goes with its row") end
        s:scrollNear(0)
        assert.is_true(s.nearRows[1].flash:IsShown())
        clock = clock + ns.SnipeView.FLASH / 4
        s.flashDriver.scripts.OnUpdate(s.flashDriver, 0.3)
        assert.is_true(s.nearRows[1].flash:GetAlpha() > 0.3, "at its brightest a quarter in")
        clock = clock + ns.SnipeView.FLASH
        s.flashDriver.scripts.OnUpdate(s.flashDriver, 1)
        assert.is_false(s.nearRows[1].flash:IsShown(), "and gone once it's over")
        assert.is_false(s.flashDriver:IsShown())
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        assert.equal(0, s.nearOffset, "the wheel over the tab buys; it doesn't scroll the list")
      end)

      it("doesn't blink the rows each target brings in on its first check (#201)", function()
        local env, w, _, s = snipeSetup()
        local v = w.disenchantView
        v.tabButtons.targets:Click()
        v.newButton:Click()
        v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
        v.tabButtons.snipe:Click()
        env.GetTime = function() return 100 end
        env.browseResults[1].minPrice = 1300 -- over the max, so no find pauses the checks
        env.browseResults[2].minPrice = 1400
        s.startButton:Click()
        env.runTimers(3)
        assert.is_true(#env.browses >= 2, "both targets checked")
        assert.equal(4, #s.nearList, "the two look-alike targets each list both items")
        assert.same({}, s.flashes, "nothing changed")
        env.browseResults[2].minPrice = 1350
        env.runTimers(3)
        local n = 0
        for _ in pairs(s.flashes) do n = n + 1 end
        assert.equal(2, n, "a later check that moves a price blinks its row, under each target")
      end)

      it("shows what is left from the lookup in the closest list after a buy (#145)", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.equal("9s 0c", s.nearRows[1][3]:GetText(), "the browse's cheapest")
        s.buyButton:Click()
        env.runTimers()
        assert.equal("Ridgeback Bracers", s.nearRows[1][1]:GetText())
        assert.equal("12s 0c", s.nearRows[1][3]:GetText(), "the bought bracer is no longer the cheapest")
        assert.equal("|cff1eff0078c under|r", s.nearRows[1][5]:GetText())
        s.buyButton:Click()
        env.runTimers()
        assert.equal("Nothing under your max prices yet", s.cardName:GetText())
        assert.equal("13s 0c", s.nearRows[1][3]:GetText(), "the one left is over the max")
        assert.equal("|cffff9d3a22c over|r", s.nearRows[1][5]:GetText())
        assert.is_false(s.nearRows[1].bg:IsShown())
        s.session.taken[79] = math.huge
        s:refresh()
        assert.equal("Ridgeback Boots", s.nearRows[1][1]:GetText(), "nothing left of the bracers: their row goes")
      end)

      it("says under New target that ticking or changing a target acts at once while sniping (#206, #212)",
        function()
        local env, w, ns, s = snipeSetup()
        local v = w.disenchantView
        v.tabButtons.targets:Click()
        assert.equal(ns.DisenchantView.TARGETS_HINT, v.targetsHint:GetText())
        assert.is_false(v.targetsLive:IsShown())
        v.newButton:Click()
        assert.is_false(v:targets():list()[2].enabled, "a new target starts unticked")
        s.startButton:Click()
        env.runTimers()
        v.tabButtons.targets:Click()
        assert.is_true(v.targetsLive:IsShown())
        assert.matches("takes effect right away", v.targetsLive:GetText())
        assert.equal(v.newButton, v.targetsLive.points.TOPLEFT.rel, "under New target")
        assert.equal(ns.DisenchantView.TARGETS_HINT, v.targetsHint:GetText(), "the usual hint stays beside it")
        s:stop()
        v:render()
        assert.is_false(v.targetsLive:IsShown())
      end)

      it("ignores lookup answers for a target deleted while they were out (#206)", function()
        local env, w, ns, s = snipeSetup()
        local v = w.disenchantView
        local api, pending = ns.snipeAPI, {}
        local auctions = api.auctions
        api.auctions = function(a, key, done)
          pending[#pending + 1] = function() auctions(a, key, done) end
        end
        local sounds = 0
        local alert = api.alert
        api.alert = function(a) sounds = sounds + 1; return alert(a) end
        s.startButton:Click()
        env.runTimers()
        assert.is_true(#pending > 0, "a lookup is out")
        v.tabButtons.targets:Click()
        v:selectTarget(1)
        v:deleteTarget()
        for _, f in ipairs(pending) do f() end
        env.runTimers()
        assert.is_nil(s.session:next(), "no find from the deleted target")
        assert.equal(0, sounds, "and no sound")
      end)

      it("keeps a find while its item's details aren't loaded (#206)", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        local find = s.session:next()
        assert.is_not_nil(find)
        ns.auctionAPI.itemInfo = function() return nil end
        ns.auctionAPI.itemType = function() return nil end
        w.disenchantView:render()
        assert.equal(find, s.session:next())
      end)

      it("drops the finds of a target deleted while sniping (#206)", function()
        local env, w, _, s = snipeSetup()
        local v = w.disenchantView
        v:targets():list()[1].profit = { kind = "percent", amount = 50 } -- 9s bracers are over its max
        v.tabButtons.targets:Click()
        v.newButton:Click() -- a second target, 10% profit: it takes the bracers
        v:setEnabled(#v:targets():list(), true) -- new targets start unticked (#206)
        v.tabButtons.snipe:Click()
        env.GetTime = function() return 100 end
        s.startButton:Click()
        env.runTimers(3)
        assert.is_not_nil(s.session:next(), "the second target's find")
        v.tabButtons.targets:Click()
        v:selectTarget(2)
        v:deleteTarget()
        assert.is_nil(s.session:next(), "its finds go with it")
        v.tabButtons.snipe:Click()
        assert.equal("Nothing under your max prices yet", s.cardName:GetText())
        s.buyButton:Click()
        assert.equal(0, #env.bids)
      end)

      it("drops finds over a target's max once its profit goes up (#206)", function()
        local env, w, _, s = snipeSetup()
        local v = w.disenchantView
        s.startButton:Click()
        env.runTimers()
        assert.equal("Buy for 9s 0c", s.buyButton:GetText())
        local t = v:targets():list()[1]
        t.profit = { kind = "percent", amount = 99 }
        v:render()
        assert.is_nil(s.session:next(), "9s is now over the max")
        assert.equal(0, #env.bids)
      end)

      it("passes, logs a missed buy and stops at the spend cap", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        assert.is_true(s.loading.spinnerFrame:IsShown(), "the spinner turns while sniping runs")
        assert.equal(s.startButton, s.loading.spinnerFrame.points.LEFT.rel, "in a fixed slot after Start")
        assert.equal(s.loading.spinnerFrame, s.status.points.LEFT.rel, "with the status text after it")
        env.runTimers()
        assert.is_true(s.loading.spinnerFrame:IsShown(), "and keeps turning between checks, so it doesn't blink")
        assert.matches("checked just now", s.status:GetText())
        s.passButton:Click()
        assert.equal("Buy for 12s 0c", s.buyButton:GetText(), "most profit first: 78 was behind 77")
        env.bidFails = true
        s.buyButton:Click()
        assert.is_true(s.buySpinner:IsShown(), "the Buy button spins while the auction house answers")
        env.runTimers()
        assert.is_false(s.buySpinner:IsShown())
        assert.matches("Missed %[Ridgeback Bracers%]: sold to someone else", s.logText:GetText())
        assert.matches("Passed", s.logText:GetText())
        assert.equal(0, ns.disenchant.session.spent)
        env.bidFails = false
        s.capInput:SetFocus()
        s.capInput:SetText("10s")
        s.capInput:ClearFocus()
        assert.equal(1000, ns.disenchant.snipe.cap)
        assert.equal("Spent this session: 0c of 10s 0c", s.spentText:GetText())
        ns.disenchant.session.spent = 500
        local entry = s:runnable()[1]
        s.session:add({ auctionID = 90, itemID = 5001, name = "[Pricey]", price = 600, worth = 1420, max = 1278,
          target = "Armor", source = entry.target, band = entry.row.band.min })
        w.disenchantView:render()
        s.buyButton:Click()
        assert.equal(1, #env.bids, "no bid over the cap")
        assert.equal("Can't buy [Pricey]: over your spend cap for this session.", s.status:GetText())
      end)

      it("stops when the auction house closes and keeps the session in the history", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        s.buyButton:Click()
        env.runTimers()
        env.CloseAuctionHouse()
        assert.is_false(s.running)
        assert.equal("The auction house closed, so sniping stopped.", s.status:GetText())
        assert.equal("", s.nearRows[1][1]:GetText(), "the closest listings go with it")
        assert.equal(1, #ns.disenchant.history)
        assert.equal(900, ns.disenchant.history[1].spent)
        assert.equal("Start sniping", s.startButton:GetText())
        assert.equal("Press Start sniping", s.cardName:GetText())
        assert.equal("Spent this session: 9s 0c", s.spentText:GetText(), "the last session stays in view")
        w:select("prices")
        assert.is_false(s.settingsBox:IsShown())
      end)

      it("counts a buy the auction house confirms after Stop", function()
        local env, _, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        s.buyButton:Click()
        s.startButton:Click()
        assert.is_false(s.running)
        env.runTimers()
        assert.equal(900, ns.disenchant.history[1].spent, "the filed session has the late buy")
        assert.equal(900, ns.disenchant.session.spent)
        s.startButton:Click()
        assert.equal(1, #ns.disenchant.history, "filed once")
        assert.equal(0, ns.disenchant.session.spent, "a new session")
      end)

      it("counts a buy confirmed after the timeout", function()
        local env, _, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        local placeBid = env.C_AuctionHouse.PlaceBid
        env.C_AuctionHouse.PlaceBid = function(id, amount)
          env.bids[#env.bids + 1] = { auctionID = id, amount = amount }
        end
        s.buyButton:Click()
        env.runTimers(10)
        assert.equal(0, ns.disenchant.session.spent, "missed for now")
        env.C_AuctionHouse.PlaceBid = placeBid
        env.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
        assert.equal(900, ns.disenchant.session.spent)
        assert.equal(1, ns.disenchant.session.bought)
      end)

      it("pauses checks while a find waits and checks again once it is bought or passed", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.equal(1, #env.browses)
        env.runTimers(5)
        assert.equal(1, #env.browses, "no checks while a find waits")
        assert.equal("Sniping 1 target, paused: a find waits: buy it or pass", s.status:GetText())
        s.passButton:Click()
        s.passButton:Click()
        env.runTimers(1)
        assert.equal(2, #env.browses, "checking again")
        assert.matches("checked just now", s.status:GetText())
      end)

      it("keeps checking while the next find can't be bought", function()
        local env, _, ns, s = snipeSetup()
        ns.disenchant.snipe = { cap = 500 }
        s.startButton:Click()
        env.runTimers()
        assert.equal("[Ridgeback Bracers]", s.cardName:GetText())
        env.runTimers(1)
        assert.equal(2, #env.browses, "over the spend cap: nothing to wait for")
      end)

      it("waits for a full scan before the next check, and holds the auto scan while sniping", function()
        local env, w, ns, s = snipeSetup()
        ns.auctionAPI.pending = {}
        s.startButton:Click()
        env.runTimers(3)
        assert.equal(0, #env.browses)
        assert.equal("Sniping 1 target, paused: a full scan is running", s.status:GetText())
        ns.auctionAPI.pending = nil
        env.runTimers(1)
        assert.equal(1, #env.browses)
        assert.is_true(w:scanState().held, "a due auto scan waits for sniping to stop")
      end)

      it("keeps a find whose buy wasn't sent, and finds one with no answer again", function()
        local env, w, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        env.throttled = true
        w.disenchantView:render()
        assert.equal("Wait...", s.buyButton:GetText(), "the auction house is still answering")
        assert.is_false(s.buyButton:IsEnabled())
        s.panel.scripts.OnMouseWheel(s.panel, -1)
        assert.equal(0, #env.bids, "a wheel notch does nothing meanwhile")
        assert.equal("[Ridgeback Bracers]", s.cardName:GetText(), "still the next buy")
        assert.equal("Nothing bought, passed or missed yet.", s.logText:GetText(), "and isn't logged")
        env.throttled = false
        env.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        env.runTimers()
        assert.equal("Buy for 9s 0c", s.buyButton:GetText(), "ready again")
        assert.is_true(s.buyButton:IsEnabled())
        env.throttled = true
        w.disenchantView:render()
        env.throttled = false
        env.runTimers(1)
        assert.equal("Buy for 9s 0c", s.buyButton:GetText(), "ready without the event: the clock notices")
        local placeBid = env.C_AuctionHouse.PlaceBid
        env.C_AuctionHouse.PlaceBid = function() end
        s.buyButton:Click()
        env.runTimers(10)
        assert.matches("Missed %[Ridgeback Bracers%]: no answer", s.logText:GetText())
        assert.equal("Buy for 12s 0c", s.buyButton:GetText(), "the next find")
        assert.is_true(s.nearRows[1].bg:IsShown(), "the bracer is under the max and buyable again")
        env.C_AuctionHouse.PlaceBid = placeBid
        s.passButton:Click()
        env.runTimers(1)
        assert.equal(2, #env.searches, "its item is looked up again")
        assert.equal("Buy for 9s 0c", s.buyButton:GetText(), "still listed: found again")
      end)

      it("scrolls a long session log above the settings, newest on top", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        for i = 1, 30 do s.session:log(i, "passed", { name = "[Item " .. i .. "]" }) end
        w.disenchantView:render()
        assert.is_true(s.logFrame:IsShown())
        assert.equal("", w.detailBody:GetText(), "the log has its own area")
        assert.matches("^ Passed %[Item 30%]", s.logText:GetText())
        assert.is_true(s.logBar:IsShown(), "it doesn't fit: the bar shows")
        assert.equal(0, s.logFrame:GetVerticalScroll())
        s.logFrame.scripts.OnMouseWheel(s.logFrame, -1)
        assert.equal(ns.SnipeView.LOG_STEP, s.logFrame:GetVerticalScroll())
        assert.is_true(s.logBar:GetScrollPercentage() > 0, "the bar moves with it")
        s.logBar:drag(1)
        assert.equal(s:logRange(), s.logFrame:GetVerticalScroll(), "dragging the bar to the end")
        s.logFrame.scripts.OnMouseWheel(s.logFrame, -100)
        assert.equal(s:logRange(), s.logFrame:GetVerticalScroll(), "no further than the end")
        w.disenchantView:render()
        assert.equal(s:logRange(), s.logFrame:GetVerticalScroll(), "a redraw keeps the place")
        s.session:log(31, "passed", { name = "[Item 31]" })
        w.disenchantView:render()
        assert.equal(0, s.logFrame:GetVerticalScroll(), "a new line: back to the top to show it")
        w:select("prices")
        assert.is_false(s.logFrame:IsShown())
        assert.is_false(s.logBar:IsShown())
      end)

      it("logs a call of this addon the game blocks while sniping", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "UNKNOWN()")
        assert.matches("The game blocked UNKNOWN%(%)", s.logText:GetText())
      end)

      it("counts the age of the last check up while the next one waits", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.matches("checked just now", s.status:GetText())
        s.passButton:Click()
        s.passButton:Click()
        env.browseSilent = true
        env.runTimers(3)
        assert.matches("checked 3s ago", s.status:GetText())
        assert.is_true(s.loading.spinnerFrame:IsShown())
        s.startButton:Click()
        assert.is_false(s.loading.spinnerFrame:IsShown(), "Stop ends the spinner")
        assert.equal(s.loading.spinnerFrame, s.status.points.LEFT.rel, "and the text keeps its place")
      end)

      it("doesn't look up the same item again until a cheaper auction shows up", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.equal(1, #env.searches)
        s.passButton:Click()
        s.passButton:Click()
        env.runTimers(1)
        assert.equal(2, #env.browses)
        assert.equal(1, #env.searches, "nothing cheaper: the slot goes to other items")
        assert.equal("Ridgeback Bracers", s.nearRows[1][1]:GetText())
        assert.is_false(s.nearRows[1].bg:IsShown(), "passed: still under the max, but nothing to buy")
        ns.disenchant.targets[1].profit = { kind = "gold", amount = 1000 }
        w.disenchantView:render()
        assert.equal("4s 20c", s.nearRows[1][4]:GetText(), "an edited target's max shows at once")
        ns.disenchant.targets[1].profit = { kind = "percent", amount = 10 }
        env.browseResults[1].minPrice = 800
        env.listings[5001][4] = { buyoutAmount = 800, auctionID = 80, itemLink = "[Ridgeback Bracers]" }
        env.runTimers(2)
        assert.equal(2, #env.searches)
        assert.equal("Buy for 8s 0c", s.buyButton:GetText())
      end)

      it("finds greens when the auction house gives no item level in its keys", function()
        local env, _, _, s = snipeSetup()
        for _, r in ipairs(env.browseResults) do r.itemKey.itemLevel = 0 end
        s.startButton:Click()
        env.runTimers()
        assert.equal("[Ridgeback Bracers]", s.cardName:GetText(), "the level comes from the item's details")
        assert.equal("item level 28", s.cardLevel:GetText())
        assert.equal("Ridgeback Bracers", s.nearRows[1][1]:GetText())
      end)

      it("says how many greens the last check saw when none are in the band", function()
        local env, _, _, s = snipeSetup()
        env.browseResults = { { itemKey = { itemID = 5003, itemLevel = 35 }, minPrice = 100 } }
        s.startButton:Click()
        env.runTimers()
        assert.equal("Last checks: 1 green: 1 outside the band.", s.nearEmpty:GetText())
        env.browseResults = { { itemKey = { itemID = 5003, itemLevel = 35 }, minPrice = 100 },
          { itemKey = { itemID = 6000, itemLevel = 28 }, minPrice = 100 },
          { itemKey = { itemID = 6001, itemLevel = 28 }, minPrice = 100 } }
        env.uncached[6001] = true
        env.runTimers(2)
        assert.equal("Last checks: 3 greens: 2 not loaded yet, 1 outside the band.", s.nearEmpty:GetText())
      end)

      it("judges items only once their details are loaded", function()
        local env, _, _, s = snipeSetup()
        env.uncached[5001] = true
        s.startButton:Click()
        env.runTimers()
        assert.equal(0, #env.searches, "an unknown item isn't guessed at")
        env.uncached[5001] = nil
        env.runTimers(2)
        assert.equal(1, #env.searches)
      end)

      it("judges an item not in the cache by its class from GetItemInfoInstant", function()
        local env, _, _, s = snipeSetup()
        env.uncached[5001] = true
        env.GetItemInfoInstant = function(id)
          if id == 5001 then return id, "Armor", "Leather", "INVTYPE_WRIST", 0, 4, 2 end
          return nil
        end
        s.startButton:Click()
        env.runTimers()
        assert.equal(1, #env.searches, "the bracer is looked up at once, by its key's item level")
        assert.equal(5001, env.searches[1].itemKey.itemID)
      end)

      it("names closest rows once the item loads, with the suffix from its lookup (#147)", function()
        local env, _, _, s = snipeSetup()
        env.uncached[5002] = true
        env.GetItemInfoInstant = function(id)
          if id == 5002 then return id, "Armor", "Leather", "INVTYPE_FEET", 0, 4, 2 end
          return nil
        end
        env.listings[5001][1].itemLink = "[Ridgeback Bracers of the Eagle]"
        local asked = {}
        env.C_Item.RequestLoadItemDataByID = function(id) asked[id] = true end -- the client is slow to answer
        s.startButton:Click()
        env.runTimers()
        assert.equal("Ridgeback Bracers of the Eagle", s.nearRows[1][1]:GetText(), "the full name from the lookup")
        assert.equal("item 5002", s.nearRows[2][1]:GetText(), "not loaded yet")
        assert.is_true(asked[5002], "the client is asked to load it")
        env.uncached[5002] = nil
        s:refresh()
        assert.equal("Ridgeback Boots", s.nearRows[2][1]:GetText(), "named once it loads, without a new check")
      end)

      it("shows the item tooltip over the next buy and the closest listings", function()
        local env, _, _, s = snipeSetup()
        local shown = {}
        env.GameTooltip = {
          SetOwner = function(_, owner) shown.owner = owner end,
          IsOwned = function(_, f) return shown.visible and shown.owner == f end,
          Hide = function() shown.visible = false end,
          SetHyperlink = function(_, link) shown.link, shown.visible = link, true return true end,
          SetItemKey = function(_, id, level, suffix) shown.key, shown.visible = { id, level, suffix }, true end,
        }
        s.cardHover.scripts.OnEnter(s.cardHover)
        assert.is_false(shown.visible, "no find, no tooltip")
        s.startButton:Click()
        env.runTimers()
        s.cardHover.scripts.OnEnter(s.cardHover)
        assert.equal("[Ridgeback Bracers]", shown.link, "the auction's own link, with its random stats")
        assert.is_true(shown.visible)
        s.cardHover.scripts.OnLeave(s.cardHover)
        assert.is_false(shown.visible)
        local row = s.nearRows[2]
        row.hover.scripts.OnEnter(row.hover)
        assert.same({ 5002, 28, 0 }, shown.key, "a browse result by its item key")
        s.nearRows[5].hover.scripts.OnEnter(s.nearRows[5].hover)
        assert.is_false(shown.visible, "an empty row shows nothing")
        s.cardHover.scripts.OnEnter(s.cardHover)
        shown.link = nil
        s:passNext()
        assert.equal("[Ridgeback Bracers]", shown.link, "the tooltip follows the card to the next find")
        assert.is_true(shown.visible)
      end)

      it("keeps sniping behind other views without drawing over them", function()
        local env, w, _, s = snipeSetup()
        s.startButton:Click()
        w:select("alts")
        env.runTimers()
        assert.is_true(s.running)
        assert.are_not.equal("This session", w.detailTitle:GetText())
        assert.is_false(s.settingsBox:IsShown())
        assert.equal(1, #env.searches)
      end)

      it("asks for the auction house and a ticked target before it starts", function()
        local env, w, _, s = snipeSetup()
        w.disenchantView.tabButtons.targets:Click()
        w.disenchantView.targetRows[1].check:Click()
        w.disenchantView.tabButtons.snipe:Click()
        s.startButton:Click()
        assert.is_falsy(s.running)
        assert.equal("Tick at least one target on Targets first.", s.status:GetText())
        env.CloseAuctionHouse()
        s.startButton:Click()
        assert.equal("Open the auction house to snipe.", s.status:GetText())
      end)
    end)
  end)

  describe("Settings", function()
    it("turns the debug log on and off, and the log then follows clicks, views and browses (#99)", function()
      local env, w, ns = setup({ debug = true })
      env.openAuctionHouse()
      env.runTimers()
      sidebarButton(w, "settings"):Click()
      local sv = w.settingsView
      local drop = sv.debugDrop
      assert.equal("Off", drop:GetText(), "off to start with")
      assert.equal(0, ns.debugLog:count(), "nothing is kept while off")
      drop:Click()
      fake.pick(drop, "On")
      assert.is_true(ns.debugLog:isOn())
      assert.equal("On", drop:GetText())
      assert.same({ "On" }, fake.selected(drop))
      sidebarButton(w, "post"):Click()
      env.browseResults = { { itemKey = { itemID = 1 }, minPrice = 5 } }
      ns.snipeAPI:browse({ searchString = "Arcane" }, function() end)
      env.runTimers()
      local text = table.concat(ns.debugLog.saved.lines, "\n")
      assert.matches("%[session%]", text)
      assert.matches("%[debug%] log on", text)
      assert.matches("%[view%] settings %-> post", text)
      assert.matches("%[ui%] click \"Post\" in settings", text)
      assert.matches("%[browse%] {searchString=Arcane} %-> 1 results", text)
      sidebarButton(w, "settings"):Click()
      drop:Click()
      fake.pick(drop, "Off")
      local count = ns.debugLog:count()
      sidebarButton(w, "post"):Click()
      assert.equal(count, ns.debugLog:count(), "nothing more once off")
      assert.is_true(w.postPanel:IsShown(), "clicks still work")
    end)

    it("picks the default duration, which new items then post for", function()
      local env, w, ns = setup()
      env.containers[0] = { { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[4306] = {}
      ns.prices:importPrices("/1/Horde", env.now, { ["i:4306"] = { value = 2000 } })
      env.openAuctionHouse()
      env.runTimers()
      sidebarButton(w, "settings"):Click()
      local sv = w.settingsView
      assert.equal("Settings", w.heading:GetText())
      assert.is_false(w.placeholder:IsShown())
      assert.is_true(w.settingsPanel:IsShown())
      assert.is_false(w.postPanel:IsShown())
      assert.equal("Default duration", w.detailTitle:GetText())
      assert.equal("24 hours", sv.durationDrop:GetText(), "24 hours to start with")
      assert.same({ "2 hours", "8 hours", "24 hours" }, fake.menuLabels(sv.durationDrop))
      assert.is_true(sv.resetButton:IsShown())
      assert.is_false(sv.resetButton:IsEnabled(), "nothing to reset")
      sv.durationDrop:Click()
      fake.pick(sv.durationDrop, "8 hours")
      assert.equal(2, ns.posting:defaultDuration())
      assert.equal("8 hours", sv.durationDrop:GetText())
      assert.same({ "8 hours" }, fake.selected(sv.durationDrop))
      assert.is_true(sv.resetButton:IsEnabled())

      sidebarButton(w, "post"):Click()
      assert.is_false(sv.resetButton:IsShown(), "the reset button belongs to the Settings view")
      env.runTimers()
      w.postView:selectRow(1)
      assert.equal("8 hours", w.postView.durationDrop:GetText(), "the Post view starts on the default")
      w.postView.postButton:Click()
      assert.equal(2, env.posts[1].duration)

      sidebarButton(w, "settings"):Click()
      sv.resetButton:Click()
      assert.equal(3, ns.posting:defaultDuration())
      assert.is_false(sv.resetButton:IsEnabled())
    end)

    it("turns the tooltip parts on and off, all on to start with (#119)", function()
      local env, w, ns = setup()
      env.openAuctionHouse()
      sidebarButton(w, "settings"):Click()
      local checks = w.settingsView.tooltipChecks
      assert.equal(7, #checks)
      assert.equal("Min buyout", checks[5].label:GetText())
      assert.is_true(checks[7].points.TOPLEFT.y >= -308 + 24 + 6, "every part fits above the Mail group")
      assert.equal("Best time to sell", checks[7].label:GetText())
      assert.equal("Show Better AH prices on item tooltips", checks[1].label:GetText())
      for _, b in ipairs(checks) do assert.is_true(b:GetChecked()) end
      checks[3]:Click()
      assert.same({ paid = false }, ns.tooltipSettings)
      assert.is_false(checks[3]:GetChecked())
      checks[1]:Click()
      assert.is_false(checks[2]:IsEnabled(), "the parts wait while the block is off")
      assert.is_true(checks[1]:IsEnabled())
      checks[1]:Click()
      checks[3]:Click()
      assert.same({}, ns.tooltipSettings, "back to everything on")
    end)

    it("turns the Mailbox window's replacement of Blizzard's mail frame off and on (#154)", function()
      local env, w, ns = setup()
      ns.mailSettings = {}
      env.openAuctionHouse()
      sidebarButton(w, "settings"):Click()
      local b = w.settingsView.mailCheck
      assert.is_true(b:GetChecked(), "on to start with")
      b:Click()
      assert.same({ replace = false }, ns.mailSettings)
      assert.is_false(b:GetChecked())
      b:Click()
      assert.same({}, ns.mailSettings)
    end)

    it("keeps an item saved with only a limit on the default duration", function()
      local env, w, ns = setup()
      env.containers[0] = { { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[4306] = {}
      ns.prices:importPrices("/1/Horde", env.now, { ["i:4306"] = { value = 2000 } })
      ns.posting:setDefaultDuration(2)
      env.openAuctionHouse()
      env.runTimers()
      w.postView:selectRow(1)
      w.postView.limitInput:SetText("5")
      w.postView:saveProfile()
      assert.same({ limit = 5 }, ns.posting:profile("i:4306"), "no duration picked, none saved")
      sidebarButton(w, "settings"):Click()
      w.settingsView.resetButton:Click()
      assert.equal(3, ns.posting:durationFor("i:4306"), "follows the default when it changes")
      w.settingsView.resetButton:Click()
      assert.equal(3, ns.posting:defaultDuration(), "a disabled reset does nothing")
    end)

    it("leaves an item's own duration alone", function()
      local env, w, ns = setup()
      env.containers[0] = { { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[4306] = {}
      ns.prices:importPrices("/1/Horde", env.now, { ["i:4306"] = { value = 2000 } })
      ns.posting:setProfile("i:4306", "", 3)
      env.openAuctionHouse()
      sidebarButton(w, "settings"):Click()
      fake.pick(w.settingsView.durationDrop, "2 hours")
      sidebarButton(w, "post"):Click()
      env.runTimers()
      w.postView.postButton:Click()
      assert.equal(3, env.posts[1].duration)
    end)
  end)

  describe("Post", function()
    local linen = { itemID = 2589, count = 20, name = "Linen Cloth" }

    local function cells(w, r)
      local out = {}
      for c, cell in ipairs(w.postView.rows[r]) do out[c] = cell:GetText() end
      return out
    end

    local function postSetup()
      local env, w, ns = setup()
      env.containers[0] = { linen, { itemID = 2589, count = 20, name = "Linen Cloth" },
        { itemID = 2592, count = 3, name = "Wool Cloth" }, { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[2589] = { { unitPrice = 950, quantity = 40 } }
      env.listings[2592] = { { unitPrice = 500, quantity = 20 } }
      env.listings[4306] = {}
      ns.prices:importPrices("/1/Horde", env.now, { ["i:2589"] = { value = 1000 }, ["i:2592"] = { value = 1000 },
        ["i:4306"] = { value = 2000 } })
      ns.posting:setProfile("i:2589", "", 2)
      ns.posting:setProfile("i:2592", 20, 2)
      return env, w, ns
    end

    it("matches your own cheapest auction instead of undercutting it, even when the search doesn't mark it (#132)",
      function()
      local env, w = postSetup()
      env.listings[2589] = { { unitPrice = 950, quantity = 40 }, { unitPrice = 990, quantity = 5 } }
      env.owned = { { id = 7, itemID = 2589, quantity = 40, buyout = 950 } }
      env.openAuctionHouse()
      env.runTimers()
      assert.equal("9s 50c", cells(w, 1)[3])
      w.postView.rows[1].button:Click()
      assert.matches("Your own auction is the cheapest listing, at 9s 50c each, so this posts at 9s 50c",
        w.detailBody:GetText(), 1, true)
    end)

    it("counts other sellers' listings toward market value, once per day, and not as a full scan", function()
      local env, w, ns = setup()
      env.containers[0] = { linen, { itemID = 2592, count = 3, name = "Wool Cloth" },
        { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[2589] = { { unitPrice = 950, quantity = 40 }, { unitPrice = 1000, quantity = 10 } }
      env.listings[2592] = { { unitPrice = 500, quantity = 20 } }
      env.listings[4306] = {}
      env.openAuctionHouse()
      assert.equal(950, (ns.prices:marketValue("/1/Horde", "i:2589", env.now)), "no scan needed")
      assert.same({ "Linen Cloth", "20", "9s 49c", "7s 60c", "Ready: 20" }, cells(w, 1), "no setup needed")
      assert.is_nil(ns.prices:marketValue("/1/Horde", "i:2592", env.now), "one listing is too few to judge")
      assert.is_nil(ns.prices:marketValue("/1/Horde", "i:4306", env.now))
      assert.is_nil(ns.prices:lastScan("/1/Horde"), "a search is not a full scan")
      w.postView.rows[2].button:Click()
      assert.matches("nobody else has it listed", w.detailBody:GetText(), 1, true)
      w.postView.rows[3].button:Click()
      assert.matches("too few other listings", w.detailBody:GetText(), 1, true)
      w.postView.queue:forget("i:2589") -- looked up again, as after a post
      w.postView:refresh()
      env.runTimers()
      assert.equal(1, ns.prices:history("/1/Horde", "i:2589")[1].points, "once per day")
      w:select("prices")
      w.rows[1].button:Click()
      assert.matches("Post view check today: the middle price of the 50 units other sellers have listed.",
        w.detailBody:GetText(), 1, true)
    end)

    it("tries failed price checks again later and after a full scan, and rereads an empty bag read (#82)", function()
      local env, w, ns = postSetup()
      ns.posting:setFilter("mats")
      env.containers[1] = { { itemID = 10998, count = 4, name = "Lesser Astral Essence" } }
      env.searchSilent = true -- no answer
      env.openAuctionHouse()
      env.runTimers(11)
      local pv = w.postView
      assert.equal("failed", pv.queue:rows()[1].state)
      env.searchSilent = false
      env.listings[10998] = { { unitPrice = 1800, quantity = 60 } }
      env.runTimers(ns.PostView.RETRY)
      assert.are_not.equal("failed", pv.queue:rows()[1].state, "looked up again by itself")
      assert.matches("on post: 4 items, 1 mats", table.concat(pv:debugLines(), "\n"), 1, true)

      -- A read that finds the bags empty all of a sudden is read again a moment later.
      local saved = env.containers
      env.containers = { [0] = {}, [1] = {} }
      pv:refresh()
      assert.equal("Disenchant mats (1)", pv.filterButtons.mats:GetText(), "the empty read isn't taken")
      env.containers = saved
      env.runTimers(1)
      assert.equal("Disenchant mats (1)", pv.filterButtons.mats:GetText())

      -- Read again after 1, 2, 4 and 8 seconds; then the bags are taken to be empty.
      env.containers = { [0] = {}, [1] = {} }
      pv:refresh()
      env.runTimers(7)
      assert.equal("Disenchant mats (1)", pv.filterButtons.mats:GetText(), "still waiting")
      env.runTimers(8)
      assert.equal("Disenchant mats (0)", pv.filterButtons.mats:GetText())
    end)

    it("doesn't count partial search results", function()
      local env, _, ns = setup()
      env.containers[0] = { linen }
      env.listings[2589] = { { unitPrice = 950, quantity = 40 }, { unitPrice = 1000, quantity = 10 } }
      env.fullResults = false
      env.openAuctionHouse()
      assert.is_nil(ns.prices:marketValue("/1/Horde", "i:2589", env.now))
    end)

    it("keeps floors set before rulesets had names (ADR 0005)", function()
      local env, w, ns = postSetup()
      ns.posting:setFloor("/1/Horde", "i:2592", 400)
      env.Enum = { GameRule = { HardcoreRuleset = 1, PvPRuleset = 2, RPRuleset = 3 } }
      env.C_GameRules.IsGameRuleActive = function() return false end
      env.openAuctionHouse()
      assert.equal("/Normal/Horde", w.postView.key)
      assert.equal(400, ns.posting:floor("/Normal/Horde", "i:2592"))
      assert.is_nil(ns.posting:floor("/1/Horde", "i:2592"))
    end)

    it("is the first view, and checks the price of each item in the bags", function()
      local env, w = postSetup()
      env.openAuctionHouse()
      assert.is_true(w.postPanel:IsShown())
      assert.is_false(w.placeholder:IsShown())
      assert.equal("3 items in your bags.", w.postView.status:GetText())
      assert.same({ "Linen Cloth", "40", "9s 49c", "8s 0c", "Ready: 40" }, cells(w, 1), "both bag stacks at once")
      assert.same({ "Silk Cloth", "10", "20s 0c", "16s 0c", "Ready: 10" }, cells(w, 2), "no profile needed")
      assert.same({ "Wool Cloth", "3", "", "8s 0c", "Below floor" }, cells(w, 3))
      assert.equal("Post next: Linen Cloth, 40 for 9s 49c each", w.postView.postButton:GetText())
    end)

    it("says when combining essences earns more, from a search of the greater one (#234)", function()
      local env, w, ns = postSetup()
      env.containers[0] = { { itemID = 11174, count = 20, name = "Lesser Nether Essence" } }
      env.listings[11174] = { { unitPrice = 3884, quantity = 100 } }
      env.listings[11175] = { { unitPrice = 11960, quantity = 50 } }
      ns.prices:importPrices("/1/Horde", env.now, { ["i:11174"] = { value = 3885 }, ["i:11175"] = { value = 11575 } })
      env.openAuctionHouse()
      env.runTimers()
      local searched = {}
      for _, s in ipairs(env.searches) do searched[#searched + 1] = s.itemKey.itemID end
      assert.same({ 11174, 11175 }, searched, "the greater is looked up after the bags' items")
      local row = cells(w, 1)
      assert.equal("Lesser Nether Essence", row[1])
      assert.equal("38s 83c", row[3])
      assert.equal("|cffffd100Combine +17s|r", row[5])
      assert.equal("Post next: Lesser Nether Essence, 20 for 38s 83c each", w.postView.postButton:GetText(),
        "advice only: it still posts as is")
      w.postView.rows[1].button:Click()
      local text = w.detailBody:GetText()
      assert.matches("Post 20 as is: 7g 37s", text, 1, true)
      assert.matches("Combine into 6 Greater Nether Essence, 2 left: 7g 55s", text, 1, true)
      assert.matches("Combining earns 17s 67c more, after the 5% cut.", text, 1, true)
      assert.equal(1, #w.postView.queue:rows(), "the greater isn't a row: it isn't in the bags")
      w.postView.skipButton:Click()
      assert.equal("Skipped", cells(w, 1)[5], "a skipped essence says so, not the advice")
    end)

    it("fits a big gain in the Status column", function()
      local _, _, ns = postSetup()
      assert.equal("12g", ns.PostView.gainText(123456))
      assert.equal("4g 12s", ns.PostView.gainText(41234))
      assert.equal("17s", ns.PostView.gainText(1767))
      assert.equal("45c", ns.PostView.gainText(45))
    end)

    it("shows only disenchant materials with their floors from the rule (#71)", function()
      local env, w, ns = postSetup()
      env.containers[1] = { { itemID = 10938, count = 9, name = "Lesser Magic Essence" },
        { itemID = 10940, count = 40, name = "Strange Dust" } }
      env.listings[10938] = { { unitPrice = 699, quantity = 20 } }
      env.listings[10940] = { { unitPrice = 1800, quantity = 60 } }
      -- Greater Magic Essence under its own floor, so combining isn't advised (#234).
      env.listings[10939] = { { unitPrice = 2000, quantity = 20 } }
      ns.prices:importPrices("/1/Horde", env.now, { ["i:10938"] = { value = 900 }, ["i:10939"] = { value = 2800 },
        ["i:10940"] = { value = 2000 } })
      ns.disenchant = { targets = { { enabled = true, band = 21, types = { cloth = true },
        profit = { kind = "percent", amount = 25 } } } }
      ns.posting:setProfile("i:10940", 20, 3)
      env.openAuctionHouse()
      local pv = w.postView
      assert.is_false(pv.ruleButton:IsShown())
      assert.equal("All items (5)", pv.filterButtons.all:GetText())
      assert.equal("Disenchant mats (2)", pv.filterButtons.mats:GetText())
      pv.filterButtons.mats:Click()
      assert.equal("mats", ns.posting:filter(), "remembered")
      assert.equal("2 disenchant materials in your bags.", pv.status:GetText())
      -- Break-even at a 25% profit: 75% of market value. A lesser essence keeps a third of the greater's.
      assert.same({ "Lesser Magic Essence", "9", "", "7s 0c", "Below floor" }, cells(w, 1))
      assert.same({ "Strange Dust", "40", "17s 99c", "15s 0c", "Ready: 20" }, cells(w, 2), "Post at most 20")
      assert.equal("Post next: Strange Dust, 20 for 17s 99c each", pv.postButton:GetText())
      pv.rows[1].button:Click()
      assert.matches("a third of Greater Magic Essence's floor of 21s 0c", w.detailBody:GetText(), 1, true)
      assert.matches("Posting as is earns 2s 70c more, after the 5% cut.", w.detailBody:GetText(), 1, true)
      pv.rows[2].button:Click()
      assert.matches("75% of the 20s 0c market value: break-even for your snipes at a 25% profit",
        w.detailBody:GetText(), 1, true)

      assert.is_true(pv.ruleButton:IsShown())
      pv.ruleButton:Click()
      assert.equal("Floor rule for all mats", w.detailTitle:GetText())
      assert.is_true(pv.ruleEditor:IsShown())
      assert.is_true(pv.ruleBreakEven:GetChecked())
      assert.matches("Your smallest snipe profit is 25%", w.detailBody:GetText(), 1, true)
      pv.rulePercentInput:SetText("60")
      pv.rulePercentInput.scripts.OnEnterPressed(pv.rulePercentInput)
      assert.is_true(pv.rulePercent:GetChecked())
      assert.equal("12s 0c", cells(w, 2)[4])
      pv.ruleConvert:Click()
      assert.equal("5s 40c", cells(w, 1)[4], "60% of its own 9s, without the essence rule")

      -- A gold profit is weighed against the band's worth from this market, without the Disenchant view,
      -- and against the class worth most: that one pays the most, so it needs the highest floor.
      local both = { enabled = true, band = 21, types = { cloth = true, onehand = true } }
      local D = ns.DisenchantView
      local list = D.rows(function(id) return pv:marketValue("i:" .. id) end, D.options(ns))
      local row
      for _, r in ipairs(list) do if r.band.min == 21 then row = r end end
      assert.is_true(row.armor.net ~= row.weapon.net)
      assert.equal(math.max(row.armor.net, row.weapon.net), pv:targetWorth(both))
      pv.rulePercentInput:SetText("0")
      pv.rulePercentInput.scripts.OnEnterPressed(pv.rulePercentInput)
      assert.equal("Type a whole percent from 1 to 1000.", pv.ruleStatus:GetText())
      assert.equal(60, ns.posting:matRule().percent)

      pv.filterButtons.all:Click()
      assert.equal(5, #pv.queue:rows())
      assert.is_false(pv.ruleButton:IsShown())
      assert.is_false(pv.ruleEditor:IsShown())
    end)

    it("keeps its counts and what it found when an item's data unloads between switches (#82)", function()
      local env, w, ns = postSetup()
      env.openAuctionHouse()
      local pv = w.postView
      local searches = #env.searches
      assert.equal("All items (3)", pv.filterButtons.all:GetText())
      env.containers[0][4].unknown = true -- Silk Cloth: the client dropped its data
      pv.filterButtons.mats:Click()
      pv.filterButtons.all:Click()
      assert.equal("All items (3)", pv.filterButtons.all:GetText())
      assert.equal("3 items in your bags.", pv.status:GetText())
      assert.equal(searches, #env.searches, "nothing looked up again")

      -- Item loads re-read the bags only for an item the view asked for, once per burst.
      env.containers[0][5] = { itemID = 777, count = 2, name = "Fresh Loot", unknown = true }
      local reads, read = 0, ns.PostingAPI.readBags
      ns.PostingAPI.readBags = function(...) reads = reads + 1 return read(...) end
      pv:refresh()
      reads = 0
      env.fire("ITEM_DATA_LOAD_RESULT", 2589, true)
      env.runTimers()
      assert.equal(0, reads, "not for an item it didn't ask for")
      env.containers[0][5].unknown = nil
      env.fire("ITEM_DATA_LOAD_RESULT", 777, true)
      env.fire("ITEM_DATA_LOAD_RESULT", 777, true)
      env.runTimers()
      assert.equal(1, reads)
      assert.equal("All items (4)", pv.filterButtons.all:GetText())
    end)

    it("posts all of a commodity in one click and moves on as the bags empty", function()
      local env, w = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.postButton:Click()
      assert.same({ kind = "commodity", loc = { bag = 0, slot = 1 }, duration = 2, quantity = 40, price = 949 },
        env.posts[1], "both bag stacks in one post")
      assert.equal("Posting...", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.equal(1, #env.posts, "no second post before the game and the bags answer")
      env.containers[0][1], env.containers[0][2] = false, false
      env.runTimers() -- the auction is created
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Post next: Silk Cloth, 10 for 20s 0c each", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.same({ kind = "commodity", loc = { bag = 0, slot = 4 }, duration = 3, quantity = 10, price = 2000 },
        env.posts[2], "24 hours without a profile")
      env.containers[0][4] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Nothing ready to post", w.postView.postButton:GetText())
      assert.is_false(w.postView.postButton:IsEnabled())
    end)

    it("posts gear one auction per click, and stops at the limit", function()
      local env, w, ns = setup()
      local green = { itemID = 5001, count = 1, name = "Green Blade", item = true }
      env.containers[0] = { green, { itemID = 5001, count = 1, name = "Green Blade", item = true },
        { itemID = 5001, count = 1, name = "Green Blade", item = true } }
      env.listings[5001] = { item = true, { buyoutAmount = 5000, quantity = 1 } }
      ns.prices:importPrices("/1/Horde", env.now, { ["i:5001"] = { value = 5000 } })
      ns.posting:setProfile("i:5001", 2, 3)
      env.openAuctionHouse()
      env.runTimers()
      assert.same({ "Green Blade", "3", "49s 99c", "40s 0c", "Ready: 2 x 1" }, cells(w, 1))
      w.postView.postButton:Click()
      assert.same({ "item", 1 }, { env.posts[1].kind, env.posts[1].quantity })
      env.containers[0][1] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Ready: 1", cells(w, 1)[5], "one more to reach the limit of 2")
      w.postView.postButton:Click()
      assert.same({ bag = 0, slot = 2 }, env.posts[2].loc)
      env.containers[0][2] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Leftover", cells(w, 1)[5])
      assert.equal(2, #env.posts)
    end)

    it("shows the price checks in progress", function()
      local env, w = postSetup()
      env.searchSilent = true
      env.openAuctionHouse()
      assert.equal("Checking prices: 0 of 3 items", w.postView.status:GetText())
      local bar = w.postView.loading.barFrame
      assert.is_true(bar:IsShown())
      assert.same({ 0, 3 }, { bar:GetMinMaxValues() })
      assert.equal("Checking...", cells(w, 1)[5])
      assert.equal("Checking prices...", w.postView.postButton:GetText())
      env.runTimers(10)
      assert.equal("Not checked", cells(w, 1)[5])
      w.postView.rows[1].button:Click()
      assert.equal("Couldn't check the price: no answer from the auction house.", w.detailBody:GetText())
    end)

    it("asks for a second click when the game wants the post confirmed", function()
      local env, w = postSetup()
      env.needsConfirmation = true
      env.openAuctionHouse()
      env.runTimers()
      w.postView.postButton:Click()
      assert.equal("Confirm post: Linen Cloth, 40 for 9s 49c each", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.equal("confirm commodity", env.posts[2].kind)
    end)

    it("skips an item for this visit", function()
      local env, w = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.skipButton:Click()
      assert.equal("Skipped", cells(w, 1)[5])
      assert.equal("Post next: Silk Cloth, 10 for 20s 0c each", w.postView.postButton:GetText())
      env.CloseAuctionHouse()
      env.openAuctionHouse()
      env.runTimers()
      assert.equal("Ready: 40", cells(w, 1)[5], "a new visit forgets it")
    end)

    it("says how far under the competitor a post goes, and when it can only tie (#163)", function()
      local _, _, ns = postSetup()
      local function text(undercut, price, step)
        local row = { state = "ready", have = 1, plan = { action = "post", undercut = undercut, price = price,
          floor = 1, posts = 1, remainder = 0 } }
        return (ns.PostView.detailText(row, 1, nil, step):match("^[^\n]*"))
      end
      assert.equal("The cheapest other listing is 1s 0c each, the lowest price the auction house takes, so this "
        .. "posts at 1s 0c too.", text(100, 100, 100))
      assert.equal("The cheapest other listing is 1s 50c each, so this posts at 1s 0c, 50c under it.",
        text(150, 100, 100))
      assert.equal("The cheapest other listing is 3s 0c each, so this posts at 2s 0c, a silver under it.",
        text(300, 200, 100))
    end)

    it("explains the price and saves a posting profile from the detail panel", function()
      local env, w, ns = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.rows[1].button:Click()
      assert.equal("Linen Cloth", w.detailTitle:GetText())
      assert.equal(table.concat({
        "The cheapest other listing is 9s 50c each, so this posts at 9s 49c, 1 copper under it.",
        "Your floor is 8s 0c (80% of the 10s 0c market value).", "", "Posts all 40 in one go.",
      }, "\n"), w.detailBody:GetText())

      w.postView.rows[2].button:Click()
      assert.is_true(w.postView.editor:IsShown())
      assert.equal("Post at most", w.postView.limitLabel:GetText())
      assert.equal("", w.postView.limitInput:GetText(), "no limit: everything")
      w.postView.limitInput:SetText("5")
      fake.pick(w.postView.durationDrop, "2 hours")
      w.postView.saveButton:Click()
      assert.same({ limit = 5, duration = 1 }, ns.posting:profile("i:4306"))
      assert.equal("Ready: 5", cells(w, 2)[5])
      assert.matches("Posts 5 in one go.\nThe other 5 stay in your bags (Post at most 5).", w.detailBody:GetText(), 1,
        true)
      w.postView.limitInput:SetText("0")
      w.postView.saveButton:Click()
      assert.equal("Post at most must be a whole number of 1 or more, or empty for everything.",
        w.postView.editorStatus:GetText())
      w.postView.limitInput:SetText("")
      w.postView.saveButton:Click()
      assert.same({ duration = 1 }, ns.posting:profile("i:4306"))
      assert.equal("Ready: 10", cells(w, 2)[5])
    end)

    it("sets a floor price per market from the detail panel", function()
      local env, w, ns = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.rows[3].button:Click()
      assert.matches("below your floor of 8s 0c", w.detailBody:GetText())
      w.postView.floorInput:SetText("4s")
      w.postView.floorButton:Click()
      assert.equal(400, ns.posting:floor("/1/Horde", "i:2592"))
      assert.same({ "Wool Cloth", "3", "4s 99c", "4s 0c", "Ready: 3" }, cells(w, 3))
      w.postView.floorInput:SetText("lots")
      w.postView.floorButton:Click()
      assert.equal("Type a price like 20s or 1g 5s, or leave it empty.", w.postView.editorStatus:GetText())
      w.postView.floorInput:SetText("")
      w.postView.floorButton:Click()
      assert.is_nil(ns.posting:floor("/1/Horde", "i:2592"))
    end)

    it("never draws over another view when a price check or post answers late", function()
      local env, w = postSetup()
      env.searchSilent = true
      env.openAuctionHouse()
      w.postView.rows[1].button:Click()
      w:select("prices")
      local before = w.detailBody:GetText()
      env.runTimers(10)
      env.fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
      assert.equal(before, w.detailBody:GetText())
      assert.is_false(w.postView.editor:IsShown())
    end)

    it("explains a first post against other sellers once the price is known", function()
      local env, w = postSetup()
      env.listings[4306] = { { unitPrice = 2100, quantity = 5 } }
      env.searchSilent = true
      env.openAuctionHouse()
      w.postView.rows[2].button:Click()
      env.searchSilent = false
      env.runTimers(10) -- the silent checks time out
      env.fire("BAG_UPDATE_DELAYED") -- and are tried again
      env.runTimers()
      assert.equal("Ready: 10", cells(w, 2)[5])
      assert.matches("The cheapest other listing is 21s 0c each, so this posts at 20s 99c", w.detailBody:GetText())
      assert.equal("", w.postView.limitInput:GetText())
    end)

    it("drops a pending confirmation when the floor changes", function()
      local env, w = postSetup()
      env.needsConfirmation = true
      env.openAuctionHouse()
      env.runTimers()
      w.postView.postButton:Click()
      w.postView.rows[1].button:Click()
      w.postView.floorInput:SetText("10s")
      w.postView.floorButton:Click()
      assert.equal("Floor set to 10s 0c.", w.postView.editorStatus:GetText())
      assert.equal("Below floor", cells(w, 1)[5])
      assert.equal("Post next: Silk Cloth, 10 for 20s 0c each", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.same({ "commodity", 4306 }, { env.posts[2].kind, env.containers[0][env.posts[2].loc.slot].itemID },
        "nothing confirmed below the new floor: the next item posts instead")
    end)

    it("keeps the rest in the bags once the limit is posted", function()
      local env, w, ns = postSetup()
      env.containers[0][2] = { itemID = 2589, count = 5, name = "Linen Cloth" }
      ns.posting:setProfile("i:2589", 20, 2)
      env.openAuctionHouse()
      env.runTimers()
      assert.equal("Ready: 20", cells(w, 1)[5])
      w.postView.postButton:Click()
      env.containers[0][1] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Leftover", cells(w, 1)[5])
      assert.equal(1, #env.posts)
    end)

    it("doesn't count a refused post toward the limit", function()
      local env, w, ns = postSetup()
      ns.posting:setProfile("i:2589", 20, 2)
      env.openAuctionHouse()
      env.runTimers()
      w.postView.postButton:Click()
      assert.equal(20, env.posts[1].quantity)
      env.fire("AUCTION_HOUSE_POST_ERROR")
      env.runTimers()
      assert.equal("Ready: 20", cells(w, 1)[5])
    end)

    it("takes back a post with no answer, and counts it again if it goes up late (#163)", function()
      local env, w, ns = postSetup()
      ns.posting:setProfile("i:2589", 20, 2)
      env.openAuctionHouse()
      env.runTimers()
      env.postSilent = true
      w.postView.postButton:Click()
      assert.equal(20, env.posts[1].quantity)
      env.runTimers(5)
      env.runTimers()
      assert.equal("Ready: 20", cells(w, 1)[5], "the unanswered post doesn't count toward Post at most")
      assert.matches("No answer from the auction house for that post yet", w.postView.message, 1, true)
      env.fire("AUCTION_HOUSE_SHOW_ERROR", 7)
      assert.matches("No answer from the auction house", w.postView.message, 1, true,
        "a later error is not about that post")
      env.fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
      env.runTimers()
      assert.equal("Leftover", cells(w, 1)[5], "it went up after all")
    end)

    it("hides the editor on other views and says when nothing can be posted", function()
      local env, w = setup()
      env.openAuctionHouse()
      assert.equal("Nothing in your bags can be posted.", w.postView.status:GetText())
      w:select("prices")
      assert.is_false(w.postPanel:IsShown())
      assert.is_false(w.postView.editor:IsShown())
    end)
  end)
end)

describe("Browse view", function()
  local function browse()
    local env, w, ns = setup()
    env.openAuctionHouse()
    w:select("browse")
    return env, w, ns, w.browseView
  end
  local function results(env)
    env.itemNames = { [1] = "Ridgeback Bracers", [2] = "Battleforge Shoulderpads" }
    env.itemQualities = { [1] = 2, [2] = 2 }
    env.browseResults = {
      { itemKey = { itemID = 1, itemLevel = 28 }, totalQuantity = 3, minPrice = 890 },
      { itemKey = { itemID = 2, itemLevel = 30 }, totalQuantity = 1, minPrice = 1250 },
      { itemKey = { itemID = 3, itemLevel = 30 }, totalQuantity = 2, minPrice = 600 },
    }
  end

  it("is the first Buy entry and takes the detail panel's room", function()
    local _, w, _, view = browse()
    assert.equal("Browse", w.heading:GetText())
    assert.is_true(view.panel:IsShown())
    assert.is_false(w.detailPanel:IsShown())
    assert.is_false(w.placeholder:IsShown())
    w:select("prices")
    assert.is_true(w.detailPanel:IsShown(), "other views get the detail panel back")
    assert.is_false(view.container:IsShown())
  end)

  it("searches with the typed name and levels and lists the results cheapest first", function()
    local env, w, ns, view = browse()
    results(env)
    ns.prices:recordScan(w:market(), env.now,
      { { item = "i:1", name = "Ridgeback Bracers", count = 1, buyout = 1420 } })
    view.searchBox:SetText("bracers")
    view.minLevel:SetText("30")
    view.maxLevel:SetText("21")
    view.searchButton:Click()
    assert.equal("Searching the auction house...", view.status:GetText())
    assert.is_false(view.searchButton:IsEnabled(), "one search at a time")
    env.runTimers()
    local q = env.browses[#env.browses]
    assert.equal("bracers", q.searchString)
    assert.equal(21, q.minLevel)
    assert.equal(30, q.maxLevel)
    assert.equal("Loading item...", view.rows[1][1]:GetText(), "item 3 is cheapest but its name isn't loaded")
    assert.equal("Ridgeback Bracers", view.rows[2][1]:GetText())
    assert.equal("8s 90c", view.rows[2][4]:GetText())
    assert.equal("14s 20c", view.rows[2][5]:GetText())
    assert.equal("63%", view.rows[2][6]:GetText())
    assert.same(ns.BrowseView.TONES.cheap, view.rows[2][6].textColor)
    assert.equal("12s 50c", view.rows[3][4]:GetText())
    assert.equal("-", view.rows[3][6]:GetText(), "no market value, no percent")
    assert.truthy(view.status:GetText():find('^3 items for "bracers", level 21%-30%. Searched'))
    assert.is_true(view.searchButton:IsEnabled())
  end)

  it("sorts by a clicked header and reverses on a second click", function()
    local env, _, _, view = browse()
    results(env)
    view.searchButton:Click()
    env.runTimers()
    view.headers[1]:Click()
    assert.equal("Battleforge Shoulderpads", view.rows[1][1]:GetText())
    assert.is_true(view.headers[1].arrow:IsShown())
    assert.is_false(view.headers[4].arrow:IsShown())
    view.headers[1]:Click()
    assert.equal("Ridgeback Bracers", view.rows[1][1]:GetText())
    assert.equal("Loading item...", view.rows[3][1]:GetText(), "unknown names stay last")
    assert.same({ 0, 1, 1, 0 }, view.headers[1].arrow.texCoord)
  end)

  it("redraws names once the client loads them", function()
    local env, _, _, view = browse()
    results(env)
    view.searchButton:Click()
    env.runTimers()
    env.itemNames[3] = "Ironforge Chain"
    env.fire("ITEM_KEY_ITEM_INFO_RECEIVED", 3)
    env.runTimers(1)
    assert.equal("Ironforge Chain", view.rows[1][1]:GetText())
  end)

  it("says so when the levels are wrong, the house is busy or the search fails", function()
    local env, _, ns, view = browse()
    view.minLevel:SetText("abc")
    view.searchButton:Click()
    assert.truthy(view.status:GetText():find("whole numbers"))
    view.minLevel:SetText("")
    ns.snipeAPI.browsing = {}
    view.searchButton:Click()
    assert.truthy(view.status:GetText():find("Disenchant sniping is checking"))
    ns.snipeAPI.browsing = nil
    view.searchButton:Click()
    env.fire("AUCTION_HOUSE_BROWSE_FAILURE")
    assert.equal("The search failed: the auction house couldn't browse.", view.status:GetText())
  end)

  it("asks for the auction house when it is closed", function()
    local env, w, _, view = browse()
    env.CloseAuctionHouse()
    w.model.mode = "better"
    view:search()
    assert.equal("Open the auction house to search.", view.status:GetText())
  end)

  it("searches a shift-clicked item's name while the box has focus", function()
    local env, _, _, view = browse()
    view.searchBox:SetFocus()
    view:insertLink("|cff1eff00|Hitem:1::::::::20:::::|h[Ridgeback Bracers]|h|r")
    assert.equal("Ridgeback Bracers", env.browses[#env.browses].searchString)
    view:insertLink("|cff1eff00|Hitem:2::::::::20:::::|h[Other]|h|r")
    assert.equal(1, #env.browses, "no focus, no search")
  end)

  it("tells the player when a search hits the page limit", function()
    local env, _, ns, view = browse()
    results(env)
    ns.SnipeAPI.MAX_PAGES = 0
    env.browsePages = { {} }
    view.searchButton:Click()
    env.runTimers()
    ns.SnipeAPI.MAX_PAGES = 10
    assert.truthy(view.status:GetText():find("first ones only"))
  end)
end)

describe("Browse view, after review", function()
  local function browse()
    local env, w, ns = setup()
    env.openAuctionHouse()
    w:select("browse")
    env.itemNames = { [1] = "Ridgeback Bracers", [2] = "Battleforge Shoulderpads" }
    env.browseResults = {
      { itemKey = { itemID = 1, itemLevel = 28 }, totalQuantity = 3, minPrice = 890 },
      { itemKey = { itemID = 2, itemLevel = 30 }, totalQuantity = 1, minPrice = 1250 },
    }
    return env, w, ns, w.browseView
  end

  it("ignores Enter during its own search and shows the results' summary after", function()
    local env, _, _, view = browse()
    view:search()
    view:search()
    assert.equal(1, #env.browses)
    env.runTimers()
    assert.truthy(view.status:GetText():find("^2 items"))
  end)

  it("clears an earlier message when results arrive", function()
    local env, _, ns, view = browse()
    ns.snipeAPI.browsing = {}
    view:search()
    assert.truthy(view.status:GetText():find("Disenchant sniping"))
    ns.snipeAPI.browsing = nil
    view:search()
    env.runTimers()
    assert.truthy(view.status:GetText():find("^2 items"))
  end)

  it("keeps the selected item across a redraw and fills in levels as they load", function()
    local env, _, _, view = browse()
    env.GetItemInfo = function(id)
      if env.levels and env.levels[id] then return "x", "link", 2, 30, env.levels[id] end
    end
    view:search()
    env.runTimers()
    view.selected = view.results.rows[1].itemKey
    view:render()
    assert.is_true(view.rows[1].button.selectedTexture:IsShown())
    assert.equal("-", view.rows[1][2]:GetText())
    env.levels = { [1] = 23, [2] = 25 }
    env.fire("GET_ITEM_INFO_RECEIVED", 1)
    env.runTimers(1)
    assert.equal("23", view.rows[1][2]:GetText())
    assert.is_true(view.rows[1].button.selectedTexture:IsShown(), "still selected after the rebuild")
  end)

  it("stops rebuilding when nothing new loads, and forgets results when the house closes", function()
    local env, w, _, view = browse()
    view:search()
    env.runTimers()
    local calls = 0
    local rebuild = view.rebuild
    view.rebuild = function(v) calls = calls + 1; return rebuild(v) end
    for _ = 1, 10 do
      env.fire("GET_ITEM_INFO_RECEIVED", 1)
      env.runTimers(1)
    end
    assert.is_true(calls <= w.browseView.MAX_IDLE_REBUILDS, "gave up after a few rebuilds")
    env.CloseAuctionHouse()
    assert.is_nil(view.results)
  end)
end)

describe("Browse item page", function()
  local function setupItem()
    local env, w, ns = setup()
    env.openAuctionHouse()
    w:select("browse")
    env.guid = "Player-1"
    env.itemNames = { [10] = "Battleforge Shoulderpads", [20] = "Strange Dust" }
    env.browseResults = {
      { itemKey = { itemID = 10, itemLevel = 30 }, totalQuantity = 3, minPrice = 1250 },
      { itemKey = { itemID = 20, itemLevel = 0 }, totalQuantity = 34, minPrice = 98 },
    }
    env.listings[10] = { item = true,
      { auctionID = 7, buyoutAmount = 1500, bidAmount = 1120, minBid = 1180, timeLeft = 2, owners = { "Mirelle" } },
      { auctionID = 5, buyoutAmount = 1250, minBid = 900, timeLeft = 3, owners = { "Grukdar" } },
      { auctionID = 9, buyoutAmount = 1750, minBid = 1200, containsOwnerItem = true },
    }
    env.listings[20] = { { unitPrice = 110, quantity = 20 }, { unitPrice = 98, quantity = 6 },
      { unitPrice = 102, quantity = 8 } }
    local view = w.browseView
    view.searchButton:Click()
    env.runTimers()
    return env, w, ns, view
  end
  local function open(view, env, name)
    for _, cells in ipairs(view.rows) do
      if cells[1]:GetText() == name then cells.button:Click() break end
    end
    env.runTimers()
    return view.item
  end

  it("opens an item's auctions with the buy controls on the detail panel", function()
    local env, w, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    assert.is_false(view.panel:IsShown())
    assert.is_true(item.panel:IsShown())
    assert.is_true(w.detailPanel:IsShown(), "the detail panel comes back for the buy controls")
    assert.equal("Battleforge Shoulderpads", item.nameText:GetText())
    assert.equal("12s 50c", item.itemRows[1][1]:GetText())
    assert.equal("Grukdar", item.itemRows[1][4]:GetText())
    assert.equal("11s 20c", item.itemRows[2][2]:GetText())
    assert.equal("You", item.itemRows[3][4]:GetText())
    assert.same({ 0.6, 0.6, 0.6 }, item.itemRows[3][1].textColor)
    assert.is_true(item.itemControls.buy:IsShown())
    assert.is_false(item.itemControls.buy:IsEnabled(), "nothing selected yet")
    item.backButton:Click()
    assert.is_true(view.panel:IsShown())
    assert.is_false(w.detailPanel:IsShown())
    assert.is_false(item.itemControls.buy:IsShown())
  end)

  it("buys out the selected auction and looks again", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    local searches = #env.searches
    item.itemRows[1].button:Click()
    assert.equal("Buy out for 12s 50c", item.itemControls.buy:GetText())
    assert.is_true(item.itemControls.buy:IsEnabled())
    item.itemControls.buy:Click()
    assert.same({ auctionID = 5, amount = 1250 }, env.bids[1])
    env.runTimers()
    assert.equal("Bought Battleforge Shoulderpads for 12s 50c.", item.messageText:GetText())
    assert.equal(searches + 1, #env.searches, "the auctions are looked up again")
  end)

  it("bids at least the lowest bid, filled in on selection", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[2].button:Click()
    local boxes = item.itemControls.boxes
    assert.same({ "", "11", "80" }, { boxes[1]:GetText(), boxes[2]:GetText(), boxes[3]:GetText() })
    boxes[3]:SetText("0")
    item:renderDetail()
    assert.is_false(item.itemControls.bid:IsEnabled(), "under the lowest bid")
    boxes[2]:SetText("12")
    item:renderDetail()
    item.itemControls.bid:Click()
    assert.same({ auctionID = 7, amount = 1200 }, env.bids[1])
    env.runTimers(5)
    assert.truthy(item.messageText:GetText():find("^Bid 12s 0c sent"))
  end)

  it("takes only a bid-placed notice as the bid's answer (#163)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[2].button:Click()
    item.itemControls.boxes[2]:SetText("12")
    item:renderDetail()
    env.C_AuctionHouse.PlaceBid = function() end -- the answer comes as a notification
    item.itemControls.bid:Click()
    env.runTimers(0)
    env.fire("AUCTION_HOUSE_SHOW_NOTIFICATION", 4) -- AuctionSold, about another auction
    assert.equal("Bidding...", item.messageText:GetText(), "not this bid's answer")
    env.fire("AUCTION_HOUSE_SHOW_NOTIFICATION", 0) -- BidPlaced
    assert.truthy(item.messageText:GetText():find("^Bid 12s 80c sent"))
  end)

  it("can't buy your own auction", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[3].button:Click()
    assert.is_false(item.itemControls.buy:IsEnabled())
    assert.is_false(item.itemControls.bid:IsEnabled())
  end)

  it("buys a quantity of a commodity after a quote and a confirm", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    assert.is_true(item.commodityList:IsShown())
    assert.equal("98c", item.commodityRows[1][1]:GetText())
    assert.equal("14 for 14s 4c", item.commodityRows[2][3]:GetText())
    local c = item.commodityControls
    c.quantity:SetText("20")
    item:quantityChanged() -- the client's OnTextChanged
    assert.is_true(item.commodityRows[3].button.selectedTexture:IsShown())
    assert.equal("20 (6 of them)", item.commodityRows[3][2]:GetText())
    assert.equal("Buy 20 for 20s 64c", c.buy:GetText())
    env.quote = function(_, qty) return 106, qty * 105 + 52 end
    c.buy:Click()
    assert.same({ itemID = 20, quantity = 20 }, env.quoted)
    env.runTimers()
    assert.is_true(c.confirm:IsShown())
    assert.truthy(c.confirmText:GetText():find("The price went up: 20 now cost 21s 52c"))
    assert.equal(0, #env.commodityBuys)
    c.confirm:Click()
    env.runTimers()
    assert.same({ itemID = 20, quantity = 20 }, env.commodityBuys[1])
    assert.equal("Bought 20 Strange Dust for 21s 52c.", item.messageText:GetText())
    assert.is_false(c.confirm:IsShown())
  end)

  it("confirms a quote when more were typed than are for sale (#163)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("5000")
    item:quantityChanged()
    local qty = item.ladder.quantity
    assert.is_true(qty < 5000, "cut to what is listed")
    env.quote = function(_, q) return 100, q * 100 end
    c.buy:Click()
    env.runTimers()
    item.ladder.quantity = qty - 10 -- a Refresh found fewer for sale since the quote
    c.confirm:Click()
    env.runTimers()
    assert.same({ itemID = 20, quantity = qty }, env.commodityBuys[1], "the server's quote still stands")
  end)

  it("says the quote ran out instead of confirming a stale one (#163)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    local left = 30
    env.C_AuctionHouse.GetQuoteDurationRemaining = function() return left end
    env.quote = function(_, q) return 98, q * 98 end
    c.buy:Click()
    env.runTimers()
    left = 0
    c.confirm:Click()
    env.runTimers()
    assert.equal(0, #env.commodityBuys)
    assert.equal(1, env.quoteCancelled)
    assert.truthy(item.messageText:GetText():find("quote ran out", 1, true))
  end)

  it("still confirms on a client that always says no quote time is left (#163)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    env.C_AuctionHouse.GetQuoteDurationRemaining = function() return 0 end
    env.quote = function(_, q) return 98, q * 98 end
    c.buy:Click()
    env.runTimers()
    c.confirm:Click()
    env.runTimers()
    assert.equal(1, #env.commodityBuys)
  end)

  it("starts a commodity at 1, and goes back to 1 after a buy (#125)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    assert.equal("1", c.quantity:GetText())
    assert.truthy(c.buy:GetText():find("^Buy 1 for "))
    assert.is_true(c.buy:IsEnabled())
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    env.runTimers()
    assert.is_true(c.confirm:IsShown())
    c.confirm:Click()
    env.runTimers()
    assert.same({ itemID = 20, quantity = 1 }, env.commodityBuys[1])
    assert.equal("1", c.quantity:GetText())
  end)

  it("sets the quantity from Max or a clicked row, and cancels a quote", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    env.money = 6 * 98 + 102
    c.max:Click()
    assert.equal("7", c.quantity:GetText())
    item.commodityRows[2].button:Click()
    assert.equal("14", c.quantity:GetText())
    env.money = 100000
    env.fire("PLAYER_MONEY")
    env.quote = function(_, qty) return 100, qty * 100 end
    c.buy:Click()
    env.runTimers()
    c.cancel:Click()
    assert.equal(1, env.quoteCancelled)
    assert.is_false(c.confirm:IsShown())
  end)

  it("closes the item page when the auction house closes", function()
    local env, w, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    env.CloseAuctionHouse()
    assert.is_nil(item.row)
    assert.is_true(view:wide())
    w.model.mode = "better"
    w:select("prices")
    assert.is_false(item.commodityControls.buy:IsShown())
  end)
end)

describe("Browse item page, after review", function()
  local function setupItem()
    local env, w, ns = setup()
    env.openAuctionHouse()
    w:select("browse")
    env.itemNames = { [10] = "Battleforge Shoulderpads", [20] = "Strange Dust" }
    env.browseResults = {
      { itemKey = { itemID = 10, itemLevel = 30 }, totalQuantity = 1, minPrice = 1250 },
      { itemKey = { itemID = 20, itemLevel = 0 }, totalQuantity = 6, minPrice = 98 },
    }
    env.listings[10] = { item = true, { auctionID = 5, buyoutAmount = 1250, minBid = 900, owners = { "Grukdar" } } }
    env.listings[20] = { { unitPrice = 98, quantity = 6 } }
    w.browseView.searchButton:Click()
    env.runTimers()
    return env, w, ns, w.browseView
  end
  local function open(view, env, name)
    for _, cells in ipairs(view.rows) do
      if cells[1]:GetText() == name then cells.button:Click() break end
    end
    env.runTimers()
    return view.item
  end

  it("keeps its buy controls off other views, whatever redraws it", function()
    local env, w, _, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[1].button:Click()
    w:select("disenchant")
    env.fire("PLAYER_MONEY")
    item:load()
    env.runTimers()
    assert.is_false(item.itemControls.buy:IsShown())
    w:select("browse")
    assert.is_true(item.itemControls.buy:IsShown(), "back on Browse, the page is still open")
  end)

  it("frees the buttons when a pending quote is dropped, and never confirms an old quantity", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("3")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    c.quantity:SetText("1")
    item:quantityChanged()
    env.runTimers()
    assert.is_nil(item.quoted, "the quote for 3 is dropped")
    assert.is_nil(item.busy)
    c.buy:Click()
    item.backButton:Click()
    env.runTimers()
    open(view, env, "Strange Dust")
    assert.is_nil(view.item.busy, "reopening starts free")
  end)

  it("asks for an item's auctions ahead of the background searches (#122)", function()
    local _, _, ns = setupItem()
    local posting = ns.browseAPI:posting()
    local search = posting.search
    local first
    posting.search = function(_, _, _, f) first = f end
    ns.browseAPI:auctions({ itemID = 1, name = "x" }, function() end)
    posting.search = search
    assert.is_true(first)
  end)

  it("says a timed-out commodity buy may have gone through, and reports a late success", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("2")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    env.runTimers()
    local confirm = env.C_AuctionHouse.ConfirmCommoditiesPurchase
    env.C_AuctionHouse.ConfirmCommoditiesPurchase = function() end
    c.confirm:Click()
    env.runTimers(ns.BrowseAPI.TIMEOUT + 1)
    assert.truthy(item.messageText:GetText():find("may have gone through"))
    env.C_AuctionHouse.ConfirmCommoditiesPurchase = confirm
    env.fire("COMMODITY_PURCHASE_SUCCEEDED")
    assert.truthy(item.messageText:GetText():find("^Bought 2 Strange Dust"))
  end)

  it("drops an open quote when another view shows, so the sniper isn't held up", function()
    local env, w, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    item.commodityControls.quantity:SetText("2")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    item.commodityControls.buy:Click()
    env.runTimers()
    assert.is_true(ns.postingAPI.buying)
    w:select("disenchant")
    assert.is_nil(ns.postingAPI.buying)
    assert.is_nil(ns.browseAPI.commodity)
  end)

  it("drops an open quote when the auction house closes, so buys work after reopening (#161)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    item.commodityControls.quantity:SetText("20")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    item.commodityControls.buy:Click()
    env.runTimers()
    assert.equal("quoted", ns.browseAPI.commodity.step)
    local cancelled = env.quoteCancelled or 0
    env.CloseAuctionHouse()
    assert.is_nil(ns.browseAPI.commodity)
    assert.is_nil(ns.postingAPI.buying)
    assert.equal(cancelled + 1, env.quoteCancelled, "the client's quote is cancelled too")
    env.openAuctionHouse()
    assert.is_nil(ns.browseAPI:blocked())
    local bids = #env.bids
    ns.snipeAPI:buy(1, 100, function() end)
    assert.equal(bids + 1, #env.bids, "a snipe buy is sent")
  end)

  it("cancels a quote still waiting for its price when the auction house closes (#161)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    item.commodityControls.quantity:SetText("2")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    item.commodityControls.buy:Click()
    assert.equal("quote", ns.browseAPI.commodity.step)
    local cancelled = env.quoteCancelled or 0
    env.CloseAuctionHouse()
    assert.equal(cancelled + 1, env.quoteCancelled)
    assert.is_nil(ns.browseAPI.commodity)
    assert.is_nil(ns.postingAPI.buying)
  end)

  it("names the price quote when the game blocks it as UNKNOWN(), and frees the buttons (#108)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("1")
    item:quantityChanged()
    env.blockQuote = { "BetterAH", "UNKNOWN()" }
    c.buy:Click()
    assert.is_true(item.busy, "a price may still come for a while")
    env.runTimers(ns.BrowseAPI.BLOCK_GRACE + 1)
    assert.equal("No price: the game blocked StartCommoditiesPurchase. Click Buy to try again.",
      item.messageText:GetText())
    assert.is_nil(item.busy)
    assert.is_nil(ns.browseAPI.commodity)
    assert.is_nil(ns.postingAPI.buying)
    env.blockQuote = nil
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    env.runTimers()
    assert.is_true(c.confirm:IsShown(), "a second try works")
  end)

  it("calls StartCommoditiesPurchase directly, so its errors are not swallowed (#108)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    item.commodityControls.quantity:SetText("1")
    item:quantityChanged()
    env.C_AuctionHouse.StartCommoditiesPurchase = function() error("boom") end
    assert.has_error(function() item.commodityControls.buy:Click() end)
    env.runTimers(ns.BrowseAPI.TIMEOUT + 1)
    assert.truthy(item.messageText:GetText():find("the price request failed", 1, true))
    assert.is_nil(item.busy)
  end)

  it("does not count a bid whose call threw as placed", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[1].button:Click()
    assert.is_true(item.itemControls.bid:IsEnabled(), "the lowest bid is filled in")
    env.C_AuctionHouse.PlaceBid = function() error("boom") end
    assert.has_error(function() item.itemControls.bid:Click() end)
    env.runTimers(ns.BrowseAPI.BID_SETTLE + 1)
    assert.is_nil(ns.browseAPI.placing)
    assert.is_nil(ns.browseAPI.bidding)
    assert.truthy(item.messageText:GetText():find("^Bid not placed"))
  end)

  it("still shows a price that comes after a block (#112)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("2")
    item:quantityChanged()
    local start = env.C_AuctionHouse.StartCommoditiesPurchase
    env.C_AuctionHouse.StartCommoditiesPurchase = function(itemID, quantity)
      env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "UNKNOWN()")
      return start(itemID, quantity)
    end
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    env.runTimers()
    assert.is_true(c.confirm:IsShown(), "the price came: Confirm is offered")
    env.runTimers(ns.BrowseAPI.BLOCK_GRACE + 1)
    assert.is_true(c.confirm:IsShown(), "the block doesn't undo the quote")
  end)

  it("sends the purchase before redrawing, so the clicked button is still as clicked (#120)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("1")
    item:quantityChanged()
    local start, seen = env.C_AuctionHouse.StartCommoditiesPurchase, nil
    env.C_AuctionHouse.StartCommoditiesPurchase = function(...)
      seen = { enabled = c.buy:IsEnabled(), message = item.messageText:GetText() }
      return start(...)
    end
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    assert.is_true(seen.enabled, "Buy is still enabled when the game is asked")
    assert.are_not.equal("Asking for the price...", seen.message, "nothing redrawn yet")
    assert.equal("Asking for the price...", item.messageText:GetText(), "drawn right after")
    assert.is_false(c.buy:IsEnabled())
    local item2 = open(view, env, "Battleforge Shoulderpads")
    item2.itemRows[1].button:Click()
    local placeBid, bidSeen = env.C_AuctionHouse.PlaceBid, nil
    env.C_AuctionHouse.PlaceBid = function(...)
      bidSeen = item2.itemControls.buy:IsEnabled()
      return placeBid(...)
    end
    item2.itemControls.buy:Click()
    assert.is_true(bidSeen, "Buy out is still enabled when PlaceBid runs")
  end)

  it("asks for the price on Enter in the quantity box (#120)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("2")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    c.quantity.scripts.OnEnterPressed(c.quantity)
    env.runTimers()
    assert.is_true(c.confirm:IsShown())
    local asked = 0
    local start = env.C_AuctionHouse.StartCommoditiesPurchase
    env.C_AuctionHouse.StartCommoditiesPurchase = function(...) asked = asked + 1 return start(...) end
    c.quantity.scripts.OnEnterPressed(c.quantity)
    assert.equal(0, asked, "Enter doesn't ask again over a quote that is showing")
  end)

  it("ignores another addon's block while a quote is asked for (#108)", function()
    local env, _, _, view = setupItem()
    local item = open(view, env, "Strange Dust")
    item.commodityControls.quantity:SetText("1")
    item:quantityChanged()
    env.blockQuote = { "OtherAddon", "Foo()" }
    item.commodityControls.buy:Click()
    assert.is_true(item.busy, "still waiting for the quote")
  end)

  -- #162: a buy's answer can come after the page has moved on. It is booked for the item that was bought.
  local function booked(ns)
    local out = {}
    for _, e in ipairs(ns.ledger.store.entries) do
      if e.k == "buy" then out[#out + 1] = { item = e.item, name = e.name, n = e.n, c = e.c, src = e.src } end
    end
    return out
  end

  it("books a buyout answered after leaving the item page (#162)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[1].button:Click()
    local placeBid = env.C_AuctionHouse.PlaceBid
    env.C_AuctionHouse.PlaceBid = function(id, amount) env.bids[#env.bids + 1] = { auctionID = id, amount = amount } end
    item.itemControls.buy:Click()
    item.backButton:Click()
    assert.is_nil(item.row, "the page is closed before the answer")
    env.C_AuctionHouse.PlaceBid = placeBid
    env.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 5)
    env.runTimers()
    assert.same({ { item = 10, name = "Battleforge Shoulderpads", n = 1, c = 1250, src = "Browse" } }, booked(ns))
    assert.is_truthy(ns.purchases:paid("i:10"), "You paid is recorded")
    assert.is_nil(item.row, "the closed page stays closed")
  end)

  it("books a late buyout success without touching the page's next buy (#162)", function()
    local env, _, ns, view = setupItem()
    env.listings[10][2] = { auctionID = 6, buyoutAmount = 1300, minBid = 900, owners = { "Grukdar" } }
    local item = open(view, env, "Battleforge Shoulderpads")
    item.itemRows[1].button:Click()
    local placeBid = env.C_AuctionHouse.PlaceBid
    env.C_AuctionHouse.PlaceBid = function(id, amount) env.bids[#env.bids + 1] = { auctionID = id, amount = amount } end
    item.itemControls.buy:Click()
    env.runTimers(10)
    assert.truthy(item.messageText:GetText():find("No answer", 1, true))
    item.itemRows[2].button:Click()
    item.itemControls.buy:Click()
    assert.is_true(item.busy, "the second buy waits")
    env.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 5)
    assert.is_true(item.busy, "the late answer to the first buy doesn't free the buttons")
    assert.equal(1, #booked(ns), "but it is booked")
    env.C_AuctionHouse.PlaceBid = placeBid
  end)

  it("books a late commodity success under the item bought, not the one open now (#162)", function()
    local env, _, ns, view = setupItem()
    local item = open(view, env, "Strange Dust")
    local c = item.commodityControls
    c.quantity:SetText("2")
    item:quantityChanged()
    env.quote = function(_, qty) return 98, qty * 98 end
    c.buy:Click()
    env.runTimers()
    local confirm = env.C_AuctionHouse.ConfirmCommoditiesPurchase
    env.C_AuctionHouse.ConfirmCommoditiesPurchase = function() end
    c.confirm:Click()
    env.runTimers(ns.BrowseAPI.TIMEOUT + 1)
    env.C_AuctionHouse.ConfirmCommoditiesPurchase = confirm
    item = open(view, env, "Battleforge Shoulderpads")
    assert.equal(10, item.row.itemID)
    env.fire("COMMODITY_PURCHASE_SUCCEEDED")
    env.runTimers()
    assert.same({ { item = 20, name = "Strange Dust", n = 2, c = 196, src = "Browse" } }, booked(ns))
    assert.is_truthy(ns.purchases:paid("i:20"))
    assert.is_nil(ns.purchases:paid("i:10"), "nothing booked for the item open now")
    assert.is_nil((item.messageText:GetText() or ""):find("Bought", 1, true),
      "the other item's page doesn't say it was bought")
  end)
end)

describe("My auctions view (#123)", function()
  local DUST, PADS, BAR, SHARD = 11176, 7000, 12359, 14344
  local function owned(env)
    env.owned = {
      { id = 101, itemID = DUST, quantity = 20, buyout = 185, timeLeftSeconds = 86400, cost = 18,
        link = "|cffffffff|Hitem:11176::::::::60:::::|h[Arcane Dust]|h|r" },
      { id = 102, itemID = PADS, quantity = 1, buyout = 1500, timeLeftSeconds = 7000, cost = 42,
        link = "|cff1eff00|Hitem:7000::::::::60:::::|h[Battleforge Shoulderpads]|h|r" },
      { id = 103, itemID = BAR, quantity = 20, buyout = 3800, timeLeftSeconds = 86400, cost = 30,
        link = "|cffffffff|Hitem:12359::::::::60:::::|h[Thorium Bar]|h|r" },
      { id = 104, itemID = SHARD, quantity = 2, buyout = 11000, status = 1, timeLeftSeconds = 2700,
        link = "|cff0070dd|Hitem:14344::::::::60:::::|h[Large Brilliant Shard]|h|r" },
    }
    env.listings[DUST] = { { unitPrice = 179, quantity = 100 }, { unitPrice = 185, quantity = 20, numOwnerItems = 20 } }
    env.listings[PADS] = { item = true, { buyoutAmount = 1250, quantity = 1 },
      { buyoutAmount = 1500, quantity = 1, containsOwnerItem = true } }
    env.listings[BAR] = { { unitPrice = 3800, quantity = 20, numOwnerItems = 20 }, { unitPrice = 4000, quantity = 5 } }
  end

  local function open(opts)
    local env, w, ns = setup(opts)
    owned(env)
    env.openAuctionHouse()
    env.runTimers()
    sidebarButton(w, "auctions"):Click()
    env.runTimers()
    return env, w, ns, w.myAuctionsView
  end

  local function statusOf(v, name)
    for _, cells in ipairs(v.rows) do
      if (cells[1]:GetText() or ""):find(name, 1, true) then return cells[6]:GetText() end
    end
  end

  it("is called My auctions in the sidebar, under Sell", function()
    local _, w = setup()
    assert.equal("My auctions", w.model:label("auctions"))
    assert.is_nil(w.model:label("cancel"))
  end)

  it("lists every auction, checks each item's price once, and marks the undercut ones", function()
    local env, w, _, v = open()
    assert.is_true(w.myAuctionsPanel:IsShown())
    assert.equal(3, #env.searches, "one search per item up for sale; the sold one isn't looked up")
    assert.matches("Undercut by 6c", statusOf(v, "Arcane Dust"))
    assert.matches("Undercut by 2s 50c", statusOf(v, "Battleforge Shoulderpads"))
    assert.matches("Lowest", statusOf(v, "Thorium Bar"))
    assert.matches("Sold, gold in 45 min", statusOf(v, "Large Brilliant Shard"))
    assert.matches("Arcane Dust", v.rows[1][1]:GetText(), "undercut auctions come first")
    assert.matches("Large Brilliant Shard", v.rows[4][1]:GetText(), "sold ones last")
    assert.equal("All 4", v.filterButtons.all:GetText())
    assert.equal("Undercut 2", v.filterButtons.undercut:GetText())
    assert.matches("My auctions.*2", sidebarButton(w, "auctions"):GetText(), "the sidebar counts undercut auctions")
    assert.matches("3 auctions · listed for", v.footer:GetText())
    assert.matches("· 1 sold, you get 1g 4s$", v.footer:GetText(), "11000 sold, 10450 after the cut")
    assert.matches("Prices checked", v.status:GetText())
    assert.matches("Undercut: 2%. Cancelling them all loses 60c in deposits", w.detailBody:GetText())
  end)

  it("filters to the undercut auctions", function()
    local _, _, _, v = open()
    v.filterButtons.undercut:Click()
    assert.matches("Arcane Dust", v.rows[1][1]:GetText())
    assert.matches("Battleforge", v.rows[2][1]:GetText())
    assert.is_false(v.rows[3].button:IsShown())
  end)

  it("explains a selected auction and cancels it in the click, then moves to the next undercut", function()
    local env, w, _, v = open()
    v.rows[1].button:Click()
    assert.matches("Arcane Dust", w.detailTitle:GetText())
    local body = w.detailBody:GetText()
    assert.matches("Your price: 1s 85c each %(37s 0c%)", body)
    assert.matches("Lowest that isn't yours: 1s 79c", body)
    assert.matches("Cheaper than yours: 100 units", body)
    assert.matches("Deposit you lose: 18c", body)
    assert.matches("comes back by mail", body)
    assert.is_true(v.cancelButton:IsShown())
    v.cancelButton:Click()
    assert.same({ 101 }, env.cancels, "cancelled inside the click")
    assert.matches("Battleforge", w.detailTitle:GetText(), "the next undercut is selected for the next click")
    v.cancelButton:Click()
    assert.same({ 101, 102 }, env.cancels)
    env.runTimers()
    assert.matches("Cancelled Battleforge Shoulderpads%. It comes back by mail", v.note:GetText())
    assert.equal("All 2", v.filterButtons.all:GetText(), "the list is read again after the cancels")
    assert.is_false(v.nextButton:IsEnabled())
  end)

  it("cancels the next undercut from the detail panel's button, one per click", function()
    local env, _, _, v = open()
    assert.equal("Cancel next undercut (2 left)", v.nextButton:GetText())
    v.nextButton:Click()
    assert.same({ 101 }, env.cancels)
    assert.equal("Cancel next undercut (1 left)", v.nextButton:GetText())
    v.nextButton:Click()
    v.nextButton:Click()
    assert.same({ 101, 102 }, env.cancels, "nothing more to cancel")
  end)

  it("doesn't offer to cancel a sold auction", function()
    local env, _, _, v = open()
    v.rows[4].button:Click()
    assert.is_false(v.cancelButton:IsEnabled())
    v.cancelButton:Click()
    assert.same({}, env.cancels)
  end)

  it("waits for the auctions list when a cancel gets no answer, then lets it be tried again (#163)", function()
    local env, _, _, v = open()
    env.cancelSilent = true
    local query = env.C_AuctionHouse.QueryOwnedAuctions
    env.C_AuctionHouse.QueryOwnedAuctions = function() end -- the list comes later
    v.rows[1].button:Click()
    v.cancelButton:Click()
    env.runTimers(10)
    assert.matches("No answer yet about cancelling Arcane Dust", v.note:GetText(), 1, true)
    v.rows[1].button:Click()
    assert.is_false(v.cancelButton:IsEnabled(), "never sent twice while it may still go through")
    v.cancelButton:Click()
    assert.same({ 101 }, env.cancels)
    query() -- the list the timeout asked for still has it
    env.runTimers()
    assert.matches("The auction house didn't cancel Arcane Dust. You can try again.", v.note:GetText(), 1, true)
    v.rows[1].button:Click()
    assert.is_true(v.cancelButton:IsEnabled())
  end)

  it("counts a slow cancel as done once the auctions list no longer has it (#163)", function()
    local env, _, _, v = open()
    env.cancelSilent = true
    v.rows[1].button:Click()
    v.cancelButton:Click()
    table.remove(env.owned, 1) -- the server cancelled it, but never said so
    env.runTimers(10)
    env.runTimers()
    assert.matches("Cancelled 20 Arcane Dust. It comes back by mail", v.note:GetText(), 1, true)
  end)

  it("counts a late answer to a cancel (#163)", function()
    local env, _, ns, v = open()
    env.cancelSilent = true
    env.C_AuctionHouse.QueryOwnedAuctions = function() end -- the list is slow too
    v.rows[1].button:Click()
    v.cancelButton:Click()
    env.runTimers(10)
    assert.matches("No answer yet", v.note:GetText(), 1, true)
    env.fire("AUCTION_CANCELED", 101)
    assert.matches("Cancelled 20 Arcane Dust", v.note:GetText(), 1, true)
    assert.is_nil(ns.myAuctionsAPI.late[101])
  end)

  it("starts afresh on the next visit", function()
    local env, _, _, v = open()
    env.CloseAuctionHouse()
    assert.is_nil(v.visit)
    assert.is_false(v.cancelButton:IsShown())
    env.searches = {}
    env.openAuctionHouse()
    env.runTimers()
    env.runTimers()
    assert.equal(3, #env.searches, "prices are checked again")
  end)
end)

describe("My auctions view, after review (#123)", function()
  local DUST, CINCH = 11176, 9800
  local function setupOwned(opts)
    local env, w, ns = setup(opts)
    env.owned = {
      { id = 101, itemID = DUST, quantity = 20, buyout = 185, timeLeftSeconds = 86400 },
      { id = 102, itemID = CINCH, quantity = 1, buyout = 2200, timeLeftSeconds = 86400,
        itemKey = { itemID = CINCH, itemLevel = 0, itemSuffix = 1017 } },
    }
    env.listings[DUST] = { { unitPrice = 179, quantity = 100 }, { unitPrice = 181, quantity = 50 } }
    env.listings[CINCH] = { item = true, { buyoutAmount = 1900, quantity = 1 }, { buyoutAmount = 2000, quantity = 1 },
      { buyoutAmount = 2100, quantity = 1 } }
    return env, w, ns
  end

  it("counts a commodity's check toward market value, but not a random-suffix variant's", function()
    local env, w, ns = setupOwned()
    env.now = 1000000
    env.openAuctionHouse()
    env.runTimers()
    w:select("auctions")
    env.runTimers()
    local key = ns.AuctionAPI.currentMarket(env)
    assert.is_not_nil(ns.prices:marketValue(key, "i:" .. DUST, env.now))
    assert.is_nil(ns.prices:marketValue(key, "i:" .. CINCH, env.now), "one suffix doesn't price the whole item")
  end)

  it("takes back checks still waiting when you leave, and finishes them when you come back", function()
    local env, w = setupOwned()
    env.openAuctionHouse()
    env.runTimers()
    w:select("auctions")
    assert.equal(1, #env.searches, "the first check is running")
    w:select("post")
    env.runTimers()
    local searched = #env.searches
    w:select("auctions")
    env.runTimers()
    assert.equal(searched + 1, #env.searches, "only the item not checked yet is looked up")
    local v = w.myAuctionsView
    assert.matches("Prices checked", v.status:GetText())
  end)

  it("clears the sidebar count when the auction house closes", function()
    local env, w = setupOwned()
    env.openAuctionHouse()
    env.runTimers()
    w:select("auctions")
    env.runTimers()
    assert.matches("My auctions.*2", w.buttons.auctions:GetText())
    env.CloseAuctionHouse()
    assert.equal("My auctions", w.buttons.auctions:GetText())
  end)

  it("doesn't take another auction's cancel answer for ours", function()
    local env, w, ns = setupOwned()
    env.openAuctionHouse()
    env.runTimers()
    local done
    env.cancelSilent = true
    assert.is_true(ns.myAuctionsAPI:cancel(101, function(ok) done = ok end))
    env.fire("AUCTION_CANCELED", 555)
    assert.is_nil(done, "an id that isn't ours finishes nothing")
    env.fire("AUCTION_CANCELED", 101)
    assert.is_true(done)
    assert.is_not_nil(w)
  end)

  it("leaves asking for the auction list to the character tracker when it is installed", function()
    local env, w = setupOwned({ tracker = true })
    env.openAuctionHouse()
    env.runTimers()
    w:select("auctions")
    env.runTimers()
    assert.equal(1, env.ownedQueries, "one query on opening, from the tracker")
    w.myAuctionsView.rows[1].button:Click()
    w.myAuctionsView.cancelButton:Click()
    env.runTimers()
    assert.equal(2, env.ownedQueries, "one more after the cancel")
  end)
end)

describe("My auctions view, in-game fixes (#123)", function()
  local ESSENCE, SOUL = 11175, 11083
  local function open()
    local env, w, ns = setup()
    env.itemNames = { [SOUL] = "Soul Dust" }
    env.itemQualities = { [SOUL] = 1 }
    -- As Forever lists a partly sold commodity auction: the rest and each sale share one auction id, and a
    -- sale's buyoutAmount is the whole sale.
    env.owned = {
      { id = 7, itemID = ESSENCE, quantity = 54, buyout = 1444, timeLeftSeconds = 25200,
        link = "|cff1eff00|Hitem:11175|h[Greater Astral Essence]|h|r" },
      { id = 7, itemID = ESSENCE, quantity = 2, buyout = 2888, status = 1, timeLeftSeconds = 1860,
        link = "|cff1eff00|Hitem:11175|h[Greater Astral Essence]|h|r" },
      { id = 9, itemID = SOUL, quantity = 2, buyout = 830, status = 1, timeLeftSeconds = 1860 },
    }
    env.listings[ESSENCE] = { { unitPrice = 1444, quantity = 60, numOwnerItems = 54 } }
    env.openAuctionHouse()
    env.runTimers()
    w:select("auctions")
    env.runTimers()
    return env, w, ns, w.myAuctionsView
  end

  local function rowFor(v, qty)
    for _, cells in ipairs(v.rows) do
      if cells[2]:GetText() == tostring(qty) then return cells end
    end
  end

  it("names an auction without a link from the auction house's item info, in its quality colour", function()
    local _, _, _, v = open()
    assert.equal("|cffffffffSoul Dust|r", v.rows[3][1]:GetText(), "sold rows sort by name; it has no link")
  end)

  it("selects one row when a sale shares its auction id with the rest of the auction", function()
    local _, w, _, v = open()
    rowFor(v, 54).button:Click()
    local selected = 0
    for _, cells in ipairs(v.rows) do
      if cells.button.selectedTexture:IsShown() then selected = selected + 1 end
    end
    assert.equal(1, selected)
    assert.matches("54 units", w.detailBody:GetText())
  end)

  it("reads a sale's buyout as the whole sale", function()
    local _, w, _, v = open()
    local sale = v.rows[2]
    assert.matches("Greater Astral Essence", sale[1]:GetText())
    assert.equal("14s 44c", sale[3]:GetText(), "the price per unit, like the other rows")
    sale.button:Click()
    assert.matches("You get 27s 44c after the 5%% cut", w.detailBody:GetText())
  end)

  it("keeps the active part selected when a new sale of it is listed first", function()
    local env, w, _, v = open()
    rowFor(v, 54).button:Click()
    table.insert(env.owned, 1, { id = 7, itemID = ESSENCE, quantity = 3, buyout = 4332, status = 1,
      timeLeftSeconds = 3600 })
    env.owned[2].quantity = 51
    env.fire("OWNED_AUCTIONS_UPDATED")
    assert.matches("51 units · 7 h left", w.detailBody:GetText())
    assert.is_true(v.cancelButton:IsEnabled())
  end)

  it("names an item once the client loads it, asking only once", function()
    local env, _, _, v = open()
    local asked = 0
    env.C_Item.RequestLoadItemDataByID = function(id)
      asked = asked + 1
      env.C_Timer.After(0, function() env.fire("GET_ITEM_INFO_RECEIVED", id, false) end)
    end
    env.owned[#env.owned + 1] = { id = 12, itemID = 99999, quantity = 1, buyout = 100, status = 1 }
    env.fire("OWNED_AUCTIONS_UPDATED")
    env.runTimers()
    env.runTimers()
    assert.equal(1, asked, "an item that never loads isn't asked for again and again")
    env.itemNames[99999] = "Mystery Dust"
    env.fire("OWNED_AUCTIONS_UPDATED")
    local names = {}
    for _, cells in ipairs(v.rows) do names[#names + 1] = cells[1]:GetText() or "" end
    assert.matches("Mystery Dust", table.concat(names, ","))
  end)

  it("says a cancel that costs nothing loses nothing", function()
    local _, w, _, v = open()
    rowFor(v, 54).button:Click()
    assert.matches("Deposit you lose: nothing", w.detailBody:GetText())
  end)
end)

describe("Browse search history", function()
  local function browse(settings)
    local env, w, ns = setup()
    if settings then ns.browseSettings = settings end
    env.openAuctionHouse()
    w:select("browse")
    env.itemNames = { [1] = "Ridgeback Bracers" }
    env.browseResults = { { itemKey = { itemID = 1, itemLevel = 28 }, totalQuantity = 3, minPrice = 890 } }
    return env, w, ns, w.browseView
  end
  local function run(env, view, text, lo, hi)
    view.searchBox:SetText(text)
    view.minLevel:SetText(lo or "")
    view.maxLevel:SetText(hi or "")
    view.searchButton:Click()
    env.runTimers()
  end

  it("lists searches that ran in the panel right of the results, newest first", function()
    local env, _, ns, view = browse()
    local h = view.history
    assert.is_true(h.panel:IsShown())
    assert.is_true(h.empty:IsShown(), "nothing searched yet")
    run(env, view, "bracers", "30", "21")
    run(env, view, "")
    run(env, view, "linen")
    local _, recent = ns.searchHistory:list()
    assert.equal(2, #recent, "the blank search isn't kept")
    assert.is_false(h.empty:IsShown())
    assert.equal("RECENT", h.lines[1].heading:GetText())
    assert.equal("linen", h.lines[2].name:GetText())
    assert.equal("bracers", h.lines[3].name:GetText())
    assert.equal("level 21-30", h.lines[3].detail:GetText())
    assert.equal("now", h.lines[3].age:GetText())
    assert.is_false(h.lines[4]:IsShown())
  end)

  it("does not remember a search that failed", function()
    local env, _, ns, view = browse()
    env.browseSilent = true
    run(env, view, "linen")
    env.runTimers()
    local _, recent = ns.searchHistory:list()
    assert.equal(0, #recent)
  end)

  it("searches again with a click, filling the search row", function()
    local env, _, _, view = browse()
    run(env, view, "bracers", "21", "30")
    run(env, view, "linen")
    local h = view.history
    local before = #env.browses
    h.lines[1]:Click() -- the heading does nothing
    assert.equal(before, #env.browses)
    h.lines[3]:Click()
    assert.equal("bracers", view.searchBox:GetText())
    assert.equal("21", view.minLevel:GetText())
    assert.equal("30", view.maxLevel:GetText())
    env.runTimers()
    assert.equal(before + 1, #env.browses)
    local q = env.browses[#env.browses]
    assert.equal("bracers", q.searchString)
    assert.equal(21, q.minLevel)
    assert.equal(30, q.maxLevel)
    assert.equal("bracers", h.lines[2].name:GetText(), "moved to the top")
  end)

  it("leaves the search row alone while a search is running", function()
    local env, _, _, view = browse()
    run(env, view, "bracers", "21", "30")
    view.searchBox:SetText("linen")
    view.minLevel:SetText("")
    view.maxLevel:SetText("")
    view.searchButton:Click()
    local h = view.history
    h.lines[2]:Click()
    assert.equal("linen", view.searchBox:GetText())
    assert.equal("Wait for this search to finish.", h.foot:GetText())
    env.runTimers()
    assert.equal("linen", env.browses[#env.browses].searchString)
  end)

  it("pins, unpins and removes entries, and clears only the recent ones", function()
    local env, _, ns, view = browse()
    run(env, view, "a")
    run(env, view, "b")
    local h = view.history
    h.lines[3].star:Click() -- pin "a"
    assert.equal("PINNED", h.lines[1].heading:GetText())
    assert.equal("a", h.lines[2].name:GetText())
    assert.equal("", h.lines[2].age:GetText(), "pinned searches show no age")
    assert.equal("RECENT", h.lines[3].heading:GetText())
    assert.equal("b", h.lines[4].name:GetText())
    h.clearButton:Click()
    assert.equal("a", h.lines[2].name:GetText())
    assert.is_false(h.lines[3]:IsShown())
    assert.is_false(h.clearButton:IsShown(), "nothing left to clear")
    h.lines[2].star:Click() -- unpin
    assert.equal("RECENT", h.lines[1].heading:GetText())
    h.lines[2].remove:Click()
    assert.is_true(h.empty:IsShown())
    local pinned, recent = ns.searchHistory:list()
    assert.equal(0, #pinned + #recent)
  end)

  it("scrolls a long history with the wheel", function()
    local env, _, _, view = browse()
    for i = 1, 15 do run(env, view, "s" .. i) end
    local h = view.history
    local lines = #h.lines
    assert.is_true(lines < 16)
    h.panel.scripts.OnMouseWheel(h.panel, -50)
    assert.equal(16 - lines, h.offset, "stops at the end")
    assert.equal("s1", h.lines[lines].name:GetText())
    h.panel.scripts.OnMouseWheel(h.panel, 50)
    assert.equal(0, h.offset)
  end)

  it("gives way to an item's page and comes back with the results", function()
    local env, _, _, view = browse()
    run(env, view, "bracers")
    view.rows[1].button:Click()
    assert.is_false(view.history.panel:IsShown())
    assert.is_false(view.divider:IsShown())
    view:closeItem()
    assert.is_true(view.history.panel:IsShown())
    assert.is_true(view.divider:IsShown())
  end)

  describe("divider", function()
    it("starts at the saved width, and lays the results out for the room left", function()
      local _, _, ns, view = browse({ historyWidth = 270 })
      assert.equal(270, view.historyWidth)
      assert.equal(ns.BrowseView.WIDTH - ns.BrowseView.DIVIDER - 270, view.panel:GetWidth())
      local name = view.rows[1][1]
      assert.equal(view.columns[1][3], name.width)
      assert.equal(view.listWidth - 22 - 4, view.columns[6][2] + view.columns[6][3])
    end)

    it("turns cursor movement into window units at any UI and window scale", function()
      local env, w, _, view = browse({})
      env.uiScale = 0.75
      w.frame:SetScale(1.2)
      local start = view.historyWidth
      local d = view.divider
      env.cursorX, env.mouseDown = 600, true
      d.scripts.OnMouseDown(d, "LeftButton")
      env.cursorX = 600 - 9 -- 9 screen px = 12 UI units = 10 px of the scaled window
      d.scripts.OnUpdate(d, 0.01)
      assert.equal(start + 10, view.historyWidth)
      env.mouseDown = false
      d.scripts.OnUpdate(d, 0.01) -- released where the divider didn't hear it
      assert.is_nil(view.dragging)
    end)

    it("keeps the status line inside the results when the history widens", function()
      local env, _, _, view = browse({})
      run(env, view, "bracers")
      local d = view.divider
      env.uiScale = 1
      env.cursorX, env.mouseDown = 500, true
      d.scripts.OnMouseDown(d, "LeftButton")
      env.cursorX = 400
      d.scripts.OnUpdate(d, 0.01)
      assert.is_true(view.status.width <= view.listWidth - 8)
    end)

    it("drags wider and narrower within limits, saves on release, and resets on double-click", function()
      local env, w, ns, view = browse({})
      local settings = ns.browseSettings
      local d = view.divider
      local start = view.historyWidth
      env.uiScale = 1 -- cursor pixels are window units (the window is at scale 1)
      w.frame:SetScale(1)
      env.cursorX, env.mouseDown = 500, true
      d.scripts.OnMouseDown(d, "LeftButton")
      env.cursorX = 485 -- 15 px left: the history gets wider
      d.scripts.OnUpdate(d, 0.01)
      assert.equal(start + 15, view.historyWidth)
      env.cursorX = 0
      d.scripts.OnUpdate(d, 0.01)
      assert.equal(ns.Browse.HISTORY_MAX, view.historyWidth, "no wider than the filter row allows (#213)")
      assert.is_nil(settings.historyWidth, "saved only when the drag ends")
      env.cursorX = 2000
      d.scripts.OnUpdate(d, 0.01)
      assert.equal(ns.Browse.HISTORY_MIN, view.historyWidth)
      env.cursorX = 485
      d.scripts.OnUpdate(d, 0.01)
      env.mouseDown = false
      d.scripts.OnMouseUp(d, "LeftButton")
      assert.equal(start + 15, settings.historyWidth)
      d.scripts.OnDoubleClick(d)
      assert.equal(ns.Browse.HISTORY_WIDTH, view.historyWidth)
      assert.is_nil(settings.historyWidth)
      assert.truthy(w)
    end)
  end)
end)

describe("Browse categories and filters", function()
  -- Shaped like Blizzard's AuctionCategories.
  local function categories()
    local chest = { name = "Chest", filters = { { classID = 4, subClassID = 3, inventoryType = 5 } } }
    local mail = { name = "Mail", filters = { { classID = 4, subClassID = 3 } }, subCategories = { chest } }
    return {
      { name = "Weapons", filters = { { classID = 2, subClassID = 0 } } },
      { name = "Armor", filters = { { classID = 4, subClassID = 3 } }, subCategories = { mail } },
      { name = "Quest Items", filters = { { classID = 12 } } },
      { name = "WoW Token", filters = { { classID = 18 } }, flags = { WOW_TOKEN_FLAG = true } },
    }
  end
  local function browse(opts)
    local env, w, ns = setup(opts)
    env.AuctionCategories = categories()
    if opts and opts.settings then ns.browseSettings = opts.settings end
    env.openAuctionHouse()
    w:select("browse")
    env.itemNames = { [1] = "Ridgeback Bracers" }
    env.browseResults = { { itemKey = { itemID = 1, itemLevel = 28 }, totalQuantity = 3, minPrice = 890 } }
    return env, w, ns, w.browseView, w.browseView.filterBar
  end

  it("lists Forever's categories and searches the one picked, submenu by submenu", function()
    local env, _, _, view, bar = browse()
    assert.equal("All items", bar.categoryButton:GetText())
    assert.equal("WowStyle2DropdownTemplate", bar.categoryButton.template, "Blizzard's drop-down (#189)")
    bar.categoryButton:Click()
    assert.is_true(bar.categoryButton:IsMenuOpen())
    assert.same({ "All items", "Weapons", "Armor", "Quest Items" }, fake.menuLabels(bar.categoryButton),
      "no WoW Token")
    assert.same({ "All items" }, fake.selected(bar.categoryButton))
    assert.same({ "All armor", "Mail" }, fake.menuLabels(bar.categoryButton, "Armor"))
    assert.same({ "All mail", "Chest" }, fake.menuLabels(bar.categoryButton, "Armor", "Mail"))
    fake.pick(bar.categoryButton, "Armor", "All armor")
    env.runTimers()
    assert.is_false(bar.categoryButton:IsMenuOpen())
    assert.equal("Armor", bar.categoryButton:GetText())
    local q = env.browses[#env.browses]
    assert.same({ { classID = 4, subClassID = 3 } }, q.itemClassFilters)
    assert.is_nil(q.path, "Browse's own fields aren't sent to the client")
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Armor", "Mail", "Chest")
    env.runTimers()
    assert.is_false(bar.categoryButton:IsMenuOpen(), "a category without subcategories closes the menu")
    assert.equal("Armor / Mail / Chest", bar.categoryButton:GetText())
    assert.same({ "Armor" }, fake.selected(bar.categoryButton), "the chosen category's parents are ticked")
    assert.same({ "Chest" }, fake.selected(bar.categoryButton, "Armor", "Mail"))
    q = env.browses[#env.browses]
    assert.same({ { classID = 4, subClassID = 3, inventoryType = 5 } }, q.itemClassFilters)
    assert.truthy(view.status:GetText():find("in Armor / Mail / Chest", 1, true))
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "All items")
    env.runTimers()
    assert.equal("All items", bar.categoryButton:GetText())
    assert.same({}, env.browses[#env.browses].itemClassFilters)
  end)

  it("keeps the menu open when a category with subcategories is picked itself", function()
    local env, _, _, _, bar = browse()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Armor")
    env.runTimers()
    assert.is_true(bar.categoryButton:IsMenuOpen(), "Armor's subcategories still to show")
    assert.equal("Armor", bar.categoryButton:GetText())
    assert.same({ { classID = 4, subClassID = 3 } }, env.browses[#env.browses].itemClassFilters)
  end)

  it("sends the filter chips with the next search, and clears them", function()
    local env, _, _, view, bar = browse()
    assert.is_false(bar.clearButton:IsShown())
    bar.usableCheck:Click()
    assert.equal(0, #env.browses, "a filter waits for Search")
    bar.rarityButton:Click()
    assert.is_true(bar.rarityButton:IsMenuOpen())
    local labels = fake.menuLabels(bar.rarityButton)
    assert.equal(6, #labels)
    assert.truthy(labels[3]:find("Uncommon", 1, true))
    fake.pick(bar.rarityButton, labels[1]) -- Poor off
    fake.pick(bar.rarityButton, labels[2]) -- Common off
    assert.is_true(bar.rarityButton:IsMenuOpen(), "ticking keeps the menu open")
    assert.equal(4, #fake.selected(bar.rarityButton))
    assert.equal("Uncommon and up", bar.rarityButton:GetText())
    view.searchButton:Click()
    assert.is_false(bar.rarityButton:IsMenuOpen(), "searching closes the menu")
    env.runTimers()
    assert.same({ 2, 8, 9, 10, 11 }, env.browses[#env.browses].filters)
    assert.is_true(bar.clearButton:IsShown())
    bar.clearButton:Click()
    assert.is_false(bar.usableCheck:GetChecked())
    assert.equal("Any rarity", bar.rarityButton:GetText())
    assert.is_false(bar.clearButton:IsShown())
  end)

  it("keeps the category and filters in the search history and brings them back", function()
    local env, _, ns, view, bar = browse()
    bar.usableCheck:Click()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Armor", "All armor")
    env.runTimers()
    local _, recent = ns.searchHistory:list()
    assert.equal("Everything", recent[1].name)
    assert.equal("Armor · usable by me", recent[1].detail)
    bar:clear()
    env.runTimers() -- leaving the category searched everything
    view.history.lines[2]:Click()
    assert.equal("Armor", bar.categoryButton:GetText())
    assert.is_true(bar.usableCheck:GetChecked())
    env.runTimers()
    local q = env.browses[#env.browses]
    assert.same({ { classID = 4, subClassID = 3 } }, q.itemClassFilters)
    assert.equal(2, q.filters[1])
  end)

  it("remembers the last category and filters per character", function()
    local settings = {}
    local env, _, _, _, bar = browse({ tracker = true, settings = settings })
    env.guid = "Player-6841-0A1B2C3D"
    bar.exactCheck:Click()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Quest Items")
    local saved = settings.characters["Thrall-6841"]
    assert.same({ "Quest Items" }, saved.path)
    assert.is_true(saved.chips.exact)
    local _, _, _, _, again = browse({ tracker = true, settings = settings })
    assert.equal("Quest Items", again.categoryButton:GetText(), "after a reload")
    assert.is_true(again.exactCheck:GetChecked())
    settings.characters = nil
    local stranger, _, _, _, other = browse({ tracker = true, settings = settings })
    assert.truthy(stranger)
    assert.equal("All items", other.categoryButton:GetText(), "another character starts fresh")
  end)

  it("searches everything when a saved category is no longer on the auction house", function()
    local settings = { characters = { ["Thrall-6841"] = { path = { "Gone" }, chips = {} } } }
    local env, _, _, view, bar = browse({ tracker = true, settings = settings })
    assert.truthy(env)
    assert.equal("Gone", bar.categoryButton:GetText())
    view.searchButton:Click()
    env.runTimers()
    assert.equal("All items", bar.categoryButton:GetText())
    assert.truthy(view.status:GetText():find("isn't on this auction house", 1, true))
  end)

  it("searches a category picked during a search once that one ends, and saves only that one", function()
    local env, _, ns, _, bar = browse()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Armor") -- Armor: searching, menu open
    fake.pick(bar.categoryButton, "Armor", "Mail") -- Mail, before Armor's answer
    assert.equal(1, #env.browses)
    env.runTimers()
    assert.equal(2, #env.browses, "Mail is searched after Armor")
    local _, recent = ns.searchHistory:list()
    assert.equal(1, #recent, "Armor was replaced before it finished, so it isn't kept (#185)")
    assert.equal("Armor / Mail", recent[1].detail)
    assert.is_true(bar.categoryButton:IsMenuOpen(), "Mail has a slot submenu to show")
  end)

  it("keeps only the last of several categories picked while searches run (#185)", function()
    local env, _, ns, _, bar = browse()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Weapons") -- searching
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Armor", "All armor") -- before Weapons' answer
    env.runTimers()
    local _, recent = ns.searchHistory:list()
    assert.equal(1, #recent)
    assert.equal("Armor", recent[1].detail, "Weapons was replaced, Armor kept")
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Quest Items") -- searching
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "All items") -- before its answer: a blank search, never kept
    env.runTimers()
    _, recent = ns.searchHistory:list()
    assert.equal(1, #recent, "Quest Items was replaced too")
    assert.equal("Armor", recent[1].detail)
  end)

  it("searches everything when Clear filters leaves a category", function()
    local env, _, _, _, bar = browse()
    bar.categoryButton:Click()
    fake.pick(bar.categoryButton, "Quest Items")
    env.runTimers()
    local n = #env.browses
    bar.clearButton:Click()
    env.runTimers()
    assert.equal(n + 1, #env.browses)
    assert.same({}, env.browses[#env.browses].itemClassFilters)
  end)

  it("lets a long submenu scroll instead of running off the screen", function()
    local env, _, _, _, bar = browse()
    local many = {}
    for i = 1, 25 do many[i] = { name = "Sub " .. i, filters = { { classID = 7, subClassID = i } } } end
    env.AuctionCategories[#env.AuctionCategories + 1] = { name = "Trade Goods", filters = {}, subCategories = many }
    bar.categoryButton:Click()
    local trade = fake.menu(bar.categoryButton, "Trade Goods")
    assert.equal(26, #trade.children)
    assert.equal(400, trade.scrollExtent)
    assert.is_nil(fake.menu(bar.categoryButton).scrollExtent, "the short top list doesn't scroll")
  end)
  describe("Ledger view", function()
    local function open()
      local env, w, ns = setup()
      env.date, env.time = os.date, os.time
      env.UnitName = function() return "Me" end
      ns.CharacterTracker = ns.CharacterTracker or { characterKey = function() return "Me" end }
      local now = env.now
      ns.ledger:sale({ t = now - 60, char = "Me", name = "Large Brilliant Shard", n = 2, money = 20900 + 50, cut = 1100,
        deposit = 50 })
      ns.ledger:buy({ t = now - 120, char = "Me", name = "Ridge Cleaver", n = 1, c = 2210, src = "Snipe" })
      ns.ledger:deposit({ t = now - 180, char = "Me", name = "Large Brilliant Shard", n = 2, c = 50 })
      ns.ledger:buy({ t = now - 40 * 86400, char = "Alt", name = "Old", n = 1, c = 5 })
      env.openAuctionHouse()
      env.runTimers()
      sidebarButton(w, "ledger"):Click()
      return env, w, ns, w.ledgerView
    end

    it("is in the sidebar under Data", function()
      local _, w = setup()
      assert.equal("Ledger", w.model:label("ledger"))
    end)

    it("lists the last 7 days' entries, newest first, with totals on the right", function()
      local _, w, _, v = open()
      assert.is_true(w.ledgerPanel:IsShown())
      assert.equal("Sold", v.entryRows[1][2]:GetText())
      assert.equal("Large Brilliant Shard", v.entryRows[1][3]:GetText())
      assert.matches("%+2g 9s 0c", v.entryRows[1][5]:GetText(), "after the cut")
      assert.equal("Bought · Snipe", v.entryRows[2][2]:GetText())
      assert.matches("%-22s 10c", v.entryRows[2][5]:GetText())
      assert.equal("Deposit", v.entryRows[3][2]:GetText())
      assert.is_false(v.entryRows[4].button:IsShown(), "the 40-day-old buy is outside 7 days")
      assert.equal("Last 7 days, all characters", w.detailTitle:GetText())
      local body = w.detailBody:GetText()
      assert.matches("Sales %(1 auction%): |c%x+2g 20s 0c", body)
      assert.matches("Purchases %(1 item%): |c%x+22s 10c", body)
      assert.matches("Deposits not back yet: |c%x+0c", body, "the deposit came back with the sale")
      assert.matches("%+1g 86s 90c", body, "22000 - 1100 - 2210 = 18690")
    end)

    it("filters money in and out, and changes period", function()
      local _, _, _, v = open()
      assert.equal("7 days", v.periodDrop:GetText())
      assert.equal("WowStyle2DropdownTemplate", v.filterDrop.template, "Blizzard's Settings drop-down")
      v.filterDrop:Click()
      assert.is_true(v.filterDrop:IsMenuOpen())
      assert.same({ "Money in and out", "Money in", "Money out" }, fake.menuLabels(v.filterDrop))
      fake.pick(v.filterDrop, "Money out")
      assert.is_false(v.filterDrop:IsMenuOpen(), "picking closes the menu")
      assert.equal("Money out", v.filterDrop:GetText())
      assert.equal("Bought · Snipe", v.entryRows[1][2]:GetText())
      fake.pick(v.filterDrop, "Money in and out")
      v.periodDrop:Click()
      fake.pick(v.periodDrop, "All time")
      assert.equal("All time", v.periodDrop:GetText())
      assert.equal("Old", v.entryRows[4][3]:GetText())
    end)

    it("ticks the chosen option, and closes an open menu on leaving the view", function()
      local _, w, _, v = open()
      v.periodDrop:Click()
      assert.same({ "7 days" }, fake.selected(v.periodDrop), "the chosen period is ticked")
      sidebarButton(w, "browse"):Click()
      sidebarButton(w, "ledger"):Click()
      assert.is_false(v.periodDrop:IsMenuOpen())
      v.tabButtons["items"]:Click()
      v.tabButtons["entries"]:Click()
      assert.is_true(v.filterDrop:IsShown(), "back on Transactions")
    end)

    it("shows one character only when asked", function()
      local _, _, _, v = open()
      fake.pick(v.periodDrop, "All time")
      assert.equal("All characters", v.charsDrop:GetText())
      fake.pick(v.charsDrop, "This character")
      assert.equal("This character", v.charsDrop:GetText())
      assert.is_false(v.entryRows[4].button:IsShown(), "Alt's buy is left out")
    end)

    it("shows an entry's details when its row is clicked", function()
      local _, w, _, v = open()
      v.entryRows[1].button:Click()
      assert.equal("Large Brilliant Shard", w.detailTitle:GetText())
      assert.matches("2 units sold for 2g 20s 0c", w.detailBody:GetText())
      assert.matches("AH cut: |c%x+11s 0c", w.detailBody:GetText())
    end)

    it("adds up each item on By item", function()
      local _, w, _, v = open()
      v.periodDrop:Click()
      v.tabButtons["items"]:Click()
      assert.is_false(v.periodDrop:IsMenuOpen(), "changing tab closes an open menu")
      assert.is_false(v.filterDrop:IsShown(), "money in or out is for Transactions only")
      assert.is_true(v.itemList:IsShown())
      assert.is_false(v.entryList:IsShown())
      assert.equal("Large Brilliant Shard", v.itemRows[1][1]:GetText())
      assert.matches("%+2g 9s 0c", v.itemRows[1][6]:GetText(), "sold 22000, cut 1100, deposit back")
      assert.equal("Ridge Cleaver", v.itemRows[2][1]:GetText())
      v.itemRows[2].button:Click()
      assert.equal("Ridge Cleaver", w.detailTitle:GetText())
      assert.matches("1 for |c%x+22s 10c", w.detailBody:GetText())
    end)

    it("draws a column per day on By day", function()
      local _, w, _, v = open()
      v.tabButtons["days"]:Click()
      assert.is_true(v.chart:IsShown())
      assert.equal(7, #v.columns)
      local today = v.columns[7]
      assert.is_true(today.up:IsShown())
      assert.is_true(today.down:IsShown())
      assert.is_false(v.columns[1].up:IsShown())
      today:Click()
      assert.matches("Net: |c%x+%+1g 86s 90c", w.detailBody:GetText())
    end)

    it("redraws when something is recorded while it is on screen", function()
      local _, _, ns, v = open()
      ns.ledgerAPI:bought(1, "New thing", 1, 100, "Browse")
      assert.equal("New thing", v.entryRows[1][3]:GetText())
    end)

    it("says how sales are counted while it is empty", function()
      local env, w = setup()
      env.date, env.time = os.date, os.time
      env.openAuctionHouse()
      env.runTimers()
      sidebarButton(w, "ledger"):Click()
      assert.matches("take their gold", w.ledgerView.empty:GetText())
    end)
  end)
end)

describe("My bids view (#95)", function()
  local BELT, BRACERS, BOOTS = 10275, 15366, 9900
  local ME, OTHER = "Player-6841-0A1B2C3D", "Player-6841-FFFF0000"
  local function bids(env)
    env.myBids = {
      { id = 201, itemID = BELT, band = 2, minBid = 20075, bid = 19500, buyout = 21000, bidder = OTHER,
        outbidUnlessNamed = true, link = "|cff1eff00|Hitem:10275::::::::60:::::|h[Gryphon Mail Belt]|h|r" },
      { id = 202, itemID = BRACERS, band = 0, minBid = 790, bid = 750, buyout = 890, bidder = ME,
        link = "|cff1eff00|Hitem:15366::::::::60:::::|h[Ridgeback Bracers]|h|r" },
      { id = 203, itemID = BOOTS, band = 1, minBid = 1500, bid = 1400, bidder = OTHER, outbidUnlessNamed = true,
        link = "|cff1eff00|Hitem:9900::::::::60:::::|h[Scouting Boots of the Bear]|h|r" },
    }
  end

  local function open(opts, before)
    local env, w, ns = setup(opts)
    bids(env)
    if before then before(env, ns) end
    env.openAuctionHouse()
    env.runTimers()
    sidebarButton(w, "bids"):Click()
    env.runTimers()
    return env, w, ns, w.myBidsView
  end

  local function rowText(v, r)
    local cells = v.rows[r]
    return cells[1]:GetText(), cells[2]:GetText(), cells[3]:GetText(), cells[4]:GetText(), cells[5]:GetText()
  end

  it("sits under Buy, after Browse", function()
    local _, w = setup()
    assert.equal("My bids", w.model:label("bids"))
  end)

  it("lists the bids the client knows, and the outbid ones it was asked about", function()
    -- What this character bid earlier, still in the store: the belt at 1g 80s, the boots unknown.
    local env, w, _, v = open(nil, function(_, ns)
      ns.myBidsAPI.session[201] = { bid = 18000, at = 1000000, misses = 0 }
      ns.myBidsAPI.session[203] = { misses = 0 }
    end)
    assert.is_true(w.myBidsPanel:IsShown())
    local q = env.bidQueries[#env.bidQueries]
    table.sort(q)
    assert.same({ 201, 203 }, q, "the query names the auctions bid on before")
    local item, yours, status, _, buyout = rowText(v, 1)
    assert.matches("Scouting Boots", item, "outbid first, ending soonest first")
    assert.equal("-", yours, "an amount never seen")
    assert.matches("Outbid", status)
    assert.equal("none", buyout)
    local left
    item, yours, status, left, buyout = rowText(v, 2)
    assert.matches("Gryphon Mail Belt", item)
    assert.equal("1g 80s 0c", yours)
    assert.matches("Outbid", status)
    assert.equal("2-12 h", left)
    assert.equal("2g 10s 0c", buyout)
    item, yours, status, left = rowText(v, 3)
    assert.matches("Ridgeback Bracers", item)
    assert.equal("7s 50c", yours)
    assert.matches("Highest", status)
    assert.equal("under 30 min", left)
    assert.matches("^3 bids · highest on 1 · 7s 50c tied up in bids · checked just now$", v.footer:GetText())
    assert.matches("My bids.*2", sidebarButton(w, "bids"):GetText(), "the sidebar counts outbid bids")
    assert.matches("Tied up in bids: 7s 50c", w.detailBody:GetText())
  end)

  it("asks once per visit and again on Refresh", function()
    local env, _, _, v = open()
    assert.equal(1, #env.bidQueries)
    v.refreshButton:Click()
    env.runTimers()
    assert.equal(2, #env.bidQueries)
  end)

  it("fills the lowest new bid and bids again inside the click", function()
    local env, w, _, v = open(nil, function(_, ns)
      ns.myBidsAPI.session[201] = { bid = 18000, at = 1000000, misses = 0 }
    end)
    v.rows[1].button:Click()
    assert.matches("Gryphon Mail Belt", w.detailTitle:GetText())
    assert.matches("Lowest new bid: 2g 0s 75c", w.detailBody:GetText())
    assert.matches("Current bid: 1g 95s 0c %(not yours%)", w.detailBody:GetText())
    local c = v.controls
    assert.same({ "2", "0", "75" }, { c.boxes[1]:GetText(), c.boxes[2]:GetText(), c.boxes[3]:GetText() })
    assert.equal("Bid again", c.bid:GetText())
    assert.equal("Buy out for 2g 10s 0c", c.buy:GetText())
    c.boxes[3]:SetText("70")
    c.bid:Click()
    assert.equal(0, #env.bids, "below the lowest new bid nothing is sent")
    assert.matches("lowest you can bid is 2g 0s 75c", c.note:GetText())
    c.boxes[3]:SetText("80")
    c.bid:Click()
    assert.same({ auctionID = 201, amount = 20080 }, env.bids[1])
    assert.equal("Bidding...", c.note:GetText())
    env.runTimers(5)
    assert.equal(20080, v:store()[201].bid, "what we bid is remembered")
    assert.matches("Bid 2g 0s 80c sent on Gryphon Mail Belt", c.note:GetText())
    assert.equal(2, #env.bidQueries, "the list is asked for again, once")
  end)

  it("can't bid on a bid that is already the highest, but can buy it out", function()
    local env, _, _, v = open()
    v.rows[1].button:Click() -- only the bracers are listed: nothing was asked for by id
    local c = v.controls
    assert.equal("You're the highest bidder", c.bid:GetText())
    assert.is_false(c.bid:IsEnabled())
    assert.is_true(c.buy:IsEnabled())
    c.buy:Click()
    assert.same({ auctionID = 202, amount = 890 }, env.bids[1])
    env.runTimers()
    assert.matches("Bought Ridgeback Bracers for 8s 90c", c.note:GetText())
    assert.is_nil(v:store()[202], "a bought auction is forgotten")
  end)

  it("keeps the bids per character in saved variables", function()
    local env, _, ns = open({ tracker = true })
    local key = ns.CharacterTracker.characterKey(env)
    assert.is_table(ns.bidSettings.characters[key][202])
    assert.equal(750, ns.bidSettings.characters[key][202].bid)
    assert.is_nil(next(ns.myBidsAPI.session))
  end)

  it("tracks a bid placed in Browse, even with My bids never opened, and lists it once outbid", function()
    local env, w, ns = setup()
    bids(env)
    env.openAuctionHouse()
    env.runTimers()
    ns.myBidsAPI:placed(201, 18000) -- as Browse's Place bid does once the bid went
    env.fire("BID_ADDED", 203)
    assert.same({ bid = 18000, at = env.now, misses = 0 }, ns.myBidsAPI.session[201])
    assert.is_table(ns.myBidsAPI.session[203])
    sidebarButton(w, "bids"):Click()
    env.runTimers()
    local q = env.bidQueries[1]
    table.sort(q)
    assert.same({ 201, 203 }, q)
    assert.equal(3, #w.myBidsView.shown)
  end)

  it("stops waiting when a query gets no answer", function()
    local env, _, _, v = open(nil, function(e) e.bidsSilent = true end)
    assert.equal("Reading your bids...", v.status:GetText())
    assert.is_false(v.refreshButton:IsEnabled())
    env.runTimers(11)
    assert.is_nil(v.asking)
    assert.is_true(v.refreshButton:IsEnabled())
    assert.matches("didn't answer", v.controls.note:GetText())
  end)

  it("waits for the auction house when it is busy, and asks by itself once it is ready (#204)", function()
    local env, _, _, v = open(nil, function(e) e.throttled = true end)
    assert.equal(0, #env.bidQueries)
    assert.equal("Waiting for the auction house to finish a search...", v.status:GetText())
    env.runTimers(3)
    assert.equal(0, #env.bidQueries)
    env.throttled = false
    env.runTimers(2)
    assert.equal(1, #env.bidQueries, "sent by itself")
    assert.is_nil(v.waiting)
    assert.matches("highest on 1", v.footer:GetText())
  end)

  it("leaves it to Refresh when the auction house stays busy (#204)", function()
    local env, _, _, v = open(nil, function(e) e.throttled = true end)
    env.runTimers(40)
    assert.equal(0, #env.bidQueries)
    assert.is_nil(v.waiting)
    assert.equal("Click Refresh to read your bids.", v.status:GetText())
    assert.matches("still busy", v.controls.note:GetText())
    assert.is_true(v.refreshButton:IsEnabled())
    env.throttled = false
    v.refreshButton:Click()
    env.runTimers()
    assert.equal(1, #env.bidQueries)
    assert.is_false(v.controls.note:IsShown(), "the busy note goes once the query is sent")
  end)

  it("stops waiting when another view is opened, and asks again on coming back (#204)", function()
    local env, w, _, v = open(nil, function(e) e.throttled = true end)
    sidebarButton(w, "browse"):Click()
    env.throttled = false
    env.runTimers(3)
    assert.equal(0, #env.bidQueries, "no retry while My bids is hidden")
    sidebarButton(w, "bids"):Click()
    env.runTimers()
    assert.equal(1, #env.bidQueries)
    assert.matches("highest on 1", v.footer:GetText())
  end)

  it("says so when the query can't be sent (#204)", function()
    local env, _, _, v = open(nil, function(e)
      e.C_AuctionHouse.QueryBids = function() error("nope") end
    end)
    assert.is_nil(v.waiting)
    assert.equal("Click Refresh to read your bids.", v.status:GetText())
    assert.matches("Couldn't ask", v.controls.note:GetText())
    assert.equal(0, #env.bidQueries)
  end)

  it("starts afresh when the auction house closes, and clears the outbid count", function()
    local env, w, _, v = open(nil, function(_, ns) ns.myBidsAPI.session[201] = { misses = 0 } end)
    assert.matches("My bids.*1", sidebarButton(w, "bids"):GetText())
    env.CloseAuctionHouse()
    env.runTimers()
    assert.is_nil(v.visit)
    assert.is_nil(v.bids)
    assert.is_false(v.controls.buy:IsShown())
    assert.equal("My bids", sidebarButton(w, "bids"):GetText())
  end)
end)

describe("Browse layout, tidied (#213)", function()
  local function browse()
    local env, w, ns = setup()
    env.openAuctionHouse()
    w:select("browse")
    env.itemNames = { [1] = "Ridgeback Bracers" }
    env.browseResults = { { itemKey = { itemID = 1, itemLevel = 28 }, totalQuantity = 3, minPrice = 890 } }
    return env, w, ns, w.browseView, w.browseView.filterBar
  end

  it("puts Search beside the box and the level range on the filter row, after Rarity", function()
    local _, _, _, view, bar = browse()
    assert.same({ "TOPRIGHT", view.panel, "TOPRIGHT", -4, -1 }, { unpack(view.searchButton.point, 1, 5) })
    assert.equal("Item name, or shift-click an item", view.searchHint:GetText())
    assert.equal(bar.rarityButton, view.levelLabel.point[2], "Level follows Rarity")
    assert.equal(bar.categoryButton, bar.rarityButton.point[2])
    assert.equal(view.maxLevel, bar.usableCheck.point[2], "the check boxes follow the level range")
    assert.equal(view.listWidth - 98, view.searchBox.width, "the box takes the row, less Search")
  end)

  it("shows Clear filters beside Search only once a filter is set, and gives it room", function()
    local _, _, _, view, bar = browse()
    local full = view.searchBox.width
    assert.is_false(bar.clearButton:IsShown())
    bar.usableCheck:Click()
    assert.is_true(bar.clearButton:IsShown())
    assert.equal(view.searchButton, bar.clearButton.point[2])
    assert.equal(full - 84 - 6, view.searchBox.width)
    bar.clearButton:Click()
    assert.is_false(bar.clearButton:IsShown())
    assert.equal(full, view.searchBox.width)
  end)

  it("says what to do in the middle of the empty list, until the first search", function()
    local env, _, _, view = browse()
    assert.is_true(view.emptyTitle:IsShown())
    assert.equal("Search the auction house", view.emptyTitle:GetText())
    assert.matches("press Enter", view.emptyHint:GetText())
    assert.equal("", view.status:GetText(), "the hint isn't repeated at the bottom")
    view.searchButton:Click()
    assert.is_false(view.emptyTitle:IsShown())
    env.runTimers()
    assert.is_false(view.emptyHint:IsShown())
    assert.matches("Ridgeback Bracers", view.rows[1][1]:GetText())
  end)

  it("draws the divider as a thin line", function()
    local _, _, _, view = browse()
    assert.same({ 0.24, 0.19, 0.13, 1 }, view.divider.line.color, "dark, not the old gold grip")
  end)
end)

describe("Resizable detail panel (#236)", function()
  local function open(panes)
    local env, w, ns = setup({ panes = panes })
    env.openAuctionHouse()
    env.uiScale = 1
    w.frame:SetScale(1)
    return env, w, ns
  end
  local function drag(env, d, from, to)
    env.cursorX, env.mouseDown = from, true
    d.scripts.OnMouseDown(d, "LeftButton")
    env.cursorX = to
    d.scripts.OnUpdate(d, 0.01)
  end

  it("shows the divider on Prices and Alts, and not on Settings or a placeholder", function()
    local _, w = open()
    sidebarButton(w, "prices"):Click()
    assert.is_true(w.paneDivider:IsShown())
    sidebarButton(w, "alts"):Click()
    assert.is_true(w.paneDivider:IsShown())
    sidebarButton(w, "settings"):Click()
    assert.is_false(w.paneDivider:IsShown())
    assert.equal(300, w.detailPanel:GetWidth())
    sidebarButton(w, "deals"):Click()
    assert.is_false(w.paneDivider:IsShown())
  end)

  it("hides the divider on a view not laid out for other widths yet", function()
    local _, w, ns = open({ ledger = 400, disenchant = 400 })
    -- Every resizable view lays itself out now: take Ledger's away to check the gate.
    local layout = ns.LedgerView.layoutPanes
    ns.LedgerView.layoutPanes = nil
    sidebarButton(w, "ledger"):Click()
    ns.LedgerView.layoutPanes = layout
    assert.is_false(w.paneDivider:IsShown())
    assert.equal(300, w.detailPanel:GetWidth(), "a saved width doesn't apply to it")
    sidebarButton(w, "disenchant"):Click()
    assert.is_false(w.paneDivider:IsShown())
    assert.equal(300, w.detailPanel:GetWidth(), "Disenchant snipe keeps its fixed panel")
  end)

  it("saves nothing for a click without a drag", function()
    local env, w, ns = open()
    sidebarButton(w, "prices"):Click()
    drag(env, w.paneDivider, 500, 500)
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    assert.is_nil(ns.paneSettings.prices)
  end)

  it("saves a drag to the view it began in", function()
    local env, w, ns = open()
    sidebarButton(w, "prices"):Click()
    drag(env, w.paneDivider, 500, 450)
    sidebarButton(w, "alts"):Click() -- by a key binding, say, with the mouse still held
    assert.is_nil(w.paneDivider.dragging, "the drag ends with the view")
    assert.is_nil(w.paneDivider.scripts.OnUpdate)
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    assert.equal(350, ns.paneSettings.prices)
    assert.is_nil(ns.paneSettings.alts)
    assert.equal(300, w.detailPanel:GetWidth())
  end)

  it("drags the Prices detail panel wider, laying the list out for the room left, and saves on release", function()
    local env, w, ns = open()
    sidebarButton(w, "prices"):Click()
    drag(env, w.paneDivider, 500, 440) -- 60 px left: the panel gets wider
    assert.equal(360, w.detailPanel:GetWidth())
    assert.equal(336, w.detailBody.width)
    assert.equal(480, w.pricesPanel:GetWidth())
    assert.equal(-(360 + 10), w.mainPanel.points.BOTTOMRIGHT.x, "the main panel ends at the detail panel")
    local last = w.rows[1][5]
    assert.is_true(last.points.LEFT.x + last.width <= 480 - 22, "the last column stays clear of the scroll bar")
    assert.is_nil(ns.paneSettings.prices, "saved only when the drag ends")
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    assert.equal(360, ns.paneSettings.prices)
  end)

  it("keeps the panel between 240 and 420", function()
    local env, w = open()
    sidebarButton(w, "alts"):Click()
    drag(env, w.paneDivider, 500, 0)
    assert.equal(420, w.detailPanel:GetWidth())
    env.cursorX = 2000
    w.paneDivider.scripts.OnUpdate(w.paneDivider, 0.01)
    assert.equal(240, w.detailPanel:GetWidth())
    assert.equal(600, w.altsPanel:GetWidth())
    assert.equal(600, w.altsStatus.width)
  end)

  it("keeps one width per view, and the default on Settings", function()
    local env, w, ns = open({ alts = 250 })
    sidebarButton(w, "prices"):Click()
    assert.equal(300, w.detailPanel:GetWidth())
    drag(env, w.paneDivider, 500, 400)
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    sidebarButton(w, "alts"):Click()
    assert.equal(250, w.detailPanel:GetWidth())
    assert.equal(590, w.altsPanel:GetWidth())
    sidebarButton(w, "settings"):Click()
    assert.equal(300, w.detailPanel:GetWidth())
    sidebarButton(w, "prices"):Click()
    assert.equal(400, w.detailPanel:GetWidth())
    assert.equal(400, ns.paneSettings.prices)
  end)

  it("resets to the default on double-click and forgets the saved width", function()
    local _, w, ns = open({ prices = 400 })
    sidebarButton(w, "prices"):Click()
    assert.equal(400, w.detailPanel:GetWidth())
    w.paneDivider.scripts.OnDoubleClick(w.paneDivider)
    assert.equal(300, w.detailPanel:GetWidth())
    assert.equal(540, w.pricesPanel:GetWidth())
    assert.is_nil(ns.paneSettings.prices)
  end)

  it("lays the Prices columns out at the default as they were built", function()
    local _, w = open({ prices = 420 })
    sidebarButton(w, "prices"):Click()
    w.paneDivider.scripts.OnDoubleClick(w.paneDivider)
    -- Built for 540 with a scroll bar: scaled by 518/540, as buildRows placed them.
    assert.equal(math.floor(196 * 518 / 540 + 0.5), w.rows[1][2].points.LEFT.x)
    assert.equal(math.floor(190 * 518 / 540), w.rows[1][1].width)
  end)

  it("lays Post out for the width: list, rows, Post button and the sell time line (#239)", function()
    local env, w, ns = open()
    sidebarButton(w, "post"):Click()
    assert.is_true(w.paneDivider:IsShown())
    local v = w.postView
    drag(env, w.paneDivider, 500, 2000) -- as narrow as it goes
    assert.equal(240, w.detailPanel:GetWidth())
    assert.equal(600, v.panel:GetWidth())
    assert.equal(600, v.list:GetWidth())
    assert.equal(504, v.postButton.width)
    assert.equal(216, v.sellTimeLine:GetWidth())
    env.cursorX = 0
    w.paneDivider.scripts.OnUpdate(w.paneDivider, 0.01)
    assert.equal(420, w.detailPanel:GetWidth())
    assert.equal(420, v.panel:GetWidth())
    local last = v.rows[1][#ns.PostView.COLUMNS]
    assert.is_true(last.points.LEFT.x + last.width <= 420 - 22, "the last column stays clear of the scroll bar")
    assert.equal(396, v.sellTimeLine:GetWidth())
    v.loading:show(1, 4) -- "Checking prices: 1 of 4" beside its bar
    env.cursorX = 440
    w.paneDivider.scripts.OnUpdate(w.paneDivider, 0.01)
    assert.equal(360, w.detailPanel:GetWidth())
    assert.equal(480 - ns.Loading.BAR_WIDTH - 6, v.status.width, "the status line ends at the list's edge")
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    assert.equal(360, ns.paneSettings.post)
  end)

  local views = { { "auctions", "myAuctionsView", "MyAuctionsView" }, { "bids", "myBidsView", "MyBidsView" } }
  for _, case in ipairs(views) do
    it("lays " .. case[3] .. " out for the width (#240)", function()
      local env, w, ns = open()
      sidebarButton(w, case[1]):Click()
      assert.is_true(w.paneDivider:IsShown())
      local v = w[case[2]]
      local note = v.note or v.controls.note
      drag(env, w.paneDivider, 500, 2000)
      assert.equal(600, v.panel:GetWidth())
      assert.equal(600, v.list:GetWidth())
      assert.equal(576, v.footer.width)
      assert.equal(216, note.width)
      env.cursorX = 0
      w.paneDivider.scripts.OnUpdate(w.paneDivider, 0.01)
      assert.equal(420, v.panel:GetWidth())
      assert.equal(396, note.width)
      if v.filterButtons then
        local right
        for _, b in pairs(v.filterButtons) do
          right = math.max(right or 0, b.points.TOPLEFT.x + b.width)
        end
        assert.is_true(right <= 420 - 24 - 110, "the filters stay clear of Check prices")
      end
      local cols = ns[case[3]].COLUMNS
      local last = v.rows[1][#cols]
      assert.is_true(last.points.LEFT.x + last.width <= 420 - 22, "the last column stays clear of the scroll bar")
      env.mouseDown = false
      w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
      assert.equal(420, ns.paneSettings[case[1]])
    end)
  end

  it("lays the Ledger out for the width, with the By day chart spread over it (#242)", function()
    local env, w, ns = open()
    sidebarButton(w, "ledger"):Click()
    assert.is_true(w.paneDivider:IsShown())
    local v = w.ledgerView
    drag(env, w.paneDivider, 500, 2000)
    assert.equal(600, v.panel:GetWidth())
    assert.equal(600, v.entryList:GetWidth())
    assert.equal(600, v.itemList:GetWidth())
    assert.equal(576, v.chart:GetWidth())
    assert.equal(576, v.footer.width)
    assert.equal(600, v.width, "the chart's days spread over the new width")
    env.cursorX = 0
    w.paneDivider.scripts.OnUpdate(w.paneDivider, 0.01)
    assert.equal(420, v.entryList:GetWidth())
    local lists = { { v.entryRows, ns.LedgerView.ENTRY_COLUMNS }, { v.itemRows, ns.LedgerView.ITEM_COLUMNS } }
    for _, pair in ipairs(lists) do
      local last = pair[1][1][#pair[2]]
      assert.is_true(last.points.LEFT.x + last.width <= 420 - 22, "the last column stays clear of the scroll bar")
    end
  end)

  it("opens Post at its saved width", function()
    local _, w = open({ post = 260 })
    sidebarButton(w, "prices"):Click()
    sidebarButton(w, "post"):Click()
    assert.equal(260, w.detailPanel:GetWidth())
    assert.equal(580, w.postView.panel:GetWidth())
  end)

  it("follows Browse: hidden on the results, at Browse's saved width on an item's page (#243)", function()
    local env, w, ns = open({ browse = 400 })
    sidebarButton(w, "browse"):Click()
    assert.is_false(w.paneDivider:IsShown(), "the results fill both panels")
    env.itemNames = { [10] = "Battleforge Shoulderpads" }
    env.browseResults = { { itemKey = { itemID = 10, itemLevel = 30 }, totalQuantity = 1, minPrice = 1250 } }
    env.listings[10] = { item = true, { auctionID = 5, buyoutAmount = 1250, minBid = 900, owners = { "Grukdar" } } }
    local view = w.browseView
    view.searchButton:Click()
    env.runTimers()
    view.rows[1].button:Click()
    env.runTimers()
    assert.is_true(w.paneDivider:IsShown())
    assert.equal(400, w.detailPanel:GetWidth())
    local item = view.item
    assert.equal(440, item.panel:GetWidth())
    assert.equal(130, item.nameText.width)
    assert.equal(376, item.messageText.width)
    local last = item.itemRows[1][#ns.BrowseItemView.ITEM_COLUMNS]
    assert.is_true(last.points.LEFT.x + last.width <= 440 - 22, "the last column stays clear of the scroll bar")
    assert.equal(376, item.commodityControls.confirmText.width)
    assert.equal(432 - ns.Loading.SPINNER - 6, item.status.width, "beside the spinner slot, inside the page")
    drag(env, w.paneDivider, 500, 600)
    assert.equal(300, w.detailPanel:GetWidth())
    assert.equal(540, item.panel:GetWidth())
    env.mouseDown = false
    w.paneDivider.scripts.OnMouseUp(w.paneDivider, "LeftButton")
    assert.equal(300, ns.paneSettings.browse)
    view:closeItem()
    assert.is_false(w.paneDivider:IsShown())
    assert.is_false(w.detailPanel:IsShown())
    assert.equal(-6, w.mainPanel.points.BOTTOMRIGHT.x)
  end)
end)
