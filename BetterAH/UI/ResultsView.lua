-- Disenchant > Results (#258): what each target really earned, from the greens it sniped, their
-- disenchants and the Ledger's mat sales (Core/SnipeProfit.lua does the sums). Layout follows the mockup
-- linked from #258: one row per target and band, then Not sniped and a total; the detail panel shows the
-- picked row's mats.
local _, ns = ...
ns = ns or {}

local ResultsView = {}
ResultsView.__index = ResultsView

ResultsView.PERIODS = { { "today", "Today" }, { "7d", "7 days" }, { "30d", "30 days" }, { "all", "All time" } }
-- Laid out to fit beside the scroll bar (518 px), as Targets.
ResultsView.COLUMNS = {
  { "Target", 4, 124, "LEFT" }, { "Greens", 130, 42 }, { "Spent", 176, 66 }, { "Earned", 246, 66 },
  { "Not sold", 316, 66 }, { "Waiting", 386, 46 }, { "Profit", 436, 78 },
}
ResultsView.MAT_ROWS = 8
ResultsView.UP, ResultsView.DOWN = { 0.31, 0.82, 0.42 }, { 1, 0.35, 0.31 }
ResultsView.GREEN, ResultsView.GREY = { 0.12, 1, 0 }, { 0.7, 0.7, 0.7 }

function ResultsView.new(dview)
  return setmetatable({ dview = dview, window = dview.window, env = dview.env, addon = dview.addon,
    period = "30d", offset = 0 }, ResultsView)
end

-- "+8g 65s" or "-80s": a signed amount, short.
function ResultsView.signed(copper)
  copper = copper or 0
  if copper == 0 then return "0" end
  return (copper > 0 and "+" or "-") .. ns.Money.short(math.abs(copper))
end

local function money(copper)
  if not copper or copper == 0 then return "0" end
  return ns.Money.short(copper)
end

-- A row's name as the list shows it: "Armor 21-25", or "Not sniped".
function ResultsView.rowName(row)
  if row.other or not row.min then return row.name end
  local max = row.max
  if not max then return row.name .. " " .. row.min .. "+" end
  return row.name .. " " .. ns.DisenchantView.range(row.min, max)
end

-- The cells of one list row, as text: name, greens, spent, earned, not sold, waiting, profit.
function ResultsView.cells(row)
  return { ResultsView.rowName(row), tostring(row.greens), money(row.spent), money(row.earned),
    money(row.unsold), tostring(row.waiting.n), ResultsView.signed(row.profit) }
end

function ResultsView:build(p, width)
  local env = self.env
  self.panel = p
  local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -4)
  status:SetWidth(width - 140)
  status:SetJustifyH("LEFT")
  if status.SetMaxLines then status:SetMaxLines(1) end
  self.status = status
  self.periodDrop = ns.Dropdown.radio(env, p, { width = 110, options = ResultsView.PERIODS,
    get = function() return self.period end, set = function(v) self:setPeriod(v) end, title = "Period",
    tip = "Greens bought in these days. Their mats count whenever they sold." })
  self.periodDrop:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, 0)
  self.rows = self.window:buildRows(p, ResultsView.COLUMNS, function(index) self:select(index + self.offset) end,
    function(offset) self:scroll(offset) end)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta) self:scroll(self.offset - delta * 3) end)
  -- An open Period menu goes with the tab, as Ledger's do.
  p:SetScript("OnHide", function() self:closeMenu() end)
  local tips = {
    [2] = { "Greens", "Greens bought in the period, disenchanted or not." },
    [4] = { "Earned", "What the mats from these greens sold for, after the 5% cut. A sale counts once its gold "
      .. "is taken from the mail." },
    [5] = { "Not sold", "Mats from these greens you still hold, at market value after the cut." },
    [6] = { "Waiting", "Greens not disenchanted yet. Their price is in Spent; their expected worth is not in "
      .. "Profit." },
    [7] = { "Profit", "Earned + Not sold - Spent." },
  }
  for c, tip in pairs(tips) do
    local cell = self.rows.header[c]
    local hit = env.CreateFrame("Frame", nil, p)
    hit:SetAllPoints(cell)
    if hit.EnableMouse then hit:EnableMouse(true) end
    ns.Window.tooltip(env, hit, tip[1], tip[2])
  end
  self.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -56)
  self.empty:SetWidth(width - 8)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetText("No greens bought in this period yet. Snipe some, disenchant them, and their mats show here.")
  self:buildDetail()
