-- The Ledger view (#137): every copper in and out of the auction house, with totals for a period. Three
-- tabs: Transactions, By item and By day. Layout follows the mockup linked from issue #137. This file only
-- draws and wires; the rules live in Core/Ledger.lua, the game reading in Game/LedgerAPI.lua.
local _, ns = ...
ns = ns or {}

local LedgerView = {}
LedgerView.__index = LedgerView

LedgerView.TABS = { { "entries", "Transactions" }, { "items", "By item" }, { "days", "By day" } }
LedgerView.PERIODS = { { "today", "Today" }, { "7d", "7 days" }, { "30d", "30 days" }, { "all", "All time" } }
LedgerView.FILTERS = { { "all", "Money in and out" }, { "in", "Money in" }, { "out", "Money out" } }
LedgerView.CHARACTERS = { { "all", "All characters" }, { "this", "This character" } }
LedgerView.ENTRY_COLUMNS = {
  { "When", 4, 84, "LEFT" }, { "What", 92, 96, "LEFT" }, { "Item", 192, 186, "LEFT" }, { "Qty", 382, 36 },
  { "Gold", 422, 94 },
}
LedgerView.ITEM_COLUMNS = {
  { "Item", 4, 170, "LEFT" }, { "Bought", 178, 46 }, { "Avg paid", 228, 70 }, { "Sold", 302, 40 },
  { "Avg sold", 346, 70 }, { "Profit", 420, 96 },
}
LedgerView.TOP_ROWS = 30 -- the tab and drop-down rows above the list; its headings sit 32 below this
LedgerView.ROWS = 14
LedgerView.CHART_HEIGHT = 240
LedgerView.MAX_BARS = 60 -- the most days the chart draws; older ones are left off
-- Gold in light blue, gold out orange: they differ in lightness too, so they can be told apart without hue.
LedgerView.COLORS = { moneyIn = "ff8fd0ff", moneyOut = "ffff9a3c", dim = "ff9d9d9d", head = "ffffd100" }
LedgerView.BAR_IN = { 0.29, 0.62, 0.85, 1 }
LedgerView.BAR_OUT = { 0.85, 0.47, 0.17, 1 }

local function color(code, text) return "|c" .. code .. text .. "|r" end
local function money(c) return ns.Money.format(c) end

-- A signed amount: "+2g 9s 0c" in light blue, "-14s 80c" in orange, "0c" plain.
function LedgerView.signed(c)
  c = c or 0
  if c > 0 then return color(LedgerView.COLORS.moneyIn, "+" .. money(c)) end
  if c < 0 then return color(LedgerView.COLORS.moneyOut, "-" .. money(-c)) end
  return "0c"
end

-- Local time minus UTC, in seconds, at time now: from the client's date and time.
function LedgerView.utcOffset(env, now)
  if type(env.date) ~= "function" or type(env.time) ~= "function" then return 0 end
  local ok, offset = pcall(function()
    local here, utc = env.date("*t", now), env.date("!*t", now)
    utc.isdst = here.isdst
    return env.time(here) - env.time(utc)
  end)
  return ok and offset or 0
end

-- When an entry happened, short: "16:41" today, "Yest. 22:05", a weekday this week, else "24 Nov".
function LedgerView.when(env, t, now, offset)
  if type(env.date) ~= "function" then return "" end
  local today = ns.Ledger.dayStart(now, offset)
  local clock = env.date("%H:%M", t)
  if t >= today then return clock end
  if t >= today - ns.Ledger.DAY then return "Yest. " .. clock end
  if t >= today - 6 * ns.Ledger.DAY then return env.date("%a", t) .. " " .. clock end
  return env.date("%d %b", t)
end

-- What an entry was, for the What column.
function LedgerView.what(e)
  if e.k == "sale" then return "Sold" end
  if e.k == "deposit" then return "Deposit" end
  if e.src == "mail" then return "Bought · other" end
  return "Bought" .. (e.src and (" · " .. e.src) or "")
end

-- The entries one filter keeps: "all", "in" (sales) or "out" (buys and deposits).
function LedgerView.filter(entries, filter)
  if filter == "all" then return entries end
  local out = {}
  for _, e in ipairs(entries) do
    if (filter == "in") == (e.k == "sale") then out[#out + 1] = e end
  end
  return out
end

-- The period's totals, for the detail panel with nothing selected. t = Ledger.totals, mail = copper waiting.
function LedgerView.totalsText(t, mail, mails, hint)
  local c = LedgerView.COLORS
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  local function kv(label, value) add(label .. ": " .. value) end
  if hint then
    add(hint)
    add("")
  end
  add(color(c.head, "Money in"))
  kv(string.format("Sales (%d %s)", t.sold, t.sold == 1 and "auction" or "auctions"), color(c.moneyIn, money(t.sales)))
  add("")
  add(color(c.head, "Money out"))
  kv(string.format("Purchases (%d %s)", t.bought, t.bought == 1 and "item" or "items"),
    color(c.moneyOut, money(t.purchases)))
  kv("AH cut", color(c.moneyOut, money(t.cut)))
  -- Paid and not back yet: it comes back when the auction sells and its gold is taken, and is lost only on
  -- a cancelled or expired auction.
  kv("Deposits not back yet", t.kept >= 0 and color(c.moneyOut, money(t.kept)) or LedgerView.signed(-t.kept))
  kv("Total out", color(c.moneyOut, money(t.moneyOut)))
  add("")
  add(color(c.head, "Net profit"))
  add(LedgerView.signed(t.net))
  if mail and mail > 0 then
    add("")
    add(color(c.head, "Not counted yet"))
    kv(string.format("Sold, gold still in the mail (%d)", mails or 0), money(mail))
  end
  return table.concat(lines, "\n")
end

-- One entry, for the detail panel.
function LedgerView.entryText(env, e, charName)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add(LedgerView.what(e) .. (type(env.date) == "function" and (" · " .. env.date("%d %b %H:%M", e.t)) or ""))
  if charName then add("By " .. charName) end
  add("")
  local units = (e.n or 1) == 1 and "1 item" or ((e.n or 1) .. " units")
  if e.k == "sale" then
    add(units .. " sold for " .. money(e.c))
    add("AH cut: " .. color(LedgerView.COLORS.moneyOut, money(e.cut or 0)))
    add("You got: " .. LedgerView.signed(e.c - (e.cut or 0)))
    if (e.dep or 0) > 0 then add("Its deposit came back too: " .. money(e.dep)) end
  elseif e.k == "deposit" then
    add("Deposit for posting " .. units .. ": " .. LedgerView.signed(-e.c))
    add("You get it back if the auction sells.")
  else
    add(units .. " for " .. LedgerView.signed(-e.c))
    if (e.n or 1) > 1 then add("Per unit: " .. money(math.floor(e.c / e.n + 0.5))) end
    if e.src == "mail" then add("Bought outside Better AH, or a won bid: counted when its mail was taken.") end
  end
  return table.concat(lines, "\n")
end

-- One item row from Ledger.byItem, for the detail panel.
function LedgerView.itemText(r)
  local c = LedgerView.COLORS
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add(color(c.head, "Bought"))
  if r.bought > 0 then
    add(string.format("%d for %s", r.bought, color(c.moneyOut, money(r.paid))))
    add("Average per unit: " .. money(r.avgPaid))
  else
    add(color(c.dim, "None in this period"))
  end
  add("")
  add(color(c.head, "Sold"))
  if r.sold > 0 then
    add(string.format("%d for %s", r.sold, color(c.moneyIn, money(r.sales))))
    add("Average per unit: " .. money(r.avgSold))
  else
    add(color(c.dim, "None in this period"))
  end
  add("AH cut and deposits: " .. (r.cost >= 0 and color(c.moneyOut, money(r.cost)) or LedgerView.signed(-r.cost)))
  add("")
  add(color(c.head, "Profit"))
  local profit = LedgerView.signed(r.profit)
  if r.paid > 0 and r.sold > 0 then
    profit = profit .. string.format("  (%d%% on what you paid)", math.floor(r.profit * 100 / r.paid + 0.5))
  end
  add(profit)
  return table.concat(lines, "\n")
end

-- One day from Ledger.byDay, for the detail panel.
function LedgerView.dayText(d)
  local c = LedgerView.COLORS
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add("Gold in: " .. color(c.moneyIn, money(d.moneyIn)))
  add("Gold out: " .. color(c.moneyOut, money(d.moneyOut)))
  add("Net: " .. LedgerView.signed(d.net))
  add(d.entries == 1 and "1 entry" or (d.entries .. " entries"))
  return table.concat(lines, "\n")
end

function LedgerView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, tab = "entries", period = "7d",
    filterBy = "all", allChars = true, offset = 0 }, LedgerView)
