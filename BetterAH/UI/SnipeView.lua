-- The Snipe tab of the Disenchant view (issue #12): runs the ticked targets, one browse after another,
-- and shows one next buy at a time. Buy (or a mouse wheel turn over the tab) buys it, Pass drops it.
-- The session's spend is kept against a spend cap and a floor of gold to keep, with a log of what was
-- bought, passed and missed. The rules live in Core/Sniper.lua, the game calls in Game/SnipeAPI.lua.
-- Layout follows the mockup linked from #12.
local _, ns = ...
ns = ns or {}

local SnipeView = {}
SnipeView.__index = SnipeView

SnipeView.REST = 2 -- seconds between browses
SnipeView.HISTORY = 20 -- finished sessions kept
-- The "closest to your max prices" list: columns as { label, x, width, justify } on a 540 px row.
-- Listed (how many the auction house has of the item, at all prices: a browse doesn't say how many
-- are at the cheapest) is last in the list but sits
-- between Target and Cheapest.
SnipeView.NEAR_COLUMNS = { { "Item", 4, 150, "LEFT" }, { "Target", 158, 116, "LEFT" }, { "Cheapest", 316, 70 },
  { "Max", 390, 70 }, { "vs. max", 462, 74 }, { "Listed", 274, 38 } }
SnipeView.NEAR_ROW = 17
SnipeView.LOG_LINES = 14

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
  end
  return string.format("%s Missed %s: %s", when, name, entry.note or "gone")
end

function SnipeView.new(dview)
  return setmetatable({ dview = dview, window = dview.window, env = dview.env, addon = dview.addon,
    round = 0, near = {}, seen = {}, why = {} }, SnipeView)
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
  p:SetScript("OnMouseWheel", function() self:buyNext() end)

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
  self.loading = ns.Loading.attach(env, p, status, { "LEFT", start, "RIGHT", 10, 0 })

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
  buy:SetScript("OnClick", function() self:buyNext() end)
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
  for i = 1, ns.Sniper.CLOSEST do
    local y = top - 16 - i * SnipeView.NEAR_ROW
    local row = {}
    local shade = p:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + 2)
    shade:SetSize(width, SnipeView.NEAR_ROW)
    shade:SetColorTexture(0.12, 1, 0, 0.12)
    shade:Hide()
    row.bg = shade
    for c, col in ipairs(SnipeView.NEAR_COLUMNS) do
      row[c] = cell(c == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall", col, y)
    end
    row.hover = self:hoverItem(p, function() return row.entry end)
    row.hover:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y + 2)
    row.hover:SetSize(width, SnipeView.NEAR_ROW)
    self.nearRows[i] = row
  end
  self:buildSettings()
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
  box:SetSize(196, 96)
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
  self.session = ns.Sniper.Session.new(db.session, self:now())
  self.running, self.message, self.lastCheck, self.near, self.seen, self.why = true, nil, nil, {}, {}, {}
  self.requested = {}
  self.run = {} -- this run's identity: late answers from an earlier run are dropped
  self:refresh()
  self:tick(self.run)
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
  self.running, self.run, self.checking = false, nil, false
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
  self.round = self.round % #list + 1
  local entry = list[self.round]
  local band = entry.row.band
  local query = ns.Sniper.browseQuery(entry.target, band)
  local api = self:api()
  local function rest()
    if self.run == run then
      self.checking = false
      self:refresh()
    end
    if self.running and self.run == run and self.env.C_Timer then
      self.env.C_Timer.After(SnipeView.REST, function() self:tick(run) end)
    end
  end
  self.checking = true
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
    local near = ns.Sniper.near(band, results, max, level)
    for _, e in ipairs(near) do
      local auctionAPI = self.addon.auctionAPI
      e.name = auctionAPI and auctionAPI:itemName("i:" .. e.itemKey.itemID) or ("item " .. e.itemKey.itemID)
      e.target = name
    end
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
        local found = false
        for _, l in ipairs(ns.Sniper.buys(listings, c.max)) do
          local auctionAPI = self.addon.auctionAPI
          local itemName = l.link or (auctionAPI and auctionAPI:itemName("i:" .. c.itemKey.itemID))
          found = self.session:add({ auctionID = l.auctionID, itemID = c.itemKey.itemID, itemKey = c.itemKey,
            link = l.link, count = l.count,
            name = itemName or ("item " .. c.itemKey.itemID),
            price = l.unit, worth = worthOf[c.itemKey.itemID], max = c.max, target = name,
            level = c.level }) or found
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
function SnipeView:buyNext()
  local find = self.running and self.session and self.session:next()
  if not find or self.buying then return end
  local s = SnipeView.settings(self.addon)
  local api = self:api()
  local ok, why = self.session:canBuy(find.price, api:money(), s.cap, s.keep)
  if not ok then
    self.message = "Can't buy " .. find.name .. ": " .. why .. "."
    return self:refresh()
  end
  self.buying = find
  self.message = nil
  self:refresh()
  -- The answer counts in the session the buy was made in, even after Stop or a new Start.
  local session = self.session
  api:buy(find.auctionID, find.price, function(bought, failure)
    if self.buying == find then self.buying = nil end
    if bought then
      session:bought(self:now(), find)
    else
      session:missed(self:now(), find, failure)
    end
    self:refresh()
  end)
