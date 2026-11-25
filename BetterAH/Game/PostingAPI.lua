-- Posting API (spec #8): the only module that searches one item's listings and posts auctions.
-- Thin on purpose; the rules live in Core/Posting.lua. Checked in game with /bah selftest; specs use
-- spec/fake_client.lua.
--
-- Searches use C_AuctionHouse.SendSearchQuery (at most 100 a minute, so one item at a time, and only
-- while the throttled message system is ready) and answer with COMMODITY_SEARCH_RESULTS_UPDATED or
-- ITEM_SEARCH_RESULTS_UPDATED. Posting uses PostCommodity or PostItem, which need a hardware event:
-- post() and confirm() must run inside a click. When Post* returns true the client wants the post
-- confirmed (AUCTION_HOUSE_POST_WARNING), which takes a second click: confirm().
local _, ns = ...
ns = ns or {}

local PostingAPI = {}
PostingAPI.__index = PostingAPI

PostingAPI.TIMEOUT = 10
PostingAPI.BAGS = { 0, 1, 2, 3, 4, 5 }
local ITEM, COMMODITY = 1, 2 -- Enum.ItemCommodityStatus; 0 is Unknown (item data not loaded yet)
local PRICE_SORT = { { sortOrder = 0, reverseSort = false } } -- Enum.AuctionHouseSortOrder.Price

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- How many fit in one stack, from C_Item or GetItemInfo's 8th return; nil while the item isn't cached.
local function maxStack(env, id)
  local n = env.C_Item and try(env.C_Item.GetItemMaxStackSizeByID, id)
  if n then return tonumber(n) end
  if type(env.GetItemInfo) ~= "function" then return nil end
  local r = { pcall(env.GetItemInfo, id) }
  return r[1] and tonumber(r[9]) or nil
end

-- The smallest price step the client accepts: 1 copper, or 100 when it has no copper values
-- (C_AuctionHouse.SupportsCopperValues() is false, as on retail). Pass it to Posting.plan.
function PostingAPI.priceStep(env)
  local ah = env.C_AuctionHouse
  if ah and type(ah.SupportsCopperValues) == "function" and try(ah.SupportsCopperValues) == false then
    return 100
  end
  return 1
end

-- The items in the bags that the auction house accepts, sorted by name:
--   { item = "i:id", itemID, name, have, commodity, itemKey, maxStack,
--     slots = { { bag, slot, location, count } } }
-- Locked slots (mid-post or being moved) and items whose commodity status isn't known yet are left out;
-- they show up on the next read. Returns nil and a reason when the client lacks a needed function.
function PostingAPI.readBags(env)
  local container, ah, loc = env.C_Container, env.C_AuctionHouse, env.ItemLocation
  if not (container and container.GetContainerNumSlots and container.GetContainerItemInfo) then
    return nil, "C_Container is missing"
  end
  if not (ah and ah.IsSellItemValid and ah.GetItemKeyFromItem and ah.GetItemCommodityStatus
    and loc and loc.CreateFromBagAndSlot) then
    return nil, "C_AuctionHouse.IsSellItemValid, GetItemKeyFromItem, GetItemCommodityStatus or ItemLocation is missing"
  end
  local byItem, out = {}, {}
  for _, bag in ipairs(PostingAPI.BAGS) do
    for slot = 1, try(container.GetContainerNumSlots, bag) or 0 do
      local info = try(container.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and info.itemID and not info.isBound and not info.isLocked then
        local location = try(loc.CreateFromBagAndSlot, loc, bag, slot)
        local valid = location and try(ah.IsSellItemValid, location, false)
        local status = valid and try(ah.GetItemCommodityStatus, location)
        if status == ITEM or status == COMMODITY then
          local item = "i:" .. info.itemID
          local entry = byItem[item]
          if not entry then
            entry = {
              item = item, itemID = info.itemID, name = info.itemName, have = 0, slots = {},
              commodity = status == COMMODITY, itemKey = try(ah.GetItemKeyFromItem, location),
              maxStack = maxStack(env, info.itemID),
            }
            byItem[item] = entry
            out[#out + 1] = entry
          end
          local count = info.stackCount or 1
          entry.have = entry.have + count
          entry.slots[#entry.slots + 1] = { bag = bag, slot = slot, location = location, count = count }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
    if an ~= bn then return an < bn end
    return a.itemID < b.itemID
  end)
  return out
end

-- The listings the client holds for an item, for Posting.plan: { unit, count, ownCount }, plus
-- whether the client says it has them all.
function PostingAPI.readListings(env, entry)
  local ah, listings = env.C_AuctionHouse, {}
  if entry.commodity then
    for i = 1, try(ah.GetNumCommoditySearchResults, entry.itemID) or 0 do
      local r = try(ah.GetCommoditySearchResultInfo, entry.itemID, i)
      if type(r) == "table" and r.unitPrice then
        listings[#listings + 1] = { unit = r.unitPrice, count = r.quantity or 0, ownCount = r.numOwnerItems or 0 }
      end
    end
    return listings, try(ah.HasFullCommoditySearchResults, entry.itemID) ~= false
  end
  for i = 1, try(ah.GetNumItemSearchResults, entry.itemKey) or 0 do
    local r = try(ah.GetItemSearchResultInfo, entry.itemKey, i)
    if type(r) == "table" and r.buyoutAmount and r.buyoutAmount > 0 then
      -- buyoutAmount is per item (Blizzard's sell frame totals quantity * buyout); a result with
      -- quantity above 1 is that many single auctions at that price.
      local count = math.max(1, r.quantity or 1)
      listings[#listings + 1] = { unit = r.buyoutAmount, count = count,
        ownCount = r.containsOwnerItem and count or 0, auctionID = r.auctionID, link = r.itemLink }
    end
  end
  return listings, try(ah.HasFullItemSearchResults, entry.itemKey) ~= false
end

PostingAPI.EVENTS = {
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_ERROR",
  "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "ITEM_KEY_ITEM_INFO_RECEIVED", "GET_ITEM_INFO_RECEIVED",
}

function PostingAPI.new(env)
  local self = setmetatable({ env = env, queue = {}, open = false }, PostingAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  for _, e in ipairs(PostingAPI.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
  return self
end

function PostingAPI:ready()
  local ah = self.env.C_AuctionHouse
  return not (ah and type(ah.IsThrottledMessageSystemReady) == "function")
    or try(ah.IsThrottledMessageSystemReady) ~= false
end

-- Looks up an item's current listings. done(listings, complete) on an answer, done(nil, reason) when
-- the search can't run or gets no answer in TIMEOUT seconds. Searches run one at a time, in order,
-- and only while the auction house is open.
function PostingAPI:search(entry, done)
  if not self.open then return done(nil, "the auction house is closed") end
  self.queue[#self.queue + 1] = { entry = entry, done = done }
  if not self.active then self:nextSearch() end
end

-- A search entry for an item that isn't in the bags, such as a disenchant material (a commodity).
function PostingAPI.commodityEntry(env, itemID, name)
  local ah = env.C_AuctionHouse
  local itemKey = ah and ah.MakeItemKey and try(ah.MakeItemKey, itemID)
  -- Whether it is a commodity is read from C_AuctionHouse.GetItemKeyInfo just before the search, as
  -- Blizzard's own window does; until then either kind of answer is taken (unsure).
  return { item = "i:" .. itemID, itemID = itemID, name = name, commodity = true, unsure = true, itemKey = itemKey }
end

function PostingAPI:nextSearch()
  if self.active or not self.open then return end
  local job = table.remove(self.queue, 1)
  if not job then return end
  self.active = job
  local ah = self.env.C_AuctionHouse
  if not (ah and ah.SendSearchQuery and job.entry.itemKey) then
    return self:finishSearch(job, nil, "C_AuctionHouse.SendSearchQuery is missing")
  end
  local timer = self.env.C_Timer
  if timer and timer.After then
    timer.After(PostingAPI.TIMEOUT, function()
      if self.active == job then self:finishSearch(job, nil, "no answer from the auction house") end
    end)
  end
  -- Over the throttle the query waits for AUCTION_HOUSE_THROTTLED_SYSTEM_READY.
  if self:ready() then self:prepare(job) end
end

-- An unsure entry needs the item's details in the client before its search: without them the client
-- can't route the search and sends no answer. Blizzard's window only searches keys whose info is
-- loaded (GetItemKeyInfo), and waits for ITEM_KEY_ITEM_INFO_RECEIVED otherwise; so does this.
function PostingAPI:prepare(job)
  local e, ah = job.entry, self.env.C_AuctionHouse
  if e.unsure and type(ah.GetItemKeyInfo) == "function" then
    local info = try(ah.GetItemKeyInfo, e.itemKey)
    if type(info) ~= "table" then
      job.waitingInfo, e.uncached = true, true
      local item = self.env.C_Item
      if not (item and try(item.RequestLoadItemDataByID, e.itemID) ~= nil) then try(self.env.GetItemInfo, e.itemID) end
      return
    end
    job.waitingInfo = nil
    if info.isCommodity ~= nil then e.commodity = info.isCommodity and true or false end
  end
  self:send(job)
end

function PostingAPI:send(job)
  job.sent = true
  local ok, err = pcall(self.env.C_AuctionHouse.SendSearchQuery, job.entry.itemKey, PRICE_SORT, true)
  if not ok then self:finishSearch(job, nil, "search failed: " .. tostring(err)) end
end

function PostingAPI:finishSearch(job, listings, complete)
  if self.active ~= job then return end
  self.active = nil
  -- The next search starts first, so an error in done can't stall the queue.
  self:nextSearch()
  local ok, err = pcall(job.done, listings, complete)
  if not ok and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

function PostingAPI:onEvent(event, arg)
  local job = self.active
  if event == "AUCTION_HOUSE_SHOW" then
    self.open = true
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.open = false
    self.pending = nil
    local waiting = self.queue
    self.queue = {}
    if job then self:finishSearch(job, nil, "the auction house closed") end
    for _, j in ipairs(waiting) do pcall(j.done, nil, "the auction house closed") end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if job and not job.sent and not job.waitingInfo then self:prepare(job) end
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- The client dropped a query: send it again once, when the system is ready.
    if job and job.sent and not job.resent then
      job.sent, job.resent = false, true
      if self:ready() then self:prepare(job) end
    end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED" then
    if job and job.waitingInfo and arg == job.entry.itemID and self:ready() then self:prepare(job) end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if not (job and job.sent) then return end
    local e = job.entry
    -- Item events are matched on itemID only: the client may hand back the key with level and suffix
    -- cleared, and one search runs at a time.
    local commodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED" and arg == e.itemID
    local item = event == "ITEM_SEARCH_RESULTS_UPDATED" and type(arg) == "table" and arg.itemID == e.itemID
    if e.unsure and (commodity or item) then
      -- Read the listings the way the answer came.
      local read = { itemID = e.itemID, itemKey = item and arg or e.itemKey, commodity = commodity }
      self:finishSearch(job, PostingAPI.readListings(self.env, read))
    elseif e.commodity and commodity then
      self:finishSearch(job, PostingAPI.readListings(self.env, e))
    elseif not e.commodity and item then
      -- Read with the searched key, like Blizzard's window; if the client filed the answer under its own
      -- key (level or suffix cleared), read with that.
      local listings, complete = PostingAPI.readListings(self.env, e)
      if #listings == 0 then
        listings, complete = PostingAPI.readListings(self.env, { itemID = e.itemID, itemKey = arg, commodity = false })
      end
      self:finishSearch(job, listings, complete)
    end
  elseif event == "AUCTION_HOUSE_POST_WARNING" then
    if self.onPostWarning then self.onPostWarning() end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    self.pending = nil
    if self.onPosted then self.onPosted(true) end
  elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_HOUSE_SHOW_ERROR" then
    -- While the sniper waits on a buy (SnipeAPI sets buying), the error is about that buy.
    if event == "AUCTION_HOUSE_SHOW_ERROR" and self.buying then return end
    self.pending = nil
    if self.onPosted then self.onPosted(false, arg) end
  end
end

-- The first slot that still holds the item, unlocked: bags change between reading them and a click.
local function liveSlot(env, entry)
  for _, s in ipairs(entry.slots or {}) do
    local info = try(env.C_Container.GetContainerItemInfo, s.bag, s.slot)
    if type(info) == "table" and info.itemID == entry.itemID and not info.isLocked then
      s.count = info.stackCount or 1
      return s
    end
  end
  return nil
end

-- Posts one auction for an entry from readBags following a "post" plan from Posting.plan. Must run
-- inside a click. Returns "sent", "confirm" (the client wants a second click: call confirm()), or
-- nil and a reason. A non-commodity post takes at most the one slot's stack; for single items the
-- client creates one auction per item (a multisell), each with its own AUCTION_HOUSE_AUCTION_CREATED.
function PostingAPI:post(entry, plan)
  self.pending = nil
  local ah = self.env.C_AuctionHouse
  if not (plan and plan.action == "post") then return nil, "nothing to post" end
  if not self:ready() then return nil, "the auction house is busy; try again in a moment" end
  local slot = liveSlot(self.env, entry)
  if not slot then return nil, "your bags changed; the list will update" end
  local args
  if entry.commodity then
    args = { "Commodity", slot.location, plan.duration, plan.quantity, plan.price, n = 5 }
  else
    args = { "Item", slot.location, plan.duration, math.min(plan.quantity, slot.count), nil, plan.price, n = 6 }
  end
  args.entry = entry
  local fn = ah and ah["Post" .. args[1]]
  if type(fn) ~= "function" then return nil, "C_AuctionHouse.Post" .. args[1] .. " is missing" end
  local ok, needsConfirmation = pcall(fn, unpack(args, 2, args.n))
  if not ok then return nil, "the auction house refused: " .. tostring(needsConfirmation) end
  if needsConfirmation then
    self.pending = args
    return "confirm"
  end
  return "sent"
end

-- Confirms the post the client asked about. Must run inside a click.
function PostingAPI:confirm()
  local args = self.pending
  self.pending = nil
  if not args then return nil, "nothing to confirm" end
  local slot = liveSlot(self.env, args.entry)
  if not (slot and slot.location == args[2]) then return nil, "your bags changed; the list will update" end
  local fn = self.env.C_AuctionHouse["ConfirmPost" .. args[1]]
  if type(fn) ~= "function" then return nil, "C_AuctionHouse.ConfirmPost" .. args[1] .. " is missing" end
  local ok, err = pcall(fn, unpack(args, 2, args.n))
  if not ok then return nil, "the auction house refused: " .. tostring(err) end
  return "sent"
end

PostingAPI.NEEDED = {
  "SendSearchQuery", "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo", "HasFullCommoditySearchResults",
  "GetNumItemSearchResults", "GetItemSearchResultInfo", "HasFullItemSearchResults", "IsSellItemValid",
  "GetItemKeyFromItem", "GetItemCommodityStatus", "PostCommodity", "PostItem", "ConfirmPostCommodity",
  "ConfirmPostItem", "IsThrottledMessageSystemReady",
}

function PostingAPI.install(env, addon)
  local api = PostingAPI.new(env)
  addon.postingAPI = api
  if addon.Probes then
    addon.Probes.suite():add("Posting API", function()
      local ah = env.C_AuctionHouse or {}
      local missing = {}
      for _, name in ipairs(PostingAPI.NEEDED) do
        if type(ah[name]) ~= "function" then missing[#missing + 1] = "C_AuctionHouse." .. name end
      end
      if not (env.ItemLocation and env.ItemLocation.CreateFromBagAndSlot) then
        missing[#missing + 1] = "ItemLocation:CreateFromBagAndSlot"
      end
      if #missing > 0 then return "fail", "missing: " .. table.concat(missing, ", ") end
      local entries = PostingAPI.readBags(env) or {}
      local commodities = 0
      for _, e in ipairs(entries) do if e.commodity then commodities = commodities + 1 end end
      local copper = type(ah.SupportsCopperValues) ~= "function" and "unknown (no SupportsCopperValues)"
        or (PostingAPI.priceStep(env) == 1 and "yes" or "no, prices go in whole silver")
      return "pass", string.format("%d items in your bags can be posted (%d commodities, %d items); copper prices: %s",
        #entries, commodities, #entries - commodities, copper)
    end)
  end
  return api
end

ns.PostingAPI = PostingAPI
if CreateFrame then PostingAPI.install(_G, ns) end
return PostingAPI