end

function LedgerView:build(f, x, y, width, height)
  local env, w = self.env, self.window
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.panel, self.width = panel, width
  -- Leaving the view or closing the window closes an open menu, so it isn't open on the way back.
  panel:SetScript("OnHide", function() self:closeMenus() end)

  self.tabButtons = {}
  for i, tab in ipairs(LedgerView.TABS) do
    local b = ns.Window.entryButton(env, panel, 100)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * 104, 0)
    b:SetText(tab[2])
    b:SetScript("OnClick", function() self:setTab(tab[1]) end)
    self.tabButtons[tab[1]] = b
  end
  -- Drop-downs for the period, money in or out (Transactions only) and characters, on the second row.
  self.periodDrop = self:dropdown(panel, 110, LedgerView.PERIODS, function() return self.period end,
    function(v) self:setPeriod(v) end, "Period", "Which days to add up.")
  self.periodDrop:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
  self.charsDrop = self:dropdown(panel, 130, LedgerView.CHARACTERS,
    function() return self.allChars and "all" or "this" end,
    function(v) self:setChars(v == "all") end, "Characters", "All your characters together, or only the one "
    .. "you're on.")
  self.charsDrop:SetPoint("LEFT", self.periodDrop, "RIGHT", 8, 0)
  self.filterDrop = self:dropdown(panel, 130, LedgerView.FILTERS, function() return self.filterBy end,
    function(v) self:setFilter(v) end, "Show", "Every entry, only money in (sales), or only money out "
    .. "(buys and deposits).")
  -- Last, so hiding it on the other tabs leaves no gap.
  self.filterDrop:SetPoint("LEFT", self.charsDrop, "RIGHT", 8, 0)

  -- Two lists in the same place, one per tab with rows; By day draws a chart there instead.
  local function list()
    local l = env.CreateFrame("Frame", nil, panel)
    l:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -LedgerView.TOP_ROWS)
    l:SetSize(width, height - LedgerView.TOP_ROWS)
    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
    return l
  end
  local onScroll = function(offset) self.offset = offset; self:render() end
  self.entryList = list()
  self.entryRows = w:buildRows(self.entryList, LedgerView.ENTRY_COLUMNS, function(i) self:selectRow(i) end, onScroll)
  self.itemList = list()
  self.itemRows = w:buildRows(self.itemList, LedgerView.ITEM_COLUMNS, function(i) self:selectRow(i) end, onScroll)
  self:buildChart(panel, width)

  local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -LedgerView.TOP_ROWS - 62) -- below the column headings
  empty:SetWidth(width - 40)
  empty:SetJustifyH("LEFT")
  self.empty = empty

  local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 6) -- clear of the last row and the frame edge
  footer:SetWidth(width - 24)
  footer:SetJustifyH("LEFT")
  self.footer = footer

  local api = self.addon.ledgerAPI
  if api then
    api.onChange = function()
      if self.window.model.view == "ledger" and self.window.frame and self.window.frame:IsShown() then
        self:render()
      end
    end
  end
  return panel
