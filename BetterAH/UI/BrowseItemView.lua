-- One item's page in the Browse view (#93, #94): clicking a result opens it. An item shows its auctions,
-- to buy out or bid on; a commodity shows its price ladder, to buy a quantity cheapest first. The buy
-- controls sit on the detail panel. Layout follows artboards 2 and 3 of the mockup linked from #90.
-- This file only draws and wires; the rules live in Core/Buying.lua, the client calls in
-- Game/BrowseAPI.lua.
local _, ns = ...
ns = ns or {}

local ItemView = {}
ItemView.__index = ItemView

ItemView.ITEM_COLUMNS = {
  { "Buyout", 4, 90 }, { "Bid", 98, 90 }, { "Time left", 192, 84 }, { "Seller", 290, 140, "LEFT" },
  { "Of market", 436, 70 },
}
ItemView.COMMODITY_COLUMNS = {
  { "Price each", 4, 100 }, { "Available", 108, 80 }, { "Running total", 192, 180 }, { "Of market", 380, 70 },
}
ItemView.LIST_TOP = -26 -- the lists sit under the top line (back, name, market value, refresh)
ItemView.GOLD, ItemView.GREY = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }

local function money(v) return v and ns.Money.format(v) or "-" end

function ItemView.new(browse)
  local w = browse.window
  return setmetatable({ browse = browse, window = w, env = w.env, addon = browse.addon, offset = 0 }, ItemView)
end

function ItemView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

function ItemView:api()
  return self.addon.browseAPI
end

local function button(env, parent, text, width)
  local b = env.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 90, 22)
  b:SetText(text)
  return b
end

local function input(env, parent, width, letters)
  local e = env.CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  if e.SetMaxLetters then e:SetMaxLetters(letters) end
  e:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  return e
end

function ItemView:build(parent, width, height)
  local env, w = self.env, self.window
  local panel = env.CreateFrame("Frame", nil, parent)
  panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  panel:Hide()
  self.panel = panel

  local back = button(env, panel, "< Results", 80)
  back:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  back:SetScript("OnClick", function() self.browse:closeItem() end)
  ns.Window.tooltip(env, back, "Back to results", "Go back to the search results.")
  self.backButton = back
  local name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("LEFT", back, "RIGHT", 10, 0)
  name:SetWidth(230)
  name:SetJustifyH("LEFT")
  if name.SetWordWrap then name:SetWordWrap(false) end
  self.nameText = name
  local refresh = button(env, panel, "Refresh", 70)
  refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  refresh:SetScript("OnClick", function() self:load() end)
  ns.Window.tooltip(env, refresh, "Refresh", "Look up this item's auctions again.")
  self.refreshButton = refresh
  local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
  value:SetJustifyH("RIGHT")
  self.valueText = value

  -- Two lists in the same place: an item's auctions, or a commodity's price ladder.
  local function list(columns, onClick)
    local frame = env.CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, ItemView.LIST_TOP)
    frame:SetSize(width, height + ItemView.LIST_TOP)
    local rows = w:buildRows(frame, columns, onClick, function(offset) self.offset = offset; self:render() end)
    frame:Hide()
    return frame, rows
  end
  self.itemList, self.itemRows = list(ItemView.ITEM_COLUMNS, function(i) self:selectAuction(i) end)
  self.commodityList, self.commodityRows = list(ItemView.COMMODITY_COLUMNS, function(i) self:takeTo(i) end)

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
  status:SetWidth(width - 8)
  status:SetJustifyH("LEFT")
  if status.SetWordWrap then status:SetWordWrap(false) end
  self.status = status
  self.loading = ns.Loading.attach(env, panel, status, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4, width - 8,
    slot = true })

  self:buildItemControls()
  self:buildCommodityControls()
  local layer = w.detailLayer
  local gold = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gold:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 12)
  gold:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 12)
  gold:SetJustifyH("LEFT")
  gold:Hide()
  self.goldText = gold
  local message = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  message:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 30)
  message:SetWidth(ns.BrowseView.DETAIL_WIDTH)
  message:SetJustifyH("LEFT")
  message:Hide()
  self.messageText = message
  return panel
