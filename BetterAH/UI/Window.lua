-- The Better AH window: native Forever frame templates and fonts (ADR 0002),
-- driven by WindowModel. Thin on purpose; game wiring is checked in game and
-- with the fake client in spec/window_spec.lua.
local _, ns = ...
ns = ns or {}

local Window = {}

local WIDTH, HEIGHT, SIDEBAR = 820, 470, 180
local ROWS, ROW_HEIGHT = 14, 18
local COLUMNS = { { "Item", 0, 260 }, { "Lowest buyout", 270, 130 }, { "Quantity", 410, 70 }, { "Seen", 490, 110 } }
local BLIZZARD_FRAMES = { "AuctionFrame", "AuctionHouseFrame" }
local TOP = -60 -- where the panels start, below the title bar and the toggle button

-- Art from Blizzard's own auction house (Blizzard_AuctionHouseUI in Forever build 1.60.1.71091), so the
-- window looks like it: the panel backgrounds and the category list's button art. The self-test checks
-- each one exists in the client.
Window.ART = {
  sidebar = "auctionhouse-background-categories",
  main = "auctionhouse-background-index",
  entry = "auctionhouse-nav-button",
  entrySelected = "auctionhouse-nav-button-select",
  entryHighlight = "auctionhouse-nav-button-highlight",
}

-- What each placeholder view will show, until it is built.
Window.EMPTY = {
  post = "Items in your bags that are ready to post will be listed here.",
  cancel = "Your auctions that have been undercut will be listed here, ready to cancel.",
  disenchant = "Green, blue and epic listings worth more disenchanted than their buyout will be listed here.",
  deals = "Listings below 70% of market value and your shopping list hits will be listed here.",
  shopping = "Your shopping lists: items you want, with the most you'll pay for each.",
  crafting = "Recipes your characters know, with what each one costs to make and sells for.",
  alts = "Everything your characters own, with counts per character.",
}

-- env is the game's global table (_G in the client, a fake in specs).
-- addon is the namespace holding prices (PriceDB) and auctionAPI; optional in specs of the frame.
function Window.new(env, model, addon)
  local self = setmetatable({ env = env, model = model, addon = addon or {}, buttons = {}, concealed = {},
    offset = 0 }, { __index = Window })
  return self
end

function Window:blizzardFrame()
  for _, name in ipairs(BLIZZARD_FRAMES) do
    if self.env[name] then return self.env[name] end
  end
end

-- Hide Blizzard's window without calling Hide(): its OnHide closes the
-- auction house. It stays loaded, just invisible and out of the way.
function Window:concealBlizzard()
  local frame = self:blizzardFrame()
  if not frame or self.concealed[frame] then return end
  self.concealed[frame] = { alpha = frame:GetAlpha(), scale = frame:GetScale(), mouse = frame:IsMouseEnabled() }
  frame:SetAlpha(0)
  frame:SetScale(0.001)
  frame:EnableMouse(false)
end

function Window:revealBlizzard()
  local frame = self:blizzardFrame()
  local saved = frame and self.concealed[frame]
  if not saved then return end
  frame:SetAlpha(saved.alpha)
  frame:SetScale(saved.scale)
  frame:EnableMouse(saved.mouse)
  self.concealed[frame] = nil
end

function Window:closeAuctionHouse()
  local env = self.env
  if env.C_AuctionHouse and env.C_AuctionHouse.CloseAuctionHouse then
    env.C_AuctionHouse.CloseAuctionHouse()
  elseif env.CloseAuctionHouse then
    env.CloseAuctionHouse()
  end
end

