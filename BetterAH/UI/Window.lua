-- The Better AH window: native Forever frame templates and fonts (ADR 0002),
-- driven by WindowModel. Thin on purpose; game wiring is checked in game and
-- with the fake client in spec/window_spec.lua.
local _, ns = ...
ns = ns or {}

local Window = {}

-- The detail panel is 300 wide (#101: the snipe session log needed the room); the window grew with it,
-- so the main panel kept its size.
local WIDTH, HEIGHT, SIDEBAR, DETAIL = 1060, 470, 180, 300
local ROWS, ROW_HEIGHT, LIST_WIDTH = 14, 18, 540
-- A list with a scroll bar gives up this much width on its right, so the bar has room from the rows and
-- from the panel's edge (#53).
local SCROLL_ROOM, SCROLL_GAP = 22, 8
local COLUMNS = {
  { "Item", 4, 190 }, { "Lowest buyout", 196, 95 }, { "Market value", 293, 95 }, { "Quantity", 390, 55 },
  { "Seen", 447, 90 },
}
local ALT_COLUMNS = { { "Item", 4, 300 }, { "Total", 310, 90 }, { "Characters", 405, 90 } }
local HISTORY_LINES = 7
Window.WIDTH, Window.HEIGHT, Window.DETAIL = WIDTH, HEIGHT, DETAIL
local BLIZZARD_FRAMES = { "AuctionFrame", "AuctionHouseFrame" }
local TOP = -60 -- where the panels start, below the title bar and the toggle button

-- Art from Blizzard's own auction house (Blizzard_AuctionHouseUI in Forever build 1.60.1.71091), so the
-- window looks like it: the panel backgrounds and the category list's button art. The self-test checks
-- each one exists in the client.
-- The title bar's scan state: right-aligned left of the Blizzard UI button, clear of the portrait.
Window.SCAN_STATE_WIDTH = 480

Window.ART = {
  sidebar = "auctionhouse-background-categories",
  main = "auctionhouse-background-index",
  entry = "auctionhouse-nav-button",
  entrySelected = "auctionhouse-nav-button-select",
  entryHighlight = "auctionhouse-nav-button-highlight",
  rowHighlight = "auctionhouse-ui-row-highlight",
  rowSelected = "auctionhouse-ui-row-select",
  detail = "auctionhouse-background-sell-right",
}

-- What each placeholder view will show, until it is built.
Window.EMPTY = {
  cancel = "Your auctions that have been undercut will be listed here, ready to cancel.",
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
  self.mainPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(DETAIL + 10), 6)
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

  -- The full scan's state, on every view (#30): left of the Blizzard UI button.
  local scanState = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanState:SetPoint("RIGHT", toggle, "LEFT", -10, 0)
  scanState:SetJustifyH("RIGHT")
  scanState:SetWidth(Window.SCAN_STATE_WIDTH)
  if scanState.SetWordWrap then scanState:SetWordWrap(false) end
  self.scanStateText = scanState
  self.scanSpinner = ns.Loading.spinner(env, text)

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
  placeholder:SetWidth(WIDTH - SIDEBAR - DETAIL - 50)
  placeholder:SetJustifyH("LEFT")
  self.placeholder = placeholder

  self:buildDetail(f)
  self:buildPrices(f)
  self:buildAlts(f)
  self.postView = ns.PostView.new(self, self.addon)
  self.postPanel = self.postView:build(f, SIDEBAR + 16, TOP - 42, LIST_WIDTH, HEIGHT + TOP - 42 - 8)
  self.disenchantView = ns.DisenchantView.new(self, self.addon)
  self.disenchantPanel = self.disenchantView:build(f, SIDEBAR + 16, TOP - 42, LIST_WIDTH, HEIGHT + TOP - 42 - 8)
  if ns.BrowseView then
    -- Browse uses the main and detail panels' room together (mockup on #90).
    self.browseView = ns.BrowseView.new(self, self.addon)
    self.browsePanel = self.browseView:build(f, SIDEBAR + 16, TOP - 42, ns.BrowseView.WIDTH, HEIGHT + TOP - 42 - 8)
  end
  if ns.SettingsView then
    self.settingsView = ns.SettingsView.new(self, self.addon)
    self.settingsPanel = self.settingsView:build(f, SIDEBAR + 16, TOP - 42, LIST_WIDTH, HEIGHT + TOP - 42 - 8)
  end
  self:attachResize(f)
  self:renderView()
  return f
end

-- The resize grip (UI/WindowResize.lua), with the scale saved in BetterAHDB.window.
function Window:attachResize(f)
  if not (ns.WindowResize and ns.WindowScale) then return end
  local db = self.addon.db
  local saved = db and db.window or {}
  if db then db.window = saved end
  self.resize = ns.WindowResize.attach(self.env, f, WIDTH, HEIGHT, saved, Window.tooltip)
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

-- Prices and history: a Scan materials button, the scan status and one row per item on this market.
function Window:buildPrices(f)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 16, TOP - 42)
  panel:SetSize(LIST_WIDTH, HEIGHT + TOP - 42 - 8) -- down to the main panel's inner bottom
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scrollPrices(-delta * 3) end)
  self.pricesPanel = panel

  -- No Scan button: full scans run by themselves (#30, see autoScan).
  local mats = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  mats:SetSize(120, 22)
  mats:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  mats:SetText("Scan materials")
  mats:SetScript("OnClick", function() self:scanMaterials() end)
  Window.tooltip(env, mats, "Scan materials",
    "Look up the 24 disenchant materials only, so disenchant values use fresh prices without a full scan.")
  self.materialsButton = mats

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", mats, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
  status:SetJustifyH("LEFT")
  if status.SetMaxLines then status:SetMaxLines(2) end -- clear of the column headers below
  self.scanStatus = status
  self.scanLoading = ns.Loading.attach(env, panel, status, { "LEFT", mats, "RIGHT", 10, 0 })

  self.rows = self:buildRows(panel, COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:renderPrices() end)
end

-- A header row and ROWS selectable item rows under it, starting 32px below the panel's top, across
-- listWidth (LIST_WIDTH when nil).
-- Returns the item rows; each is an array of cells (font strings) plus .button. With onScroll, the rows
-- also get a scroll bar (rows.scrollBar, see buildScrollBar).
function Window:buildRows(panel, columns, onClick, onScroll, listWidth)
  local env, rows = self.env, {}
  listWidth = listWidth or LIST_WIDTH -- wider for a view without the detail panel (Browse)
  -- With a scroll bar the rows give up room for it. Columns laid out for the full width are narrowed
  -- to fit; a list can instead lay its columns out to fit the narrower rows and keep their widths.
  local width = onScroll and (listWidth - SCROLL_ROOM) or listWidth
  local last = columns[#columns]
  local scale = (last[2] + last[3] > width) and width / listWidth or 1
  rows.width = width
  for r = 0, ROWS do
    -- Item rows are buttons, so they can be selected; the header is plain text on the panel.
    local parent = panel
    if r > 0 then
      parent = env.CreateFrame("Button", nil, panel)
      parent:SetSize(width, ROW_HEIGHT)
      parent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -32 - r * ROW_HEIGHT + 3)
      local highlight = parent:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAtlas(Window.ART.rowHighlight, false)
      highlight:SetAllPoints(parent)
      highlight:SetBlendMode("ADD")
      local selected = parent:CreateTexture(nil, "ARTWORK")
      selected:SetAtlas(Window.ART.rowSelected, false)
      selected:SetAllPoints(parent)
      selected:SetBlendMode("ADD")
      selected:SetAlpha(0.5) -- softer than the art at full strength, so white text stays readable
      selected:Hide()
      parent.selectedTexture = selected
      local index = r
      parent:SetScript("OnClick", function() onClick(index) end)
    end
    local row = { button = r > 0 and parent or nil }
    for c, col in ipairs(columns) do
      local font = r == 0 and "GameFontNormalSmall" or "GameFontHighlightSmall"
      local cell = parent:CreateFontString(nil, "OVERLAY", font)
      local x, w = math.floor(col[2] * scale + 0.5), math.floor(col[3] * scale)
      if r == 0 then
        cell:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -32)
      else
        cell:SetPoint("LEFT", parent, "LEFT", x, 0)
      end
      cell:SetWidth(w)
      cell:SetJustifyH(col[4] or (c == 1 and "LEFT" or "RIGHT"))
      if r == 0 then cell:SetText(col[1]) end
      row[c] = cell
    end
    if r > 0 then rows[r] = row end
  end
  if onScroll then rows.scrollBar = self:buildScrollBar(panel, onScroll, width + SCROLL_GAP) end
  return rows
