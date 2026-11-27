-- Ledger adapter (#137): feeds the Ledger (Core/Ledger.lua) from the game. Nothing here decides what counts;
-- it only reads.
--
--   Sales and buys from elsewhere: auction mail invoices (GetInboxInvoiceInfo), once their gold or item is
--     taken (TakeInboxMoney, TakeInboxItem, AutoLootMailItem: hooked, so the game's mail frame and other mail
--     addons count too). The inbox is read on each MAIL_INBOX_UPDATE, before anything is taken, because a
--     taken mail may no longer say what it held; a take counts once the next read shows it done.
--   Deposits: C_AuctionHouse.PostItem / PostCommodity and their Confirm calls (hooked, so posts from the
--     game's own sell frame count too), with the deposit worked out at the call; it counts once
--     AUCTION_HOUSE_AUCTION_CREATED says the auction is up. AUCTION_HOUSE_POST_ERROR drops the post it is
--     about, and a Post that AUCTION_HOUSE_POST_WARNING held for a Confirm waits aside until it is confirmed,
--     so neither shifts later deposits onto the wrong post.
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
LedgerAPI.TAKE_WAIT = 120 -- seconds a take from the mail waits for the inbox to show it done
LedgerAPI.WARN_GAP = 2 -- seconds between a Post and the POST_WARNING that holds it for a Confirm
LedgerAPI.EVENTS = { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_POST_WARNING", "PLAYER_ENTERING_WORLD" }

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
  return setmetatable({ env = env, addon = addon, inbox = {}, posts = {}, pending = {} }, LedgerAPI)
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

-- One mail as the inbox shows it: { invoice = type, name, money, bid, buyout, deposit, cut, count, hasItem,
-- ident }, or nil for a mail that isn't an auction invoice. ident tells mails apart by what they are, not by
-- what is still in them, so a mail is the same mail after its gold or item is taken.
function LedgerAPI.readMail(env, index)
  local _, _, sender, subject, money, _, _, hasItem = try(env.GetInboxHeaderInfo, index)
  local kind, name, _, bid, buyout, deposit, cut, _, _, _, count = try(env.GetInboxInvoiceInfo, index)
  if kind ~= "seller" and kind ~= "buyer" then return nil end
  local m = { invoice = kind, name = name, money = tonumber(money) or 0, bid = tonumber(bid) or 0,
    buyout = tonumber(buyout) or 0, deposit = tonumber(deposit) or 0, cut = tonumber(cut) or 0,
    count = tonumber(count) or 1, hasItem = hasItem and hasItem ~= 0 and true or false }
  m.ident = table.concat({ kind, tostring(name), tostring(sender), tostring(subject), m.bid, m.buyout, m.deposit,
    m.cut, m.count }, "|")
  return m
end

-- What a take of a mail's part takes: "money" for a seller invoice's gold, "item" for a buyer invoice's item,
-- or nil when there is nothing of it left to take.
local function part(m, what)
  if m.invoice == "seller" and what ~= "item" and m.money > 0 then return "money" end
  if m.invoice == "buyer" and what ~= "money" and m.hasItem then return "item" end
  return nil
end

-- Records a take the game has carried out.
function LedgerAPI:record(p)
  local ledger, m = self:ledger(), p.mail
  if not ledger then return end
  if m.invoice == "seller" then
    ledger:sale({ t = p.t, char = p.char, name = m.name, n = m.count, money = m.money, cut = m.cut,
      deposit = m.deposit })
  else
    ledger:buyerInvoice({ t = p.t, char = p.char, name = m.name, n = m.count,
      c = m.bid > 0 and m.bid or m.buyout })
  end
  self.changed = true
end

-- How many mails of each kind (ident and part) still hold their part: the gold of a seller invoice, the item
-- of a buyer invoice.
local function holding(inbox, n)
  local count = {}
  for i = 1, n do
    local m = inbox[i]
    if m then
      local p = part(m, "all")
      if p then
        local k = m.ident .. "|" .. p
        count[k] = (count[k] or 0) + 1
      end
    end
  end
  return count
end

-- Reads the inbox: what each auction invoice holds, and the sale gold still waiting (Ledger:setMail). It is
-- also where a take is confirmed (#150). A take only asks the server; mail addons and the game's Open All ask
-- again for a mail that hasn't gone yet, and a failed take asks for nothing. So a take waits (self.pending)
-- until the inbox shows it done: fewer mails of its kind (same invoice, same part) still hold their part
-- than at the last read, one confirmed take for each, oldest first. Other mails coming and going don't
-- confirm it. fresh = a new visit to the mailbox: what was waiting from the last one is forgotten.
function LedgerAPI:readInbox(fresh)
  local env = self.env
  local n = tonumber((try(env.GetInboxNumItems))) or 0
  local inbox, waiting, mails = {}, 0, 0
  for i = 1, n do
    local m = LedgerAPI.readMail(env, i)
    inbox[i] = m
    if m and m.invoice == "seller" and m.money > 0 then waiting, mails = waiting + m.money, mails + 1 end
  end
  local now = self:now()
  local before = self.holding
  local after = holding(inbox, n)
  if fresh then self.pending, before = {}, nil end
  local still = {}
  for _, p in ipairs(self.pending) do
    local k = p.mail.ident .. "|" .. p.part
    local fewer = before and (before[k] or 0) - (after[k] or 0) or 0
    if fewer > 0 then
      before[k] = before[k] - 1
      self:record(p)
    elseif now - p.t <= LedgerAPI.TAKE_WAIT then
      still[#still + 1] = p -- a take the server never carried out is dropped after a while
    end
  end
  self.pending, self.inbox, self.holding = still, inbox, after
  local ledger = self:ledger()
  if ledger then ledger:setMail(self:char(), waiting, mails, now) end
  if self.changed then
    self.changed = false
    if self.onChange then pcall(self.onChange) end
  end
end

-- A mail's gold or item was asked for: what = "money", "item" or "all". It waits for readInbox to confirm it.
function LedgerAPI:took(index, what)
  -- No read yet this visit: read now. The server hasn't carried the take out yet, so this is the before.
  if not self.holding then self:readInbox() end
  -- The client's list as it is now: another addon may take on MAIL_INBOX_UPDATE before our read of it.
  local m = LedgerAPI.readMail(self.env, index)
  if not m then return end
  local p = part(m, what)
  if not p then return end
  -- Asked again before the inbox changed: still the one take.
  for _, q in ipairs(self.pending) do
    if q.index == index and q.part == p and q.mail.ident == m.ident then return end
  end
  self.pending[#self.pending + 1] = { index = index, part = p, mail = m, t = self:now(), char = self:char() }
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
  -- A post the client wanted confirmed comes twice (Post, then ConfirmPost): it is one auction. Two Posts
  -- are two auctions, even of the same bag slot.
  if call == "ConfirmPost" then
    for i = #self.posts, 1, -1 do
      local p = self.posts[i]
      if p.call == "Post" and p.location == location and p.kind == kind and p.quantity == quantity
        and now - p.t <= LedgerAPI.POST_WAIT then
        p.t, p.call, p.deposit, p.held = now, call, deposit or p.deposit, nil
        return
      end
    end
  end
  local p = { t = now, call = call, kind = kind, location = location, quantity = quantity, item = itemID,
    name = name, deposit = deposit }
  -- The warning can come inside the Post call, before this hook runs.
  if call == "Post" and self.warnedAt and now - self.warnedAt <= LedgerAPI.WARN_GAP then p.held = true end
  self.warnedAt = nil
  self.posts[#self.posts + 1] = p
end

-- AUCTION_HOUSE_POST_WARNING: the newest Post waits for a Confirm, and gets no answer until then.
function LedgerAPI:warned()
  local now, last = self:now(), self.posts[#self.posts]
  if last and last.call == "Post" and now - last.t <= LedgerAPI.WARN_GAP then
    last.held = true
  else
    self.warnedAt = now
  end
end

-- The oldest post still waiting for its answer, taken off the list. Posts waiting longer than POST_WAIT are
-- dropped, and a Post held for a Confirm is not waiting for an answer.
function LedgerAPI:nextAnswered()
  local now, keep = self:now(), {}
  for _, p in ipairs(self.posts) do
    if now - p.t <= LedgerAPI.POST_WAIT then keep[#keep + 1] = p end
  end
  self.posts = keep
  for i, p in ipairs(keep) do
    if not p.held then return table.remove(keep, i) end
  end
  return nil
end

-- AUCTION_HOUSE_AUCTION_CREATED: the oldest post still waiting is up, and its deposit paid.
function LedgerAPI:created()
  local now = self:now()
  local p = self:nextAnswered()
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
  if event == "MAIL_SHOW" then
    self:readInbox(true)
  elseif event == "MAIL_INBOX_UPDATE" then
    self:readInbox()
  elseif event == "MAIL_CLOSED" then
    -- Closed: a list the client clears or shortens now is not mail taken. Waiting takes are dropped.
    self.pending, self.holding = {}, nil
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    self:created()
  elseif event == "AUCTION_HOUSE_POST_ERROR" then
    self:nextAnswered() -- the oldest waiting post failed: no auction, no deposit
  elseif event == "AUCTION_HOUSE_POST_WARNING" then
    self:warned()
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
