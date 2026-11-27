-- The Snipe tab of the Disenchant view (issue #12): runs the ticked targets, one browse after another,
-- and shows one next buy at a time. Buy (or a mouse wheel turn over the tab) buys it, Pass drops it.
-- The session's spend is kept against a spend cap and a floor of gold to keep, with a log of what was
-- bought, passed and missed. The rules live in Core/Sniper.lua, the game calls in Game/SnipeAPI.lua.
-- Layout follows the mockup linked from #12.
local _, ns = ...
ns = ns or {}

local SnipeView = {}
SnipeView.__index = SnipeView

SnipeView.REST = 0.5 -- seconds between browses; the auction house's own throttle paces the queries
SnipeView.HISTORY = 20 -- finished sessions kept
-- The "closest to your max prices" list: columns as { label, x, width, justify } on a row NEAR_BAR_ROOM
-- narrower than the panel, which leaves room for its scroll bar inside the panel (#201).
-- Listed (how many the auction house has of the item, at all prices: a browse doesn't say how many
-- are at the cheapest) is last in the list but sits
-- between Target and Cheapest.
SnipeView.NEAR_COLUMNS = { { "Item", 4, 140, "LEFT" }, { "Target", 148, 116, "LEFT" }, { "Cheapest", 304, 68 },
  { "Max", 374, 68 }, { "vs. max", 444, 74 }, { "Listed", 264, 38 } }
-- Room right of the rows for the scroll bar, and the gap before it, as the other lists have (Window).
SnipeView.NEAR_BAR_ROOM, SnipeView.NEAR_BAR_GAP = 22, 8
SnipeView.NEAR_ROW = 17
-- Rows the closest list shows at a time; a scroll bar beside it reaches the rest (Sniper.CLOSEST, #201).
-- The mouse wheel over the tab still buys, so the list scrolls only by its bar (Christian, #201).
SnipeView.NEAR_VISIBLE = 5
-- A row whose listing is new or changed blinks: two fades in and out over FLASH seconds, up to
-- FLASH_ALPHA (#201).
SnipeView.FLASH, SnipeView.FLASH_PULSES, SnipeView.FLASH_ALPHA = 1.2, 2, 0.35
-- The session log's scroll area runs from under the title down to the settings box (#101); this is its
-- height until the client has laid it out.
SnipeView.LOG_HEIGHT = 250
SnipeView.LOG_STEP = 30 -- pixels a mouse wheel notch scrolls the log

-- The sniping settings, saved in BetterAHDB.disenchant.snipe: spend cap and gold to keep (copper, 0 for
-- none) and the sound on a find.
function SnipeView.settings(addon)
  addon.disenchant = addon.disenchant or {}
  local s = addon.disenchant.snipe or {}
  addon.disenchant.snipe = s
  s.cap, s.keep = tonumber(s.cap) or 0, tonumber(s.keep) or 0
  if s.sound == nil then s.sound = true end
  return s
end

-- One line of the session log.
function SnipeView.logLine(entry, env)
  local when = env and type(env.date) == "function" and env.date("%H:%M", entry.time) or ""
  local name = entry.name or "an item"
  if entry.kind == "bought" then
    return string.format("%s Bought %s for %s", when, name, ns.Money.format(entry.price or 0))
  elseif entry.kind == "passed" then
    return string.format("%s Passed %s", when, name)
  elseif entry.kind == "unsent" then
    return string.format("%s Not bought %s: %s. It's still next.", when, name, entry.note or "not sent")
  elseif entry.kind == "blocked" then
    return string.format("%s The game blocked %s", when, entry.note or "a call")
  end
  return string.format("%s Missed %s: %s", when, name, entry.note or "gone")
end

function SnipeView.new(dview)
  return setmetatable({ dview = dview, window = dview.window, env = dview.env, addon = dview.addon,
    round = 0, near = {}, seen = {}, why = {}, listed = {} }, SnipeView)
end

-- Redraws the Disenchant view, but only while the window shows it: sniping runs on behind other views,
-- whose detail panel it must not draw over.
function SnipeView:refresh()
  local w = self.window
  if w.model and w.model.view ~= "disenchant" then return end
  self.dview:render()
end

function SnipeView:api()
  return self.addon.snipeAPI
end

function SnipeView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

function SnipeView:build(p, width)
  local env = self.env
  self.panel = p
  p:EnableMouseWheel(true)
  -- A mouse wheel turn is a hardware event, so it can buy: each notch buys the next find.
  p:SetScript("OnMouseWheel", function() self:buyNext("the mouse wheel") end)

  local start = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  start:SetSize(110, 22)
  start:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  start:SetScript("OnClick", function() if self.running then self:stop() else self:start() end end)
  self.startButton = start
  local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", start, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  status:SetJustifyH("LEFT")
  self.status = status
  -- The spinner has a fixed slot in front of the line, kept free while it's hidden: the line is drawn
  -- again several times a second while sniping, and a spinner that followed the text would jitter.
  self.loading = ns.Loading.attach(env, p, status, { "LEFT", start, "RIGHT", 10, 0, slot = true })
  self.loading:clear()

  local spent = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  spent:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -34)
  self.spentText = spent
  local bar = p:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(0, 0, 0, 0.6)
  bar:SetPoint("TOPLEFT", p, "TOPLEFT", 230, -36)
  bar:SetSize(width - 230, 10)
  local fill = p:CreateTexture(nil, "OVERLAY")
  fill:SetColorTexture(0.79, 0.64, 0.23, 1)
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  fill:SetSize(1, 10)
  self.bar, self.fill, self.barWidth = bar, fill, width - 230
  local summary = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -52)
  summary:SetWidth(width)
  summary:SetJustifyH("LEFT")
  self.summary = summary

  -- The next buy.
  local card = env.CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -72)
  card:SetSize(width, 128)
  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(card)
  bg:SetColorTexture(0.14, 0.10, 0.05, 0.9)
  self.card = card
  local function text(font, x, y, w)
    local t = card:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
    if w then t:SetWidth(w) end
    t:SetJustifyH("LEFT")
    return t
  end
  self.cardLabel = text("GameFontDisableSmall", 10, -8, width - 20)
  self.cardName = text("GameFontNormalLarge", 10, -22, width - 130)
  self.cardHover = self:hoverItem(card, function() return self.shownFind end)
  self.cardHover:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -20)
  self.cardHover:SetSize(width - 136, 22)
  self.cardLevel = text("GameFontHighlightSmall", width - 120, -26, 110)
  self.cardLevel:SetJustifyH("RIGHT")
  self.cols = {}
  local third = math.floor((width - 20) / 3)
  for i, label in ipairs({ "Price", "Worth disenchanted", "Profit" }) do
    local x = 10 + (i - 1) * third
    text("GameFontDisableSmall", x, -46, third):SetText(label)
    self.cols[i] = { value = text("GameFontHighlightLarge", x, -60, third), note = text("GameFontDisableSmall", x,
      -80, third) }
  end
  local buy = env.CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  buy:SetSize(width - 120, 26)
  buy:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 6)
  buy:SetScript("OnClick", function() self:buyNext("the Buy button") end)
  self.buyButton = buy
  -- Turns while the auction house answers a buy.
  self.buySpinner = ns.Loading.spinner(env, buy)
  self.buySpinner:SetPoint("LEFT", buy, "LEFT", 10, 0)
  local pass = env.CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  pass:SetSize(90, 26)
  pass:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
  pass:SetText("Pass")
  pass:SetScript("OnClick", function() self:passNext() end)
  ns.Window.tooltip(env, pass, "Pass", "Skip this auction for the rest of the session.")
  self.passButton = pass
  -- The listings closest to the targets' max prices, buyable ones first (#59).
  local top = -206
  self.nearTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.nearTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 0, top)
  self.nearTitle:SetText("Closest to your max prices")
  self.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.hint:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, top)
  self.hint:SetWidth(width - 160)
  self.hint:SetJustifyH("RIGHT")
  if self.hint.SetWordWrap then self.hint:SetWordWrap(false) end
  local function cell(font, col, y)
    local t = p:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", p, "TOPLEFT", col[2], y)
    t:SetWidth(col[3])
    t:SetJustifyH(col[4] or "RIGHT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
  end
  for _, col in ipairs(SnipeView.NEAR_COLUMNS) do cell("GameFontDisableSmall", col, top - 16):SetText(col[1]) end
  -- Shown in place of the rows when nothing is close: what the last checks saw, and why none fit.
  self.nearEmpty = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.nearEmpty:SetPoint("TOPLEFT", p, "TOPLEFT", 4, top - 16 - SnipeView.NEAR_ROW)
  self.nearEmpty:SetWidth(width - 8)
  self.nearEmpty:SetJustifyH("LEFT")
  self.nearRows = {}
  local rowWidth = width - SnipeView.NEAR_BAR_ROOM
  for i = 1, SnipeView.NEAR_VISIBLE do
    local y = top - 16 - i * SnipeView.NEAR_ROW
    local row = {}
    local shade = p:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + 2)
    shade:SetSize(rowWidth, SnipeView.NEAR_ROW)
    shade:SetColorTexture(0.12, 1, 0, 0.12)
    shade:Hide()
    row.bg = shade
    local flash = p:CreateTexture(nil, "BORDER")
    flash:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + 2)
    flash:SetSize(rowWidth, SnipeView.NEAR_ROW)
    flash:SetColorTexture(1, 0.82, 0, 1)
    flash:SetAlpha(0)
    flash:Hide()
    row.flash = flash
    for c, col in ipairs(SnipeView.NEAR_COLUMNS) do
      row[c] = cell(c == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall", col, y)
    end
    row.hover = self:hoverItem(p, function() return row.entry end)
    row.hover:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + 2)
    row.hover:SetSize(rowWidth, SnipeView.NEAR_ROW)
    self.nearRows[i] = row
  end
  self:buildNearBar(p, rowWidth, top - 16 - SnipeView.NEAR_ROW + 2)
  -- Drives the row blinks while any is running; hidden (so no OnUpdate) otherwise.
  self.flashDriver = env.CreateFrame("Frame", nil, p)
  self.flashDriver:Hide()
  self.flashDriver:SetScript("OnUpdate", function() self:drawFlashes() end)
  self.nearOffset, self.nearList, self.flashes = 0, {}, {}
  self:buildSettings()
  self:buildLog()
