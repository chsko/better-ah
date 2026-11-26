-- The My auctions view (#123): every auction the player has up, whether each has been undercut, and a
-- one-click cancel per auction. It takes the Cancel view's place in the sidebar (#9). Layout follows the
-- mockup linked from issue #123. This file only draws and wires; the rules live in Core/MyAuctions.lua,
-- the game calls in Game/MyAuctionsAPI.lua (owned auctions, cancel) and Game/PostingAPI.lua (searches).
local _, ns = ...
ns = ns or {}

local MyAuctionsView = {}
MyAuctionsView.__index = MyAuctionsView

MyAuctionsView.COLUMNS = {
  { "Item", 4, 174 }, { "Qty", 182, 34 }, { "Yours", 220, 66 }, { "Lowest", 290, 66 }, { "Left", 360, 44 },
  { "Status", 410, 108, "LEFT" },
}
MyAuctionsView.FILTERS = { { "all", "All" }, { "undercut", "Undercut" }, { "lowest", "Lowest" }, { "sold", "Sold" } }
MyAuctionsView.FILTER_HEIGHT = 26
MyAuctionsView.ROWS = 14
-- Status colours: orange and light blue differ in lightness too, so they can be told apart without hue.
MyAuctionsView.COLORS = { undercut = "ffff9a3c", lowest = "ff8fd0ff", sold = "ffffd100", dim = "ff9d9d9d" }

local function color(code, text) return "|c" .. code .. text .. "|r" end
local function money(c) return ns.Money.format(c) end

function MyAuctionsView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, offset = 0, filter = "all" },
    MyAuctionsView)
end

-- The status cell for a row; cancelling = a cancel for it was sent.
function MyAuctionsView.statusText(row, cancelling)
  local c = MyAuctionsView.COLORS
  local k, a = row.kind, row.auction
  if cancelling and k ~= "sold" then return color(c.dim, "Cancelling...") end
  if k == "undercut" then return color(c.undercut, "Undercut by " .. money(row.by)) end
  if k == "lowest" then return color(c.lowest, row.cheapest and "Lowest" or "Only one listed") end
  if k == "bid" then return "Has a bid" .. (a.bid and (": " .. money(a.bid)) or "") end
  if k == "sold" then
    local left = a.timeLeft and a.timeLeft > 0 and (", gold in " .. ns.MyAuctions.timeLeft(a.timeLeft)) or ""
    return color(c.sold, "Sold" .. left)
  end
  if k == "checking" then return color(c.dim, "Checking...") end
  if k == "failed" then return color(c.dim, "Check failed") end
  if k == "nobuyout" then return color(c.dim, "No buyout") end
  return color(c.dim, "Not checked yet")
end

-- The item's name, in its quality colour when the link gave one.
function MyAuctionsView.itemText(a)
  local name = a.name or a.item
  return a.color and ("|c" .. a.color .. name .. "|r") or name
end