end

-- The By day chart: a column per day, gold in rising from the middle line, gold out falling below it.
function LedgerView:buildChart(panel, width)
  local env = self.env
  local chart = env.CreateFrame("Frame", nil, panel)
  chart:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -LedgerView.TOP_ROWS - 26) -- 12 below the drop-downs
  chart:SetSize(width - 24, LedgerView.CHART_HEIGHT)
  local bg = chart:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(chart)
  bg:SetColorTexture(0, 0, 0, 0.3)
  local zero = chart:CreateTexture(nil, "ARTWORK")
  zero:SetColorTexture(0.54, 0.46, 0.31, 1)
  zero:SetHeight(1)
  zero:SetPoint("LEFT", chart, "LEFT", 0, 0)
  zero:SetPoint("RIGHT", chart, "RIGHT", 0, 0)
  self.chartTop = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.chartTop:SetPoint("TOPLEFT", chart, "TOPLEFT", 3, -2)
  self.chartBottom = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.chartBottom:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 3, 2)
  self.chartFirst = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.chartFirst:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -4)
  self.chartLast = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.chartLast:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -4)
  self.chartKey = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.chartKey:SetPoint("TOP", chart, "BOTTOM", 0, -4)
  self.chartKey:SetText(color(LedgerView.COLORS.moneyIn, "Gold in") .. "   " .. color(LedgerView.COLORS.moneyOut,
    "Gold out") .. "   Click a day to see it")
  self.chart, self.columns = chart, {}
