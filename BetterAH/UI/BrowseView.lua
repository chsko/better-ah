-- The Browse view (#91): the regular auction house's search, inside Better AH. A search row (name or
-- item link, required level range) and a results table that sorts by any column, with market value and
-- how the lowest buyout compares to it. Layout follows the mockup linked from #90. This file only draws
-- and wires; the rules live in Core/Browse.lua and the client calls in Game/BrowseAPI.lua.
local _, ns = ...
ns = ns or {}

local BrowseView = {}
BrowseView.__index = BrowseView

BrowseView.WIDTH = 848 -- the main and detail panels together: the results list has no detail panel
BrowseView.DIVIDER = 8 -- the draggable gap between the results and the search history panel (#129)
BrowseView.ITEM_WIDTH = 540 -- an item's page uses the main panel, with the buy controls on the detail panel
BrowseView.DETAIL_WIDTH = 276 -- text width on the detail panel
-- { header, x, width, justify, sort column }, for the width the results start at; Browse.columns lays
-- them out again for any other width.
BrowseView.COLUMNS = ns.Browse.columns(BrowseView.WIDTH - BrowseView.DIVIDER - ns.Browse.HISTORY_WIDTH - 22)
BrowseView.TONES = { cheap = { 0.12, 1, 0 }, dear = { 1, 0.5, 0.25 } }
BrowseView.REBUILD_DELAY = 0.3 -- item names that load in a burst are drawn once
BrowseView.MAX_IDLE_REBUILDS = 5 -- rebuilds in a row that load nothing new before giving up

function BrowseView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, offset = 0,
    sortColumn = ns.Browse.DEFAULT_SORT, descending = false, columns = BrowseView.COLUMNS }, BrowseView)
end

-- Where the history panel's width is kept (BetterAHDB.browse), or nil in specs without one.
function BrowseView:settings()
  return self.addon.browseSettings
end

-- This character's key for its saved category and filters, or nil while the game hasn't said.
function BrowseView:characterKey()
  local tracker = ns.CharacterTracker
  return tracker and tracker.characterKey and tracker.characterKey(self.env) or nil
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
  self.width, self.height = width, height
  -- A menu left open doesn't come back open with the window.
  container:SetScript("OnHide", function() self:closeMenus() end)
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

  -- The Category button and the filter row under the search row (#92).
  local top = 0
  if ns.BrowseFilterBar then
    self.filterBar = ns.BrowseFilterBar.new(self)
    self.filterBar:build(panel, hi)
    top = ns.BrowseFilterBar.TOP
  end
  -- The results table sits under them.
  local list = env.CreateFrame("Frame", nil, panel)
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
  list:SetSize(width, height - top)
  self.list = list

  local go = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  go:SetSize(80, 22)
  go:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -1)
  go:SetText("Search")
  go:SetScript("OnClick", function() self:search() end)
  ns.Window.tooltip(env, go, "Search", "Search the auction house. A blank search lists everything.")
  self.searchButton = go

  local w = self.window
  self.rows = w:buildRows(list, BrowseView.COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:render() end, width)
  self:buildHeaders(list)

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
  status:SetWidth(width - 8)
  status:SetJustifyH("LEFT")
  if status.SetWordWrap then status:SetWordWrap(false) end
  self.status = status
  self.loading = ns.Loading.attach(env, panel, status, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4,
    width - 8, slot = true })

  -- The search history (#129) right of the results, with a divider to drag between them.
  if ns.BrowseHistory then
    self.history = ns.BrowseHistory.new(self)
    self.history:build(container, height)
    self:buildDivider(container, height)
  end
  self:layout(self:settings() and self:settings().historyWidth)

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
  self.built = true
  return container
end

-- The divider between the results and the history: dragging it left widens the history, right narrows
-- it. The width is saved when the drag ends; a double-click puts the default back.
function BrowseView:buildDivider(container, height)
  local env = self.env
  local d = env.CreateFrame("Button", nil, container)
  d:SetSize(BrowseView.DIVIDER, height)
  local grip = d:CreateTexture(nil, "ARTWORK")
  grip:SetSize(2, 40)
  grip:SetPoint("CENTER", d, "CENTER", 0, 0)
  grip:SetColorTexture(0.79, 0.64, 0.23, 0.6)
  local highlight = d:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetSize(4, height)
  highlight:SetPoint("CENTER", d, "CENTER", 0, 0)
  highlight:SetColorTexture(0.79, 0.64, 0.23, 0.25)
  ns.Window.tooltip(env, d, "Resize", "Drag to make the search history wider or narrower. Double-click to reset it.")
  local function cursorX()
    local x = env.GetCursorPosition()
    local ui = env.UIParent and env.UIParent:GetEffectiveScale() or 1
    local frame = self.window.frame
    local scale = frame and frame:GetScale() or 1
    return x / ui / scale
  end
  local function stop()
    if not self.dragging then return end
    self.dragging = nil
    d:SetScript("OnUpdate", nil)
    local settings = self:settings()
    if settings then settings.historyWidth = self.historyWidth end
  end
  d:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if env.GameTooltip then env.GameTooltip:Hide() end
    self.dragging = { x = cursorX(), width = self.historyWidth }
    d:SetScript("OnUpdate", function()
      -- The button can come up where we don't hear it (the game lost focus mid-drag).
      if env.IsMouseButtonDown and not env.IsMouseButtonDown("LeftButton") then return stop() end
      local drag = self.dragging
      if not drag then return end
      local width = ns.Browse.historyWidth(drag.width - (cursorX() - drag.x))
      if width ~= self.historyWidth then self:layout(width) end
    end)
  end)
  d:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then stop() end end)
  d:SetScript("OnHide", stop)
  d:SetScript("OnDoubleClick", function()
    stop()
    local settings = self:settings()
    if settings then settings.historyWidth = nil end
    self:layout(nil)
  end)
  self.divider = d
