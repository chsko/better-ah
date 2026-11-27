-- The My bids view (#95): every auction this character has bid on, whether the bid is still the highest,
-- and a bid again or buy out for each. Its own entry under Buy. Layout follows artboard 8 of the Browse
-- mockup linked from #90 (approved by Christian, 2026-11-27). This file only draws and wires; the rules live
-- in Core/MyBids.lua, reading the bids in Game/MyBidsAPI.lua, bidding and buying out in Game/BrowseAPI.lua.
local _, ns = ...
ns = ns or {}

local MyBidsView = {}
MyBidsView.__index = MyBidsView

MyBidsView.COLUMNS = {
  { "Item", 4, 196 }, { "Your bid", 204, 80 }, { "Status", 292, 70, "LEFT" }, { "Time left", 366, 74 },
  { "Buyout", 444, 74 },
}
MyBidsView.TOP = 26
MyBidsView.ROWS = 14
-- Outbid in orange, highest in light blue: they differ in lightness too, as My auctions' colours do.
MyBidsView.COLORS = { outbid = "ffff9a3c", highest = "ff8fd0ff", dim = "ff9d9d9d" }
MyBidsView.HINT = "If someone outbids you, your gold comes back by mail. Win or lose, the item or gold "
  .. "arrives by mail."

local function color(code, text) return "|c" .. code .. text .. "|r" end
local function money(c) return ns.Money.format(c) end

function MyBidsView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, offset = 0, session = {} }, MyBidsView)
end

function MyBidsView.itemText(b)
  local name = b.name or b.item
  return b.color and ("|c" .. b.color .. name .. "|r") or name
end

function MyBidsView.statusText(row)
  local c = MyBidsView.COLORS
  if row.status == "highest" then return color(c.highest, "Highest") end
  return color(c.outbid, "Outbid")
end

-- The detail text for one row; value = the item's market value or nil.
function MyBidsView.detailText(row, value)
  local b, lines = row.bid, {}
  local function add(text) lines[#lines + 1] = text end
  add("Your bid: " .. (row.yours and money(row.yours) or "not known (bid before Better AH saw it)"))
  if b.bid then
    add("Current bid: " .. money(b.bid) .. (row.status == "highest" and " (yours)" or " (not yours)"))
  end
  if row.status ~= "highest" and b.minBid then add("Lowest new bid: " .. money(b.minBid)) end
  add("Buyout: " .. (b.buyout and money(b.buyout) or "none"))
  add("Market value: " .. (value and money(value) or "none yet"))
  add("Time left: " .. ns.MyBids.timeLeft(b.band))
  add("")
  if row.status == "highest" then
    add("You're the highest bidder. If nobody bids more before it ends, it's yours.")
  else
    add("Someone outbid you. Bid again to get back on top.")
  end
  add(MyBidsView.HINT)
  return table.concat(lines, "\n")
end

-- The detail text with nothing selected. t is MyBids.totals.
function MyBidsView.totalsText(t)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add("Click a bid to bid again or buy it out.")
  add("")
  add(string.format("Bids: %d", t.count))
  add(string.format("Highest bidder on: %d", t.highest))
  add(string.format("Outbid on: %d", t.outbid))
  add("Tied up in bids: " .. money(t.tiedUp))
  add("")
  add(MyBidsView.HINT)
  return table.concat(lines, "\n")
end

local function button(env, parent, text, height)
  local b = env.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetHeight(height or 22)
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

function MyBidsView:build(f, x, y, width, height)
  local env, w = self.env, self.window
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.panel = panel

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
  title:SetText("Auctions you have bid on")
  self.title = title
  local refresh = button(env, panel, "Refresh", 20)
  refresh:SetWidth(90)
  refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, 0)
  refresh:SetScript("OnClick", function() self:query() end)
  ns.Window.tooltip(env, refresh, "Refresh", "Ask the auction house for your bids again.")
  self.refreshButton = refresh

  local list = env.CreateFrame("Frame", nil, panel)
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -MyBidsView.TOP)
  list:SetSize(width, height - MyBidsView.TOP)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.list = list
  local status = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6)
  status:SetWidth(width)
  status:SetJustifyH("LEFT")
  self.status = status
  self.loading = ns.Loading.attach(env, list, status, { "TOPLEFT", list, "TOPLEFT", 0, -6, width })
  self.rows = w:buildRows(list, MyBidsView.COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:render() end)

  local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 4)
  footer:SetWidth(width - 24)
  footer:SetJustifyH("LEFT")
  self.footer = footer

  self:buildControls()

  local api = self.addon.myBidsAPI
  if api then
    api.onChange = function(answered) if self.visit then self:refresh(answered) end end
    -- A new bid (ours from Blizzard's window, or one this view sent): ask for the list again.
    api.onAdded = function() if self.visit and not self.asking then self:query() end end
    api.onTimeout = function()
      if not self.visit then return end
      self.asking = nil
      self:say("The auction house didn't answer. Click Refresh to try again.")
    end
  end
  return panel
end

-- On the shared detail panel, so shown only while this view is: the new bid boxes, Bid again, Buy out.
function MyBidsView:buildControls()
  local env, layer = self.env, self.window.detailLayer
  local c = {}
  local buy = button(env, layer, "Buy out", 26)
  buy:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 12)
  buy:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 12)
  buy:SetScript("OnClick", function() self:buyout() end)
  ns.Window.tooltip(env, buy, "Buy out", "Buy this auction now, at its buyout price. Your bid comes back by mail.")
  c.buy = buy
  local bid = button(env, layer, "Bid again")
  bid:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 46)
  bid:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -12, 46)
  bid:SetScript("OnClick", function() self:bidAgain() end)
  ns.Window.tooltip(env, bid, "Bid again", "Bid the amount in the boxes. It starts at the lowest new bid the "
    .. "auction house takes.")
  c.bid = bid
  local boxes, xAt = {}, 14
  for i, unit in ipairs({ "g", "s", "c" }) do
    local box = input(env, layer, i == 1 and 52 or 26, i == 1 and 6 or 2)
    box:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", xAt, 76)
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged", function() if not self.filling then self:renderControls() end end)
    local text = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(unit)
    boxes[i], c["unit" .. i] = box, text
    xAt = xAt + (i == 1 and 52 or 26) + 18
  end
  c.boxes = boxes
  local label = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 100)
  label:SetText("New bid")
  c.label = label
  -- What the last bid or buy did, above the controls.
  local note = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 12, 118)
  note:SetWidth(ns.Window.DETAIL - 24)
  note:SetJustifyH("LEFT")
  c.note = note
  self.controls = c
  self:showControls(false)