end

-- The closest list's scroll bar, right of the rows (rowWidth wide), from y (its top) down NEAR_VISIBLE
-- rows. It hides itself while every row fits. Dragging it, clicking its track or arrows, or wheeling over the bar
-- itself scrolls the list a row at a time.
function SnipeView:buildNearBar(p, rowWidth, y)
  local bar = self.env.CreateFrame("EventFrame", nil, p, "MinimalScrollBar")
  local x = rowWidth + SnipeView.NEAR_BAR_GAP
  bar:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
  bar:SetPoint("BOTTOMLEFT", p, "TOPLEFT", x, y - SnipeView.NEAR_VISIBLE * SnipeView.NEAR_ROW)
  bar:SetHideIfUnscrollable(true)
  bar.wheelPanScalar = 1
  bar:RegisterCallback("OnScroll", function(_, percentage)
    if self.nearSyncing then return end
    local max = #self.nearList - SnipeView.NEAR_VISIBLE
    if max <= 0 then return end
    self.nearMoving = true
    local ok, err = pcall(function()
      self.nearOffset = math.floor(percentage * max + 0.5)
      self:drawNear()
    end)
    self.nearMoving = nil
    if not ok then error(err, 0) end
  end, bar)
  self.nearBar = bar
end

-- Sizes the bar's thumb for the list and moves it to the offset (not while the player moves the bar).
function SnipeView:syncNearBar()
  local bar, total, rows = self.nearBar, #self.nearList, SnipeView.NEAR_VISIBLE
  local max = total - rows
  local held = self.nearMoving or (bar.IsThumbMouseDown and bar:IsThumbMouseDown())
  self.nearSyncing = true
  local ok, err = pcall(function()
    if max > 0 then
      bar:SetPanExtentPercentage(1 / max)
      bar:SetVisibleExtentPercentage(rows / total)
      if not held then bar:SetScrollPercentage(self.nearOffset / max, true) end
    else
      bar:SetVisibleExtentPercentage(1)
      bar:SetScrollPercentage(0, true)
    end
  end)
  self.nearSyncing = nil
  if not ok then error(err, 0) end