function Window:build()
  if self.frame then return self.frame end
  local env = self.env
  -- The same outer frame as Blizzard's AuctionHouseFrame (Shared/Blizzard_AuctionHouseFrame.xml).
  local f = env.CreateFrame("Frame", "BetterAHFrame", env.UIParent, "PortraitFrameTemplate")
  -- Claim the frame at once so a later error can't lead to a second one.
  self.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 16, -116)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  -- Escape or the close button hides us; while we are the active window that
  -- means the player wants the auction house closed.
  f:SetScript("OnHide", function()
    if self.model.mode == "better" and not self.switching then self:closeAuctionHouse() end
  end)
  if env.UISpecialFrames then table.insert(env.UISpecialFrames, "BetterAHFrame") end

  f:SetTitle("Better AH")
  f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_02")
  self.sidebarPanel = Window.panel(env, f, Window.ART.sidebar)
  self.sidebarPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 4, TOP)
  self.sidebarPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 6)
  self.sidebarPanel:SetWidth(SIDEBAR - 2)
  self.mainPanel = Window.panel(env, f, Window.ART.main)
  self.mainPanel:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 6, TOP)
  self.mainPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  -- InsetFrameTemplate uses its parent's frame level, so text drawn on f could end up under the panel
  -- art. Texts live on this layer, one level up.
  local text = env.CreateFrame("Frame", nil, f)
  text:SetAllPoints(f)
  text:SetFrameLevel(f:GetFrameLevel() + 1)
  self.textLayer = text

  local toggle = env.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  toggle:SetSize(100, 22)
  toggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -28)
  toggle:SetText("Blizzard UI")
  toggle:SetScript("OnClick", function() self:toggle() end)
  Window.tooltip(env, toggle, "Blizzard UI",
    "Switch to Blizzard's auction house window. Use the Better AH button there to come back.")
  self.toggleButton = toggle

  local y = TOP - 10
  for _, section in ipairs(self.model:sections()) do
    local header = text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
    header:SetText(section.title:upper())
    y = y - 16
    for _, entry in ipairs(section.entries) do
      local b = Window.entryButton(env, f, SIDEBAR - 20)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y)
      b:SetText(entry.label)
      b:SetScript("OnClick", function() self:select(entry.id) end)
      self.buttons[entry.id] = b
      y = y - 21
    end
    y = y - 8
  end

  local heading = text:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  heading:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 16, TOP - 12)
  self.heading = heading

  local placeholder = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  placeholder:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
  placeholder:SetWidth(WIDTH - SIDEBAR - 40)
  placeholder:SetJustifyH("LEFT")
  self.placeholder = placeholder

  self:buildPrices(f)
  self:renderView()
  return f
end

-- An inset panel with an auction house background, like AuctionHouseBackgroundTemplate. That template
-- is load-on-demand, so its few lines are copied here rather than inherited.
function Window.panel(env, parent, atlas)
  local p = env.CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 3, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  bg:SetAtlas(atlas, false)
  p.Background = bg
  return p
end

-- A sidebar entry drawn like a button in Blizzard's auction category list. The sizes and anchors are the
-- ones AuctionHouseFilterButton_SetUp gives a "category" button, widened to our sidebar. We build our own
-- rather than use AuctionCategoryButtonTemplate, which needs Blizzard's setup code to look right.
function Window.entryButton(env, parent, width)
  local b = env.CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
  local normal = b:CreateTexture(nil, "BACKGROUND")
  normal:SetAtlas(Window.ART.entry, false)
  normal:SetSize(width + 4, 32)
  normal:SetPoint("TOPLEFT", -2, 0)
  local selected = b:CreateTexture(nil, "ARTWORK")
  selected:SetAtlas(Window.ART.entrySelected, false)
  selected:SetSize(width, 21)
  selected:SetPoint("LEFT")
  selected:Hide()
  b.selectedTexture = selected
  -- The HIGHLIGHT layer shows only while the mouse is over the button.
  local highlight = b:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAtlas(Window.ART.entryHighlight, false)
  highlight:SetSize(width, 21)
  highlight:SetPoint("LEFT")
  highlight:SetBlendMode("BLEND")
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("LEFT", b, "LEFT", 8, 0)
  text:SetJustifyH("LEFT")
  b:SetFontString(text)
  return b
end

-- Selected entries get Blizzard's selected art and white text; the rest keep gold text.
function Window.markSelected(b, on)
  b.selectedTexture:SetShown(on)
  b:GetFontString():SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
end

