-- The Browse view (#91): the regular auction house's search, inside Better AH. A search row (name or
-- item link, required level range) and a results table that sorts by any column, with market value and
-- how the lowest buyout compares to it. Layout follows the mockup linked from #90. This file only draws
-- and wires; the rules live in Core/Browse.lua and the client calls in Game/BrowseAPI.lua.
local _, ns = ...
ns = ns or {}

local BrowseView = {}
BrowseView.__index = BrowseView

BrowseView.WIDTH = 848 -- the main and detail panels together: the results list has no detail panel
BrowseView.ITEM_WIDTH = 540 -- an item's page uses the main panel, with the buy controls on the detail panel
BrowseView.DETAIL_WIDTH = 276 -- text width on the detail panel
-- { header, x, width, justify, sort column }
BrowseView.COLUMNS = {
  { "Item", 4, 300, "LEFT", "name" }, { "Req.", 310, 40, nil, "level" }, { "Listed", 356, 56, nil, "listed" },
  { "Lowest buyout", 418, 100, nil, "lowest" }, { "Market value", 524, 100, nil, "value" },
  { "Of market", 630, 70, nil, "percent" },
}
BrowseView.TONES = { cheap = { 0.12, 1, 0 }, dear = { 1, 0.5, 0.25 } }
BrowseView.REBUILD_DELAY = 0.3 -- item names that load in a burst are drawn once
BrowseView.MAX_IDLE_REBUILDS = 5 -- rebuilds in a row that load nothing new before giving up

function BrowseView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, offset = 0,
    sortColumn = ns.Browse.DEFAULT_SORT, descending = false }, BrowseView)
end

function BrowseView:api()
  return self.addon.browseAPI
end

local function input(env, parent, width, numeric)
  local e = env.CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  if numeric then
    e:SetNumeric(true)
    if e.SetMaxLetters then e:SetMaxLetters(3) end
  end
  return e
end

-- Returns a frame holding the results list (self.panel) and an item's page (self.item.panel).
function BrowseView:build(f, x, y, width, height)
  local env = self.env
  local container = env.CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  container:SetSize(width, height)
  self.container = container
  local panel = env.CreateFrame("Frame", nil, container)
  panel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.panel = panel

  local search = input(env, panel, 260)
  search:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -2)
  search:SetScript("OnEnterPressed", function() self:search() end)
  search:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
  search:SetScript("OnTextChanged", function() self:renderHint() end)
  search:SetScript("OnEditFocusGained", function() self:renderHint() end)
  search:SetScript("OnEditFocusLost", function() self:renderHint() end)
  self.searchBox = search
  -- On the box itself, so its border art can't draw over the hint.
  local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", search, "LEFT", 2, 0)
  hint:SetText("Search by name, or shift-click an item")
  self.searchHint = hint

  local levelLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  levelLabel:SetPoint("LEFT", search, "RIGHT", 14, 0)
  levelLabel:SetText("Level")
  local lo = input(env, panel, 32, true)
  lo:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
  local to = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  to:SetPoint("LEFT", lo, "RIGHT", 6, 0)
  to:SetText("to")
  local hi = input(env, panel, 32, true)
  hi:SetPoint("LEFT", to, "RIGHT", 10, 0)
  for _, box in ipairs({ lo, hi }) do
    box:SetScript("OnEnterPressed", function() self:search() end)
    box:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    box:SetScript("OnTabPressed", function(e) (e == lo and hi or search):SetFocus() end)
  end
  search:SetScript("OnTabPressed", function() lo:SetFocus() end)
  self.minLevel, self.maxLevel = lo, hi

  local go = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  go:SetSize(80, 22)
  go:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -1)
  go:SetText("Search")
  go:SetScript("OnClick", function() self:search() end)
  ns.Window.tooltip(env, go, "Search", "Search the auction house. A blank search lists everything.")
  self.searchButton = go

  local w = self.window
  self.rows = w:buildRows(panel, BrowseView.COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:render() end, width)
  self:buildHeaders(panel)

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
  status:SetWidth(width - 8)
  status:SetJustifyH("LEFT")
  if status.SetWordWrap then status:SetWordWrap(false) end
  self.status = status
  self.loading = ns.Loading.attach(env, panel, status, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4,
    width - 8, slot = true })

  -- Shift-clicking an item while the search box has focus searches for its name, as in Blizzard's window.
  if type(env.hooksecurefunc) == "function" and type(env.ChatEdit_InsertLink) == "function" then
    env.hooksecurefunc("ChatEdit_InsertLink", function(link) self:insertLink(link) end)
  end

  local api = self:api()
  if api then
    api.onInfo = function() self:itemInfoLoaded() end
    -- Gold changes what can be bought: redraw an open item page.
    api.onMoney = function() if self.item and self.item.row then self.item:render() end end
  end
  self.item = ns.BrowseItemView.new(self)
  self.item:build(container, BrowseView.ITEM_WIDTH, height)
  return container
