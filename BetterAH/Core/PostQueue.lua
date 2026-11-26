-- Post queue (glossary): the items in your bags that are ready to be posted right now. Pure: the Post
-- view hands in what the bags hold and what each item's search found, and gets rows back.
--
-- Each row is one item with a state:
--   "checking"  its listings are being looked up
--   "ready"     it will post (plan is a Posting "post" plan)
--   "skipped"   it stays in your bags (plan.reason says why, or skipped = "you" when you skipped it, or
--               "kept" when this visit already posted its Post at most limit)
--   "failed"    the lookup failed (reason says why)
local _, ns = ...
ns = ns or {}

local PostQueue = {}
PostQueue.__index = PostQueue

-- opts: { settings = Posting.Settings, key = market key, marketValue = function(item) -> copper or nil,
--         step = price step (1 or 100),
--         matFloor = function(item) -> a MatFloors.floor result for a disenchant material, or nil }
function PostQueue.new(opts)
  return setmetatable({
    settings = opts.settings, key = opts.key, marketValue = opts.marketValue or function() return nil end,
    matFloor = opts.matFloor or function() return nil end,
    step = opts.step or 1, entries = {}, all = {}, found = {}, skipped = {}, posted = {}, filter = "all",
  }, PostQueue)
end

local function shows(filter, e)
  return filter ~= "mats" or (ns.MatFloors and ns.MatFloors.material(e.item)) ~= nil
end

-- Which items the queue covers: "all" or "mats" (disenchant materials only). Rows, the next post and
-- the progress only count those. Returns the items that now need a lookup, as setEntries does.
function PostQueue:setFilter(filter)
  self.filter = filter == "mats" and "mats" or "all"
  return self:setEntries(self.all)
end

-- How many of the bags' items the filter shows, and how many there are.
function PostQueue:counts()
  local mats = 0
  for _, e in ipairs(self.all) do
    if shows("mats", e) then mats = mats + 1 end
  end
  return mats, #self.all
end

-- entries: from PostingAPI.readBags ({ item, name, have, maxStack, ... }). Listings already found for an
-- item are kept; items that left the bags drop out. Returns the items that still need a lookup,
-- including ones whose lookup failed (so they are tried again).
function PostQueue:setEntries(entries)
  self.all = entries or {}
  self.entries = {}
  local need = {}
  for _, e in ipairs(self.all) do
    if shows(self.filter, e) then
      self.entries[#self.entries + 1] = e
      local found = self.found[e.item]
      if not found or found.failed then need[#need + 1] = e end
    end
  end
  -- What was found stays for the visit even when a bag read misses an item for a moment (#82): a post
  -- forgets its item's listings itself.
  return need
end

-- What an item's lookup found: listings, or nil and the reason it failed.
function PostQueue:setListings(item, listings, reason)
  self.found[item] = listings and { listings = listings } or { failed = reason or "lookup failed" }
end

-- Forget an item's listings, so the next setEntries looks it up again (after posting it, for example).
function PostQueue:forget(item)
  self.found[item] = nil
end

-- Record that units of an item were posted this visit (negative to take back a post the auction house
-- refused). They count toward the item's Post at most limit until the next visit.
function PostQueue:sent(item, units)
  self.posted[item] = math.max(0, (self.posted[item] or 0) + (tonumber(units) or 0))
end

-- Leave an item in the bags for this visit to the auction house.
function PostQueue:skip(item)
  self.skipped[item] = true
end

-- The counts of the entry's bag stacks, in bag order, or nil when readBags didn't list them.
local function stacks(e)
  local out = {}
  for _, slot in ipairs(e.slots or {}) do
    if slot.count and slot.count > 0 then out[#out + 1] = slot.count end
  end
  return #out > 0 and out or nil
end

function PostQueue:row(e)
  local row = { item = e.item, name = e.name, have = e.have, entry = e }
  local found = self.found[e.item]
  if not found then
    row.state = "checking"
    return row
  end
  if found.failed then
    row.state, row.reason = "failed", found.failed
    return row
  end
  local settings = self.settings
  local own = settings and settings:floor(self.key, e.item)
  row.own = own
  row.matFloor = self.matFloor(e.item)
  row.plan = ns.Posting.plan({
    have = e.have, listings = found.listings, marketValue = self.marketValue(e.item),
    floor = own, ruleFloor = row.matFloor and row.matFloor.floor, profile = settings and settings:profile(e.item),
    commodity = e.commodity, stacks = stacks(e), maxStack = e.maxStack, posted = self.posted[e.item],
    step = self.step,
  })
  if self.skipped[e.item] then
    row.state, row.skipped = "skipped", "you"
  elseif row.plan.reason == "limit" then
    row.state, row.skipped = "skipped", "kept"
  elseif row.plan.action == "post" then
    row.state = "ready"
  else
    row.state = "skipped"
  end
  return row
end

-- Every item, in bag order (sorted by name), as rows.
function PostQueue:rows()
  local out = {}
  for _, e in ipairs(self.entries) do out[#out + 1] = self:row(e) end
  return out
end

-- The row the Post button posts next: the first ready one, or nil.
function PostQueue:nextPost()
  for _, e in ipairs(self.entries) do
    local row = self:row(e)
    if row.state == "ready" then return row end
  end
  return nil
end

-- How many items are still being looked up, and how many there are.
function PostQueue:progress()
  local checking = 0
  for _, e in ipairs(self.entries) do
    local found = self.found[e.item]
    if not found then checking = checking + 1 end
  end
  return #self.entries - checking, #self.entries
end

ns.PostQueue = PostQueue
return PostQueue