-- The detail text for one row. info = { cost = cancel cost or nil, value = market value or nil,
-- plan = Posting.plan for a repost or nil }.
function MyAuctionsView.detailText(row, info)
  local a, lines = row.auction, {}
  local function add(text) lines[#lines + 1] = text end
  local q = a.quantity or 1
  local units = q == 1 and "1 item" or (q .. " units")
  if row.kind == "sold" then
    add(units .. " · sold")
    add("")
    local price = a.total or (a.unit and math.floor(a.unit * q + 0.5)) or a.bid
    if price then add("You get " .. money(ns.MyAuctions.net(price)) .. " after the 5% cut.") end
    add("The gold comes by mail" .. (a.timeLeft and a.timeLeft > 0 and (" in about "
      .. ns.MyAuctions.timeLeft(a.timeLeft)) or "") .. ".")
    return table.concat(lines, "\n")
  end
  add(units .. " · " .. ns.MyAuctions.timeLeft(a.timeLeft, a.band) .. " left")
  add("")
  if a.unit then
    if q == 1 then
      add("Your buyout: " .. money(a.unit))
    else
      add(string.format("Your price: %s each (%s)", money(a.unit), money(a.unit * q)))
    end
  else
    add("No buyout: bids only")
  end
  if row.kind == "checking" or row.kind == "unchecked" then
    add("Lowest that isn't yours: " .. (row.kind == "checking" and "checking..." or "not checked yet"))
  elseif row.kind == "failed" then
    add("Lowest that isn't yours: the check failed (" .. tostring(row.reason) .. ")")
  elseif a.unit then
    add("Lowest that isn't yours: " .. (row.cheapest and money(math.ceil(row.cheapest)) or "nobody else lists it"))
    if row.kind == "undercut" then
      add(string.format("Cheaper than yours: %d %s", row.cheaper, row.cheaper == 1 and "unit" or "units"))
    end
  end
  add("Market value: " .. (info.value and money(info.value) or "none yet"))
  if a.bidder then add("Someone has bid" .. (a.bid and (" " .. money(a.bid)) or "") .. ".") end
  add("")
  add("If you cancel")
  if info.cost then add("Deposit you lose: " .. (info.cost > 0 and money(info.cost) or "nothing")) end
  local plan = info.plan
  if plan and plan.action == "post" then
    add("Post would repost it at " .. money(plan.price) .. (q > 1 and " each" or ""))
  elseif plan and plan.reason == "below-floor" then
    add(string.format("Post would keep it in your bags: %s is below your floor of %s", money(plan.price),
      money(plan.floor)))
  end
  add("It comes back by mail. Once it's in your bags, it shows up in Post.")
  return table.concat(lines, "\n")
end

-- The detail text with nothing selected. t is MyAuctions.totals.
function MyAuctionsView.totalsText(t)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add("Click an auction to see its prices and cancel it.")
  add("")
  add("Up for sale")
  add(string.format("Auctions: %d (%d %s)", t.active, t.units, t.units == 1 and "unit" or "units"))
  add("At your prices: " .. money(t.atYours))
  add("At market value: " .. money(t.atMarket) .. (t.unpriced > 0 and string.format(" (%d without one)", t.unpriced)
    or ""))
  add("You'd get after the 5% cut: " .. money(t.afterCut))
  add("Ending within 2 hours: " .. t.soon)
  if t.sold > 0 then
    add("")
    add(string.format("Sold, gold on the way: %s from %d %s, after the cut. It comes by mail.",
      money(t.soldGold), t.sold, t.sold == 1 and "auction" or "auctions"))
  end
  if t.undercut > 0 then
    add("")
    add(string.format("Undercut: %d. Cancelling them all loses %s in deposits.", t.undercut, money(t.undercutCost)))
  end
  return table.concat(lines, "\n")
end

function MyAuctionsView:build(f, x, y, width, height)
  local env, w = self.env, self.window
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.panel = panel

  self.filterButtons = {}
  for i, filter in ipairs(MyAuctionsView.FILTERS) do
    local b = ns.Window.entryButton(env, panel, 92)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * 96, 0)
    b:SetScript("OnClick", function() self:setFilter(filter[1]) end)
    self.filterButtons[filter[1]] = b
  end
  local check = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  check:SetSize(110, 20)
  check:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, 0)
  check:SetText("Check prices")
  check:SetScript("OnClick", function() self:checkPrices() end)
  ns.Window.tooltip(env, check, "Check prices", "Look up each item you have up, once, to see which of your auctions "
    .. "someone has listed cheaper.")
  self.checkButton = check

  local list = env.CreateFrame("Frame", nil, panel)
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -MyAuctionsView.FILTER_HEIGHT)
  list:SetSize(width, height - MyAuctionsView.FILTER_HEIGHT)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.list = list
  local status = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6)
  status:SetWidth(width)
  status:SetJustifyH("LEFT")
  self.status = status
  self.loading = ns.Loading.attach(env, list, status, { "TOPLEFT", list, "TOPLEFT", 0, -6, width })
  self.rows = w:buildRows(list, MyAuctionsView.COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:render() end)

  local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 4)
  footer:SetWidth(width - 24)
  footer:SetJustifyH("LEFT")
  self.footer = footer

  -- On the shared detail panel, so shown only while this view is.
  local nextButton = env.CreateFrame("Button", nil, w.detailLayer, "UIPanelButtonTemplate")
  nextButton:SetHeight(22)
  nextButton:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  nextButton:SetPoint("BOTTOMRIGHT", w.detailLayer, "BOTTOMRIGHT", -12, 12)
  nextButton:SetScript("OnClick", function() self:cancelNext() end)
  ns.Window.tooltip(env, nextButton, "Cancel next undercut", "Cancel the first undercut auction in the list. "
    .. "One click per auction: the game needs a click for each cancel.")
  nextButton:Hide()
  self.nextButton = nextButton
  local cancel = env.CreateFrame("Button", nil, w.detailLayer, "UIPanelButtonTemplate")
  cancel:SetHeight(26)
  cancel:SetPoint("BOTTOMLEFT", nextButton, "TOPLEFT", 0, 6)
  cancel:SetPoint("BOTTOMRIGHT", nextButton, "TOPRIGHT", 0, 6)
  cancel:SetText("Cancel auction")
  cancel:SetScript("OnClick", function() self:cancelSelected() end)
  ns.Window.tooltip(env, cancel, "Cancel auction", "Take this auction off the auction house. You lose its deposit, "
    .. "and the items come back by mail.")
  cancel:Hide()
  self.cancelButton = cancel
  -- What the last cancel did, above the buttons.
  local note = w.detailLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("BOTTOMLEFT", cancel, "TOPLEFT", 0, 8)
  note:SetWidth(ns.Window.DETAIL - 24)
  note:SetJustifyH("LEFT")
  note:Hide()
  self.note = note

  local api = self.addon.myAuctionsAPI
  if api then
    api.onChange = function()
      if self.visit then self:refresh() end
    end
  end
  return panel