end

-- Scrolls the closest list to show from row offset + 1 (kept in range).
function SnipeView:scrollNear(offset)
  self.nearOffset = offset
  self:drawNear()
end

-- A fine clock for the blinks: GetTime (seconds, with fractions), or the auction house's clock.
function SnipeView:fineTime()
  local t = self.env.GetTime and self.env.GetTime()
  return tonumber(t) or self:now()
end

-- Sets each shown row's blink for where it is in its FLASH, and forgets blinks that are over.
function SnipeView:drawFlashes()
  local now, live = self:fineTime(), false
  for key, started in pairs(self.flashes) do
    if now - started >= SnipeView.FLASH then self.flashes[key] = nil else live = true end
  end
  for _, row in ipairs(self.nearRows) do
    local started = row.entry and self.flashes[ns.Sniper.nearKey(row.entry)]
    if started then
      local phase = (now - started) * SnipeView.FLASH_PULSES / SnipeView.FLASH
      row.flash:SetAlpha(SnipeView.FLASH_ALPHA * (1 - math.cos(2 * math.pi * phase)) / 2)
      row.flash:Show()
    else
      row.flash:SetAlpha(0)
      row.flash:Hide()
    end
  end
  self.flashDriver:SetShown(live)
end

-- The session log, in the detail panel: newest first, in a scroll area above the settings box, with a
-- slim scroll bar that shows while it doesn't all fit (#101).
function SnipeView:buildLog()
  local env, w = self.env, self.window
  local layer = w.detailLayer
  local width = ns.Window.DETAIL - 24 - 16 -- room on the right for the bar
  local frame = env.CreateFrame("ScrollFrame", nil, layer)
  frame:SetPoint("TOPLEFT", w.detailTitle, "BOTTOMLEFT", 0, -8)
  frame:SetPoint("BOTTOMLEFT", self.settingsBox, "TOPLEFT", 0, 10)
  frame:SetWidth(width)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta) self:scrollLog(self.logScroll - delta * SnipeView.LOG_STEP) end)
  local child = env.CreateFrame("Frame", nil, frame)
  child:SetSize(width, SnipeView.LOG_HEIGHT)
  frame:SetScrollChild(child)
  local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
  text:SetWidth(width)
  text:SetJustifyH("LEFT")
  text:SetSpacing(3)
  local bar = env.CreateFrame("EventFrame", nil, layer, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 0)
  bar:SetHideIfUnscrollable(true)
  bar:RegisterCallback("OnScroll", function(_, percentage)
    if self.logSyncing then return end
    self:scrollLog(percentage * self:logRange(), true)
  end, bar)
  frame:Hide()
  bar:Hide()
  self.logFrame, self.logChild, self.logText, self.logBar, self.logScroll = frame, child, text, bar, 0
end

-- The scroll area's height: as laid out, or LOG_HEIGHT before that.
function SnipeView:logHeight()
  local h = tonumber(self.logFrame:GetHeight())
  return (h and h > 0) and h or SnipeView.LOG_HEIGHT
end

-- How far the log can scroll: its text's height past the scroll area.
function SnipeView:logRange()
  local height = tonumber(self.logText:GetStringHeight()) or 0
  return math.max(0, height - self:logHeight())
end

-- Scrolls the log to offset pixels from the top, kept in range, and moves the bar with it (unless the
-- bar itself moved it).
function SnipeView:scrollLog(offset, fromBar)
  local range = self:logRange()
  offset = math.max(0, math.min(range, offset or 0))
  self.logScroll = offset
  self.logFrame:SetVerticalScroll(offset)
  local height = tonumber(self.logText:GetStringHeight()) or 0
  local visible = self:logHeight()
  self.logChild:SetHeight(math.max(height, visible))
  local bar = self.logBar
  bar:SetShown(range > 0)
  self.logSyncing = true
  local ok, err = pcall(function()
    bar:SetVisibleExtentPercentage(range > 0 and visible / height or 1)
    bar:SetPanExtentPercentage(range > 0 and SnipeView.LOG_STEP / range or 0)
    if not fromBar then bar:SetScrollPercentage(range > 0 and offset / range or 0) end
  end)
  self.logSyncing = nil
  if not ok then error(err, 0) end
end