function Window.tooltip(env, button, title, text)
  button:SetScript("OnEnter", function(b)
    local tip = env.GameTooltip
    if not tip then return end
    tip:SetOwner(b, "ANCHOR_RIGHT")
    tip:SetText(title, 1, 1, 1)
    tip:AddLine(text, nil, nil, nil, true)
    tip:Show()
  end)
  button:SetScript("OnLeave", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
end

-- A small button on Blizzard's window to come back to Better AH.
function Window:attachReturnButton()
  local blizz = self:blizzardFrame()
  if not blizz or self.returnButton then return end
  local b = self.env.CreateFrame("Button", nil, blizz, "UIPanelButtonTemplate")
  b:SetSize(100, 22)
  b:SetPoint("TOPRIGHT", blizz, "TOPRIGHT", -60, -12)
  b:SetText("Better AH")
  b:SetScript("OnClick", function() self:toggle() end)
  Window.tooltip(self.env, b, "Better AH", "Switch back to the Better AH window.")
  self.returnButton = b
end

-- Prices and history: a Scan button, the scan status and one row per item on this market.
function Window:buildPrices(f)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 16, TOP - 42)
  panel:SetSize(WIDTH - SIDEBAR - 30, HEIGHT + TOP - 42 - 8) -- down to the main panel's inner bottom
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scrollPrices(-delta * 3) end)
  self.pricesPanel = panel

  local scan = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  scan:SetSize(90, 22)
  scan:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  scan:SetText("Scan")
  scan:SetScript("OnClick", function() self:startScan() end)
  self.scanButton = scan

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", scan, "RIGHT", 10, 0)
  self.scanStatus = status

  self.rows = {}
  for r = 0, ROWS do
    local row = {}
    for c, col in ipairs(COLUMNS) do
      local font = r == 0 and "GameFontNormalSmall" or "GameFontHighlightSmall"
      local cell = panel:CreateFontString(nil, "OVERLAY", font)
      cell:SetPoint("TOPLEFT", panel, "TOPLEFT", col[2], -32 - r * ROW_HEIGHT)
      cell:SetWidth(col[3])
      cell:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
      if r == 0 then cell:SetText(col[1]) end
      row[c] = cell
    end
    if r > 0 then self.rows[r] = row end
  end
end

function Window:market()
  return ns.AuctionAPI and ns.AuctionAPI.currentMarket(self.env)
end

function Window:startScan()
  local addon = self.addon
  if not (addon.auctionAPI and addon.prices) then
    self.statusMarket = self:market()
    self.statusText = "Scanning isn't ready yet. Try again in a moment."
    return self:renderPrices()
  end
  -- Set the waiting text first: the reply may come before scanIntoPrices returns.
  self.statusMarket = self:market()
  self.statusText = "Scanning the auction house. This can take a minute or two."
  local started, why = ns.AuctionAPI.scanIntoPrices(addon, function(_, message)
    self.statusText = message
    self.offset = 0
    self:renderPrices()
  end)
  if not started then self.statusText = why end
  self:renderPrices()
end

function Window:scrollPrices(by)
  self.offset = self.offset + by
  self:renderPrices()
end