end

function MyBidsView:showControls(on)
  local c = self.controls
  if not c then return end
  for _, part in ipairs({ c.buy, c.bid, c.label, c.unit1, c.unit2, c.unit3, c.boxes[1], c.boxes[2], c.boxes[3] }) do
    part:SetShown(on)
  end
  c.note:SetShown(self.message ~= nil and self.window.model.view == "bids")
end

function MyBidsView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

function MyBidsView:marketValue(item)
  local prices = self.addon.prices
  local key = ns.AuctionAPI and ns.AuctionAPI.currentMarket(self.env) or nil
  return prices and key and prices:marketValue(key, item, self:now()) or nil
end

-- This character's store of bids, kept by Game/MyBidsAPI.lua (a table for the session without it).
function MyBidsView:store()
  local api = self.addon.myBidsAPI
  return api and api:store() or self.session
end

function MyBidsView:me()
  local api = self.addon.myBidsAPI
  return api and api:me() or nil
end

-- Called whenever the view is shown: the first showing of each auction house visit asks for the bids.
function MyBidsView:show()
  if not self.visit then
    self.visit = {}
    self.selected, self.offset, self.message = nil, 0, nil
    self:query()
  end
  self:render()
end

-- The auction house closed: the next visit starts afresh.
function MyBidsView:reset()
  self.visit, self.bids, self.complete, self.selected, self.message, self.sending = nil, nil, nil, nil, nil, nil
  self.checkedAt, self.asking = nil, nil
  self:hide()
  self.window:setBadge("bids", 0)
end

function MyBidsView:hide()
  self:showControls(false)
end

-- Asks for the bids again, naming every auction this character has bid on.
function MyBidsView:query()
  local api = self.addon.myBidsAPI
  if not api then return end
  if not api.open then
    self.message = "Open the auction house to see your bids."
    return self:render()
  end
  local sent, why = api:query(ns.MyBids.ids(self:store()))
  self.asking = sent or nil
  if why == "busy" then self.message = "The auction house is still answering a search. Click Refresh in a moment." end
  self:render()