-- An invisible frame over a region that shows the item tooltip of what item() returns: a table with a
-- link (an auction's item link, which knows its random stats) or an itemKey. Nothing while it is nil.
function SnipeView:hoverItem(parent, item)
  local env = self.env
  local f = env.CreateFrame("Frame", nil, parent)
  f:EnableMouse(true)
  -- The tooltip API answers false (and hides the tooltip) when it has no data, so try each way in turn.
  local function try(tip, method, ...)
    if not tip[method] then return false end
    local ok, r = pcall(tip[method], tip, ...)
    return ok and r ~= false
  end
  function f.showTip()
    local tip, it = env.GameTooltip, item()
    if not tip then return end
    if not it then return tip:Hide() end
    tip:SetOwner(f, "ANCHOR_CURSOR")
    local key = it.itemKey
    local shown = (it.link and try(tip, "SetHyperlink", it.link))
      or (key and try(tip, "SetItemKey", key.itemID, key.itemLevel or 0, key.itemSuffix or 0))
      or (key and try(tip, "SetItemByID", key.itemID))
    if not shown then tip:Hide() end
  end
  f:SetScript("OnEnter", f.showTip)
  f:SetScript("OnLeave", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
  self.hovers = self.hovers or {}
  self.hovers[#self.hovers + 1] = f
  return f
end

-- After a render the item under the mouse may have changed (a buy, a new check): redraw its tooltip.
function SnipeView:refreshTips()
  local tip = self.env.GameTooltip
  if not (tip and tip.IsOwned) then return end
  for _, f in ipairs(self.hovers or {}) do
    if tip:IsOwned(f) then f.showTip() end
  end
end

-- Spend cap, gold to keep and the sound, at the bottom of the detail panel.
function SnipeView:buildSettings()
  local env, w = self.env, self.window
  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  box:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  box:SetSize(ns.Window.DETAIL - 24, 96)
  box:Hide()
  self.settingsBox = box
  local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  title:SetText("While sniping")
  local function field(label, y, key, tip)
    local l = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y - 4)
    l:SetText(label)
    local e = env.CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    e:SetSize(80, 20)
    e:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, y)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function(b) b.cancel = true; b:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(b)
      if type(env.EditBox_ClearHighlight) == "function" then pcall(env.EditBox_ClearHighlight, b) end
      local cancel = b.cancel
      b.cancel = nil
      if not cancel then self:saveSetting(key, b:GetText()) end
      self:render()
    end)
    ns.Window.tooltip(env, e, label, tip)
    return e
  end
  self.capInput = field("Spend cap", -16, "cap", "The most to spend in one sniping session, like 5g. "
    .. "Empty or 0 for no cap.")
  self.keepInput = field("Always keep", -40, "keep", "Never buy if it would leave you with less gold than "
    .. "this, like 20g. Empty or 0 for none.")
  local sound = env.CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
  sound:SetSize(20, 20)
  sound:SetPoint("TOPLEFT", box, "TOPLEFT", -2, -64)
  local label = sound.Text
  if not label then
    label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", sound, "RIGHT", 1, 0)
  end
  label:SetText("Sound on a find")
  if sound.SetHitRectInsets then sound:SetHitRectInsets(0, -90, 0, 0) end
  sound:SetScript("OnClick", function(b) SnipeView.settings(self.addon).sound = b:GetChecked() and true or false end)
  self.soundBox = sound
end

function SnipeView:saveSetting(key, text)
  text = (text or ""):gsub("%s", "")
  local amount = text == "" and 0 or ns.Money.parse(text)
  if not amount then
    self.message = "Type an amount like 5g or 20g 50s."
    return
  end
  SnipeView.settings(self.addon)[key] = amount
  self.message = nil
end