end

-- The column for day i, made on first use: a button holding a bar up and a bar down.
function LedgerView:column(i)
  local col = self.columns[i]
  if col then return col end
  local env = self.env
  col = env.CreateFrame("Button", nil, self.chart)
  local up = col:CreateTexture(nil, "ARTWORK")
  up:SetColorTexture(unpack(LedgerView.BAR_IN))
  up:SetPoint("BOTTOM", col, "CENTER", 0, 1)
  local down = col:CreateTexture(nil, "ARTWORK")
  down:SetColorTexture(unpack(LedgerView.BAR_OUT))
  down:SetPoint("TOP", col, "CENTER", 0, -1)
  local selected = col:CreateTexture(nil, "BACKGROUND")
  selected:SetAllPoints(col)
  selected:SetColorTexture(0.23, 0.17, 0.08, 1)
  selected:Hide()
  local highlight = col:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(col)
  highlight:SetColorTexture(1, 1, 1, 0.08)
  col.up, col.down, col.selectedTexture = up, down, selected
  col:SetScript("OnClick", function() self:selectDay(col.day) end)
  self.columns[i] = col
  return col
end

function LedgerView:now()
  local api = self.addon.ledgerAPI
  return api and api:now() or 0
end

function LedgerView:char()
  local api = self.addon.ledgerAPI
  return api and api:char() or nil
end

function LedgerView:show()
  self:render()
end

function LedgerView:setTab(tab)
  self:closeMenus()
  self.tab, self.offset, self.selected = tab, 0, nil
  self:render()
end

function LedgerView:setPeriod(period)
  self.period, self.offset, self.selected = period, 0, nil
  self:render()
end

function LedgerView:setFilter(filter)
  self.filterBy, self.offset, self.selected = filter, 0, nil
  self:render()
end

function LedgerView:setChars(all)
  self.allChars, self.offset, self.selected = all, 0, nil
  self:render()
end