function Window:renderPrices()
  if not self.pricesPanel then return end
  local addon = self.addon
  local key = self:market()
  -- Sorting every item is only redone when the market or its last scan changes, not per scroll.
  -- recordScan is the only writer today; a later writer (imports) must also bump lastScan.
  local stamp = key and addon.prices and addon.prices:lastScan(key)
  if not (self.cache and self.cache.key == key and self.cache.stamp == stamp) then
    -- Names the item cache has loaded since the scan are picked up here, so they sort in place.
    local nameOf = addon.auctionAPI and function(item) return addon.auctionAPI:itemName(item) end
    self.cache = { key = key, stamp = stamp, items = (key and addon.prices) and addon.prices:items(key, nameOf) or {} }
  end
  local items = self.cache.items
  local now = addon.auctionAPI and addon.auctionAPI:now() or 0
  local maxOffset = math.max(0, #items - ROWS)
  self.offset = math.max(0, math.min(self.offset, maxOffset))
  local scanning = addon.auctionAPI and addon.auctionAPI.pending
  if scanning then self.scanButton:Disable() else self.scanButton:Enable() end

  -- A scan message belongs to the market it was about; on another market, show that one's state.
  if self.statusText and self.statusMarket ~= key then self.statusText = nil end
  local text = self.statusText
  if not text then
    local last = key and addon.prices and addon.prices:lastScan(key)
    if last then
      text = string.format("%d items. Last scan of %s: %s.", #items, ns.MarketKey.describe(key), ns.Time.ago(last, now))
    else
      text = "No scan of this market yet. Press Scan to record its prices."
    end
  end
  self.scanStatus:SetText(text)

  for r, row in ipairs(self.rows) do
    local item = items[r + self.offset]
    if item then
      -- Only the sorted name: a name looked up now would show out of order until the list is rebuilt.
      row[1]:SetText(item.name or item.item)
      row[2]:SetText(item.lowest and ns.Money.format(item.lowest) or "bid only")
      row[3]:SetText(tostring(item.quantity))
      row[4]:SetText(ns.Time.ago(item.seen, now))
    else
      for _, cell in ipairs(row) do cell:SetText("") end
    end
  end
end

function Window:renderView()
  for id, b in pairs(self.buttons) do Window.markSelected(b, id == self.model.view) end
  self.heading:SetText(self.model:label(self.model.view))
  self.placeholder:SetText(Window.EMPTY[self.model.view] or "")
  local prices = self.model.view == "prices"
  if prices then
    self.placeholder:Hide()
    self.pricesPanel:Show()
    self:renderPrices()
  else
    self.placeholder:Show()
    self.pricesPanel:Hide()
  end
end

function Window:render()
  local mode = self.model.mode
  self.switching = true
  if mode == "better" then
    self.cache = nil -- rebuild the price list on open, with any item names loaded since
    self:build():Show()
    self:concealBlizzard()
  else
    if self.frame then self.frame:Hide() end
    self:revealBlizzard()
  end
  self.switching = false
  if mode == "blizzard" then self:attachReturnButton() end
end

function Window:select(id)
  if self.model:select(id) then self:renderView() end
end

function Window:toggle()
  self.model:toggle()
  self:render()
end

function Window:onEvent(event)
  if event == "AUCTION_HOUSE_SHOW" then
    self.model:auctionOpened()
    -- Blizzard shows its own window on the same event; let it finish first.
    if self.env.C_Timer then
      self.env.C_Timer.After(0, function() self:render() end)
    else
      self:render()
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.model:auctionClosed()
    self:render()
  end
end

-- Finds a part of a frame template and says how it was found: by parent key first, then by
-- global name (frame name plus suffix), accepting a global only if it is a child of the frame.
-- Templates differ between clients: a close button may have a CloseButton parent key, only the
-- global name $parentCloseButton, or neither. Each name is tried as a parent key and as a global suffix.
function Window.templatePart(env, frame, ...)
  for i = 1, select("#", ...) do
    local key = select(i, ...)
    if frame[key] then return key end
  end
  local name = frame:GetName()
  if not name then return nil end
  for i = 1, select("#", ...) do
    local global = name .. select(i, ...)
    local part = env[global]
    if type(part) == "table" and part.GetParent and part:GetParent() == frame then return global end
  end
  return nil
end

-- The ART atlases the client doesn't have, sorted; nil if the client can't say.
function Window.missingArt(env)
  local lookup = env.C_Texture and env.C_Texture.GetAtlasInfo
  if not lookup then return nil end
  local missing = {}
  for _, atlas in pairs(Window.ART) do
    if not lookup(atlas) then missing[#missing + 1] = atlas end
  end
  table.sort(missing)
  return missing
end

function Window.install(env, addon)
  local w = Window.new(env, addon.WindowModel.new(), addon)
  local events = env.CreateFrame("Frame")
  events:RegisterEvent("AUCTION_HOUSE_SHOW")
  events:RegisterEvent("AUCTION_HOUSE_CLOSED")
  events:SetScript("OnEvent", function(_, event) w:onEvent(event) end)
  addon.window = w
  if addon.Probes then
    addon.Probes.suite():add("Better AH window", function()
      local ok, frame = pcall(w.build, w)
      if not ok then return "fail", "could not create window: " .. tostring(frame) end
      local close = Window.templatePart(env, frame, "CloseButton")
      if not close then
        return "fail", "window has no close button (looked for CloseButton and " .. (frame:GetName() or "?")
          .. "CloseButton)"
      end
      local missing = Window.missingArt(env)
      if missing and #missing > 0 then
        return "fail", "auction house art missing from this client: " .. table.concat(missing, ", ")
      end
      local count = 0
      for _ in pairs(w.buttons) do count = count + 1 end
      return "pass", "window created with " .. count .. " sidebar entries; close button " .. close
        .. "; " .. (missing and "auction house art found" or "art not checked (no C_Texture.GetAtlasInfo)")
    end)
  end
  return w
end

ns.Window = Window
if ns.WindowModel and CreateFrame then Window.install(_G, ns) end
return Window