end

function MyAuctionsView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

function MyAuctionsView:market()
  return ns.AuctionAPI and ns.AuctionAPI.currentMarket(self.env) or nil
end

function MyAuctionsView:marketValue(item)
  local prices, key = self.addon.prices, self:market()
  return prices and key and prices:marketValue(key, item, self:now()) or nil
end

-- Called whenever the view is shown: the first showing of each auction house visit asks for the list.
function MyAuctionsView:show()
  if not self.visit then
    self.visit = { checks = {}, sent = {}, recorded = {} }
    self.selected, self.offset, self.message = nil, 0, nil
    local api = self.addon.myAuctionsAPI
    if api then api:query() end
  end
  self:refresh()
end

-- The auction house closed: the next visit starts afresh.
function MyAuctionsView:reset()
  self.visit, self.auctions, self.complete, self.checking, self.selected, self.message = nil, nil, nil, nil, nil, nil
  self:hide()
  self.window:setBadge("auctions", 0)
end

-- Leaving the view: hides what it puts on the shared detail panel, and takes back the price checks
-- still waiting, so the Post view's and the sniper's searches don't queue behind them. Showing the
-- view again checks what is left.
function MyAuctionsView:hide()
  local api = self.addon.postingAPI
  if self.checking and api and api.drop then api:drop(self) end
  if not self.cancelButton then return end
  self.cancelButton:Hide()
  self.nextButton:Hide()
  self.note:Hide()
end

function MyAuctionsView:read()
  local api = self.addon.auctionAPI
  local nameOf = api and function(item) return api:itemName(item) end
  local auctions, complete
  local myApi = self.addon.myAuctionsAPI
  if myApi then
    auctions, complete = myApi:read(nameOf)
  elseif ns.MyAuctionsAPI then
    auctions, complete = ns.MyAuctionsAPI.readOwned(self.env, nameOf)
  end
  self.auctions, self.complete = auctions or {}, auctions ~= nil and complete
  -- A cancel the list no longer shows has done its part.
  if self.visit then
    local up = {}
    for _, a in ipairs(self.auctions) do
      if not a.sold then up[a.id] = true end -- a sold part keeps the id of an auction that is gone
    end
    for id, state in pairs(self.visit.sent) do
      if state == "done" and not up[id] then self.visit.sent[id] = nil end
    end
  end
end

function MyAuctionsView:refresh()
  self:read()
  -- Items not checked yet this visit are checked by themselves: on the first showing, after a check
  -- was left half done, and for auctions posted since. A failed check waits for Check prices.
  if self.visit and self.complete and not self.checking and self.window.model.view == "auctions"
    and #self:unchecked() > 0 then
    return self:checkPrices(true)
  end
  self:render()
end