end

-- The buy out and bid controls for an item, on the detail panel.
function ItemView:buildItemControls()
  local env, layer = self.env, self.window.detailLayer
  local c = {}
  local buy = button(env, layer, "Buy out")
  buy:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 150)
  buy:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 150)
  buy:SetScript("OnClick", function() self:buyout() end)
  ns.Window.tooltip(env, buy, "Buy out", "Buy the selected auction now, at its buyout price.")
  c.buy = buy
  local label = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 124)
  label:SetText("Or bid")
  c.label = label
  local boxes = {}
  local x = 14
  for i, unit in ipairs({ "g", "s", "c" }) do
    local box = input(env, layer, i == 1 and 52 or 26, i == 1 and 6 or 2)
    box:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", x, 98)
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged", function() self:renderDetail() end)
    local text = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(unit)
    boxes[i], c["unit" .. i] = box, text
    x = x + (i == 1 and 52 or 26) + 18
  end
  c.boxes = boxes
  local bid = button(env, layer, "Place bid")
  bid:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 68)
  bid:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 68)
  bid:SetScript("OnClick", function() self:placeBid() end)
  ns.Window.tooltip(env, bid, "Place bid", "Bid this much on the selected auction. If someone outbids you, "
    .. "your gold comes back by mail.")
  c.bid = bid
  self.itemControls = c
end

-- The quantity and buy controls for a commodity, on the detail panel.
function ItemView:buildCommodityControls()
  local env, layer = self.env, self.window.detailLayer
  local c = {}
  local label = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 182)
  label:SetText("How many")
  c.label = label
  local qty = input(env, layer, 80, 6)
  qty:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 16, 156)
  qty:SetScript("OnTextChanged", function() self:quantityChanged() end)
  -- Enter asks for the price too: a key press is a hardware event the game has let through (#120).
  qty:SetScript("OnEnterPressed", function(b)
    b:ClearFocus()
    if c.buy:IsEnabled() then self:quote() end
  end)
  c.quantity = qty
  local max = button(env, layer, "Max", 60)
  max:SetPoint("LEFT", qty, "RIGHT", 8, 0)
  max:SetScript("OnClick", function() self:maxQuantity() end)
  ns.Window.tooltip(env, max, "Max", "As many as you can afford, cheapest first.")
  c.max = max
  local buy = button(env, layer, "Buy")
  buy:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 124)
  buy:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 124)
  buy:SetScript("OnClick", function() self:quote() end)
  ns.Window.tooltip(env, buy, "Buy",
    "Ask the auction house for the price of this many, then confirm. Or press Enter in the quantity box.")
  c.buy = buy
  local confirmText = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  confirmText:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 92)
  confirmText:SetWidth(ns.BrowseView.DETAIL_WIDTH)
  confirmText:SetJustifyH("LEFT")
  c.confirmText = confirmText
  local confirm = button(env, layer, "Confirm", 110)
  confirm:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 60)
  confirm:SetScript("OnClick", function() self:confirm() end)
  ns.Window.tooltip(env, confirm, "Confirm", "Buy them at the price the auction house quoted.")
  c.confirm = confirm
  local cancel = button(env, layer, "Cancel", 76)
  cancel:SetPoint("LEFT", confirm, "RIGHT", 6, 0)
  cancel:SetScript("OnClick", function() self:cancelQuote() end)
  c.cancel = cancel
  self.commodityControls = c
end

local function showAll(controls, on)
  for k, v in pairs(controls) do
    if k == "boxes" then
      for _, b in ipairs(v) do b:SetShown(on) end
    else
      v:SetShown(on)
    end
  end
end

-- Hides the detail panel controls (another view, or the results list, is showing).
function ItemView:hideControls()
  if not self.itemControls then return end
  showAll(self.itemControls, false)
  showAll(self.commodityControls, false)
  self.goldText:Hide()
  self.messageText:Hide()
end