end

-- The list came (answered: it answers our query).
function MyBidsView:refresh(answered)
  local api = self.addon.myBidsAPI
  local auctionAPI = self.addon.auctionAPI
  local nameOf = auctionAPI and function(item) return auctionAPI:itemName(item) end
  local bids, complete = api:read(nameOf)
  self.bids, self.complete = bids or {}, bids ~= nil and complete
  if answered then
    self.asking = nil
    self.checkedAt = self:now()
  end
  ns.MyBids.update(self:store(), self.bids, self:me(), self:now(), answered and self.complete)
  self:render()
  self:fillBoxes()
end

function MyBidsView:rowsNow()
  return ns.MyBids.rows(self.bids or {}, self:store(), self:me())
end

function MyBidsView:selectedRow(rows)
  for _, r in ipairs(rows or self:rowsNow()) do
    if r.bid.id == self.selected then return r end
  end
  return nil
end

function MyBidsView:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function MyBidsView:selectRow(r)
  local row = self.shown and self.shown[r + self.offset]
  if not row then return end
  if self.selected ~= row.bid.id then self.message = nil end
  self.selected = row.bid.id
  self.filledFor = nil
  self:render()
  self:fillBoxes()
end

-- Puts the lowest new bid in the boxes, once per selection and again when it changes (someone bid more).
function MyBidsView:fillBoxes()
  local row = self:selectedRow()
  local c = self.controls
  if not (row and c) then return end
  local min = row.bid.minBid or 0
  local mark = tostring(row.bid.id) .. ":" .. min
  if self.filledFor == mark then return end
  self.filledFor = mark
  local g, s, cp = ns.Buying.split(min)
  self.filling = true
  c.boxes[1]:SetText(g > 0 and tostring(g) or "")
  c.boxes[2]:SetText((g > 0 or s > 0) and tostring(s) or "")
  c.boxes[3]:SetText(tostring(cp))
  self.filling = nil
  self:renderControls()
end

function MyBidsView:amount()
  local b = self.controls.boxes
  return ns.Buying.money(b[1]:GetText(), b[2]:GetText(), b[3]:GetText())
end