end

-- A scroll bar beside the item rows: Blizzard's slim MinimalScrollBar (the classic AH's own bar is
-- 25px, too wide for this layout). It hides itself while every item fits. Dragging it, clicking its
-- track or arrows, or wheeling over it calls onScroll(offset) with the first item to show (0-based);
-- Window.syncScrollBar keeps it in step with a list scrolled any other way.
function Window:buildScrollBar(panel, onScroll, x)
  local bar = self.env.CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -32 - ROW_HEIGHT + 3)
  bar:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x, -32 - (ROWS + 1) * ROW_HEIGHT + 3)
  bar.x = x
  bar:SetHideIfUnscrollable(true)
  bar.wheelPanScalar = 3 -- 3 rows per wheel notch, as over the list
  bar.total = 0
  bar:RegisterCallback("OnScroll", function(_, percentage)
    if bar.syncing then return end
    local max = bar.total - ROWS
    if max <= 0 then return end
    bar.moving = true
    local ok, err = pcall(onScroll, math.floor(percentage * max + 0.5))
    bar.moving = nil
    if not ok then error(err, 0) end
  end, bar)
  return bar
end

-- Sizes the bar's thumb for total items and moves it to offset. While the player is moving the bar
-- itself, only the sizes are updated, so the thumb stays under the cursor.
function Window.syncScrollBar(bar, offset, total)
  if not bar then return end
  bar.total = total
  local max = total - ROWS
  local held = bar.moving or (bar.IsThumbMouseDown and bar:IsThumbMouseDown())
  bar.syncing = true
  local ok, err = pcall(function()
    if max > 0 then
      bar:SetPanExtentPercentage(1 / max) -- one row per step
      bar:SetVisibleExtentPercentage(ROWS / total)
      if not held then bar:SetScrollPercentage(offset / max, true) end
    else
      bar:SetVisibleExtentPercentage(1) -- everything fits: the bar hides itself
      bar:SetScrollPercentage(0, true)
    end
  end)
  bar.syncing = nil
  if not ok then error(err, 0) end