end

-- Splits Browse's width between the results and a history panel historyWidth wide (kept in range),
-- and lays the results out again for their new width.
function BrowseView:layout(historyWidth)
  if not self.history then return end
  historyWidth = ns.Browse.historyWidth(historyWidth)
  self.historyWidth = historyWidth
  local listWidth = self.width - BrowseView.DIVIDER - historyWidth
  self.listWidth = listWidth
  self.panel:SetWidth(listWidth)
  -- The search box gives up room for the level boxes, the Category button and Search.
  local fixed = self.filterBar and 380 or 250
  self.searchBox:SetWidth(math.max(120, math.min(260, listWidth - fixed)))
  self.list:SetWidth(listWidth)
  -- The status line's width, spinner room included, is set by Loading when the view renders.
  if self.loading and self.loading.at then self.loading.at[6] = listWidth - 8 end
  self.columns = ns.Browse.columns(listWidth - 22)
  ns.Window.layoutRows(self.rows, self.list, self.columns, listWidth)
  self:layoutHeaders()
  self.divider:ClearAllPoints()
  self.divider:SetPoint("TOPLEFT", self.container, "TOPLEFT", listWidth, 0)
  self.history:layout(listWidth + BrowseView.DIVIDER, historyWidth)
  if self.built then self:render() end
end

-- Whether the view wants the detail panel's room: yes for the results list, no on an item's page.
function BrowseView:wide()
  return not (self.item and self.item.row)
end

-- Opens a result's page: its auctions or price ladder, with the buy controls on the detail panel.
function BrowseView:openItem(row)
  self:closeMenus()
  self:showHistory(false)
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
  self:showHistory(true)
  self:render()
end

-- Another view is showing: the buy controls on the shared detail panel go.
function BrowseView:hide()
  self:closeMenus()
  if not self.item then return end
  -- An open quote would hold up buys elsewhere (the sniper's): drop it.
  if self.item.quoted or self.item.quoting then self.item:cancelQuote() end
  self.item:hideControls()
end

-- Clickable headers over the table's header row: a click sorts by that column, again reverses it.
function BrowseView:buildHeaders(panel)
  local env = self.env
  self.headers = {}
  for c, col in ipairs(self.columns) do
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

function BrowseView:layoutHeaders()
  for c, b in ipairs(self.headers) do
    local col = self.columns[c]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.list, "TOPLEFT", col[2], -29)
    b:SetWidth(col[3])
  end
end

function BrowseView:renderHeaders()
  for c, b in ipairs(self.headers) do
    local col = self.columns[c]
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