-- The ticked targets that can run: with item types and a known band.
function SnipeView:runnable()
  local out = {}
  for _, t in ipairs(self.dview:targets():list()) do
    local row = self.dview:rowFor(t.band)
    if t.enabled and row and next(ns.Targets.classes(t)) then out[#out + 1] = { target = t, row = row } end
  end
  return out
end

-- The most to pay for a find under the targets as they are now, or nil when the target it came from no
-- longer runs (deleted, unticked, its band or item types changed) or its item is no longer wanted (#206).
function SnipeView:currentMax(find)
  for _, e in ipairs(self:runnable()) do
    if e.target == find.source and e.row.band.min == find.band then
      local m, _, no = self:maxFor(e, find.itemID)
      if no == "loading" then return find.max end
      return m
    end
  end
  return nil
end

-- Drops the finds the targets no longer want (#206), but never the one a buy waits on.
function SnipeView:prune()
  if not self.session then return 0 end
  return self.session:keep(function(f) return self:currentMax(f) end, self.buying)
end

function SnipeView:start()
  local api = self:api()
  if not (api and api:open()) then
    self.message = "Open the auction house to snipe."
    return self:refresh()
  end
  if #self:runnable() == 0 then
    self.message = "Tick at least one target on Targets first."
    return self:refresh()
  end
  local db = self.addon.disenchant
  SnipeView.file(db, self:now())
  db.session = {}
  -- A new session's closest list starts at the top, with nothing to compare its first rows with.
  self.nearSigs, self.flashes, self.nearOffset, self.nearBaseline = nil, {}, 0, {}
  self.session = ns.Sniper.Session.new(db.session, self:now())
  self.running, self.message, self.lastCheck, self.near, self.seen, self.why = true, nil, nil, {}, {}, {}
  self.requested = {}
  self.run = {} -- this run's identity: late answers from an earlier run are dropped
  self.held = nil
  -- Any call of this addon the game blocks while sniping goes in the session log (#96).
  local session = self.session
  -- Deferred a moment: queries waiting for the auction house (this addon's own) are sent on the same
  -- event, and the Buy button should see that.
  api.onReady = function()
    if not self.env.C_Timer then return end
    self.env.C_Timer.After(0, function()
      if self.running and self.session == session then self:refresh() end
    end)
  end
  api.onBlocked = function(event, what)
    if not self.running or self.session ~= session then return end
    session:log(self:now(), "blocked", nil, what .. (event == "ADDON_ACTION_FORBIDDEN" and " (forbidden)" or ""))
    self:refresh()
  end
  self:refresh()
  self:tick(self.run)
  self:clock(self.run)
end

-- Why the next check waits (#96), or nil. Checks keep the auction house's one query pipe busy, and a buy
-- sent while it is busy gets no answer: so no checks while a find waits to be bought or passed, or a buy
-- waits for its answer. A full scan or a materials scan uses the same pipe, so checks wait for those too.
-- A find that can't be bought now (spend cap, gold) doesn't hold checks: nothing would ever free them.
function SnipeView:holdReason()
  local find = self.session and self.session:next()
  if find and not self.buying then
    local s, api = SnipeView.settings(self.addon), self:api()
    if not self.session:canBuy(find.price, api and api:money(), s.cap, s.keep, self:now()) then find = nil end
  end
  if self.buying or find then return "a find waits: buy it or pass" end
  local api = self.addon.auctionAPI
  if api and api.pending then return "a full scan is running" end
  if self.window.materialScan then return "the materials scan is running" end
  return nil
end

-- Keeps "checked Xs ago" current while a check waits on the auction house: once a second, the status
-- line alone is drawn again.
function SnipeView:clock(run)
  if not (self.running and self.run == run and self.env.C_Timer) then return end
  self.env.C_Timer.After(1, function()
    if not (self.running and self.run == run) then return end
    self:renderStatus()
    -- The Buy button follows the auction house's readiness; a missed ready event mustn't leave it on
    -- "Wait..." (#101).
    if self.drawnReady ~= nil and self.drawnReady ~= self:api():ready() then self:refresh() end
    self:clock(run)
  end)
end

-- Files the saved session in the history (once), unless nothing happened in it (busy: a buy is still
-- waiting for its answer). The entry is the session table itself, so a buy the auction house confirms
-- after Stop still counts in it.
function SnipeView.file(db, now, busy)
  local s = db.session
  if not s or s.ended or (not busy and ((s.bought or 0) + #(s.log or {})) == 0) then return end
  s.ended = now
  db.history = db.history or {}
  table.insert(db.history, 1, s)
  while #db.history > SnipeView.HISTORY do table.remove(db.history) end
end

-- Ends sniping and files the session in the history.
function SnipeView:stop(why)
  if not self.running then return end
  self.running, self.run = false, nil
  self.message = why
  SnipeView.file(self.addon.disenchant, self:now(), self.buying ~= nil)
  if self.session then self.session.finds = {} end
  self:refresh()
end

-- The most to pay for an item of a target, by the item's class (armor and weapons are worth different
-- amounts), and its worth. nil when it isn't one of the target's types, has no worth, or not even its
-- class is known yet.
-- The third value says why there is no max: "loading", "type" (not one of the target's types, or a known
-- quality that isn't green) or "worth" (no material prices for its class).
function SnipeView:maxFor(entry, itemID)
  local t, row = entry.target, entry.row
  local api = self.addon.auctionAPI
  local info = api and api:itemInfo("i:" .. itemID)
  if not (info and info.classID) then
    -- Not in the cache: ask for it (for the name and level), and judge it by its class meanwhile, which
    -- GetItemInfoInstant knows right away. The browse only asks for greens, so the quality is known.
    local load = self.env.C_Item and self.env.C_Item.RequestLoadItemDataByID
    self.requested = self.requested or {}
    if type(load) == "function" and not self.requested[itemID] then
      self.requested[itemID] = true
      pcall(load, itemID)
    end
    info = api and api:itemType("i:" .. itemID)
    if not (info and info.classID) then return nil, nil, "loading" end
  end
  local typeID = ns.Targets.typeOf(info)
  local quality = tonumber(info.quality)
  if not (typeID and t.types[typeID]) or (quality and quality ~= 2) then return nil, nil, "type" end
  local worth = row[ns.Targets.BY_ID[typeID].class].net
  if not worth then return nil, nil, "worth" end
  return ns.Targets.maxPrice(t, worth), worth
end

SnipeView.WHY = { { "loading", "not loaded yet" }, { "type", "other types" }, { "band", "outside the band" },
  { "worth", "no worth known" }, { "profit", "profit above worth" }, { "price", "no buyout" },
  { "unreadable", "unreadable" } }

-- One round: browse the next target, then look up the auctions of the browse results under its max
-- price. The next round starts REST seconds after this one's lookups are done.
function SnipeView:tick(run)
  if not self.running or self.run ~= run then return end
  local list = self:runnable()
  if #list == 0 then return self:stop("No ticked targets left to snipe.") end
  self:prune()
  local hold = self:holdReason()
  if hold ~= self.held then
    self.held = hold
    self:refresh()
  end
  if hold then
    if self.env.C_Timer then self.env.C_Timer.After(SnipeView.REST, function() self:tick(run) end) end
    return
  end
  self.round = self.round % #list + 1
  local entry = list[self.round]
  local band = entry.row.band
  local query = ns.Sniper.browseQuery(entry.target, band)
  local api = self:api()
  local function rest()
    if self.run == run then self:refresh() end
    if self.running and self.run == run and self.env.C_Timer then
      self.env.C_Timer.After(SnipeView.REST, function() self:tick(run) end)
    end
  end
  self:refresh()
  api:browse(query, function(results, why)
    if self.run ~= run then return end
    self.lastCheck = self:now()
    if not results then
      self.problem = why
      self:refresh()
      return rest()
    end
    self.problem = nil
    local worthOf, maxOf, whyOf, levelOf = {}, {}, {}, {}
    local function max(itemID)
      if maxOf[itemID] == nil then
        local m, worth, no = self:maxFor(entry, itemID)
        maxOf[itemID], worthOf[itemID], whyOf[itemID] = m or false, worth, no
      end
      return maxOf[itemID] or nil, whyOf[itemID]
    end
    local function level(itemID)
      if levelOf[itemID] == nil then
        local info = self.addon.auctionAPI and self.addon.auctionAPI:itemInfo("i:" .. itemID)
        levelOf[itemID] = info and info.level or false
      end
      return levelOf[itemID] or nil
    end
    local name = ns.DisenchantView.targetName(entry.target, entry.row)
    self.seen[entry.target] = #results
    self.why[entry.target] = ns.Sniper.why(band, results, max, level)
    -- What this check saw, cheapest per item, for Profit now on Targets (#246). Kept after sniping stops:
    -- Targets uses it on this market while it is newer than the full scan and the target still asks the
    -- same query.
    local listed = {}
    for _, r in ipairs(results) do
      local id = r.itemKey and r.itemKey.itemID
      if id and (r.minPrice or 0) > 0 then listed[#listed + 1] = { item = "i:" .. id, price = r.minPrice } end
    end
    self.listed[entry.target] = { time = self:now(), market = self.window:market(),
      signature = ns.Targets.signature(entry.target), listings = listed }
    local near = ns.Sniper.near(band, results, max, level)
    for _, e in ipairs(near) do e.target = name end
    self.near[entry.target] = near
    local candidates = ns.Sniper.candidates(band, results, max,
      function(key, minPrice) return self.session:fresh(key, minPrice, self:now()) end, level)
    local left = #candidates
    if left == 0 then
      self:refresh()
      return rest()
    end
    for _, c in ipairs(candidates) do
      self.session:lookedUp(c.itemKey, c.minPrice, self:now())
      api:auctions(c.itemKey, function(listings)
        if self.run ~= run then return end
        if listings then self.session:sawListings(c.itemKey, listings) end
        local found = false
        for _, l in ipairs(ns.Sniper.buys(listings, c.max)) do
          local auctionAPI = self.addon.auctionAPI
          local itemName = l.link or (auctionAPI and auctionAPI:itemName("i:" .. c.itemKey.itemID))
          local find = { auctionID = l.auctionID, itemID = c.itemKey.itemID, itemKey = c.itemKey,
            link = l.link, count = l.count,
            name = itemName or ("item " .. c.itemKey.itemID),
            price = l.unit, worth = worthOf[c.itemKey.itemID], max = c.max, target = name,
            level = c.level, source = entry.target, band = band.min }
          -- The target may have been deleted or edited while the lookup was out (#206).
          local now = self:currentMax(find)
          if now and find.price <= now then found = self.session:add(find) or found end
        end
        if found and SnipeView.settings(self.addon).sound then api:alert() end
        left = left - 1
        self:refresh()
        if left == 0 then rest() end
      end)
    end
  end)
end

-- Buys the next find. Runs inside a click or a mouse wheel turn (a hardware event).
function SnipeView:buyNext(source)
  -- No prune here (#206): nothing but the buy goes before PlaceBid (#130). Every redraw prunes, so the
  -- card shows what this buys.
  local find = self.running and self.session and self.session:next()
  if not find or self.buying then return end
  -- Still answering the last buy or check: a buy now would be refused, so this notch does nothing. The
  -- Buy button says to wait, and comes back when the auction house is ready (#101).
  if not self:api():ready() then return end
  local s = SnipeView.settings(self.addon)
  local api = self:api()
  local ok, why = self.session:canBuy(find.price, api:money(), s.cap, s.keep, self:now())
  if not ok then
    self.message = "Can't buy " .. find.name .. ": " .. why .. "."
    return self:refresh()
  end
  -- PlaceBid goes first and the view is redrawn after it (#130), as Browse does since #120: with the redraw
  -- first (the Buy button greyed to "Buying..."), the game blocked PlaceBid from the click and the wheel
  -- in game, and Browse's purchase stopped being blocked once it sent first. The cause is believed, not
  -- proven. self.buying is set first so a second notch in the same moment doesn't buy twice.
  self.buying = find
  self.message = nil
  -- The answer counts in the session the buy was made in, even after Stop or a new Start.
  local session = self.session
  api:buy(find.auctionID, find.price, function(bought, failure, kind)
    if self.buying == find then self.buying = nil end
    if bought then
      session:bought(self:now(), find)
      -- find.price is one auction's buyout (buyoutAmount is per item: a result of quantity n is n
      -- single auctions), and PlaceBid buys one of them.
      if self.addon.purchases then self.addon.purchases:bought(find.itemID, find.link, 1, find.price, self:now()) end
      if self.addon.ledgerAPI then self.addon.ledgerAPI:bought(find.itemID, find.name, 1, find.price, "Snipe") end
      -- pcall: the record must never cost the redraw below.
      if self.addon.snipeProfit then
        pcall(function()
          self.addon.snipeProfit:bought(find.itemID, find.link, find.price, self:now(), self:profitTarget(find))
        end)
      end
    else
      session:missed(self:now(), find, failure, kind)
    end
    self:refresh()
  end, source)
  self:refresh()
end

-- The target a bought find counts toward in Disenchant > Results (#254): a copy of its name, item level
-- band, profit and the worth the sniper saw, taken now so a later edit of the target doesn't move it.
function SnipeView:profitTarget(find)
  local target = find.source
  if type(target) ~= "table" then return nil end
  local row = self.dview and self.dview:rowFor(find.band)
  local max = row and row.band.max
  if not max then
    for _, b in ipairs(ns.Disenchant.greenBands()) do
      if b.min == find.band then max = b.max end
    end
  end
  return { name = ns.Targets.typesText(target), min = find.band, max = max,
    profit = ns.Targets.profitText(target), worth = find.worth }
end

function SnipeView:passNext()
  local find = self.session and self.session:next()
  if not find or self.buying then return end
  self.session:pass(self:now(), find.auctionID)
  self:refresh()
end

-- A closest-list row's item name, looked up each time the list is drawn: an item the client hadn't
-- loaded at the check gets its name once it loads (#147). A lookup's link gives the full name with
-- the random suffix, which tells "of the Eagle" from "of Stamina".
function SnipeView:nearName(key)
  local full = self.session and self.session:nameOf(key)
  if full then return full end
  local auctionAPI = self.addon.auctionAPI
  local name = auctionAPI and auctionAPI:itemName("i:" .. key.itemID)
  if name then return name end
  local load = self.env.C_Item and self.env.C_Item.RequestLoadItemDataByID
  self.requested = self.requested or {}
  if type(load) == "function" and not self.requested[key.itemID] then
    self.requested[key.itemID] = true
    pcall(load, key.itemID)
  end
  return "item " .. key.itemID
end

-- The listings closest to the targets' max prices, from each ticked target's last check.
function SnipeView:renderNear()
  -- Each target's last check, with its max price and name as the target is now (it may have been
  -- edited since).
  local lists, seen, checked, why = {}, 0, false, {}
  if self.running then
    for _, entry in ipairs(self:runnable()) do
      if self.seen[entry.target] then seen, checked = seen + self.seen[entry.target], true end
      for k, n in pairs(self.why[entry.target] or {}) do why[k] = (why[k] or 0) + n end
      local list, fresh = self.near[entry.target], {}
      local name = ns.DisenchantView.targetName(entry.target, entry.row)
      local now = self:now()
      for _, e in ipairs(list or {}) do
        local max = self:maxFor(entry, e.itemKey.itemID)
        -- The browse's cheapest can lag behind what was just bought or found gone (#145). While the
        -- item's lookup still matches this browse's cheapest (Session:fresh), its listings, less what
        -- was bought or written off since, say what is left. Nothing left drops the row.
        local price = e.minPrice
        if self.session and self.session:fresh(e.itemKey, e.minPrice, now) then
          local left = self.session:cheapest(e.itemKey)
          if left ~= nil then price = left end
        end
        if max and max > 0 and price then
          fresh[#fresh + 1] = { itemKey = e.itemKey, minPrice = price, browsePrice = e.minPrice, max = max,
            delta = max - price, target = name, quantity = e.quantity, targetKey = tostring(entry.target),
            targetRef = entry.target }
        end
      end
      lists[#lists + 1] = fresh
    end
  end
  local near = ns.Sniper.closest(lists)
  -- An item under the max is buyable while it has a find waiting, or hasn't been looked up yet. Once
  -- looked up with nothing to buy (passed, or only your own auctions), it isn't tinted.
  local queued = {}
  for _, f in ipairs(self.session and self.session.finds or {}) do queued[f.itemID or 0] = true end
  local now = self:now()
  local function buyable(e)
    if e.delta < 0 then return false end
    return queued[e.itemKey.itemID] or not (self.session and self.session:fresh(e.itemKey, e.browsePrice, now))
  end
  if self.running then
    local finds = self.session and self.session.finds or {}
    local parts = {}
    for _, w in ipairs(SnipeView.WHY) do
      if (why[w[1]] or 0) > 0 then parts[#parts + 1] = why[w[1]] .. " " .. w[2] end
    end
    self.nearEmpty:SetText(#near == 0 and (checked and string.format("Last checks: %d green%s%s", seen,
      seen == 1 and "" or "s", #parts > 0 and (": " .. table.concat(parts, ", ") .. ".") or " listed.")
      or "Waiting for the first check.") or "")
    self.hint:SetText(#near == 0 and "Nothing close yet."
      or #finds > 0 and "Turn the mouse wheel over this tab to buy the next find."
      or "From the last check of each target.")
  else
    self.hint:SetText("Shows what is close to your max prices while sniping.")
    self.nearEmpty:SetText("")
  end
  -- Blink the rows whose listing is new or changed since the last draw (none on a session's first list).
  -- An empty list (before a session's first check, or between) isn't compared with, so the first
  -- rows to arrive don't all blink.
  local changed, sigs = ns.Sniper.changes(self.nearSigs, near)
  if #near > 0 then self.nearSigs = sigs end
  -- A target's first check of the session only sets its baseline: with several targets checked one after
  -- another, the rows each one brings in at first don't blink either.
  local flashAt = self:fineTime()
  self.nearBaseline = self.nearBaseline or {}
  for _, e in ipairs(near) do
    local key = ns.Sniper.nearKey(e)
    local started = self.flashes[key]
    -- A row still blinking carries on rather than jumping back to the start.
    local live = started and flashAt - started < SnipeView.FLASH
    if changed[key] and self.nearBaseline[e.targetRef] and not live then self.flashes[key] = flashAt end
  end
  for _, entry in ipairs(self.running and self:runnable() or {}) do
    if self.near[entry.target] then self.nearBaseline[entry.target] = true end
  end
  self.nearList = near
  self.nearBuyable = {}
  for i, e in ipairs(near) do self.nearBuyable[i] = buyable(e) and true or false end
  self:drawNear()
end

-- Draws the NEAR_VISIBLE rows of the closest list from nearOffset, and its scroll bar.
function SnipeView:drawNear()
  local short = ns.Money.short
  local near = self.nearList
  self.nearOffset = math.max(0, math.min(self.nearOffset or 0, #near - SnipeView.NEAR_VISIBLE))
  for i, row in ipairs(self.nearRows) do
    local e = near[self.nearOffset + i]
    row.entry = e
    -- Named only for the rows shown: the list behind them can hold hundreds of items.
    row[1]:SetText(e and self:nearName(e.itemKey) or "")
    row[2]:SetText(e and e.target or "")
    row[3]:SetText(e and short(e.minPrice) or "")
    row[6]:SetText(e and e.quantity and tostring(e.quantity) or "")
    row[4]:SetText(e and short(e.max) or "")
    local delta = e and e.delta
    if delta == nil then
      row[5]:SetText("")
    elseif delta >= 0 then
      row[5]:SetText("|cff1eff00" .. short(delta) .. " under|r")
    else
      row[5]:SetText("|cffff9d3a" .. short(-delta) .. " over|r")
    end
    row.bg:SetShown(e ~= nil and self.nearBuyable[self.nearOffset + i] or false)
  end
  self:syncNearBar()
  self:drawFlashes()
end

function SnipeView:hide()
  if self.settingsBox then self.settingsBox:Hide() end
  if self.logFrame then self.logFrame:Hide(); self.logBar:Hide() end
end

-- The Start/Stop button and the status line, with its spinner.
function SnipeView:renderStatus()
  local targets = #self:runnable()
  self.startButton:SetText(self.running and "Stop" or "Start sniping")
  local status
  if self.running then
    local ago = self.lastCheck and math.max(0, self:now() - self.lastCheck)
    status = string.format("Sniping %d target%s%s", targets, targets == 1 and "" or "s",
      self.held and (", paused: " .. self.held)
      or ago and (ago < 1 and ", checked just now" or string.format(", checked %ds ago", ago)) or "")
    if self.problem then status = status .. ". Last check failed: " .. self.problem end
  else
    status = targets > 0 and string.format("Not sniping. %d target%s ticked on Targets.", targets,
      targets == 1 and " is" or "s are") or "Not sniping. Tick a target on Targets to snipe it."
  end
  self.status:SetText(self.message or status)
  -- The spinner turns for as long as sniping runs. With checks only REST apart it would blink if it
  -- stopped between them.
  if self.running then self.loading:spin() else self.loading:clear() end
end

function SnipeView:render()
  local money = ns.Money.format
  local w = self.window
  local s = SnipeView.settings(self.addon)
  self:renderStatus()
  self.buySpinner:SetShown(self.buying ~= nil)

  local summary = self.session and self.session:summary() or (self.addon.disenchant.session
    and ns.Sniper.Session.new(self.addon.disenchant.session, 0):summary())
  local spent = summary and summary.spent or 0
  self.spentText:SetText("Spent this session: " .. money(spent) .. (s.cap > 0 and (" of " .. money(s.cap)) or ""))
  local share = s.cap > 0 and math.min(1, spent / s.cap) or 0
  self.bar:SetShown(s.cap > 0)
  self.fill:SetShown(s.cap > 0 and share > 0)
  self.fill:SetWidth(math.max(1, self.barWidth * share))
  if summary and summary.bought > 0 then
    self.summary:SetText(string.format("%d bought, worth %s disenchanted: %s%s expected profit", summary.bought,
      money(summary.worth), summary.profit >= 0 and "+" or "-", money(math.abs(summary.profit))))
  else
    self.summary:SetText("Nothing bought this session yet.")
  end

  local finds = self.session and self.running and self.session.finds or {}
  local find = finds[1]
  self.shownFind = find
  if find then
    -- How many of this item wait to be bought at this price (bought and passed ones drop out).
    local count = 0
    for _, f in ipairs(finds) do
      if f.itemID == find.itemID and f.price == find.price then count = count + (f.count or 1) end
    end
    self.cardLabel:SetText(string.format("Next buy: %s  ·  %d at this price", find.target, count))
    self.cardName:SetText(find.name)
    self.cardLevel:SetText(find.level and find.level > 0 and ("item level " .. find.level) or "")
    self.cols[1].value:SetText(money(find.price))
    self.cols[1].note:SetText("max " .. money(find.max))
    self.cols[2].value:SetText(find.worth and money(find.worth) or "-")
    self.cols[2].note:SetText("after the cut")
    self.cols[3].value:SetText("+" .. money(find.profit))
    self.cols[3].note:SetText(find.worth and find.worth > 0 and
      string.format("%d%%", math.floor(find.profit * 100 / find.worth + 0.5)) or "")
    local ready = self:api():ready()
    self.drawnReady = ready
    self.buyButton:SetText(self.buying and "Buying..." or not ready and "Wait..." or ("Buy for " .. money(find.price)))
    -- Pass waits for a buy in flight too, so it shows as off until the auction house answers.
    if self.buying then self.buyButton:Disable(); self.passButton:Disable()
    else self.buyButton:SetEnabled(ready); self.passButton:Enable() end
  else
    self.cardLabel:SetText(self.running and "Next buy" or "")
    self.cardName:SetText(self.running and "Nothing under your max prices yet" or "Press Start sniping")
    self.cardLevel:SetText("")
    for _, c in ipairs(self.cols) do c.value:SetText("-"); c.note:SetText("") end
    self.drawnReady = nil
    self.buyButton:SetText("Buy")
    self.buyButton:Disable()
    self.passButton:Disable()
  end
  self:renderNear()
  self:refreshTips()

  -- The session log, in the detail panel.
  w.detailTitle:SetText("This session")
  local log = self.addon.disenchant.session and self.addon.disenchant.session.log or {}
  local lines = {}
  for i = 1, #log do lines[#lines + 1] = SnipeView.logLine(log[i], self.env) end
  w.detailBody:SetText("")
  self.logText:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing bought, passed or missed yet.")
  self.logFrame:Show()
  -- A new line goes on top, so the log jumps back to the top to show it; otherwise it stays put.
  local top = log[1]
  if top ~= self.logTop then self.logTop, self.logScroll = top, 0 end
  self:scrollLog(self.logScroll)
  self.settingsBox:Show()
  local function fill(box, amount)
    if not (box.HasFocus and box:HasFocus()) then box:SetText(amount > 0 and money(amount) or "") end
  end
  fill(self.capInput, s.cap)
  fill(self.keepInput, s.keep)
  self.soundBox:SetChecked(s.sound)
end

ns.SnipeView = SnipeView
return SnipeView