end

-- Whether the view wants the detail panel's room: yes for the results list, no on an item's page.
function BrowseView:wide()
  return not (self.item and self.item.row)
end

-- Opens a result's page: its auctions or price ladder, with the buy controls on the detail panel.
function BrowseView:openItem(row)
  self.panel:Hide()
  self.item:open(row)
  self.window:widenMain(false)
  self.item:render()
end

function BrowseView:closeItem()
  self.item:close()
  self.window:widenMain(true)
  self.window.detailTitle:SetText("")
  self.window.detailBody:SetText("")
  self.panel:Show()
  self:render()
end

-- Another view is showing: the buy controls on the shared detail panel go.
function BrowseView:hide()
  if not self.item then return end
  -- An open quote would hold up buys elsewhere (the sniper's): drop it.
  if self.item.quoted or self.item.quoting then self.item:cancelQuote() end
  self.item:hideControls()
end

-- Clickable headers over the table's header row: a click sorts by that column, again reverses it.
function BrowseView:buildHeaders(panel)
  local env = self.env
  self.headers = {}
  for c, col in ipairs(BrowseView.COLUMNS) do
    local b = env.CreateFrame("Button", nil, panel)
    b:SetSize(col[3], 16)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", col[2], -29)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas(ns.Window.ART.rowHighlight, false)
    highlight:SetAllPoints(b)
    highlight:SetBlendMode("ADD")
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
    arrow:Hide()
    b.arrow, b.column = arrow, col[5]
    b:SetScript("OnClick", function() self:sortBy(col[5]) end)
    ns.Window.tooltip(env, b, col[1], "Sort by " .. col[1]:lower() .. ". Click again to reverse.")
    self.headers[c] = b
  end
end

function BrowseView:renderHeaders()
  for c, b in ipairs(self.headers) do
    local col = BrowseView.COLUMNS[c]
    local on = col[5] == self.sortColumn
    b.arrow:SetShown(on)
    if on then
      b.arrow:ClearAllPoints()
      -- Beside the header text: right of a left-aligned header, left of a right-aligned one.
      if col[4] == "LEFT" then
        b.arrow:SetPoint("LEFT", b, "LEFT", BrowseView.textWidth(col[1]) + 4, 0)
      else
        b.arrow:SetPoint("RIGHT", b, "RIGHT", -BrowseView.textWidth(col[1]) - 4, 0)
      end
      -- The art points up; descending flips it.
      if self.descending then b.arrow:SetTexCoord(0, 1, 1, 0) else b.arrow:SetTexCoord(0, 1, 0, 1) end
    end
  end
end

-- About how wide a header's text is in GameFontNormalSmall, for placing its arrow.
function BrowseView.textWidth(text)
  return #text * 6
end

function BrowseView:renderHint()
  local box = self.searchBox
  self.searchHint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
end

function BrowseView:insertLink(link)
  local box = self.searchBox
  if not (box and box:HasFocus() and self.panel:IsShown()) then return end
  local name = ns.Browse.searchText(link)
  if name == "" then return end
  box:SetText(name)
  self:search()
end

function BrowseView:sortBy(column)
  self.sortColumn, self.descending = ns.Browse.click(column, self.sortColumn, self.descending)
  if self.results then ns.Browse.sort(self.results.rows, self.sortColumn, self.descending) end
  self.offset = 0
  self:render()
end

function BrowseView:search()
  local api = self:api()
  -- Enter or a shift-click during our own search does nothing, like the disabled Search button.
  if self.searching then return end
  self.searchBox:ClearFocus()
  self.minLevel:ClearFocus()
  self.maxLevel:ClearFocus()
  local query, why = ns.Browse.query({ text = self.searchBox:GetText(), minLevel = self.minLevel:GetText(),
    maxLevel = self.maxLevel:GetText() })
  if not query then
    self.message = why
    return self:render()
  end
  if not (api and api:open()) then
    self.message = "Open the auction house to search."
    return self:render()
  end
  if api:busy() then
    self.message = "Disenchant sniping is checking the auction house. Try again in a moment."
    return self:render()
  end
  local job = { query = query }
  self.searching, self.message = job, nil
  self:render()
  api:search(query, function(results, truncated)
    if self.searching ~= job then return end
    self.searching = nil
    if not results then
      self.message = "The search failed: " .. tostring(truncated) .. "."
    else
      job.raw, job.truncated, job.at, job.values = results, truncated, self:now(), {}
      self.results, self.message = job, nil
      self.selected, self.offset = nil, 0
      self:rebuild()
    end
    self:render()
  end)
end

function BrowseView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

-- Rows for the last results, with names, levels and market values as the client and prices know them now.
function BrowseView:rebuild()
  local job = self.results
  if not job then return end
  local api, prices, key = self:api(), self.addon.prices, self.window:market()
  local now, values = self:now(), job.values
  -- Market values are worked out once per search (false: none); names and levels are looked up again,
  -- as the client loads them.
  job.rows = ns.Browse.rows(job.raw, {
    info = api and function(k) return api:info(k) end,
    required = api and function(id) return api:required(id) end,
    value = function(id)
      if values[id] == nil then
        values[id] = prices and key and (prices:marketValue(key, "i:" .. id, now)) or false
      end
      return values[id] or nil
    end,
  })
  -- Required level is never really 0, so a row without one is still loading. Rows that stay missing
  -- through several rebuilds (an item the client never loads) stop further rebuilds.
  local missing = 0
  for _, row in ipairs(job.rows) do
    if not (row.name and row.level) then missing = missing + 1 end
  end
  job.idle = (job.missing == missing) and (job.idle or 0) + 1 or 0
  job.missing = missing
  if job.idle >= BrowseView.MAX_IDLE_REBUILDS then job.missing = 0 end
  job.stale = false
  ns.Browse.sort(job.rows, self.sortColumn, self.descending)
end

-- The auction house closed: its results are gone with it.
function BrowseView:reset()
  self.results, self.searching, self.selected, self.message, self.offset = nil, nil, nil, nil, 0
  if self.item and self.item.row then
    self.item:close()
    self.panel:Show()
  end
  if self.panel and self.panel:IsShown() then self:render() end
end

-- The client loaded more item data: redraw once the burst is over, if some names or levels were still
-- missing. While the view is hidden the rows are only marked stale, and rebuilt when it shows again.
function BrowseView:itemInfoLoaded()
  local job = self.results
  if not (job and (job.missing or 0) > 0) or self.rebuildQueued then return end
  if not (self.panel and self.panel:IsShown()) then
    job.stale = true
    return
  end
  local timer = self.env.C_Timer
  if not (timer and timer.After) then return end
  self.rebuildQueued = true
  timer.After(BrowseView.REBUILD_DELAY, function()
    self.rebuildQueued = nil
    if self.results ~= job then return end
    if not self.panel:IsShown() then
      job.stale = true
      return
    end
    self:rebuild()
    self:render()
  end)
end

function BrowseView:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function BrowseView:selectRow(r)
  local rows = self.results and self.results.rows
  local row = rows and rows[r + self.offset]
  if not row then return end
  self.selected = row.itemKey
  self:render()
  self:openItem(row)
end

local function money(v) return v and ns.Money.format(v) or "-" end

function BrowseView:statusText()
  if self.message then return self.message end
  if self.searching then return "Searching the auction house..." end
  local job = self.results
  if not job then return "Type a name and press Enter, or search with the box blank to list everything." end
  if #job.rows == 0 then return "Nothing on the auction house matches that search." end
  local line = ns.Browse.summary(#job.rows, job.query, job.truncated)
  return line .. ". Searched " .. ns.Time.ago(job.at, self:now()) .. "."
end

function BrowseView:render()
  if not self.panel then return end
  if self.item and self.item.row then return self.item:render() end
  if self.results and self.results.stale then self:rebuild() end
  local api = self:api()
  local rows = self.results and self.results.rows or {}
  local visible = #self.rows
  self.offset = math.max(0, math.min(self.offset, math.max(0, #rows - visible)))
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #rows)
  if self.searching then self.searchButton:Disable() else self.searchButton:Enable() end
  if self.searching then self.loading:spin() else self.loading:clear() end
  self.status:SetText(self:statusText())
  self:renderHint()
  self:renderHeaders()
  for r, cells in ipairs(self.rows) do
    local row = rows[r + self.offset]
    if row then
      cells[1]:SetText(row.name or "Loading item...")
      if api and row.quality then cells[1]:SetTextColor(api:qualityColor(row.quality))
      else cells[1]:SetTextColor(1, 1, 1) end
      cells[2]:SetText(row.level and tostring(row.level) or "-")
      cells[3]:SetText(tostring(row.listed))
      cells[4]:SetText(row.lowest and money(row.lowest) or "bid only")
      cells[5]:SetText(money(row.value))
      cells[6]:SetText(row.percent and (row.percent .. "%") or "-")
      local tone = BrowseView.TONES[ns.Browse.tone(row.percent)]
      if tone then cells[6]:SetTextColor(tone[1], tone[2], tone[3]) else cells[6]:SetTextColor(1, 1, 1) end
      cells.button:Show()
      self:attachTooltip(cells.button, row)
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and ns.Browse.sameKey(row.itemKey, self.selected))
  end
end

-- The item's own tooltip over its row, as in Blizzard's list.
function BrowseView:attachTooltip(button, row)
  local env, api = self.env, self:api()
  button:SetScript("OnEnter", function(b)
    local tip, link = env.GameTooltip, api and api:link(row.itemID)
    if not (tip and link) then return end
    tip:SetOwner(b, "ANCHOR_RIGHT")
    tip:SetHyperlink(link)
    tip:Show()
  end)
  button:SetScript("OnLeave", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
end

ns.BrowseView = BrowseView
return BrowseView