-- keepMenu: the category menu stays open (a category was picked that has subcategories to show).
function BrowseView:search(keepMenu)
  local api = self:api()
  -- Enter or a shift-click during our own search does nothing, like the disabled Search button.
  if self.searching then return end
  if not keepMenu then self:closeMenus() end
  self.searchBox:ClearFocus()
  self.minLevel:ClearFocus()
  self.maxLevel:ClearFocus()
  local typed = { text = self.searchBox:GetText(), minLevel = self.minLevel:GetText(),
    maxLevel = self.maxLevel:GetText() }
  local note
  if self.filterBar then
    local filters
    filters, note = self.filterBar:input()
    typed.category, typed.path, typed.chips = filters.category, filters.path, filters.chips
  end
  local query, why = ns.Browse.query(typed)
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
  -- What the history keeps is what was searched, not what the bar says when the answer comes.
  local category, filters
  if self.filterBar then category, filters = self.filterBar:history() end
  local job = { query = query, note = note, category = category, filters = filters }
  self.searchAfter = nil
  self.searching, self.message = job, nil
  self:render()
  api:search(query, function(results, truncated)
    if self.searching ~= job then return end
    self.searching = nil
    if self.history then self.history.message = nil end -- "Wait for this search to finish."
    if not results then
      self.message = "The search failed: " .. tostring(truncated) .. "."
    else
      job.raw, job.truncated, job.at, job.values = results, truncated, self:now(), {}
      self:remember(job)
      self.results, self.message = job, nil
      self.selected, self.offset = nil, 0
      self:rebuild()
    end
    self:render()
    local after = self.searchAfter
    if after then
      self.searchAfter = nil
      self:search(after.keepMenu)
    end
  end)
end

-- Saves a search that ran in the search history (a blank one is not kept).
function BrowseView:remember(job)
  local history = self.addon.searchHistory
  if not history then return end
  local query = job.query
  history:add({ text = query.searchString, minLevel = query.minLevel, maxLevel = query.maxLevel,
    category = query.path and job.category or nil, filters = job.filters }, job.at)
  if self.history then self.history:render() end
end

-- Fills the search row from a search in the history and runs it.
function BrowseView:searchAgain(search)
  if not search then return end
  self.searchBox:SetText(search.text or "")
  self.minLevel:SetText((search.minLevel or 0) > 0 and tostring(search.minLevel) or "")
  self.maxLevel:SetText((search.maxLevel or 0) > 0 and tostring(search.maxLevel) or "")
  if self.filterBar then self.filterBar:restore(search) end
  self:search()
end

-- The category or a filter changed: a new category searches at once (as in Blizzard's window), a
-- filter waits for Search or Enter.
function BrowseView:filtersChanged(searchNow, keepMenu)
  -- A category picked while a search runs is searched as soon as that one ends.
  if searchNow and self.searching then
    self.searchAfter = { keepMenu = keepMenu }
    return self:render()
  end
  if searchNow then return self:search(keepMenu) end
  self:render()
end

function BrowseView:closeMenus()
  if self.filterBar then self.filterBar:closeMenus() end
end

function BrowseView:showHistory(on)
  if self.history then
    self.history:show(on)
    self.divider:SetShown(on)
  end
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
  self:closeMenus()
  self.results, self.searching, self.selected, self.message, self.offset = nil, nil, nil, nil, 0
  if self.item and self.item.row then
    self.item:close()
    self.panel:Show()
    self:showHistory(true)
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
  line = line .. ". Searched " .. ns.Time.ago(job.at, self:now()) .. "."
  if job.note then line = job.note .. " " .. line end
  return line
end

function BrowseView:render()
  if not self.panel then return end
  if self.item and self.item.row then return self.item:render() end
  if self.results and self.results.stale then self:rebuild() end
  if self.history then self.history:render() end
  local api = self:api()
  local rows = self.results and self.results.rows or {}
  local visible = #self.rows
  self.offset = math.max(0, math.min(self.offset, math.max(0, #rows - visible)))
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #rows)
  if self.searching then self.searchButton:Disable() else self.searchButton:Enable() end
  if self.searching then self.loading:spin() else self.loading:clear() end
  self.status:SetText(self:statusText())
  if self.filterBar then self.filterBar:render() end
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
