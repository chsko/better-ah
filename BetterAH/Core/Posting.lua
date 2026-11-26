-- Posting (spec #8): what to post an item for, or why not. Pure: the post view hands in the item's
-- current listings, its market value and the player's settings, and gets a plan back.
--
-- The price is an undercut: the highest whole copper below the cheapest unit price that isn't the
-- player's. With no other listings the item is priced at its market value. If the price is below the
-- item's floor price (its own floor on this market, else 80% of market value) the item is skipped and
-- stays in the bags, with the reason. Otherwise it posts everything in the bags, or at most the
-- profile's limit, for the profile's duration (24 hours without one). A commodity goes up as one post
-- of any size, since C_AuctionHouse.PostCommodity takes units from every bag slot; other items post
-- one auction per bag stack.
local _, ns = ...
ns = ns or {}

local Posting = {}

Posting.FLOOR_SHARE = 0.8
-- C_AuctionHouse durations are indices 1-3 into the client's own list (AUCTION_DURATION_ONE..THREE).
-- Forever's are 2, 8 and 24 hours (self-test, build 1.60.1.71139), so 24 hours is 3.
Posting.DURATIONS = { 1, 2, 3 }
Posting.DEFAULT_DURATION = 3

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- How many of a listing's units are someone else's. A commodity row can mix the player's units with
-- other sellers' at the same price, so ownCount counts only the player's.
local function others(l)
  local count = tonumber(l.count) or 0
  return count - math.min(count, tonumber(l.ownCount) or 0)
end

-- listings: array of { unit = copper per unit (may be fractional), count = units,
-- ownCount = how many of them are the player's }. The adapter turns whole-stack buyouts into unit.
-- Returns the cheapest unit price with units that aren't the player's, or nil.
function Posting.cheapestOther(listings)
  local cheapest
  for _, l in ipairs(listings or {}) do
    local unit = tonumber(l.unit)
    if others(l) > 0 and unit and unit > 0 and (not cheapest or unit < cheapest) then cheapest = unit end
  end
  return cheapest
end

-- The item's floor price in copper: its own floor if set, else the rule's floor (disenchant materials,
-- Core/MatFloors.lua), else FLOOR_SHARE of market value rounded up. nil when none is known.
function Posting.floor(marketValue, ownFloor, ruleFloor)
  if ownFloor and ownFloor > 0 then return math.floor(ownFloor) end
  if ruleFloor and ruleFloor > 0 then return math.ceil(ruleFloor) end
  if marketValue and marketValue > 0 then return math.ceil(marketValue * Posting.FLOOR_SHARE) end
  return nil
end

-- args: { have = units in bags, listings = {...}, marketValue = copper or nil, floor = own floor or nil,
--         ruleFloor = the floor a rule gives when there's no own floor (or nil),
--         profile = { limit, duration } or nil, commodity = true for a commodity,
--         stacks = the counts of the item's bag stacks in bag order (a non-commodity posts one per click),
--         maxStack = the item's stack size or nil (caps a non-commodity post when stacks is nil),
--         posted = units of the item already posted this visit (they count toward the limit), or nil,
--         step = the smallest price step the client takes, 1 copper (default) or 100 (whole silver) }
-- Returns a plan, one of
--   { action = "skip", reason = why, price, floor }      stays in the bags, where why is
--     "none-left", "limit" (this visit already posted the profile's limit), "no-floor" (no market value
--     and no own floor) or "below-floor"
--   { action = "post", price, floor, undercut, quantity, posts, remainder, duration, limit }
-- price is per unit. Posting makes posts auctions of quantity units each (the last of a non-commodity
-- run may be smaller) and leaves remainder in the bags. undercut is the competing unit price it went
-- under (nil when priced at market value). limit is the profile's limit, or nil for everything.
function Posting.plan(args)
  local have = math.floor(tonumber(args.have) or 0)
  if have <= 0 then return { action = "skip", reason = "none-left" } end
  local profile = type(args.profile) == "table" and args.profile or {}
  local limit = Posting.limit(profile.limit)
  local due = limit and limit - math.max(0, math.floor(tonumber(args.posted) or 0)) or have
  if due <= 0 then return { action = "skip", reason = "limit", limit = limit } end
  local listings = args.listings or {}

  local step = math.max(1, math.floor(tonumber(args.step) or 1))
  local floor = Posting.floor(args.marketValue, args.floor, args.ruleFloor)
  local other = Posting.cheapestOther(listings)
  local price
  if other then
    -- The highest price step strictly below the competitor.
    price = math.max(step, (math.ceil(other / step) - 1) * step)
  elseif args.marketValue and args.marketValue > 0 then
    price = math.max(math.floor(args.marketValue / step) * step, floor and math.ceil(floor / step) * step or 0, step)
  else
    price = floor and math.ceil(floor / step) * step
  end
  if not floor then return { action = "skip", price = price, reason = "no-floor" } end
  if price < floor then return { action = "skip", price = price, floor = floor, reason = "below-floor" } end

  local duration = Posting.duration(profile.duration) or Posting.DEFAULT_DURATION
  local total = math.min(have, due)
  local quantity, posts = total, 1
  if not args.commodity then
    local stacks = type(args.stacks) == "table" and #args.stacks > 0 and args.stacks
    if stacks then
      -- One auction per bag stack, in bag order, the last one cut to what the limit leaves.
      quantity, posts = math.min(total, stacks[1]), 0
      local left = total
      for _, count in ipairs(stacks) do
        if left <= 0 then break end
        left, posts = left - math.min(count, left), posts + 1
      end
    else
      local maxStack = tonumber(args.maxStack)
      quantity = math.min(total, maxStack and finite(maxStack) and maxStack >= 1 and math.floor(maxStack) or total)
      posts = math.ceil(total / quantity)
    end
  end
  return {
    action = "post", price = price, floor = floor, undercut = other, duration = duration, limit = limit,
    quantity = quantity, posts = posts, remainder = have - total,
  }
end

-- A post limit as a whole number of 1 or more, or nil for none (nil, "" or anything else).
function Posting.limit(value)
  local n = tonumber(value)
  if n and finite(n) and n >= 1 then return math.floor(n) end
  return nil
end

-- A duration the client offers, or nil.
function Posting.duration(value)
  local n = tonumber(value)
  for _, d in ipairs(Posting.DURATIONS) do
    if d == n then return d end
  end
  return nil
end

-- Posting settings, kept across sessions in BetterAHDB.posting:
--   profiles[item] = { limit, duration }      the same on every market; limit nil posts everything
--                                             (profiles saved before #80 may still hold a stack, unused)
--   floors[marketKey][item] = copper          a price, so per market like all prices (ADR 0003)
--   mats = { kind, percent, convert }          the floor rule for disenchant materials (MatFloors.rule)
--   filter = "all" or "mats"                   which items the Post view shows
local Settings = {}
Settings.__index = Settings
Posting.Settings = Settings

function Settings.new(store)
  store = store or {}
  store.profiles = store.profiles or {}
  store.floors = store.floors or {}
  return setmetatable({ store = store }, Settings)
end

function Settings:matRule()
  return ns.MatFloors and ns.MatFloors.rule(self.store.mats) or nil
end

-- Changes part of the material floor rule: kind ("breakeven" or "percent"), percent (1-1000) or convert.
-- Returns false (and changes nothing) for a value that doesn't fit.
function Settings:setMatRule(field, value)
  local mats = type(self.store.mats) == "table" and self.store.mats or {}
  if field == "kind" and (value == "breakeven" or value == "percent") then
    mats.kind = value
  elseif field == "percent" then
    local n = tonumber(value)
    if not (n and finite(n) and n >= 1 and n <= 1000) then return false end
    mats.percent = math.floor(n + 0.5)
  elseif field == "convert" and type(value) == "boolean" then
    mats.convert = value
  else
    return false
  end
  self.store.mats = mats
  return true
end

function Settings:filter()
  return self.store.filter == "mats" and "mats" or "all"
end

function Settings:setFilter(filter)
  self.store.filter = filter == "mats" and "mats" or "all"
end

function Settings:profile(item)
  return self.store.profiles[item]
end

-- limit is empty (or nil) for no limit, else a whole number of 1 or more. Returns false (and changes
-- nothing) for any other limit, or a duration the client doesn't offer.
function Settings:setProfile(item, limit, duration)
  local text = limit == nil and "" or tostring(limit):match("^%s*(.-)%s*$")
  local n = tonumber(text)
  if not (text == "" or n and finite(n) and n >= 1 and n == math.floor(n)) then return false end
  duration = Posting.duration(duration)
  if not duration then return false end
  self.store.profiles[item] = { limit = text ~= "" and n or nil, duration = duration }
  return true
end

function Settings:floor(key, item)
  local floors = self.store.floors[key]
  return floors and floors[item]
end

-- Moves every floor saved under an old market key to a new one, when the new one has none yet. Used
-- once rulesets got names (ADR 0005): floors set under "/1/Horde" belong to "/Normal/Horde" (or
-- whichever ruleset the player is on). Returns true when it moved anything.
function Settings:adoptFloors(from, to)
  local floors = self.store.floors
  if from == to or not floors[from] or next(floors[from]) == nil then return false end
  if floors[to] and next(floors[to]) ~= nil then return false end
  floors[to], floors[from] = floors[from], nil
  return true
end

-- Sets the item's own floor on a market in whole copper; nil or 0 goes back to the default share of
-- market value. Returns false (and changes nothing) for anything else that isn't at least 1 copper.
function Settings:setFloor(key, item, copper)
  if copper == nil or copper == 0 then
    if self.store.floors[key] then self.store.floors[key][item] = nil end
    return true
  end
  copper = tonumber(copper)
  if not (copper and finite(copper) and copper >= 1) then return false end
  self.store.floors[key] = self.store.floors[key] or {}
  self.store.floors[key][item] = math.floor(copper)
  return true
end

ns.Posting = Posting
return Posting