end

function ResultsView:buildDetail()
  local env, w = self.env, self.window
  local W = ns.Window.DETAIL - 24
  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  box:SetPoint("TOPLEFT", w.detailTitle, "BOTTOMLEFT", 0, -8)
  box:SetSize(W, 340)
  box:Hide()
  self.detail = box
  local function text(parent, font, x, y, width, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetWidth(width)
    t:SetJustifyH(justify or "LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
  end
  self.sub = text(box, "GameFontDisableSmall", 0, 0, W)
  self.facts = {}
  local labels = { "Bought", "Disenchanted", "Waiting", "Profit" }
  for i, l in ipairs(labels) do
    local y = -18 - (i - 1) * 15
    text(box, "GameFontNormalSmall", 0, y, 90):SetText(l)
    self.facts[i] = text(box, "GameFontHighlightSmall", 90, y, W - 90, "RIGHT")
  end
  local top = -88
  local cols = { { "Mat", 0, 120, "LEFT" }, { "Got", 122, 34 }, { "Sold", 158, 34 }, { "Held", 194, 34 },
    { "Earned", 230, W - 230 } }
  for _, c in ipairs(cols) do
    text(box, "GameFontNormalSmall", c[2], top, c[3], c[4] or "RIGHT"):SetText(c[1])
  end
  self.matRows = {}
  for r = 1, ResultsView.MAT_ROWS do
    local row = {}
    for i, c in ipairs(cols) do
      row[i] = text(box, "GameFontHighlightSmall", c[2], top - r * 15, c[3], c[4] or "RIGHT")
    end
    self.matRows[r] = row
  end
  self.held = text(box, "GameFontDisableSmall", 0, top - (ResultsView.MAT_ROWS + 1) * 15 - 4, W)
end

function ResultsView:closeMenu()
  if self.periodDrop and self.periodDrop.CloseMenu then self.periodDrop:CloseMenu() end
end

function ResultsView:setPeriod(period)
  self.period, self.offset, self.selected = period, 0, nil
  self:render()
end

-- Clicking the picked row again lets it go, as on Ledger.
function ResultsView:select(index)
  self:closeMenu()
  local row = self.shown and self.shown[index]
  if not row then return end
  local key = ResultsView.key(row)
  self.selected = self.selected ~= key and key or nil
  self:draw()
end

-- Scrolling redraws the rows already worked out, without adding everything up again.
function ResultsView:scroll(offset)
  self:closeMenu()
  self.offset = offset
  self:draw()
end

function ResultsView.key(row)
  return row.total and "total" or (tostring(row.name) .. ":" .. tostring(row.min) .. ":" .. tostring(row.max))
end

function ResultsView:hide()
  if self.detail then self.detail:Hide() end
end

-- What one unit of a mat brings when sold now, after the cut: its market value on this market.
function ResultsView:valueOf(key, now)
  local prices = self.addon.prices
  return function(id)
    local v = key and prices and (prices:marketValue(key, "i:" .. id, now))
    if not v then return nil end
    return ns.MyAuctions and ns.MyAuctions.net(v) or math.floor(v * 0.95 + 0.5)
  end
end

-- The results for the chosen period, or nil when there is nothing to add up yet.
function ResultsView:results(now)
  local profit = self.addon.snipeProfit
  if not profit then return nil end
  local offset = ns.LedgerView and ns.LedgerView.utcOffset(self.env, now) or 0
  local from = ns.Ledger.periodStart(self.period, now, offset)
  local ledger = self.addon.ledger
  local sales = ledger and ledger.store and ledger.store.entries or {}
  return profit:results(from or 0, sales, self:valueOf(self.window:market(), now))
end

-- The status line: how many disenchants are recorded and when the last was.
function ResultsView:statusText(now)
  local profit = self.addon.snipeProfit
  local n, last = 0, nil
  for _, g in ipairs(profit and profit.store.greens or {}) do
    if g.de then
      n = n + 1
      if not last or (g.de.t or 0) > last then last = g.de.t end
    end
  end
  if n == 0 then return "No disenchants recorded yet." end
  return string.format("%d disenchant%s recorded. Last %s.", n, n == 1 and "" or "s", ns.Time.ago(last, now))
end

local function color(cell, rgb) cell:SetTextColor(rgb[1], rgb[2], rgb[3]) end

function ResultsView:render()
  if not self.panel then return end
  local now = self.addon.auctionAPI and self.addon.auctionAPI:now() or 0
  self.periodDrop.refresh()
  self.status:SetText(self:statusText(now))
  local r = self:results(now)
  local shown = {}
  if r and #r.rows > 0 then
    for _, row in ipairs(r.rows) do shown[#shown + 1] = row end
    r.total.total = true
    shown[#shown + 1] = r.total
  end
  self.shown = shown
  self:draw()
end

function ResultsView:draw()
  local shown = self.shown or {}
  local count = #self.rows
  self.offset = math.max(0, math.min(self.offset, #shown - count))
  for i, cells in ipairs(self.rows) do
    local row = shown[i + self.offset]
    if row then
      local texts = ResultsView.cells(row)
      for c = 1, #ResultsView.COLUMNS do cells[c]:SetText(texts[c]) end
      color(cells[1], row.total and { 1, 0.82, 0 } or row.other and ResultsView.GREY or ResultsView.GREEN)
      color(cells[7], row.profit < 0 and ResultsView.DOWN or ResultsView.UP)
      cells.button:Show()
      cells.button.selectedTexture:SetShown(ResultsView.key(row) == self.selected)
    else
      cells.button:Hide()
    end
  end
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #shown)
  self.empty:SetShown(#shown == 0)
  self:renderDetail()
end

function ResultsView:renderDetail()
  local w = self.window
  local row
  for _, x in ipairs(self.shown or {}) do
    if ResultsView.key(x) == self.selected then row = x end
  end
  if not row then
    self.detail:Hide()
    w.detailTitle:SetText("")
    w.detailBody:SetText(#(self.shown or {}) > 0 and "Select a row to see its mats." or "")
    return
  end
  w.detailTitle:SetText(row.total and "All greens" or ResultsView.rowName(row))
  w.detailBody:SetText("")
  local periodName = ""
  for _, p in ipairs(ResultsView.PERIODS) do if p[1] == self.period then periodName = p[2] end end
  local sub = row.targetProfit and ("Target profit " .. row.targetProfit .. ". ") or ""
  self.sub:SetText(sub .. (self.period == "all" and "All time." or ("Last " .. periodName:lower() .. ".")))
  if self.period == "today" then self.sub:SetText(sub .. "Today.") end
  local each = function(total, n) return n > 0 and money(math.floor(total / n + 0.5)) or "0" end
  self.facts[1]:SetText(string.format("%d greens, %s each", row.greens, each(row.spent, row.greens)))
  self.facts[2]:SetText(string.format("%d, back %s each", row.disenchanted,
    each(row.earned + row.unsold, row.disenchanted)))
  self.facts[3]:SetText(row.waiting.n > 0 and string.format("%d, worth about %s", row.waiting.n,
    money(row.waiting.worth)) or "none")
  self.facts[4]:SetText(ResultsView.signed(row.profit))
  color(self.facts[4], row.profit < 0 and ResultsView.DOWN or ResultsView.UP)
  local mats = {}
  for id, m in pairs(row.mats) do mats[#mats + 1] = { id = id, m = m } end
  table.sort(mats, function(a, b)
    if a.m.got ~= b.m.got then return a.m.got > b.m.got end
    return a.id < b.id
  end)
  for i, cells in ipairs(self.matRows) do
    local e = mats[i]
    local m = e and e.m
    local mat = e and ns.Disenchant.BY_ID[e.id]
    local texts = e and { mat and mat.name or ("Item " .. e.id), tostring(m.got), tostring(m.sold), tostring(m.held),
      money(m.earned) } or { "", "", "", "", "" }
    for c, cell in ipairs(cells) do cell:SetText(texts[c]) end
  end
  local more = #mats - ResultsView.MAT_ROWS
  local held = row.unsold > 0 and ("Held mats: " .. money(row.unsold) .. " at market value.") or ""
  if more > 0 then held = string.format("%d more mat%s. %s", more, more == 1 and "" or "s", held) end
  self.held:SetText(held)
  self.detail:Show()
end

ns.ResultsView = ResultsView
return ResultsView
