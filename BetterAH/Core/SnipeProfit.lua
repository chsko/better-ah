-- Snipe profit (#254): what each disenchant target really earned. Pure: the Snipe view hands in each green
-- it buys, with the target it was sniped for, and Game/DisenchantWatch.lua hands in each disenchant with the
-- mats it gave. Specs in spec/snipe_profit_spec.lua.
--
-- Kept in BetterAHDB.snipeProfit as
--   greens = { green, ... } oldest first, where a green is
--     { t = time bought, item = itemID, s = suffix id or nil, c = copper paid,
--       target = { name, min, max, profit, worth } or nil,
--       de = { t = time, char = character key, mats = { [matID] = count } } or nil }
--
-- target is a copy taken when the green was bought: its name (the target's item types, as the Targets tab
-- shows them), its item level band (min, max), its profit text and what the sniper expected the green to
-- be worth. A copy, so editing or deleting a target later doesn't move old results. A green with no target
-- was not sniped: a disenchant of a green Better AH didn't snipe adds one, at the price the caller knows
-- (the Purchases record of a Browse buy) or nothing.
local _, ns = ...
ns = ns or {}

local SnipeProfit = {}
SnipeProfit.__index = SnipeProfit

SnipeProfit.MAX_GREENS = 5000 -- the oldest go first
SnipeProfit.MAX_DAYS = 400 -- as long as the Ledger keeps the sales they are matched to
SnipeProfit.DAY = 86400

local function int(v) return math.floor((tonumber(v) or 0) + 0.5) end

function SnipeProfit.new(store)
  if type(store) ~= "table" then store = {} end
  if type(store.greens) ~= "table" then store.greens = {} end
  return setmetatable({ store = store }, SnipeProfit)
end

local function push(self, g)
  local list = self.store.greens
  list[#list + 1] = g
  while #list > SnipeProfit.MAX_GREENS do table.remove(list, 1) end
  return g
end

local function suffixOf(link)
  if not ns.Purchases or type(link) ~= "string" then return nil end
  local _, suffix = ns.Purchases.parseLink(link)
  return suffix
end

-- Records a green bought through the sniper: itemID (and its link, for the suffix) for copper, at t.
-- target = { name, min, max, profit, worth }, or nil for a green bought another way.
function SnipeProfit:bought(itemID, link, copper, t, target)
  local item, c = tonumber(itemID), int(copper)
  if not item or c <= 0 then return false end
  local g = { t = int(t), item = item, s = suffixOf(link), c = c }
  if type(target) == "table" then
    g.target = { name = target.name, min = tonumber(target.min), max = tonumber(target.max),
      profit = target.profit, worth = tonumber(target.worth) }
  end
  push(self, g)
  return true
end

-- The oldest green of item not disenchanted yet that ok(green) takes.
local function oldestWaiting(greens, item, ok)
  for _, g in ipairs(greens) do
    if not g.de and g.item == item and ok(g) then return g end
  end
  return nil
end

-- Records a disenchant on char at t of itemID (with its suffix id or nil), which gave mats ({ [matID] =
-- count }). The mats go to the oldest green of that item and suffix not disenchanted yet. When one side's
-- suffix is unknown (nil) they may pair up, but two known suffixes that differ never do: that green is
-- another one, still waiting in the bags. With none, a Not sniped green is added at paid copper (0 when
-- unknown). Returns the green, or nil when there is nothing to record.
function SnipeProfit:disenchanted(itemID, suffix, char, t, mats, paid)
  local item = tonumber(itemID)
  if not item or type(mats) ~= "table" then return nil end
  local got, any = {}, false
  for id, n in pairs(mats) do
    id, n = tonumber(id), int(n)
    if id and n > 0 then got[id], any = n, true end
  end
  if not any then return nil end
  suffix = tonumber(suffix)
  local greens = self.store.greens
  local g = oldestWaiting(greens, item, function(x) return x.s == suffix end)
    or oldestWaiting(greens, item, function(x) return suffix == nil or x.s == nil end)
  if not g then
    g = push(self, { t = int(t), item = item, s = suffix, c = math.max(0, int(paid)) })
  end
  g.de = { t = int(t), char = char, mats = got }
  return g
end

-- Drops greens bought more than MAX_DAYS before now.
function SnipeProfit:prune(now)
  local cutoff = int(now) - SnipeProfit.MAX_DAYS * SnipeProfit.DAY
  local kept = {}
  for _, g in ipairs(self.store.greens) do
    if (g.t or 0) >= cutoff then kept[#kept + 1] = g end
  end
  self.store.greens = kept
end

ns.SnipeProfit = SnipeProfit
return SnipeProfit
