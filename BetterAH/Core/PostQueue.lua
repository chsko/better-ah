-- Post queue (glossary): the items in your bags that are ready to be posted right now. Pure: the Post
-- view hands in what the bags hold and what each item's search found, and gets rows back.
--
-- Each row is one item with a state:
--   "checking"  its listings are being looked up
--   "ready"     it will post (plan is a Posting "post" plan)
--   "setup"     it would post but needs a posting profile first
--   "skipped"   it stays in your bags (plan.reason says why, or skipped = "you" when you skipped it, or
--               "kept" for the leftovers of its posts this visit, which the plan said stay in the bags)
--   "failed"    the lookup failed (reason says why)
local _, ns = ...
ns = ns or {}

local PostQueue = {}
PostQueue.__index = PostQueue

-- opts: { settings = Posting.Settings, key = market key, marketValue = function(item) -> copper or nil,
--         step = price step (1 or 100) }
function PostQueue.new(opts)
  return setmetatable({
    settings = opts.settings, key = opts.key, marketValue = opts.marketValue or function() return nil end,
    step = opts.step or 1, entries = {}, found = {}, skipped = {}, kept = {},
  }, PostQueue)
end

-- entries: from PostingAPI.readBags ({ item, name, have, maxStack, ... }). Listings already found for an
-- item are kept; items that left the bags drop out. Returns the items that still need a lookup,
-- including ones whose lookup failed (so they are tried again).
function PostQueue:setEntries(entries)
  self.entries = entries or {}
  local need, present = {}, {}
  for _, e in ipairs(self.entries) do
    present[e.item] = true
    local found = self.found[e.item]
    if not found or found.failed then need[#need + 1] = e end
  end
  for item in pairs(self.found) do
    if not present[item] then self.found[item] = nil end
  end
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

-- Record that an item was posted following its plan: once only its leftovers are in the bags, they
-- stay there for the rest of this visit, as the plan said.
function PostQueue:sent(item, plan)
  if self.kept[item] == nil then self.kept[item] = plan and plan.remainder or 0 end
end

-- Leave an item in the bags for this visit to the auction house.
function PostQueue:skip(item)
  self.skipped[item] = true
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
  row.plan = ns.Posting.plan({
    have = e.have, listings = found.listings, marketValue = self.marketValue(e.item),
    floor = settings and settings:floor(self.key, e.item), profile = settings and settings:profile(e.item),
    maxStack = e.maxStack, step = self.step,
  })
  if self.skipped[e.item] then
    row.state, row.skipped = "skipped", "you"
  elseif self.kept[e.item] and e.have <= self.kept[e.item] then
    row.state, row.skipped = "skipped", "kept"
  elseif row.plan.action == "post" then
    row.state = "ready"
  elseif row.plan.action == "profile" then
    row.state = "setup"
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