end

-- Alts and inventory: every item the player's characters own, with totals.
function Window:buildAlts(f)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 16, TOP - 42)
  panel:SetSize(LIST_WIDTH, HEIGHT + TOP - 42 - 8)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scrollAlts(-delta * 3) end)
  self.altsPanel = panel
  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -6)
  status:SetWidth(LIST_WIDTH)
  status:SetJustifyH("LEFT")
  self.altsStatus = status
  self.altsRows = self:buildRows(panel, ALT_COLUMNS, function(index) self:selectAlt(index) end,
    function(offset) self.altsOffset = offset; self:renderAlts() end)
  self.altsOffset = 0
end

function Window:scrollAlts(by)
  self.altsOffset = self.altsOffset + by
  self:renderAlts()
end

function Window:selectAlt(r)
  local item = self.altsItems and self.altsItems[r + self.altsOffset]
  if not item then return end
  self.altSelected = item.item
  self:renderAlts()
end

Window.PLACE_NAMES = { bags = "in bags", bank = "in the bank", auctions = "on the auction house" }

-- Who has how many of an item, for the detail panel. by is CharacterRecords:count's second value.
function Window.altsDetailText(total, by)
  local lines = { "Total: " .. total, "" }
  for _, c in ipairs(by) do
    local parts = {}
    for _, place in ipairs({ "bags", "bank", "auctions" }) do
      if c[place] > 0 then parts[#parts + 1] = c[place] .. " " .. Window.PLACE_NAMES[place] end
    end
    if #parts == 1 then
      lines[#lines + 1] = string.format("%s: %s", c.name, parts[1])
    else
      lines[#lines + 1] = string.format("%s: %d (%s)", c.name, c.total, table.concat(parts, ", "))
    end
  end
  return table.concat(lines, "\n")
end

function Window:renderAlts()
  if not self.altsPanel then return end
  local records = self.addon.characters
  local api = self.addon.auctionAPI
  local nameOf = api and function(item) return api:itemName(item) end
  local items = records and records:items(nameOf) or {}
  self.altsItems = items
  local chars = records and records:characters() or {}
  self.altsOffset = math.max(0, math.min(self.altsOffset, math.max(0, #items - ROWS)))
  Window.syncScrollBar(self.altsRows.scrollBar, self.altsOffset, #items)
  if #chars == 0 then
    self.altsStatus:SetText("Nothing recorded yet. Your bags are read as you play, your bank when you open it.")
  else
    local unread = {}
    for _, c in ipairs(chars) do
      if not (c.seen and c.seen.bank) then unread[#unread + 1] = c.name end
    end
    local text = string.format("%d items across %d %s.", #items, #chars, #chars == 1 and "character" or "characters")
    if #unread > 0 then
      text = text .. " Bank not read yet for " .. table.concat(unread, ", ") .. ": open it once to include it."
    end
    self.altsStatus:SetText(text)
  end
  local selected
  for r, row in ipairs(self.altsRows) do
    local item = items[r + self.altsOffset]
    if item then
      row[1]:SetText(item.name or item.item)
      row[2]:SetText(tostring(item.total))
      row[3]:SetText(tostring(item.characters))
      row.button:Show()
    else
      for _, cell in ipairs(row) do cell:SetText("") end
      row.button:Hide()
    end
    row.button.selectedTexture:SetShown(item ~= nil and item.item == self.altSelected)
  end
  for _, it in ipairs(items) do
    if it.item == self.altSelected then selected = it break end
  end
  if selected then
    self.detailTitle:SetText(selected.name or selected.item)
    self.detailBody:SetText(Window.altsDetailText(records:count(selected.item)))
  else
    self.altSelected = nil
    self.detailTitle:SetText("")
    self.detailBody:SetText(#items > 0 and "Select an item to see which characters have it, and where." or "")
  end
end

-- The detail panel on the right of the window, beside the main panel: it explains the selected
-- thing, such as how an item's market value was worked out. Its art is the panel Blizzard's auction
-- house uses beside its sell form.
function Window:buildDetail(f)
  local env = self.env
  local detail = Window.panel(env, f, Window.ART.detail)
  detail:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, TOP)
  detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  detail:SetWidth(DETAIL)
  -- Text one level above the panel art (InsetFrameTemplate uses its parent's level).
  local text = env.CreateFrame("Frame", nil, detail)
  text:SetAllPoints(detail)
  text:SetFrameLevel(detail:GetFrameLevel() + 1)
  local title = text:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", text, "TOPLEFT", 12, -12)
  title:SetWidth(DETAIL - 24)
  title:SetJustifyH("LEFT")
  local body = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  body:SetWidth(DETAIL - 24)
  body:SetJustifyH("LEFT")
  body:SetSpacing(3)
  self.detailPanel, self.detailLayer, self.detailTitle, self.detailBody = detail, text, title, body
end

-- The disenchant part of the detail text, from Disenchant.value: the expected value, what it nets
-- after the auction house cut, and each material with its chance, amount and value.
function Window.disenchantText(value, breakdown, missing)
  local money = ns.Money.format
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  if value then
    add(string.format("Disenchant value: %s (%s after the 5%% auction house cut)", money(value),
      money(ns.Disenchant.net(value))))
  else
    add("Disenchant value: no prices for its materials yet")
  end
  for _, y in ipairs(breakdown or {}) do
    local amount = y.min == y.max and tostring(y.min) or (y.min .. "-" .. y.max)
    add(string.format("%s (%s%%, %s): %s", y.name, string.format("%.1f", y.chance * 100):gsub("%.0$", ""), amount,
      y.value and money(y.value) or "no price"))
  end
  if value and (missing or 0) > 0 then
    add("Materials without a price count as nothing. Scan to price them.")
  end
  return table.concat(lines, "\n")
end

-- The detail text for one item: its market value and how it was worked out, then its history.
-- Pure apart from formatting; value/info come from PriceDB:marketValue and history from PriceDB:history.
function Window.detailText(item, value, info, history, now)
  local money = ns.Money.format
  local today = ns.MarketValue.day(now)
  local function when(day)
    local age = today - day
    return age <= 0 and "today" or age == 1 and "yesterday" or (age .. " days ago")
  end
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add("Market value: " .. (value and money(value) or "none yet"))
  if not item.seen then
    add("Lowest buyout: not scanned yet")
  else
    add("Lowest buyout: " .. (item.lowest and money(item.lowest) or "none (bid only)"))
    add("Quantity listed: " .. tostring(item.quantity or 0))
  end
  add("")
  if value then
    local scan, search = info.scan, info.search
    if scan and today - scan.day < ns.MarketValue.DAYS then
      add(string.format("Scan %s: the average of the cheapest %d of %d listed, %s.", when(scan.day), scan.used,
        scan.units - scan.dropped, scan.dropped == 0 and "none left out"
        or string.format("leaving out %d priced far below the rest", scan.dropped)))
    end
    if search and today - search.day < ns.MarketValue.DAYS then
      add(string.format("Post view check %s: the middle price of the %d units other sellers have listed.",
        when(search.day), search.units))
    end
    if info.imported and today - info.imported < ns.MarketValue.DAYS then
      add("Includes imported prices from " .. when(info.imported) .. ".")
    end
    add(string.format("Smoothed over %d %s of the last 14, with recent days counting most.", info.days,
      info.days == 1 and "day" or "days"))
  elseif item.lowest and #history == 0 then
    add("Scanned before Better AH kept price history, so there's no market value yet. Scan again to get one.")
  else
    add("No buyouts seen in the last 14 days, so there's no market value yet.")
  end
  if #history > 0 then
    add("")
    add("Daily value (average of each day's scans and checks)")
    for i = #history, math.max(1, #history - HISTORY_LINES + 1), -1 do
      local h = history[i]
      local label = when(h.day)
      add(label:sub(1, 1):upper() .. label:sub(2) .. ": " .. money(h.value))
    end
  end
  return table.concat(lines, "\n")
end

function Window:selectRow(r)
  local item = self.cache and self.cache.items[r + self.offset]
  if not item then return end
  self.selected = item.item
  self:renderPrices()
end

function Window:renderDetail(items, now)
  local addon, key = self.addon, self.cache and self.cache.key
  local item
  for _, it in ipairs(items) do
    if it.item == self.selected then item = it break end
  end
  if not (item and addon.prices) then
    self.selected = nil
    self.detailTitle:SetText("")
    self.detailBody:SetText(#items > 0 and "Select an item to see its market value and how it was worked out."
      or "")
    return
  end
  local value, info = addon.prices:marketValue(key, item.item, now)
  self.detailTitle:SetText(item.name or item.item)
  local text = Window.detailText(item, value, info, addon.prices:history(key, item.item), now)
  local details = addon.auctionAPI and addon.auctionAPI:itemInfo(item.item)
  if details and ns.Disenchant and ns.Disenchant.yields(details) then
    local opts = ns.DisenchantView.options(addon)
    local deValue, breakdown, missing = ns.Disenchant.value(details, function(id)
      return (addon.prices:marketValue(key, "i:" .. id, now))
    end, opts)
    text = text .. "\n\n" .. Window.disenchantText(deValue, breakdown, missing)
    if opts.salvager and ns.Disenchant.salvagerAdds(breakdown) then
      text = text .. "\nCounts an Arcane Salvager (set in Disenchant snipe)."
    end
  end
  self.detailBody:SetText(text)
end

function Window:market()
  return ns.AuctionAPI and ns.AuctionAPI.currentMarket(self.env)
end

-- Looks up each disenchant material's listings (one search each, in the same queue as the Post view's
-- checks) and records other sellers' listings like a full scan of those items, without counting as a
-- full scan of the market.
function Window:scanMaterials()
  local addon = self.addon
  local api, key = addon.postingAPI, self:market()
  if self.materialScan then return end
  self.statusMarket, self.materialMarket = key, key
  if not (api and api.open and addon.prices and key) then
    self.statusText = "Open the auction house to scan materials."
    self.materialStatus = self.statusText
    return self:renderMaterials()
  end
  local mats = ns.Disenchant.MATERIALS
  local scan = { done = 0, found = 0, empty = 0, failed = 0, total = #mats }
  self.materialScan = scan
  self.statusText = string.format("Scanning materials: 0 of %d.", scan.total)
  self.materialStatus = self.statusText
  local function lookup(m, tries)
    local entry = ns.PostingAPI.commodityEntry(self.env, m.id, m.name)
    api:search(entry, function(listings, complete)
      if self.materialScan ~= scan then return end
      -- A lookup with no answer gets one more try, at the back of the queue.
      if not listings and tries < 2 and complete == "no answer from the auction house" then
        return lookup(m, tries + 1)
      end
      scan.done = scan.done + 1
      local rows = {}
      for _, l in ipairs(listings or {}) do
        -- Only other sellers' units: own listings would feed the value that sets their own floor.
        local count = (l.count or 0) - math.min(l.count or 0, l.ownCount or 0)
        if count > 0 and (l.unit or 0) > 0 then
          rows[#rows + 1] = { item = entry.item, name = m.name, count = count,
            buyout = math.floor(l.unit * count + 0.5) }
        end
      end
      if entry.uncached then scan.uncached = (scan.uncached or 0) + 1 end
      if not listings then
        scan.failed, scan.why = scan.failed + 1, complete
      elseif complete ~= true then
        scan.failed, scan.why = scan.failed + 1, "the auction house didn't send every listing"
      elseif #rows > 0 then
        addon.prices:recordScan(key, addon.auctionAPI and addon.auctionAPI:now() or 0, rows, true)
        scan.found = scan.found + 1
      else
        scan.empty = scan.empty + 1
      end
      if scan.done < scan.total then
        self.statusText = string.format("Scanning materials: %d of %d.", scan.done, scan.total)
      else
        self.materialScan = nil
        -- The values' changes (#106) are measured from one finished scan to the next.
        if scan.found > 0 then
          ns.DisenchantView.snapshot(addon, key, addon.auctionAPI and addon.auctionAPI:now() or 0)
        end
        self.statusText = string.format("Materials: %d updated, %d not listed by others", scan.found, scan.empty)
        if scan.failed > 0 then
          self.statusText = self.statusText .. string.format(", %d failed (%s%s)", scan.failed, tostring(scan.why),
            scan.uncached and string.format("; %d had to load item data", scan.uncached) or "")
        end
        self.statusText = self.statusText .. "."
      end
      self.materialStatus = self.statusText
      self:renderMaterials()
    end)
  end
  for _, m in ipairs(mats) do lookup(m, 1) end
  self:renderMaterials()
end

-- Redraws the views that show prices, after a scan or materials scan step.
function Window:renderMaterials()
  self:renderPrices()
  if self.model.view == "disenchant" and self.disenchantView then self.disenchantView:render() end
end

function Window:startScan()
  local addon = self.addon
  if not (addon.auctionAPI and addon.prices) then
    self.statusMarket = self:market()
    self.statusText = "Scanning isn't ready yet. Try again in a moment."
    self:scanEnded(false, "scanning isn't ready yet")
    return self:renderPrices()
  end
  -- Set the waiting text first: the reply may come before scanIntoPrices returns.
  self.statusMarket = self:market()
  self.statusText = "Scanning the auction house (a minute or two)."
  self.materialStatus = nil -- a full scan supersedes the last materials scan's message
  local started, why = ns.AuctionAPI.scanIntoPrices(addon, function(ok, message)
    if ok then ns.DisenchantView.snapshot(addon, self.statusMarket, addon.auctionAPI:now()) end
    self.statusText = message
    self.offset = 0
    self:scanEnded(ok, message)
    self:renderMaterials()
  end)
  if not started then
    self.statusText = why
    self:scanEnded(false, why)
  end
  self:renderMaterials()
end

-- Auto scan (#30). A scan is due by AutoScan's rules; this schedules it while the auction house is
-- open. Only the newest schedule runs (autoToken).
function Window:scheduleAutoScan(delay)
  local timer = self.env.C_Timer
  if self.addon.autoScan == false or not (timer and timer.After) then return end
  local token = {}
  self.autoToken = token
  if not delay then
    local s = self:scanState()
    delay = ns.AutoScan.wait(s.lastScan, s.now, s.failures, s.failedAt)
  end
  timer.After(math.max(delay, ns.AutoScan.FIRST_DELAY), function()
    if self.autoToken == token then self:autoScan() end
  end)
  -- The title's countdown, redrawn every half minute while waiting.
  self:scheduleTick(token)
end

function Window:scheduleTick(token)
  self.env.C_Timer.After(ns.AutoScan.TICK, function()
    if self.autoToken == token then
      self:renderScanState()
      self:scheduleTick(token)
    end
  end)
end

function Window:autoScan()
  local addon = self.addon
  local api = addon.auctionAPI
  if not (api and api.open) then return end
  local s = self:scanState()
  if ns.AutoScan.wait(s.lastScan, s.now, s.failures, s.failedAt) > 0 then return self:scheduleAutoScan() end
  -- Not in the middle of something: a running scan, a post or sniping waits for it. A full scan shares
  -- the auction house's query pipe with the snipe checks and buys, so it waits until sniping stops (#96).
  local snipe = self.disenchantView and self.disenchantView.snipe
  if api.pending or self.materialScan or (self.postView and self.postView.busy) or (snipe and (snipe.buying
    or snipe.running)) then
    return self:scheduleAutoScan(ns.AutoScan.BUSY_DELAY)
  end
  self:startScan()
end

-- A full scan ended (ok) or failed (why): count failures for the retry, then schedule the next one.
function Window:scanEnded(ok, why)
  local api = self.addon.auctionAPI
  if ok then
    self.scanFailures, self.scanFailedAt, self.scanWhy = 0, nil, nil
  elseif api and api.open then -- closing the auction house mid-scan isn't a failure
    self.scanFailures = (self.scanFailures or 0) + 1
    self.scanFailedAt = api:now()
    self.scanWhy = Window.shortReason(why)
  end
  if api and api.open then self:scheduleAutoScan() end
  self:renderScanState()
  -- Price checks that got no answer while the scan ran get another go (#82).
  if ok and self.postView and api and api.open then self.postView:scanEnded() end
end

-- The first sentence of a scan failure, for the title bar (the Prices status line keeps all of it).
function Window.shortReason(why)
  why = tostring(why or "no answer"):gsub("^Scan failed%.%s*", "")
  why = why:match("^(.-)%.%s") or why:gsub("%.$", "")
  if #why > 90 then why = why:sub(1, 87) .. "..." end
  return why:sub(1, 1):lower() .. why:sub(2)
end

function Window:scanState()
  local addon = self.addon
  local api = addon.auctionAPI
  local key = self:market()
  local now = api and api:now() or 0
  return { open = api and api.open, scanning = api and api.pending ~= nil, now = now,
    lastScan = key and addon.prices and addon.prices:lastScan(key), failures = self.scanFailures,
    failedAt = self.scanFailedAt, why = self.scanWhy,
    held = self.disenchantView and self.disenchantView.snipe and self.disenchantView.snipe.running or nil }
end

function Window:renderScanState()
  if not self.scanStateText then return end
  local s = self:scanState()
  if self.addon.autoScan == false then
    self.scanStateText:SetText("")
  else
    self.scanStateText:SetText(ns.AutoScan.status(s))
  end
  self.scanSpinner:SetShown(s.scanning and self.addon.autoScan ~= false)
  self:placeScanSpinner()
end

-- The line is right-aligned in a wide box, so the spinner goes just left of where its text starts.
function Window:placeScanSpinner()
  local text = self.scanStateText
  local width = text.GetStringWidth and tonumber(text:GetStringWidth()) or Window.SCAN_STATE_WIDTH
  width = math.min(width, Window.SCAN_STATE_WIDTH)
  self.scanSpinner:ClearAllPoints()
  self.scanSpinner:SetPoint("RIGHT", text, "RIGHT", -width - 6, 0)
end

-- A scan's progress on a status line's loading indicator: a bar of materials looked up, or a spinner
-- while a full scan runs. The auction house doesn't say how far along a full scan is, and a bar that
-- sweeps over and over looked stuck (#83).
function Window:showProgress(loading)
  local scan = self.materialScan
  if scan then
    loading:show(scan.done, scan.total)
  elseif self.addon.auctionAPI and self.addon.auctionAPI.pending then
    loading:spin()
  else
    loading:clear()
  end
end

function Window:scrollPrices(by)
  self.offset = self.offset + by
  self:renderPrices()
end

function Window:renderPrices()
  if not self.pricesPanel then return end
  local addon = self.addon
  local key = self:market()
  local now = addon.auctionAPI and addon.auctionAPI:now() or 0
  -- Sorting every item is only redone when the market's prices or the day change, not per scroll.
  local stamp = key and addon.prices and (addon.prices:version(key) .. "/" .. ns.MarketValue.day(now))
  if not (self.cache and self.cache.key == key and self.cache.stamp == stamp) then
    -- Names the item cache has loaded since the scan are picked up here, so they sort in place.
    local nameOf = addon.auctionAPI and function(item) return addon.auctionAPI:itemName(item) end
    self.cache = { key = key, stamp = stamp,
      items = (key and addon.prices) and addon.prices:items(key, nameOf, now) or {} }
  end
  local items = self.cache.items
  local maxOffset = math.max(0, #items - ROWS)
  self.offset = math.max(0, math.min(self.offset, maxOffset))
  Window.syncScrollBar(self.rows.scrollBar, self.offset, #items)
  local scanning = addon.auctionAPI and addon.auctionAPI.pending
  if scanning or self.materialScan then self.materialsButton:Disable() else self.materialsButton:Enable() end
  self:showProgress(self.scanLoading)
  self:renderScanState()

  -- A scan message belongs to the market it was about; on another market, show that one's state.
  if self.statusText and self.statusMarket ~= key then self.statusText = nil end
  local text = self.statusText
  if not text then
    local last = key and addon.prices and addon.prices:lastScan(key)
    if last then
      text = string.format("%d items. Last scan of %s: %s.", #items, ns.MarketKey.describe(key), ns.Time.ago(last, now))
    else
      text = "No scan of this market yet. One starts when the auction house is open."
    end
  end
  self.scanStatus:SetText(text)

  for r, row in ipairs(self.rows) do
    local item = items[r + self.offset]
    if item then
      -- Only the sorted name: a name looked up now would show out of order until the list is rebuilt.
      row[1]:SetText(item.name or item.item)
      row[2]:SetText(not item.seen and "-" or item.lowest and ns.Money.format(item.lowest) or "bid only")
      row[3]:SetText(item.value and ns.Money.format(item.value) or "-")
      row[4]:SetText(item.seen and tostring(item.quantity) or "-")
      row[5]:SetText(ns.Time.ago(item.seen, now))
      row.button:Show()
    else
      for _, cell in ipairs(row) do cell:SetText("") end
      row.button:Hide()
    end
    row.button.selectedTexture:SetShown(item ~= nil and item.item == self.selected)
  end
  -- The detail panel is shared between views: only the Prices view's own render may fill it.
  if self.model.view == "prices" then self:renderDetail(items, now) end
end

function Window:renderView()
  for id, b in pairs(self.buttons) do Window.markSelected(b, id == self.model.view) end
  self.heading:SetText(self.model:label(self.model.view))
  self.placeholder:SetText(Window.EMPTY[self.model.view] or "")
  local view = self.model.view
  self.placeholder:SetShown(view ~= "prices" and view ~= "alts" and view ~= "post" and view ~= "disenchant"
    and view ~= "settings" and not (view == "browse" and self.browsePanel))
  self:widenMain(view == "browse" and self.browsePanel ~= nil and self.browseView:wide())
  if self.browsePanel then self.browsePanel:SetShown(view == "browse") end
  self.pricesPanel:SetShown(view == "prices")
  self.disenchantPanel:SetShown(view == "disenchant")
  self.altsPanel:SetShown(view == "alts")
  self.postPanel:SetShown(view == "post")
  if self.settingsPanel then self.settingsPanel:SetShown(view == "settings") end
  if view ~= "settings" and self.settingsView then self.settingsView:hide() end
  if view ~= "browse" and self.browseView then self.browseView:hide() end
  if view ~= "post" then
    self.postView.editor:Hide()
    if self.postView.ruleEditor then self.postView.ruleEditor:Hide() end
  end
  if view ~= "disenchant" then self.disenchantView:hideEditors() end
  if view == "prices" then
    self:renderPrices()
  elseif view == "alts" then
    self:renderAlts()
  elseif view == "post" then
    if self.frame:IsShown() then self.postView:show() end
  elseif view == "disenchant" then
    self.disenchantView:render()
  elseif view == "settings" and self.settingsView then
    self.settingsView:render()
  elseif view == "browse" and self.browseView then
    self.browseView:render()
  else
    self.detailTitle:SetText("")
    self.detailBody:SetText("")
  end
end

-- Browse spreads the main panel over the detail panel's place; every other view has both.
function Window:widenMain(wide)
  if self.wide == wide then return end
  self.wide = wide
  local f = self.frame
  self.mainPanel:ClearAllPoints()
  self.mainPanel:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR + 6, TOP)
  self.mainPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", wide and -6 or -(DETAIL + 10), 6)
  self.detailPanel:SetShown(not wide)
end

function Window:render()
  local mode = self.model.mode
  self.switching = true
  if mode == "better" then
    self.cache = nil -- rebuild the price list on open, with any item names loaded since
    self:build():Show()
    self:concealBlizzard()
    self:renderView()
    self:renderScanState()
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
    -- A new visit (maybe another market): earlier failures don't carry over.
    self.scanFailures, self.scanFailedAt, self.scanWhy = 0, nil, nil
    self:scheduleAutoScan(ns.AutoScan.FIRST_DELAY)
    -- Blizzard shows its own window on the same event; let it finish first.
    if self.env.C_Timer then
      self.env.C_Timer.After(0, function() self:render() end)
    else
      self:render()
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.model:auctionClosed()
    self.autoToken = nil
    self:renderScanState()
    if self.postView then self.postView:reset() end
    if self.browseView then self.browseView:reset() end
    if self.disenchantView then self.disenchantView.snipe:stop("The auction house closed, so sniping stopped.") end
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
  -- Redraw the Alts view when the tracker reads bags, bank or auctions while it is on screen.
  if addon.tracker then
    addon.tracker.onChange = function()
      if w.frame and w.frame:IsShown() and w.model.view == "alts" then w:renderAlts() end
    end
  end
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