end

function SnipeView:passNext()
  local find = self.session and self.session:next()
  if not find or self.buying then return end
  self.session:pass(self:now(), find.auctionID)
  self:refresh()
end

-- The listings closest to the targets' max prices, from each ticked target's last check.
function SnipeView:renderNear()
  local short = ns.Money.short
  -- Each target's last check, with its max price and name as the target is now (it may have been
  -- edited since).
  local lists, seen, checked, why = {}, 0, false, {}
  if self.running then
    for _, entry in ipairs(self:runnable()) do
      if self.seen[entry.target] then seen, checked = seen + self.seen[entry.target], true end
      for k, n in pairs(self.why[entry.target] or {}) do why[k] = (why[k] or 0) + n end
      local list, fresh = self.near[entry.target], {}
      local name = ns.DisenchantView.targetName(entry.target, entry.row)
      for _, e in ipairs(list or {}) do
        local max = self:maxFor(entry, e.itemKey.itemID)
        if max and max > 0 then
          fresh[#fresh + 1] = { itemKey = e.itemKey, minPrice = e.minPrice, max = max, delta = max - e.minPrice,
            name = e.name, target = name, quantity = e.quantity }
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
    return queued[e.itemKey.itemID] or not (self.session and self.session:fresh(e.itemKey, e.minPrice, now))
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
  for i, row in ipairs(self.nearRows) do
    local e = near[i]
    row.entry = e
    row[1]:SetText(e and e.name or "")
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
    row.bg:SetShown(e ~= nil and buyable(e) and true or false)
    row.entry = e
  end
end

function SnipeView:hide()
  if self.settingsBox then self.settingsBox:Hide() end
end

function SnipeView:render()
  local money = ns.Money.format
  local w = self.window
  local s = SnipeView.settings(self.addon)
  local targets = #self:runnable()
  self.startButton:SetText(self.running and "Stop" or "Start sniping")
  local status
  if self.running then
    local ago = self.lastCheck and math.max(0, self:now() - self.lastCheck)
    status = string.format("Sniping %d target%s%s", targets, targets == 1 and "" or "s",
      ago and string.format(", checked %ds ago", ago) or "")
    if self.problem then status = status .. ". Last check failed: " .. self.problem end
  else
    status = targets > 0 and string.format("Not sniping. %d target%s ticked on Targets.", targets,
      targets == 1 and " is" or "s are") or "Not sniping. Tick a target on Targets to snipe it."
  end
  self.status:SetText(self.message or status)
  -- The spinner turns while the auction house is working on one of the sniper's queries.
  if self.running and self.checking then self.loading:spin() else self.loading:clear() end
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
    self.buyButton:SetText(self.buying and "Buying..." or ("Buy for " .. money(find.price)))
    -- Pass waits for a buy in flight too, so it shows as off until the auction house answers.
    if self.buying then self.buyButton:Disable(); self.passButton:Disable()
    else self.buyButton:Enable(); self.passButton:Enable() end
  else
    self.cardLabel:SetText(self.running and "Next buy" or "")
    self.cardName:SetText(self.running and "Nothing under your max prices yet" or "Press Start sniping")
    self.cardLevel:SetText("")
    for _, c in ipairs(self.cols) do c.value:SetText("-"); c.note:SetText("") end
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
  for i = 1, math.min(#log, SnipeView.LOG_LINES) do lines[#lines + 1] = SnipeView.logLine(log[i], self.env) end
  if #log > SnipeView.LOG_LINES then lines[#lines + 1] = string.format("%d more", #log - SnipeView.LOG_LINES) end
  w.detailBody:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing bought, passed or missed yet.")
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
