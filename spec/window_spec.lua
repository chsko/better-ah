local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/WindowModel.lua")
  local core = { "Money", "Time", "MarketKey", "MarketValue", "PriceDB", "CharacterRecords", "SelfTest", "Probes" }
  for _, file in ipairs(core) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  ns.prices = ns.PriceDB.new({})
  ns.characters = ns.CharacterRecords.new({})
  ns.AuctionAPI.install(env, ns)
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
    assert.equal("Green, blue and epic listings worth more disenchanted than their buyout will be listed here.",
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
      if id ~= "prices" then assert.is_truthy((w.placeholder:GetText() or ""):find("%w"), id) end
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
      assert.same({ "Linen Cloth", "2s 0c", "2s 0c", "20", "just now" }, rowText(w, 1))
      assert.same({ "Wool Cloth", "30s 50c", "30s 50c", "10", "just now" }, rowText(w, 2))
      assert.same({ "", "", "", "", "" }, rowText(w, 3))
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
        "Daily value (average of each day's scans)",
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
        "Daily value (average of each day's scans)",
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
      assert.same({ "Wool Cloth", "3", "1" }, altRow(w, 2))
      assert.is_false(w.altsRows[3].button:IsShown())
      assert.equal("Select an item to see which characters have it, and where.", w.detailBody:GetText())

      w.altsRows[1].button:Click()
      assert.is_true(w.altsRows[1].button.selectedTexture:IsShown())
      assert.equal("Linen Cloth", w.detailTitle:GetText())
      assert.equal("Total: 75\n\nJaina: 10 (auctions 10)\nThrall: 65 (bags 25, bank 40)", w.detailBody:GetText())
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
end)
