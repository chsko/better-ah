local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/WindowModel.lua")
  local core = { "Money", "Time", "MarketKey", "MarketValue", "Disenchant", "Targets", "Sniper", "PriceDB",
    "CharacterRecords", "Posting", "PostQueue", "SelfTest", "Probes" }
  for _, file in ipairs(core) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Core/AutoScan.lua", ns)
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  helper.load("BetterAH/Game/PostingAPI.lua", ns)
  helper.load("BetterAH/Game/SnipeAPI.lua", ns)
  helper.load("BetterAH/UI/Loading.lua", ns)
  helper.load("BetterAH/UI/PostView.lua", ns)
  helper.load("BetterAH/UI/SnipeView.lua", ns)
  helper.load("BetterAH/UI/DisenchantView.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  ns.prices = ns.PriceDB.new({})
  -- Auto scan (#30) is off unless a spec turns it on, so scans start only where a spec starts one.
  ns.autoScan = false
  ns.characters = ns.CharacterRecords.new({})
  ns.posting = ns.Posting.Settings.new({})
  ns.AuctionAPI.install(env, ns)
  ns.PostingAPI.install(env, ns)
  ns.SnipeAPI.install(env, ns)
  if opts and opts.tracker then
    helper.load("BetterAH/Game/CharacterTracker.lua", ns)
    ns.CharacterTracker.install(env, ns)
  end
  local w = ns.Window.install(env, ns)
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
    assert.equal("window created with 8 sidebar entries; close button CloseButton; auction house art found",
      last.detail)
  end)

  it("finds the close button by its global name when it has no parent key", function()
    local env, _, ns = setup({ template = "named" })
    local last = ns.Probes.suite():run(env, { db = {} })
    last = last[#last]
    assert.equal("pass", last.status)
    assert.equal("window created with 8 sidebar entries; close button BetterAHFrameCloseButton; "
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
    assert.equal("window created with 8 sidebar entries; close button CloseButton; "
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
      local bar = w.scanLoading.barFrame
      assert.is_true(bar:IsShown(), "a bar that sweeps: the auction house doesn't say how far along it is")
      bar.scripts.OnUpdate(bar, 0.7)
      assert.equal(0.5, bar:GetValue())
      env.runTimers()
      assert.equal("Scanned 2 listings of 2 items in 0 seconds.", w.scanStatus:GetText())
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
      local replicate = env.C_AuctionHouse.ReplicateItems
      env.C_AuctionHouse.ReplicateItems = function()
        replicate()
        env.runTimers()
      end
      w:startScan()
      assert.equal("Scanned 0 listings of 0 items in 0 seconds.", w.scanStatus:GetText())
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
      assert.same({ "Soul Dust", "75%", "1-2", "6s 69c" },
        { line[1]:GetText(), line[2]:GetText(), line[3]:GetText(), line[4]:GetText() })
      assert.is_true(line.share > 0.4 and line.share < 0.5, "Soul Dust is under half of 14s 95c")
      assert.is_true(v.materialLines[3].track:IsShown())
      assert.is_false(v.materialLines[4].track:IsShown(), "three materials")
      assert.equal(math.floor(196 * line.share + 0.5), line.fill:GetWidth(), "the bar shows the share")
      assert.equal("", v.materialsNote:GetText())
      assert.equal("Counts the Arcane Salvager's 50% chance of one extra dust or essence.", v.salvagerNote:GetText())
      assert.equal("", w.detailBody:GetText())
      weapon:Click()
      assert.is_true(weapon.selected)
      assert.equal("What weapons give", v.materialsTitle:GetText())
      assert.equal("no price", v.materialLines[2][4]:GetText(), "Greater Magic Essence")
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
      w:startScan()
      env.runTimers()
      assert.equal("Prices from ruleset 1, Horde.", w.disenchantView.status:GetText())
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
      assert.is_true(v.targetRows[1].check:GetChecked())
      assert.equal(1, #ns.disenchant.targets, "saved")
      assert.is_true(v.editor:IsShown())
      assert.equal("Armor, req. 21-25", w.detailTitle:GetText())
      assert.equal("12s 78c", v.maxText:GetText())
      assert.equal("Worth 14s 20c after the cut", v.worthText:GetText())
      v.targetRows[1].check:Click()
      assert.is_false(ns.disenchant.targets[1].enabled, "kept but not sniped")
    end)

    it("edits a target's types, band and profit", function()
      local _, w, ns = deSetup()
      local v = w.disenchantView
      v.tabButtons.targets:Click()
      v.newButton:Click()
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
      v.bandUp:Click()
      assert.equal(31, ns.disenchant.targets[1].band)
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
      v.newButton:Click()
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
      v.targetRows.scrollBar:drag(1)
      assert.equal(2, v.targetOffset)
      v.targetRows[14].button:Click()
      assert.equal(16, v.target)
      v.targetRows[14].check:Click()
      assert.is_false(ns.disenchant.targets[16].enabled)
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
      assert.equal("Materials: 1 updated, 23 not listed by others.", w.disenchantView.status:GetText())
      assert.is_true(w.disenchantView.materialsButton:IsEnabled())
      assert.are_not.equal("14s 20c", band(w, 4)[3], "the new Soul Dust price counts")
    end)

    describe("Snipe", function()
      -- An Armor target for 26-30 (worth 14s 20c, 10% profit: max 12s 78c), and one cheap bracer on the
      -- auction house among results that aren't buys.
      local function snipeSetup()
        local env, w, ns = deSetup()
        local v = w.disenchantView
        v.tabButtons.targets:Click()
        v.newButton:Click()
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
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        s.buyButton:Click()
        assert.equal("Buying...", s.buyButton:GetText())
        assert.is_false(s.buyButton:IsEnabled())
        env.runTimers()
        assert.same({ auctionID = 77, amount = 900 }, env.bids[1])
        assert.equal("Spent this session: 9s 0c", s.spentText:GetText())
        assert.matches("Bought %[Ridgeback Bracers%] for 9s 0c", w.detailBody:GetText())
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

      it("passes, logs a missed buy and stops at the spend cap", function()
        local env, w, ns, s = snipeSetup()
        s.startButton:Click()
        assert.is_true(s.loading.spinnerFrame:IsShown(), "the spinner turns while sniping runs")
        assert.equal(s.status, s.loading.spinnerFrame.points.LEFT.rel, "after the status text")
        assert.are_not.equal(s.loading.spinnerFrame, s.status.points.LEFT.rel, "which stays where it is")
        assert.equal(s.status:GetStringWidth() + 6, s.loading.spinnerFrame.points.LEFT.x, "right of its last letter")
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
        assert.matches("Missed %[Ridgeback Bracers%]: sold to someone else", w.detailBody:GetText())
        assert.matches("Passed", w.detailBody:GetText())
        assert.equal(0, ns.disenchant.session.spent)
        env.bidFails = false
        s.capInput:SetFocus()
        s.capInput:SetText("10s")
        s.capInput:ClearFocus()
        assert.equal(1000, ns.disenchant.snipe.cap)
        assert.equal("Spent this session: 0c of 10s 0c", s.spentText:GetText())
        ns.disenchant.session.spent = 500
        s.session:add({ auctionID = 90, name = "[Pricey]", price = 600, worth = 1420, max = 1278, target = "Armor" })
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

      it("counts the age of the last check up while the next one waits", function()
        local env, _, _, s = snipeSetup()
        s.startButton:Click()
        env.runTimers()
        assert.matches("checked just now", s.status:GetText())
        env.browseSilent = true
        env.runTimers(3)
        assert.matches("checked 3s ago", s.status:GetText())
        assert.is_true(s.loading.spinnerFrame:IsShown())
        s.startButton:Click()
        assert.is_false(s.loading.spinnerFrame:IsShown(), "Stop ends the spinner")
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
      ns.posting:setProfile("i:2589", 20, 2)
      ns.posting:setProfile("i:2592", 20, 2)
      return env, w, ns
    end

    it("counts other sellers' listings toward market value, once per day, and not as a full scan", function()
      local env, w, ns = setup()
      env.containers[0] = { linen, { itemID = 2592, count = 3, name = "Wool Cloth" },
        { itemID = 4306, count = 10, name = "Silk Cloth" } }
      env.listings[2589] = { { unitPrice = 950, quantity = 40 }, { unitPrice = 1000, quantity = 10 } }
      env.listings[2592] = { { unitPrice = 500, quantity = 20 } }
      env.listings[4306] = {}
      env.openAuctionHouse()
      assert.equal(950, (ns.prices:marketValue("/1/Horde", "i:2589", env.now)), "no scan needed")
      assert.same({ "Linen Cloth", "20", "9s 49c", "7s 60c", "Needs setup" }, cells(w, 1))
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
      assert.same({ "Linen Cloth", "40", "9s 49c", "8s 0c", "Ready: 2 x 20" }, cells(w, 1))
      assert.same({ "Silk Cloth", "10", "20s 0c", "16s 0c", "Needs setup" }, cells(w, 2))
      assert.same({ "Wool Cloth", "3", "", "8s 0c", "Below floor" }, cells(w, 3))
      assert.equal("Post next: Linen Cloth, 20 for 9s 49c each", w.postView.postButton:GetText())
    end)

    it("posts one auction per click and moves on as the bags empty", function()
      local env, w = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.postButton:Click()
      assert.same({ kind = "commodity", loc = { bag = 0, slot = 1 }, duration = 2, quantity = 20, price = 949 },
        env.posts[1])
      assert.equal("Posting...", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.equal(1, #env.posts, "no second post before the game and the bags answer")
      env.containers[0][1] = false
      env.runTimers() -- the auction is created, and Linen Cloth is checked again
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal(4, #env.searches, "Linen Cloth checked again before its next post")
      assert.same({ "Linen Cloth", "20", "9s 49c", "8s 0c", "Ready: 1 x 20" }, cells(w, 1))
      w.postView.postButton:Click()
      assert.same({ bag = 0, slot = 2 }, env.posts[2].loc)
      env.containers[0][2] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Nothing ready to post", w.postView.postButton:GetText())
      assert.is_false(w.postView.postButton:IsEnabled())
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
      assert.equal("Confirm post: Linen Cloth, 20 for 9s 49c each", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.equal("confirm commodity", env.posts[2].kind)
    end)

    it("skips an item for this visit", function()
      local env, w = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.skipButton:Click()
      assert.equal("Skipped", cells(w, 1)[5])
      assert.equal("Nothing ready to post", w.postView.postButton:GetText())
      env.CloseAuctionHouse()
      env.openAuctionHouse()
      env.runTimers()
      assert.equal("Ready: 2 x 20", cells(w, 1)[5], "a new visit forgets it")
    end)

    it("explains the price and saves a posting profile from the detail panel", function()
      local env, w, ns = postSetup()
      env.openAuctionHouse()
      env.runTimers()
      w.postView.rows[1].button:Click()
      assert.equal("Linen Cloth", w.detailTitle:GetText())
      assert.equal(table.concat({
        "The cheapest other listing is 9s 50c each, so this posts at 9s 49c, 1 copper under it.",
        "Your floor is 8s 0c (80% of the 10s 0c market value).", "", "2 stacks of 20 post.",
      }, "\n"), w.detailBody:GetText())

      w.postView.rows[2].button:Click()
      assert.matches("first time you post this item", w.detailBody:GetText())
      assert.is_true(w.postView.editor:IsShown())
      assert.equal("10", w.postView.stackInput:GetText(), "all you have, with no competitors")
      w.postView.stackInput:SetText("5")
      w.postView.durationButtons[3]:Click()
      w.postView.saveButton:Click()
      assert.same({ stack = 5, duration = 3 }, ns.posting:profile("i:4306"))
      assert.equal("Ready: 2 x 5", cells(w, 2)[5])
      w.postView.stackInput:SetText("0")
      w.postView.saveButton:Click()
      assert.equal("Stack size must be a whole number of 1 or more.", w.postView.editorStatus:GetText())
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
      assert.same({ "Wool Cloth", "3", "4s 99c", "4s 0c", "Ready: 1 x 3" }, cells(w, 3))
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

    it("explains a first post against other sellers, and fills in the stack once the price is known", function()
      local env, w = postSetup()
      env.listings[4306] = { { unitPrice = 2100, quantity = 5 } }
      env.searchSilent = true
      env.openAuctionHouse()
      w.postView.rows[2].button:Click()
      env.searchSilent = false
      env.runTimers(10) -- the silent checks time out
      env.fire("BAG_UPDATE_DELAYED") -- and are tried again
      env.runTimers()
      assert.equal("Needs setup", cells(w, 2)[5])
      assert.matches("The cheapest other listing is 21s 0c each, so this posts at 20s 99c", w.detailBody:GetText())
      assert.equal("5", w.postView.stackInput:GetText(), "the most common competing stack")
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
      assert.equal("Nothing ready to post", w.postView.postButton:GetText())
      w.postView.postButton:Click()
      assert.equal(1, #env.posts, "nothing confirmed below the new floor")
    end)

    it("keeps the leftovers in the bags once the full stacks are posted", function()
      local env, w = postSetup()
      env.containers[0][2] = { itemID = 2589, count = 5, name = "Linen Cloth" }
      env.openAuctionHouse()
      env.runTimers()
      assert.equal("Ready: 1 x 20", cells(w, 1)[5])
      w.postView.postButton:Click()
      env.containers[0][1] = false
      env.runTimers()
      env.fire("BAG_UPDATE_DELAYED")
      env.runTimers()
      assert.equal("Leftover", cells(w, 1)[5])
      assert.equal(1, #env.posts)
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