function ItemView:open(row)
  if self.api and self:api() then self:api():cancelCommodity() end
  self.row, self.list, self.rows, self.ladder, self.selected = row, nil, nil, nil, nil
  self.quoted, self.message, self.offset, self.busy, self.sending = nil, nil, 0, nil, nil
  -- A commodity starts at 1 (#125): a row click fills up to that row, Max what you can afford.
  self.commodityControls.quantity:SetText("1")
  for _, b in ipairs(self.itemControls.boxes) do b:SetText("") end
  self.panel:Show()
  self:load()
end

function ItemView:close()
  local api = self:api()
  if api then api:cancelCommodity() end
  self.row, self.loadJob, self.quoted, self.busy, self.quoting, self.sending = nil, nil, nil, nil, nil, nil
  if self.panel then self.panel:Hide() end
  self:hideControls()
end

function ItemView:load()
  local api, row = self:api(), self.row
  if not (api and row) then return end
  local job = {}
  self.loadJob = job
  self:render()
  api:auctions(row, function(list, complete)
    if self.loadJob ~= job then return end
    self.loadJob = nil
    if not list then
      self.loadError = "Couldn't look up its auctions: " .. tostring(complete) .. "."
    else
      self.loadError = nil
      self.list, self.complete = list, complete
      self:rebuild()
    end
    self:render()
  end)
end

function ItemView:rebuild()
  local list, api = self.list, self:api()
  if not list then return end
  if list.commodity then
    self.rows = nil
    self:relayer()
  else
    self.ladder = nil
    self.rows = ns.Buying.itemRows(list, api and api:me(), self.row.value)
    -- Keep the selection when the auction is still there.
    local kept
    for _, r in ipairs(self.rows) do
      if self.selected and r.auctionID == self.selected.auctionID then kept = r end
    end
    self.selected = kept
  end
end

function ItemView:quantity()
  return tonumber(self.commodityControls.quantity:GetText() or "") or 0
end

function ItemView:relayer()
  if self.list and self.list.commodity then
    self.ladder = ns.Buying.ladder(self.list, self:quantity(), self.row.value)
  end
end

function ItemView:quantityChanged()
  -- A quote asked for or given is for the old quantity: drop it, so Confirm can't buy that.
  if self.quoted or self.quoting then self:cancelQuote() end
  self:relayer()
  self:render()
end

function ItemView:maxQuantity()
  if not self.ladder then return end
  local api = self:api()
  local n = ns.Buying.affordable(self.ladder.rows, api and api:money())
  self.commodityControls.quantity:SetText(tostring(n))
  self:quantityChanged()
end

-- Clicking a ladder row sets the quantity to everything up to and including it; Shift-click to only that
-- row's count (#191), which the game still fills cheapest first.
function ItemView:takeTo(r)
  local row = self.ladder and self.ladder.rows[r + self.offset]
  if not row then return end
  local shift = self.env.IsShiftKeyDown and self.env.IsShiftKeyDown() and true or false
  self.commodityControls.quantity:SetText(tostring(ns.Buying.clickQuantity(row, shift)))
  self:quantityChanged()
end

function ItemView:selectAuction(r)
  local row = self.rows and self.rows[r + self.offset]
  if not row then return end
  self.selected = row
  if row.minBid and not row.own then
    local g, s, c = ns.Buying.split(row.minBid)
    local boxes = self.itemControls.boxes
    boxes[1]:SetText(g > 0 and tostring(g) or "")
    boxes[2]:SetText((g > 0 or s > 0) and tostring(s) or "")
    boxes[3]:SetText(tostring(c))
  end
  self:render()
end

function ItemView:bidAmount()
  local b = self.itemControls.boxes
  return ns.Buying.money(b[1]:GetText(), b[2]:GetText(), b[3]:GetText())
end

function ItemView:say(text)
  self.message = text
  self:render()
end

-- Sends a purchase before the page is redrawn. In game the Buy click's StartCommoditiesPurchase was blocked
-- when the page (and the clicked button) was redrawn first, though the same code from a key press got its
-- price (#120); not redrawing first is the guess, as other addons' Buy buttons do. The message is set before
-- the call and drawn after it. A callback that answers at once has already drawn its own message.
function ItemView:sendThenDraw(text, send)
  self.message = text
  send()
  self:render()
end

-- Books a buy for item, the page's row when the buy was sent (#162): its answer can come after the player
-- has gone back to the results or opened another item, so it never reads self.row.
function ItemView:book(item, link, count, copper)
  local purchases = self.addon and self.addon.purchases
  if purchases then purchases:bought(item.itemID, link, count, copper, self:now()) end
  local ledger = self.addon and self.addon.ledgerAPI
  if ledger then ledger:bought(item.itemID, item.name, count, copper, "Browse") end
end

function ItemView:buyout()
  local api, row = self:api(), self.selected
  local ok, why = ns.Buying.canBuyout(row, api and api:money())
  if not ok then return self:say(why) end
  local item, price = self.row, row.buyout
  local name, token = item.name or "the item", {}
  self.busy, self.sending = true, token
  self:sendThenDraw("Buying...", function() api:buyout(row.auctionID, price, function(bought, reason, kind)
    if bought then self:book(item, row.link, 1, price) end
    if self.sending ~= token then return end -- the page moved on, or a later buy is waiting: only book it
    self.busy = nil
    if bought then
      self:say(string.format("Bought %s for %s.", name, money(price)))
      self.selected = nil
    elseif kind == "unknown" then
      self:say("No answer from the auction house yet. It may have gone through: check your mail before buying again.")
    else
      self:say("Not bought: " .. tostring(reason) .. ".")
    end
    self:load()
  end) end)
end

function ItemView:placeBid()
  local api, row = self:api(), self.selected
  local amount = self:bidAmount()
  local ok, why = ns.Buying.canBid(row, amount, api and api:money())
  if not ok then return self:say(why) end
  local token = {}
  self.busy, self.sending = true, token
  self:sendThenDraw("Bidding...", function() api:bid(row.auctionID, amount, function(placed, reason)
    if self.sending ~= token then return end -- the page moved on, or a later send is waiting
    self.busy = nil
    if placed then
      self:say(string.format("Bid %s sent. If someone outbids you, your gold comes back by mail.", money(amount)))
    else
      self:say("Bid not placed: " .. tostring(reason) .. ".")
    end
    self:load()
  end) end)
end

function ItemView:quote()
  local api, ladder = self:api(), self.ladder
  if not (ladder and ladder.quantity > 0) then return self:say("Type how many to buy.") end
  local have = api and api:money()
  if have and ladder.total > have then return self:say("You don't have enough gold for that many.") end
  local shown, qty, typed = ladder.total, ladder.quantity, self:quantity()
  local token = {}
  self.busy, self.quoting, self.sending = true, token, nil -- a late answer to an older buy only books it
  -- The auction house can send the quote again (a new price): each one replaces the last.
  self:sendThenDraw("Asking for the price...", function() api:quoteCommodity(self.row.itemID, qty, function(unit, total)
    if self.quoting ~= token then return end
    self.busy = nil
    if not unit then
      self.quoting = nil
      return self:say("No price: " .. tostring(total) .. ". Click Buy to try again.")
    end
    self.quoted = { quantity = qty, typed = typed, unit = unit, total = total, shown = shown,
      change = ns.Buying.quote(shown, total) }
    self.message = nil
    self:render()
  end) end)
end

function ItemView:confirm()
  local api, q = self:api(), self.quoted
  -- The quote is for what was typed then, cut to what was for sale (a Refresh may change the ladder since;
  -- the server's quote still stands). Typing again already drops the quote.
  if not q or q.typed ~= self:quantity() then return self:cancelQuote() end
  local item = self.row
  local name, token = item.name or "the item", {}
  self.busy, self.quoted, self.quoting, self.sending = true, nil, nil, token
  self:sendThenDraw("Buying...", function() api:confirmCommodity(function(bought, reason)
    if bought then self:book(item, nil, q.quantity, q.total) end
    if self.sending ~= token then return end -- the page moved on, or a later buy is waiting: only book it
    self.busy = nil
    if bought then
      self:say(string.format("Bought %d %s for %s.", q.quantity, name, money(q.total)))
      self.commodityControls.quantity:SetText("1")
      self:relayer()
    elseif reason == "no answer from the auction house" then
      self:say("No answer from the auction house yet. It may have gone through: check your mail before buying again.")
    else
      self:say("Not bought: " .. tostring(reason) .. ".")
    end
    self:load()
  end) end)
end

function ItemView:cancelQuote()
  local api = self:api()
  if api then api:cancelCommodity() end
  if self.quoting then self.busy = nil end
  self.quoted, self.quoting = nil, nil
  self:render()
end

function ItemView:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function ItemView:statusText()
  if self.loadJob then return "Looking up its auctions..." end
  if self.loadError then return self.loadError end
  if not self.list then return "" end
  local partial = self.complete == false and " The auction house didn't send them all: Refresh to try again." or ""
  if self.list.commodity then
    local n = self.ladder and self.ladder.available or 0
    if n == 0 then return "None for sale by others." .. partial end
    return string.format("%d for sale by others. Click: buy up to a row. "
      .. "Shift-click: that row's amount, cheapest first.%s", n, partial)
  end
  local n = #(self.rows or {})
  if n == 0 then return "No auctions of it right now." .. partial end
  return string.format("%d %s. Gold bid: you're the highest bidder. Grey: your own.%s", n,
    n == 1 and "auction" or "auctions", partial)
end

-- Only while the Browse view shows this page: the detail panel and its controls belong to whichever
-- view is showing.
function ItemView:showing()
  local w = self.window
  return self.panel ~= nil and self.row ~= nil and self.panel:IsShown() and w.model.view == "browse"
    and w.model.mode == "better"
end

function ItemView:render()
  if not self:showing() then return end
  local api, row = self:api(), self.row
  local commodity = self.list and self.list.commodity
  self.nameText:SetText(row.name or "Loading item...")
  if api and row.quality then self.nameText:SetTextColor(api:qualityColor(row.quality))
  else self.nameText:SetTextColor(1, 0.82, 0) end
  self.valueText:SetText("Market value " .. money(row.value) .. (commodity and " each" or ""))
  self.itemList:SetShown(self.list ~= nil and not commodity)
  self.commodityList:SetShown(commodity == true)
  if self.loadJob then self.loading:spin() else self.loading:clear() end
  self.status:SetText(self:statusText())
  if commodity then self:renderLadder() elseif self.list then self:renderAuctions() end
  self:renderDetail()
end

local function color(cell, c)
  if c then cell:SetTextColor(c[1], c[2], c[3]) else cell:SetTextColor(1, 1, 1) end
end

function ItemView:clampOffset(total, rows)
  self.offset = math.max(0, math.min(self.offset, math.max(0, total - #rows)))
  ns.Window.syncScrollBar(rows.scrollBar, self.offset, total)
end

function ItemView:renderAuctions()
  local list, rows = self.rows or {}, self.itemRows
  self:clampOffset(#list, rows)
  for r, cells in ipairs(rows) do
    local a = list[r + self.offset]
    if a then
      cells[1]:SetText(a.buyout and money(a.buyout) or "no buyout")
      cells[2]:SetText(money(a.bid or a.minBid))
      cells[3]:SetText(ns.Buying.timeLeftText(a.timeLeft))
      cells[4]:SetText(a.own and "You" or (a.seller or "?"))
      cells[5]:SetText(a.percent and (a.percent .. "%") or "-")
      local tint = a.own and ItemView.GREY or nil
      for c = 1, 5 do color(cells[c], tint) end
      if a.winning then color(cells[2], ItemView.GOLD) end
      if not a.own then color(cells[5], ns.BrowseView.TONES[ns.Browse.tone(a.percent)]) end
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(a ~= nil and a == self.selected)
  end
end

function ItemView:renderLadder()
  local ladder, rows = self.ladder or { rows = {} }, self.commodityRows
  self:clampOffset(#ladder.rows, rows)
  for r, cells in ipairs(rows) do
    local l = ladder.rows[r + self.offset]
    if l then
      cells[1]:SetText(money(l.unit))
      cells[2]:SetText(l.take > 0 and l.take < l.count and string.format("%d (%d of them)", l.count, l.take)
        or tostring(l.count))
      cells[3]:SetText(string.format("%d for %s", l.running, money(l.runningTotal)))
      cells[4]:SetText(l.percent and (l.percent .. "%") or "-")
      color(cells[4], ns.BrowseView.TONES[ns.Browse.tone(l.percent)])
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    -- Shaded: the rows the quantity buys from.
    cells.button.selectedTexture:SetShown(l ~= nil and l.take > 0)
  end
end

-- The detail panel: what is selected, and the controls to buy it.
function ItemView:renderDetail()
  local w, api = self.window, self:api()
  local commodity = self.list and self.list.commodity
  showAll(self.itemControls, self.list ~= nil and not commodity)
  showAll(self.commodityControls, commodity == true)
  self.goldText:Show()
  self.messageText:Show()
  local have = api and api:money()
  self.goldText:SetText("Your gold: " .. money(have))
  self.messageText:SetText(self.message or "")
  if not self.list then
    w.detailTitle:SetText(self.row.name or "")
    w.detailBody:SetText(self.loadJob and "Looking up its auctions..." or "")
    return
  end
  if commodity then return self:renderCommodityDetail(have) end
  local a = self.selected
  local c = self.itemControls
  if not a then
    w.detailTitle:SetText("Select an auction")
    w.detailBody:SetText("Click an auction on the left to buy it out or bid on it.")
  else
    w.detailTitle:SetText("Selected auction")
    local lines = {
      (a.own and "Yours" or ("Seller: " .. (a.seller or "?"))) .. ", " .. ns.Buying.timeLeftText(a.timeLeft) .. " left",
      "Buyout: " .. (a.buyout and money(a.buyout) or "none"),
      "Current bid: " .. (a.bid and money(a.bid) or "none") .. (a.winning and " (yours)" or ""),
      "Lowest you can bid: " .. money(a.minBid),
    }
    w.detailBody:SetText(table.concat(lines, "\n"))
  end
  c.buy:SetText(a and a.buyout and ("Buy out for " .. money(a.buyout)) or "Buy out")
  local canBuy = ns.Buying.canBuyout(a, have)
  local canBid = ns.Buying.canBid(a, self:bidAmount(), have)
  if canBuy and not self.busy then c.buy:Enable() else c.buy:Disable() end
  if canBid and not self.busy then c.bid:Enable() else c.bid:Disable() end
end

function ItemView:renderCommodityDetail(have)
  local w, c, ladder, q = self.window, self.commodityControls, self.ladder, self.quoted
  w.detailTitle:SetText("Buy " .. (self.row.name or "it"))
  local lines = {}
  if ladder and ladder.quantity > 0 then
    lines[#lines + 1] = "Price each: " .. money(ladder.average) .. " on average"
    lines[#lines + 1] = "Total: " .. money(ladder.total)
    if ladder.quantity < self:quantity() then
      lines[#lines + 1] = string.format("Only %d are for sale.", ladder.quantity)
    end
  elseif ladder and self:quantity() > 0 then
    lines[#lines + 1] = "None for sale by others."
  else
    lines[#lines + 1] = "Type how many, or click a row on the left."
  end
  w.detailBody:SetText(table.concat(lines, "\n"))
  c.buy:SetText(ladder and ladder.quantity > 0
    and string.format("Buy %d for %s", ladder.quantity, money(ladder.total)) or "Buy")
  local affordable = ladder and ladder.quantity > 0 and not (have and ladder.total > have)
  if affordable and not self.busy and not q then c.buy:Enable() else c.buy:Disable() end
  if self.busy then c.max:Disable() else c.max:Enable() end
  c.confirm:SetShown(q ~= nil)
  c.cancel:SetShown(q ~= nil)
  c.confirmText:SetShown(q ~= nil)
  if q then
    local each = money(math.floor(q.total / q.quantity + 0.5))
    if q.change == "up" then
      c.confirmText:SetText(string.format("The price went up: %d now cost %s (%s each).", q.quantity,
        money(q.total), each))
    else
      c.confirmText:SetText(string.format("%d for %s (%s each).", q.quantity, money(q.total), each))
    end
    c.confirm:SetText("Buy for " .. money(q.total))
  end
end

ns.BrowseItemView = ItemView
return ItemView