-- Sends first and redraws after: a redraw before PlaceBid got it blocked in game (#120, #130).
function MyBidsView:sendThenDraw(text, send)
  self.message = text
  send()
  self:render()
end

function MyBidsView:say(text)
  self.message = text
  self:render()
end

function MyBidsView:bidAgain()
  local api, row = self.addon.browseAPI, self:selectedRow()
  if not row then return self:say("Select a bid.") end
  local amount = self:amount()
  local ok, why = ns.Buying.canBid(ns.MyBids.buyRow(row), amount, api and api:money())
  if not ok then return self:say(why) end
  if not api then return self:say("Bidding isn't available.") end
  local b, visit, token = row.bid, self.visit, {}
  local name = b.name or b.item
  self.sending = token
  self:sendThenDraw("Bidding...", function() api:bid(b.id, amount, function(placed, reason)
    if placed and self.addon.myBidsAPI then self.addon.myBidsAPI:placed(b.id, amount) end
    if self.visit ~= visit or self.sending ~= token then return end
    self.sending = nil
    if placed then
      self.message = string.format("Bid %s sent on %s.", money(amount), name)
      if self.asking then self:render() else self:query() end
    else
      self:say("Bid not placed: " .. tostring(reason) .. ".")
    end
  end) end)
end

function MyBidsView:buyout()
  local api, row = self.addon.browseAPI, self:selectedRow()
  if not row then return self:say("Select a bid.") end
  local ok, why = ns.Buying.canBuyout(ns.MyBids.buyRow(row), api and api:money())
  if not ok then return self:say(why) end
  if not api then return self:say("Buying isn't available.") end
  local b, visit, token = row.bid, self.visit, {}
  local name, price = b.name or b.item, b.buyout
  self.sending = token
  self:sendThenDraw("Buying...", function() api:buyout(b.id, price, function(bought, reason, kind)
    if bought then
      ns.MyBids.forget(self:store(), b.id)
      local purchases, ledger = self.addon.purchases, self.addon.ledgerAPI
      if purchases then purchases:bought(b.itemID, b.link, 1, price, self:now()) end
      if ledger then ledger:bought(b.itemID, b.name, 1, price, "My bids") end
    end
    if self.visit ~= visit or self.sending ~= token then return end
    self.sending = nil
    if bought then
      self.message = string.format("Bought %s for %s. It comes by mail.", name, money(price))
      self.selected = nil
      if self.asking then self:render() else self:query() end
    elseif kind == "unknown" then
      self:say("No answer from the auction house yet. It may have gone through: check your mail before buying again.")
    else
      self:say("Not bought: " .. tostring(reason) .. ".")
    end
  end, "My bids") end)
end

function MyBidsView:statusLine(rows)
  local api = self.addon.myBidsAPI
  if not (api and api.open) then return "Open the auction house to see your bids." end
  if not self.bids then return "Reading your bids..." end
  if #rows == 0 then return "You have no bids on this character." end
  if self.asking then return "Checking your bids..." end
  return ""
end

function MyBidsView:render()
  if not self.panel then return end
  local rows = self:rowsNow()
  self.shown = rows
  local api = self.addon.myBidsAPI
  local open = api and api.open
  if open and not self.asking then self.refreshButton:Enable() else self.refreshButton:Disable() end
  self.status:SetText(self:statusLine(rows))
  if open and (self.asking or not self.bids) then self.loading:spin() else self.loading:clear() end

  local visible = MyBidsView.ROWS
  self.offset = math.max(0, math.min(self.offset, math.max(0, #rows - visible)))
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #rows)
  for r, cells in ipairs(self.rows) do
    local row = rows[r + self.offset]
    if row then
      local b = row.bid
      cells[1]:SetText(MyBidsView.itemText(b))
      cells[2]:SetText(row.yours and money(row.yours) or "-")
      cells[3]:SetText(MyBidsView.statusText(row))
      cells[4]:SetText(ns.MyBids.timeLeft(b.band))
      cells[5]:SetText(b.buyout and money(b.buyout) or "none")
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.bid.id == self.selected)
  end

  local totals = ns.MyBids.totals(rows)
  if #rows > 0 then
    local text = string.format("%d %s · highest on %d · %s tied up in bids", totals.count,
      totals.count == 1 and "bid" or "bids", totals.highest, money(totals.tiedUp))
    if self.checkedAt then text = text .. " · checked " .. ns.Time.ago(self.checkedAt, self:now()) end
    self.footer:SetText(text)
  else
    self.footer:SetText("")
  end
  self.window:setBadge("bids", totals.outbid)
  if self.window.model.view == "bids" then self:renderDetail(rows, totals) end
end

function MyBidsView:renderDetail(rows, totals)
  local w = self.window
  local row = self:selectedRow(rows)
  if not row then self.selected = nil end
  if row then
    w.detailTitle:SetText(MyBidsView.itemText(row.bid))
    w.detailBody:SetText(MyBidsView.detailText(row, self:marketValue(row.bid.item)))
  else
    w.detailTitle:SetText(#rows > 0 and "Your bids on this character" or "")
    w.detailBody:SetText(#rows > 0 and MyBidsView.totalsText(totals) or "")
  end
  self:showControls(row ~= nil)
  self:renderControls(row)
end

function MyBidsView:renderControls(row)
  local c = self.controls
  if not c then return end
  row = row or self:selectedRow()
  c.note:SetText(self.message or "")
  c.note:SetShown(self.message ~= nil and self.window.model.view == "bids")
  if not row then return end
  local api = self.addon.browseAPI
  local open = self.addon.myBidsAPI and self.addon.myBidsAPI.open
  local have = api and api:money()
  local busy = self.sending ~= nil or not open
  local buyRow = ns.MyBids.buyRow(row)
  c.bid:SetText(row.status == "highest" and "You're the highest bidder" or "Bid again")
  -- Enabled unless there is nothing to do: a click on a bid that can't go says why (too low, not enough gold).
  c.bid:SetEnabled(not busy and not buyRow.winning)
  c.buy:SetText(row.bid.buyout and ("Buy out for " .. money(row.bid.buyout)) or "No buyout")
  c.buy:SetEnabled(not busy and buyRow.buyout ~= nil and (not have or buyRow.buyout <= have))
end

ns.MyBidsView = MyBidsView
return MyBidsView