-- The items up for sale with no check this visit.
function MyAuctionsView:unchecked()
  local checks, out = self.visit and self.visit.checks or {}, {}
  for _, a in ipairs(ns.MyAuctions.toCheck(self.auctions)) do
    if not checks[a.key] then out[#out + 1] = a end
  end
  return out
end

-- Looks up each item the player has up once, in the Post view's search queue; onlyNew: just the ones not
-- checked yet this visit.
function MyAuctionsView:checkPrices(onlyNew)
  local visit, api = self.visit, self.addon.postingAPI
  if not (visit and api) or self.checking then return end
  if not api.open then
    self.message = "Open the auction house to check prices."
    return self:render()
  end
  local todo = onlyNew and self:unchecked() or ns.MyAuctions.toCheck(self.auctions)
  if #todo == 0 then return self:render() end
  local run = { done = 0, total = #todo }
  self.checking = run
  for _, a in ipairs(todo) do
    visit.checks[a.key] = { pending = true }
    -- Commodity or not is read from the client just before the search (PostingAPI:prepare).
    local entry = { item = a.item, itemID = a.itemID, itemKey = a.itemKey, name = a.name, commodity = true,
      unsure = true, tag = self }
    api:search(entry, function(listings, complete)
      if self.visit ~= visit then return end
      run.done = run.done + 1
      if listings then
        visit.checks[a.key] = { listings = listings, at = self:now(), commodity = entry.commodity }
        -- What the check saw counts toward market value as the Post view's checks do: once per item per
        -- visit, full results only, and not for one random-suffix variant of an item.
        local prices, key = self.addon.prices, self:market()
        if complete == true and prices and key and prices.recordSearch and not ns.PostingAPI.variant(entry)
          and not visit.recorded[a.item] then
          visit.recorded[a.item] = prices:recordSearch(key, self:now(), a.item, listings, a.name) or nil
        end
      elseif complete == "dropped" then
        visit.checks[a.key] = nil -- left the view; checked when it shows again
        run.dropped = true
      else
        visit.checks[a.key] = { failed = complete or "no answer" }
      end
      if run.done >= run.total then
        self.checking = nil
        if not run.dropped then visit.checkedAt = self:now() end
      end
      self:render()
    end)
  end
  self:render()
end

function MyAuctionsView:setFilter(filter)
  self.filter = filter
  self.offset = 0
  self:render()
end

function MyAuctionsView:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function MyAuctionsView:selectRow(r)
  local row = self.shown and self.shown[r + self.offset]
  if not row then return end
  self.selected = row.auction.uid
  self:render()
end

function MyAuctionsView:rowsNow()
  local visit = self.visit
  return ns.MyAuctions.rows(self.auctions or {}, visit and visit.checks or {})
end

-- Cancels one row's auction. Runs inside the click.
function MyAuctionsView:cancel(row)
  local api, visit = self.addon.myAuctionsAPI, self.visit
  if not (api and visit and row) or row.kind == "sold" or visit.sent[row.auction.id] then return end
  local a = row.auction
  local name = a.name or a.item
  local sent, why = api:cancel(a.id, function(ok, reason)
    if self.visit ~= visit then return end
    if ok then
      visit.sent[a.id] = "done"
      self.message = string.format("Cancelled %s%s. It comes back by mail, then shows up in Post.",
        (a.quantity or 1) > 1 and (a.quantity .. " ") or "", name)
    else
      visit.sent[a.id] = nil
      self.message = string.format("Couldn't cancel %s: %s.", name, tostring(reason))
    end
    self:render()
  end)
  if sent then
    visit.sent[a.id] = "sent"
    self.message = "Cancelling " .. name .. "..."
    -- Move on to the next undercut, so the next click cancels that one.
    local nextRow = ns.MyAuctions.nextUndercut(self:rowsNow(), visit.sent)
    if self.selected == a.uid and nextRow then self.selected = nextRow.auction.uid end
  else
    self.message = string.format("Couldn't cancel %s: %s.", name, tostring(why))
  end
  self:render()
end

function MyAuctionsView:selectedRow(rows)
  for _, r in ipairs(rows or self:rowsNow()) do
    if r.auction.uid == self.selected then return r end
  end
  return nil
end

function MyAuctionsView:cancelSelected()
  self:cancel(self:selectedRow())
end

function MyAuctionsView:cancelNext()
  local visit = self.visit
  local row = visit and ns.MyAuctions.nextUndercut(self:rowsNow(), visit.sent)
  if not row then return end
  self.selected = row.auction.uid
  self:cancel(row)
end

-- A repost plan, as the Post view would make it from this check's listings.
function MyAuctionsView:plan(row)
  local visit, a = self.visit, row.auction
  local check = visit and visit.checks[a.key]
  if not (check and check.listings and ns.Posting) then return nil end
  local settings, key = self.addon.posting, self:market()
  local post = self.window.postView
  local rule = post and post.matFloor and post:matFloor(a.item)
  return ns.Posting.plan({
    have = a.quantity or 1, listings = check.listings, marketValue = self:marketValue(a.item),
    floor = settings and key and settings:floor(key, a.item), ruleFloor = rule and rule.floor,
    commodity = check.commodity, step = ns.PostingAPI and ns.PostingAPI.priceStep(self.env) or 1,
  })
end

function MyAuctionsView:statusLine(rows)
  if not self.complete then
    if self.addon.myAuctionsAPI and not self.addon.myAuctionsAPI.open then return "Open the auction house to see "
      .. "your auctions." end
    return "Reading your auctions..."
  end
  if #rows == 0 then return "You have no auctions up on this character." end
  local run = self.checking
  if run then return string.format("Checking prices: %d of %d items.", run.done, run.total) end
  local at = self.visit and self.visit.checkedAt
  if at then return "Prices checked " .. ns.Time.ago(at, self:now()) .. "." end
  return "Check prices to see which of your auctions are undercut."
end

function MyAuctionsView:render()
  if not self.panel then return end
  local rows = self:rowsNow()
  local counts = ns.MyAuctions.counts(rows)
  local shown = ns.MyAuctions.filter(rows, self.filter)
  self.shown = shown
  for _, f in ipairs(MyAuctionsView.FILTERS) do
    local b = self.filterButtons[f[1]]
    b:SetText(f[2] .. " " .. counts[f[1]])
    ns.Window.markSelected(b, f[1] == self.filter)
  end
  local api = self.addon.postingAPI
  if self.checking or not (api and api.open) or #ns.MyAuctions.toCheck(self.auctions) == 0 then
    self.checkButton:Disable()
  else
    self.checkButton:Enable()
  end

  self.status:SetText(self:statusLine(rows))
  if self.checking then
    self.loading:show(self.checking.done, self.checking.total)
  elseif not self.complete and self.addon.myAuctionsAPI and self.addon.myAuctionsAPI.open then
    self.loading:spin()
  else
    self.loading:clear()
  end

  local visible = MyAuctionsView.ROWS
  self.offset = math.max(0, math.min(self.offset, math.max(0, #shown - visible)))
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #shown)
  local sent = self.visit and self.visit.sent or {}
  for r, cells in ipairs(self.rows) do
    local row = shown[r + self.offset]
    if row then
      local a = row.auction
      cells[1]:SetText(MyAuctionsView.itemText(a))
      cells[2]:SetText(tostring(a.quantity or 1))
      cells[3]:SetText(a.unit and money(math.floor(a.unit + 0.5)) or "-")
      local lowest = "-"
      if row.kind == "lowest" and row.cheapest == nil then
        lowest = "yours"
      elseif row.cheapest then
        lowest = money(math.ceil(row.cheapest))
      end
      cells[4]:SetText(row.kind == "sold" and "-" or lowest)
      cells[5]:SetText(row.kind == "sold" and "-" or ns.MyAuctions.timeLeft(a.timeLeft, a.band))
      cells[6]:SetText(MyAuctionsView.statusText(row, sent[a.id] ~= nil))
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.auction.uid == self.selected)
  end

  local totals = ns.MyAuctions.totals(rows, function(item) return self:marketValue(item) end, function(a)
    return self.addon.myAuctionsAPI and self.addon.myAuctionsAPI:cancelCost(a.id)
  end)
  if #rows > 0 then
    local text = string.format("%d %s · listed for %s · %d undercut", totals.active,
      totals.active == 1 and "auction" or "auctions", money(totals.atYours), totals.undercut)
    if totals.sold > 0 then text = text .. string.format(" · %d sold, you get %s", totals.sold,
      ns.Money.short(totals.soldGold)) end
    self.footer:SetText(text)
  else
    self.footer:SetText("")
  end
  self.window:setBadge("auctions", counts.undercut)
  if self.window.model.view == "auctions" then self:renderDetail(rows, totals) end
end

function MyAuctionsView:renderDetail(rows, totals)
  local w = self.window
  local row = self:selectedRow(rows)
  if not row then self.selected = nil end
  local sent = self.visit and self.visit.sent or {}
  local myApi = self.addon.myAuctionsAPI
  if row then
    local a = row.auction
    w.detailTitle:SetText(MyAuctionsView.itemText(a))
    w.detailBody:SetText(MyAuctionsView.detailText(row, {
      cost = row.kind ~= "sold" and myApi and myApi:cancelCost(a.id) or nil,
      value = self:marketValue(a.item), plan = row.kind ~= "sold" and self:plan(row) or nil,
    }))
    self.cancelButton:Show()
    if row.kind == "sold" or sent[a.id] or not (myApi and myApi.open) then
      self.cancelButton:Disable()
    else
      self.cancelButton:Enable()
    end
  else
    w.detailTitle:SetText(#rows > 0 and "Your auctions on this character" or "")
    w.detailBody:SetText(#rows > 0 and MyAuctionsView.totalsText(totals) or "")
    self.cancelButton:Hide()
  end
  local left = 0
  for _, r in ipairs(rows) do
    if r.kind == "undercut" and not sent[r.auction.id] then left = left + 1 end
  end
  self.nextButton:SetText(string.format("Cancel next undercut (%d left)", left))
  self.nextButton:SetShown(#rows > 0)
  if left > 0 and myApi and myApi.open then self.nextButton:Enable() else self.nextButton:Disable() end
  self.note:SetText(self.message or "")
  self.note:SetShown(self.message ~= nil)
end

ns.MyAuctionsView = MyAuctionsView
return MyAuctionsView
