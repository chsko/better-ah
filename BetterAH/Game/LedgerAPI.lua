-- Ledger adapter (#137): feeds the Ledger (Core/Ledger.lua) from the game. Nothing here decides what counts;
-- it only reads.
--
--   Sales and buys from elsewhere: auction mail invoices (GetInboxInvoiceInfo), once their gold or item is
--     taken (TakeInboxMoney, TakeInboxItem, AutoLootMailItem: hooked, so the game's mail frame and other mail
--     addons count too). The inbox is read on each MAIL_INBOX_UPDATE, before anything is taken, because a
--     taken mail may no longer say what it held.
--   Deposits: C_AuctionHouse.PostItem / PostCommodity and their Confirm calls (hooked, so posts from the
--     game's own sell frame count too), with the deposit worked out at the call; it counts once
--     AUCTION_HOUSE_AUCTION_CREATED says the auction is up.
--   Buys made in Better AH (Snipe, Browse): the views call bought() when the game confirms them.
--
-- hooksecurefunc runs after the call and leaves it untouched. Needs the client to check: in game, sell
-- something and take its gold, post one item and one commodity, buy in Snipe and Browse, and buy one
-- item from the game's own auction house frame; each should show in the Ledger view.
local _, ns = ...
ns = ns or {}

local LedgerAPI = {}
LedgerAPI.__index = LedgerAPI

LedgerAPI.POST_WAIT = 60 -- seconds a post waits for AUCTION_HOUSE_AUCTION_CREATED
LedgerAPI.EVENTS = { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_AUCTION_CREATED", "PLAYER_ENTERING_WORLD" }

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
  return nil
end

-- An item's name: the global GetItemInfo, or C_Item.GetItemInfo where a client only has that one.
function LedgerAPI.itemName(env, itemID)
  local get = env.GetItemInfo
  if type(get) ~= "function" then get = env.C_Item and env.C_Item.GetItemInfo end
  return try(get, itemID)
end

function LedgerAPI.new(env, addon)
  return setmetatable({ env = env, addon = addon, inbox = {}, posts = {} }, LedgerAPI)
end

function LedgerAPI:now()
  return try(self.env.GetServerTime) or try(self.env.time) or 0
end

function LedgerAPI:char()
  local tracker = ns.CharacterTracker
  -- The same key as the character records, so the view can name the character. Nil before the game knows it.
  return tracker and tracker.characterKey and tracker.characterKey(self.env) or nil
end

function LedgerAPI:ledger()
  return self.addon.ledger
end

-- One mail as the inbox shows it: { invoice = type, name, money, bid, buyout, deposit, cut, count, key }, or
-- nil for a mail that isn't an auction invoice.
function LedgerAPI.readMail(env, index)
  local _, _, sender, subject, money, _, daysLeft = try(env.GetInboxHeaderInfo, index)
  local kind, name, _, bid, buyout, deposit, cut, _, _, _, count = try(env.GetInboxInvoiceInfo, index)
  if kind ~= "seller" and kind ~= "buyer" then return nil end
  local m = { invoice = kind, name = name, money = tonumber(money) or 0, bid = tonumber(bid) or 0,
    buyout = tonumber(buyout) or 0, deposit = tonumber(deposit) or 0, cut = tonumber(cut) or 0,
    count = tonumber(count) or 1 }
  -- What tells a mail apart from the one at the same place before it, while the inbox doesn't move.
  m.key = table.concat({ kind, tostring(name), tostring(sender), tostring(subject), m.money, m.bid, m.buyout,
    m.count, string.format("%.4f", tonumber(daysLeft) or 0) }, "|")
  return m
end

-- Reads the inbox: what each auction invoice holds, and the sale gold still waiting (Ledger:setMail).
function LedgerAPI:readInbox()
  local env = self.env
  local n = try(env.GetInboxNumItems) or 0
  local inbox, waiting, mails = {}, 0, 0
  -- A mail already taken stays taken while the inbox still holds as many mails and the same one sits at
  -- its place: the server hasn't removed it yet. Once a mail goes, the rest move up and start fresh.
  local before = self.inbox
  local same = self.inboxSize == n
  for i = 1, n do
    local m = LedgerAPI.readMail(env, i)
    if m and same and before[i] and before[i].taken and before[i].key == m.key then m.taken = true end
    inbox[i] = m
    if m and m.invoice == "seller" and m.money > 0 then waiting, mails = waiting + m.money, mails + 1 end
  end
  self.inbox, self.inboxSize = inbox, n
  local ledger = self:ledger()
  if ledger then ledger:setMail(self:char(), waiting, mails, self:now()) end
end

-- A mail's gold or item was taken: records its invoice once. what = "money", "item" or "all".
function LedgerAPI:took(index, what)
  local m = self.inbox[index]
  if not m then
    -- A mail the inbox read hasn't seen: read it now, and keep it so a second take of it counts once.
    m = LedgerAPI.readMail(self.env, index)
    self.inbox[index] = m
  end
  local ledger = self:ledger()
  if not (m and ledger) or m.taken then return end
  if m.invoice == "seller" and what == "item" then return end
  if m.invoice == "buyer" and what == "money" then return end
  m.taken = true
  local now = self:now()
  if m.invoice == "seller" then
    ledger:sale({ t = now, char = self:char(), name = m.name, n = m.count, money = m.money, cut = m.cut,
      deposit = m.deposit })
  else
    ledger:buyerInvoice({ t = now, char = self:char(), name = m.name, n = m.count,
      c = m.bid > 0 and m.bid or m.buyout })
  end
  if self.onChange then pcall(self.onChange) end
end

-- A post was sent: kind = "Item" or "Commodity", with the call's arguments. The deposit is worked out now,
-- while the item is still in the bags.
function LedgerAPI:posted(call, kind, location, duration, quantity)
  local env, ah = self.env, self.env.C_AuctionHouse
  local itemID = try(env.C_Item and env.C_Item.GetItemID, location)
  local deposit
  if kind == "Commodity" then
    deposit = try(ah and ah.CalculateCommodityDeposit, itemID, duration, quantity)
  else
    deposit = try(ah and ah.CalculateItemDeposit, location, duration, quantity)
  end
  local name = try(env.C_Item and env.C_Item.GetItemName, location)
    or (itemID and LedgerAPI.itemName(env, itemID))
  local now = self:now()
  local last = self.posts[#self.posts]
  -- A post the client wanted confirmed comes twice (Post, then ConfirmPost): it is one auction. Two Posts
  -- are two auctions, even of the same bag slot.
  if call == "ConfirmPost" and last and last.call == "Post" and last.location == location and last.kind == kind
    and last.quantity == quantity and now - last.t <= LedgerAPI.POST_WAIT then
    last.t, last.call, last.deposit = now, call, deposit or last.deposit
    return
  end
  self.posts[#self.posts + 1] = { t = now, call = call, kind = kind, location = location, quantity = quantity,
    item = itemID, name = name, deposit = deposit }
end

-- AUCTION_HOUSE_AUCTION_CREATED: the oldest post still waiting is up, and its deposit paid.
function LedgerAPI:created()
  local now = self:now()
  while self.posts[1] and now - self.posts[1].t > LedgerAPI.POST_WAIT do table.remove(self.posts, 1) end
  local p = table.remove(self.posts, 1)
  local ledger = self:ledger()
  if not (p and ledger) then return end
  if p.deposit and p.deposit > 0 then
    ledger:deposit({ t = now, char = self:char(), name = p.name, item = p.item, n = p.quantity, c = p.deposit })
    if self.onChange then pcall(self.onChange) end
  end
end

-- A buy made in Better AH went through: n units of an item for copper in all. src = "Snipe" or "Browse".
function LedgerAPI:bought(itemID, name, n, copper, src)
  local ledger = self:ledger()
  if not ledger then return end
  ledger:buy({ t = self:now(), char = self:char(), name = name or (itemID and LedgerAPI.itemName(self.env, itemID)),
    item = itemID, n = n, c = copper, src = src }, true)
  if self.onChange then pcall(self.onChange) end
end

function LedgerAPI:onEvent(event)
  if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
    self:readInbox()
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    self:created()
  elseif event == "PLAYER_ENTERING_WORLD" then
    local ledger = self:ledger()
    if ledger then ledger:prune(self:now()) end
  end
end

function LedgerAPI:hook()
  local env, hook = self.env, self.env.hooksecurefunc
  if type(hook) ~= "function" then return end
  local function global(name, fn)
    if type(env[name]) == "function" then pcall(hook, name, fn) end
  end
  global("TakeInboxMoney", function(index) self:took(index, "money") end)
  global("TakeInboxItem", function(index) self:took(index, "item") end)
  global("AutoLootMailItem", function(index) self:took(index, "all") end)
  local ah = env.C_AuctionHouse
  if type(ah) ~= "table" then return end
  for _, kind in ipairs({ "Item", "Commodity" }) do
    for _, call in ipairs({ "Post", "ConfirmPost" }) do
      local name = call .. kind
      if type(ah[name]) == "function" then
        pcall(hook, ah, name, function(location, duration, quantity)
          self:posted(call, kind, location, duration, quantity)
        end)
      end
    end
  end
end

function LedgerAPI.install(env, addon)
  local api = LedgerAPI.new(env, addon)
  addon.ledgerAPI = api
  api:hook()
  if type(env.CreateFrame) == "function" then
    local events = env.CreateFrame("Frame")
    for _, e in ipairs(LedgerAPI.EVENTS) do pcall(events.RegisterEvent, events, e) end
    events:SetScript("OnEvent", function(_, event) api:onEvent(event) end)
  end
  if addon.Probes then
    addon.Probes.suite():add("Ledger", function()
      local missing = {}
      for _, name in ipairs({ "GetInboxInvoiceInfo", "GetInboxHeaderInfo", "TakeInboxMoney", "AutoLootMailItem" }) do
        if type(env[name]) ~= "function" then missing[#missing + 1] = name end
      end
      local ah = env.C_AuctionHouse or {}
      for _, name in ipairs({ "CalculateItemDeposit", "CalculateCommodityDeposit" }) do
        if type(ah[name]) ~= "function" then missing[#missing + 1] = "C_AuctionHouse." .. name end
      end
      if #missing > 0 then return "fail", "missing: " .. table.concat(missing, ", ") end
      local entries = addon.ledger and #addon.ledger.store.entries or 0
      return "pass", string.format("mail and deposit functions found; %d entries recorded", entries)
    end)
  end
  return api
end

ns.LedgerAPI = LedgerAPI
if CreateFrame then LedgerAPI.install(_G, ns) end
return LedgerAPI
