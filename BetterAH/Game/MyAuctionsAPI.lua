-- My auctions API (#123): the only module that reads the player's own auctions in full and cancels them.
-- Thin on purpose; the rules live in Core/MyAuctions.lua. Checked in game; specs use spec/fake_client.lua.
--
-- Forever's C_AuctionHouse (AuctionHouseDocumentation on the forever branch of wow-ui-source):
-- QueryOwnedAuctions asks for the list, OWNED_AUCTIONS_UPDATED says it came, GetOwnedAuctionInfo(i)
-- reads one (auctionID, itemKey, itemLink, status, quantity, timeLeftSeconds, timeLeft, bidAmount,
-- buyoutAmount, bidder). CancelAuction(auctionID) needs a hardware event, so cancel() must run inside a
-- click; AUCTION_CANCELED(auctionID) follows. GetCancelCost(auctionID) is what cancelling costs.
-- An active auction's buyoutAmount is the price per unit and a sold one's the whole sale (see readOwned);
-- /bah selftest prints the raw numbers of the first auction.
local _, ns = ...
ns = ns or {}

local MyAuctionsAPI = {}
MyAuctionsAPI.__index = MyAuctionsAPI

MyAuctionsAPI.SOLD = 1 -- Enum.AuctionStatus.Sold
MyAuctionsAPI.TIMEOUT = 10
MyAuctionsAPI.EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED",
  "ITEM_KEY_ITEM_INFO_RECEIVED", "GET_ITEM_INFO_RECEIVED" }

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- The name and colour code in an item link ("|cff1eff00|Hitem:...|h[Name]|h|r"), or nil.
function MyAuctionsAPI.linkParts(link)
  if type(link) ~= "string" then return nil end
  return link:match("|h%[(.-)%]|h"), link:match("^|c(%x%x%x%x%x%x%x%x)")
end

-- The key one price check covers: the same item, level and suffix.
function MyAuctionsAPI.checkKey(itemKey)
  return string.format("%d:%d:%d", itemKey.itemID or 0, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
end

-- Item quality colours (Enum.ItemQuality 0-5), for names that come without a link.
MyAuctionsAPI.QUALITY = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }

-- The player's auctions as Core/MyAuctions auctions, plus whether the client has the whole list.
-- nameOf(item) names an auction whose link carries no name. Item ids still without a name are added to
-- missing, when given. Returns nil when the client can't say.
--
-- In game (#123, Forever 2026-11-26): an active auction's buyoutAmount is per unit, but a sold one's is the
-- whole sale (2 sold at 14s 44c each read 28s 88c), so a sold auction's unit is its buyout / quantity.
-- A partly sold commodity auction shows as the active rest plus a sold row per sale, all with the same
-- auctionID, so uid (not id) tells rows apart.
function MyAuctionsAPI.readOwned(env, nameOf, missing)
  local ah = env.C_AuctionHouse
  if not (ah and ah.GetNumOwnedAuctions and ah.GetOwnedAuctionInfo) then return nil end
  local out, seen = {}, {}
  for i = 1, try(ah.GetNumOwnedAuctions) or 0 do
    local info = try(ah.GetOwnedAuctionInfo, i)
    local key = type(info) == "table" and type(info.itemKey) == "table" and info.itemKey
    if key and key.itemID then
      local item = "i:" .. key.itemID
      local name, color = MyAuctionsAPI.linkParts(info.itemLink)
      if not name then
        local keyInfo = try(ah.GetItemKeyInfo, key)
        if type(keyInfo) == "table" then
          name = keyInfo.itemName ~= "" and keyInfo.itemName or nil
          color = color or (name and MyAuctionsAPI.QUALITY[keyInfo.quality])
        end
      end
      name = name or (nameOf and nameOf(item))
      if not name and missing then missing[key.itemID] = true end
      local quantity = math.max(1, tonumber(info.quantity) or 1)
      local sold = info.status == MyAuctionsAPI.SOLD
      local buyout = tonumber(info.buyoutAmount)
      if not (buyout and buyout > 0) then buyout = nil end
      -- The active part keeps the bare id; sold parts count up per id, so a new sale shifts only sold rows,
      -- which have no action, and never lands a selection on something that can be cancelled.
      local id = info.auctionID
      local uid = id
      if sold or id == nil then
        local n = (seen[tostring(id)] or 0) + 1
        seen[tostring(id)] = n
        uid = tostring(id) .. "#sold" .. n
      end
      out[#out + 1] = {
        id = id, uid = uid, item = item, itemID = key.itemID, itemKey = key, key = MyAuctionsAPI.checkKey(key),
        name = name, color = color, link = info.itemLink, quantity = quantity,
        unit = buyout and (sold and buyout / quantity or buyout) or nil, total = sold and buyout or nil,
        bid = tonumber(info.bidAmount), bidder = info.bidder ~= nil and info.bidder ~= false and info.bidder ~= "",
        sold = sold, timeLeft = tonumber(info.timeLeftSeconds), band = info.timeLeft,
      }
    end
  end
  local complete = not ah.HasFullOwnedAuctionResults or try(ah.HasFullOwnedAuctionResults) ~= false
  return out, complete
end

-- readOwned() for this client, asking it to load the items that have no name yet; onChange follows when one
-- loads (ITEM_KEY_ITEM_INFO_RECEIVED or GET_ITEM_INFO_RECEIVED).
function MyAuctionsAPI:read(nameOf)
  local missing = {}
  local auctions, complete = MyAuctionsAPI.readOwned(self.env, nameOf, missing)
  -- Each item is asked for once per visit (asked), so one that never loads isn't asked for over and over.
  self.waiting, self.asked = self.waiting or {}, self.asked or {}
  local items = self.env.C_Item
  for id in pairs(missing) do
    if not self.asked[id] then
      self.asked[id], self.waiting[id] = true, true
      if items and type(items.RequestLoadItemDataByID) == "function" then
        try(items.RequestLoadItemDataByID, id)
      else
        try(self.env.GetItemInfo, id)
      end
    end
  end
  return auctions, complete
end

function MyAuctionsAPI.new(env)
  local self = setmetatable({ env = env, open = false, cancelling = {} }, MyAuctionsAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  for _, e in ipairs(MyAuctionsAPI.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
  return self
end

-- Asks the client for the player's auctions again; onChange follows with OWNED_AUCTIONS_UPDATED. The
-- character tracker already asks on opening the auction house and after each cancel or post; while it is
-- installed, this asks nothing, so the throttled query pipe isn't used twice.
function MyAuctionsAPI:query()
  local ah = self.env.C_AuctionHouse
  if self.addon and self.addon.tracker then return end
  if self.open and ah and ah.QueryOwnedAuctions then try(ah.QueryOwnedAuctions, {}) end
end

function MyAuctionsAPI:cancelCost(id)
  local ah = self.env.C_AuctionHouse
  return ah and tonumber(try(ah.GetCancelCost, id)) or nil
end

-- Whether the client lets this auction be cancelled (true when it can't say).
function MyAuctionsAPI:canCancel(id)
  local ah = self.env.C_AuctionHouse
  if not (ah and type(ah.CanCancelAuction) == "function") then return true end
  return try(ah.CanCancelAuction, id) ~= false
end

-- Cancels one auction. Must run inside a click (hardware event). Returns true when it was sent, or
-- false and a reason. done(ok, reason) follows: on AUCTION_CANCELED, or after TIMEOUT seconds.
function MyAuctionsAPI:cancel(id, done)
  local ah = self.env.C_AuctionHouse
  if not self.open then return false, "the auction house is closed" end
  if not (ah and type(ah.CancelAuction) == "function") then return false, "C_AuctionHouse.CancelAuction is missing" end
  if self.cancelling[id] then return false, "already being cancelled" end
  if not self:canCancel(id) then return false, "the game won't let this auction be cancelled" end
  local ok, err = pcall(ah.CancelAuction, id)
  if not ok then return false, "cancel failed: " .. tostring(err) end
  self.sent = (self.sent or 0) + 1
  local job = { done = done, order = self.sent }
  self.cancelling[id] = job
  local timer = self.env.C_Timer
  if timer and timer.After then
    timer.After(MyAuctionsAPI.TIMEOUT, function()
      if self.cancelling[id] == job then self:finish(id, false, "no answer from the auction house") end
    end)
  end
  return true
end

function MyAuctionsAPI:finish(id, ok, reason)
  local job = self.cancelling[id]
  if not job then return end
  self.cancelling[id] = nil
  if job.done then
    local fine, err = pcall(job.done, ok, reason)
    if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
  end
end

function MyAuctionsAPI:onEvent(event, arg)
  if event == "AUCTION_HOUSE_SHOW" then
    self.open = true
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.open = false
    self.waiting, self.asked = nil, nil
    local waiting = self.cancelling
    self.cancelling = {}
    for _, job in pairs(waiting) do
      if job.done then pcall(job.done, false, "the auction house closed") end
    end
  elseif event == "AUCTION_CANCELED" then
    -- Without an id, the oldest cancel still waiting is the one. An id that isn't ours (a late answer
    -- after a timeout, or a cancel from Blizzard's window) finishes nothing.
    local id = arg
    if id == nil then
      local oldest
      for waiting, job in pairs(self.cancelling) do
        if not oldest or job.order < oldest then id, oldest = waiting, job.order end
      end
    end
    if id ~= nil and self.cancelling[id] then self:finish(id, true) end
    self:query()
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED" then
    -- A name we asked for: redraw once for a burst of them.
    if not (self.waiting and self.waiting[arg]) then return end
    self.waiting[arg] = nil
    if self.redraw or not (self.open and self.onChange) then return end
    self.redraw = true
    local timer = self.env.C_Timer
    if not (timer and timer.After) then self.redraw = nil return self.onChange() end
    timer.After(0, function()
      self.redraw = nil
      if self.open and self.onChange then self.onChange() end
    end)
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    if self.open and self.onChange then self.onChange() end
  end
end

function MyAuctionsAPI.install(env, addon)
  local api = MyAuctionsAPI.new(env)
  addon.myAuctionsAPI = api
  api.addon = addon -- query() asks addon.tracker, which may be installed after this
  if addon.Probes then
    addon.Probes.suite():add("My auctions", function()
      local ah = env.C_AuctionHouse or {}
      local missing = {}
      for _, name in ipairs({ "QueryOwnedAuctions", "GetNumOwnedAuctions", "GetOwnedAuctionInfo", "CancelAuction",
        "GetCancelCost" }) do
        if type(ah[name]) ~= "function" then missing[#missing + 1] = "C_AuctionHouse." .. name end
      end
      if #missing > 0 then return "fail", "missing: " .. table.concat(missing, ", ") end
      local n = try(ah.GetNumOwnedAuctions) or 0
      local first = n > 0 and try(ah.GetOwnedAuctionInfo, 1)
      if type(first) ~= "table" then
        return "info", string.format("%d auctions known (open the auction house to read them)", n)
      end
      return "info", string.format("%d auctions; the first: quantity %s, buyoutAmount %s, bidAmount %s, status %s, "
        .. "timeLeftSeconds %s", n, tostring(first.quantity), tostring(first.buyoutAmount), tostring(first.bidAmount),
        tostring(first.status), tostring(first.timeLeftSeconds))
    end)
  end
  return api
end

ns.MyAuctionsAPI = MyAuctionsAPI
if CreateFrame then MyAuctionsAPI.install(_G, ns) end
return MyAuctionsAPI