-- A drop-down (UI/Dropdown.lua): options = { { value, label }, ... }; get() gives the chosen value,
-- set(value) picks one.
function LedgerView:dropdown(parent, width, options, get, set, title, tip)
  local d = ns.Dropdown.radio(self.env, parent, { width = width, options = options, get = get, set = set,
    title = title, tip = tip })
  self.drops = self.drops or {}
  self.drops[#self.drops + 1] = d
  return d
end

function LedgerView:closeMenus()
  for _, d in ipairs(self.drops or {}) do d:CloseMenu() end
end

-- Shows each drop-down's chosen option on its button.
function LedgerView:renderDrops()
  for _, d in ipairs(self.drops or {}) do d.refresh() end
end

function LedgerView:scroll(by)
  self:closeMenus()
  if self.tab == "days" then return end
  self.offset = math.max(0, self.offset + by)
  self:render()
end

function LedgerView:selectRow(r)
  self:closeMenus()
  local row = self.shown and self.shown[r + self.offset]
  if not row then return end
  self.selected = (self.selected ~= row.id) and row.id or nil
  self:render()
end

function LedgerView:selectDay(day)
  self:closeMenus()
  self.selected = (self.selected ~= day) and day or nil
  self:render()
end

-- What the view shows now: entries of the period and characters, newest first, and the time it starts.
function LedgerView:data()
  local ledger, now = self.addon.ledger, self:now()
  local offset = LedgerView.utcOffset(self.env, now)
  local from = ns.Ledger.periodStart(self.period, now, offset)
  local char = not self.allChars and self:char() or nil
  local entries = ledger and ledger:entries(from, char) or {}
  return entries, from, now, offset, char
end

local function rowsOf(self, rows, list)
  local visible = LedgerView.ROWS
  self.offset = math.max(0, math.min(self.offset, math.max(0, #list - visible)))
  ns.Window.syncScrollBar(rows.scrollBar, self.offset, #list)
  return visible
end

function LedgerView:render()
  if not self.panel then return end
  local entries, from, now, offset, char = self:data()
  for _, t in ipairs(LedgerView.TABS) do ns.Window.markSelected(self.tabButtons[t[1]], t[1] == self.tab) end
  self:renderDrops()
  self.filterDrop:SetShown(self.tab == "entries")
  if self.tab ~= "entries" then self.filterDrop:CloseMenu() end
  self.entryList:SetShown(self.tab == "entries")
  self.itemList:SetShown(self.tab == "items")
  self.chart:SetShown(self.tab == "days")

  local selected
  if self.tab == "entries" then
    selected = self:renderEntries(entries, now, offset)
  elseif self.tab == "items" then
    selected = self:renderItems(entries)
  else
    selected = self:renderDays(entries, from, now, offset)
  end
  local empty = #entries == 0
  self.empty:SetText(empty and ("Nothing recorded in this period yet. Sales count once you take their gold "
    .. "from the mail; buys in Snipe and Browse, and deposits, count as they happen.") or "")
  self.empty:SetShown(empty and self.tab ~= "days")
  if self.window.model.view == "ledger" then self:renderDetail(entries, char, selected) end
end

function LedgerView:renderEntries(entries, now, offset)
  local shown = LedgerView.filter(entries, self.filterBy)
  local list = {}
  for i, e in ipairs(shown) do list[i] = { id = e, entry = e } end
  self.shown = list
  local visible = rowsOf(self, self.entryRows, list)
  local selected
  for r = 1, visible do
    local cells, row = self.entryRows[r], list[r + self.offset]
    if row then
      local e = row.entry
      cells[1]:SetText(LedgerView.when(self.env, e.t, now, offset))
      cells[2]:SetText(LedgerView.what(e))
      cells[3]:SetText(e.name or "?")
      cells[4]:SetText(tostring(e.n or 1))
      cells[5]:SetText(LedgerView.signed(ns.Ledger.amount(e)))
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.id == self.selected)
  end
  for _, row in ipairs(list) do if row.id == self.selected then selected = row end end
  self.footer:SetText(string.format("%d %s · sales shown after the 5%% cut · a sale counts once its gold is "
    .. "taken from the mail", #shown, #shown == 1 and "entry" or "entries"))
  return selected
end

function LedgerView:renderItems(entries)
  local items = ns.Ledger.byItem(entries)
  local list = {}
  for i, r in ipairs(items) do list[i] = { id = r.name, item = r } end
  self.shown = list
  local visible = rowsOf(self, self.itemRows, list)
  local selected
  for r = 1, visible do
    local cells, row = self.itemRows[r], list[r + self.offset]
    if row then
      local it = row.item
      cells[1]:SetText(it.name)
      cells[2]:SetText(it.bought > 0 and tostring(it.bought) or color(LedgerView.COLORS.dim, "-"))
      cells[3]:SetText(it.avgPaid and money(it.avgPaid) or color(LedgerView.COLORS.dim, "-"))
      cells[4]:SetText(it.sold > 0 and tostring(it.sold) or color(LedgerView.COLORS.dim, "-"))
      cells[5]:SetText(it.avgSold and money(it.avgSold) or color(LedgerView.COLORS.dim, "-"))
      cells[6]:SetText(LedgerView.signed(it.profit))
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.id == self.selected)
  end
  for _, row in ipairs(list) do if row.id == self.selected then selected = row end end
  self.footer:SetText(string.format(
    "%d %s · profit = sold after the cut - bought - deposits not back · prices per unit", #items,
    #items == 1 and "item" or "items"))
  return selected
end

function LedgerView:renderDays(entries, from, now, offset)
  local days = ns.Ledger.byDay(entries, from, now, offset)
  while #days > LedgerView.MAX_BARS do table.remove(days, 1) end
  self.shown = nil
  local top = 1
  for _, d in ipairs(days) do top = math.max(top, d.moneyIn, d.moneyOut) end
  local width = self.width - 24
  local step = width / math.max(1, #days)
  local barWidth = math.max(2, math.min(14, math.floor(step) - 2))
  local half = LedgerView.CHART_HEIGHT / 2 - 14
  local selected
  for i, d in ipairs(days) do
    local col = self:column(i)
    col.day = d.day
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", self.chart, "TOPLEFT", math.floor((i - 1) * step), 0)
    col:SetSize(math.max(3, math.floor(step)), LedgerView.CHART_HEIGHT)
    col.up:SetSize(barWidth, math.max(1, math.floor(d.moneyIn / top * half)))
    col.up:SetShown(d.moneyIn > 0)
    col.down:SetSize(barWidth, math.max(1, math.floor(d.moneyOut / top * half)))
    col.down:SetShown(d.moneyOut > 0)
    col.selectedTexture:SetShown(d.day == self.selected)
    col:Show()
    if d.day == self.selected then selected = { id = d.day, day = d } end
  end
  for i = #days + 1, #self.columns do self.columns[i]:Hide() end
  self.chartTop:SetText(ns.Money.short(top))
  self.chartBottom:SetText(ns.Money.short(top))
  local date = self.env.date
  local function label(t) return type(date) == "function" and date("%d %b", t) or "" end
  self.chartFirst:SetText(days[1] and label(days[1].day) or "")
  self.chartLast:SetText("Today")
  self.footer:SetText("Gold in: sales after the cut, with their deposits back · gold out: buys and deposits")
  return selected
end

function LedgerView:renderDetail(entries, char, selected)
  local w = self.window
  local periodName = "All time"
  for _, p in ipairs(LedgerView.PERIODS) do if p[1] == self.period then periodName = p[2] end end
  if periodName == "7 days" or periodName == "30 days" then periodName = "Last " .. periodName end
  local who = char and "this character" or "all characters"
  if selected and selected.entry then
    local e = selected.entry
    w.detailTitle:SetText(e.name or "?")
    local name = self.addon.characters and e.char and self.addon.characters.store.chars[e.char]
    w.detailBody:SetText(LedgerView.entryText(self.env, e, self.allChars and name and name.name or nil))
  elseif selected and selected.item then
    w.detailTitle:SetText(selected.item.name)
    w.detailBody:SetText(periodName .. ", " .. who .. "\n\n" .. LedgerView.itemText(selected.item))
  elseif selected and selected.day then
    local date = self.env.date
    w.detailTitle:SetText(type(date) == "function" and date("%A %d %b", selected.day.day) or "")
    w.detailBody:SetText(LedgerView.dayText(selected.day) .. "\n\n" .. periodName .. ":\n"
      .. LedgerView.totalsText(ns.Ledger.totals(entries)))
  else
    w.detailTitle:SetText(periodName .. ", " .. who)
    local mail, mails = 0, 0
    if self.addon.ledger then mail, mails = self.addon.ledger:inMail(char) end
    local hint = self.tab == "days" and "Click a day to see it." or "Click a row to see its details."
    w.detailBody:SetText(LedgerView.totalsText(ns.Ledger.totals(entries), mail, mails, hint))
  end
end

ns.LedgerView = LedgerView
return LedgerView
