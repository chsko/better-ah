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

-- The mat a Ledger sale is of: its item ID, else its name looked up among the disenchant mats (mail
-- invoices only give names).
local function matOf(e)
  if e.item then return tonumber(e.item) end
  if not ns.Disenchant or type(e.name) ~= "string" then return nil end
  local plain = e.name:match("|h%[(.-)%]|h") or e.name
  for _, m in ipairs(ns.Disenchant.MATERIALS) do
    if m.name == plain then return m.id end
  end
  return nil
end

local function newRow(g)
  local t = g.target
  return { name = t and (t.name or "?") or "Not sniped", min = t and t.min, max = t and t.max,
    targetProfit = t and t.profit, other = not t or nil, greens = 0, disenchanted = 0, spent = 0, earned = 0,
    unsold = 0, waiting = { n = 0, worth = 0 }, profit = 0, mats = {} }
end

local function rowKey(g)
  local t = g.target
  if not t then return "\255" end -- Not sniped sorts last
  return string.format("%s\0%05d\0%05d", tostring(t.name or "?"), tonumber(t.min) or 0, tonumber(t.max) or 0)
end

-- What each target earned, for greens bought at or after from. sales: Ledger entries (only k = "sale" ones
-- count: c = sold for, cut = the AH cut, n units, item or name). valueOf(matID): copper one unit brings
-- when sold now (after the cut), or nil when unknown.
--
-- Each mat's sales go to its disenchanted units first in, first out: the units of the oldest disenchant
-- first, and only units disenchanted before the sale. A sale's units beyond those are not ours (farmed or
-- bought mats). This runs over every green kept, so a period's greens get the sales their own mats made.
-- A sale's time is when its gold was taken from the mail (all the Ledger knows), not when it sold, so a
-- mat sold before a disenchant but collected after it can still be credited to it.
-- Units left are valued with valueOf. A green not disenchanted yet counts as spent and as waiting, at the
-- worth the sniper expected; that worth stays out of the profit (profit = earned + unsold - spent).
--
-- Returns { rows = { row, ... } by target name and band, Not sniped last, total = row }, where a row is
-- { name, min, max, targetProfit, other, greens, disenchanted, spent, earned, unsold,
--   waiting = { n, worth }, profit, mats = { [matID] = { got, sold, held, earned, unsold } } }.
function SnipeProfit:results(from, sales, valueOf)
  from = tonumber(from) or 0
  -- Disenchanted units per mat, oldest disenchant first: { g, left, earned }.
  local queues = {}
  local done = {}
  for _, g in ipairs(self.store.greens) do
    if g.de then done[#done + 1] = g end
  end
  table.sort(done, function(a, b) return (a.de.t or 0) < (b.de.t or 0) end)
  local units = {} -- [green][matID] = { got, left, earned, t }
  for _, g in ipairs(done) do
    units[g] = {}
    for id, n in pairs(g.de.mats or {}) do
      id = tonumber(id)
      local u = { got = n, left = n, earned = 0, t = g.de.t or 0 }
      if id then
        units[g][id] = u
        queues[id] = queues[id] or { head = 1 }
        table.insert(queues[id], u)
      end
    end
  end
  local sold = {}
  for _, e in ipairs(sales or {}) do
    if e.k == "sale" then sold[#sold + 1] = e end
  end
  table.sort(sold, function(a, b) return (a.t or 0) < (b.t or 0) end)
  for _, e in ipairs(sold) do
    local id, n = matOf(e), math.max(0, int(e.n))
    local q = id and queues[id]
    if q and n > 0 then
      -- Units are used up front to back (sales come oldest first, the queue is oldest disenchant first), so
      -- q.head skips the used ones, and the first unit disenchanted after the sale ends the walk.
      local each = ((tonumber(e.c) or 0) - (tonumber(e.cut) or 0)) / n
      local i = q.head
      while n > 0 and q[i] and q[i].t <= (e.t or 0) do
        local u = q[i]
        local take = math.min(u.left, n)
        u.left, u.earned, n = u.left - take, u.earned + take * each, n - take
        if u.left == 0 then i = i + 1 end
      end
      q.head = i
    end
  end

  local values = {}
  local function value(id)
    if values[id] == nil then values[id] = valueOf and tonumber(valueOf(id)) or false end
    return values[id] or 0
  end
  local rows, byKey, keys = {}, {}, {}
  local total = newRow({ target = { name = "Total" } })
  total.targetProfit = nil
  local function add(row, g)
    row.greens = row.greens + 1
    row.spent = row.spent + (g.c or 0)
    if g.de then
      row.disenchanted = row.disenchanted + 1
      for id, u in pairs(units[g] or {}) do
        local m = row.mats[id]
        if not m then
          m = { got = 0, sold = 0, held = 0, earned = 0, unsold = 0 }
          row.mats[id] = m
        end
        m.got, m.sold, m.held = m.got + u.got, m.sold + u.got - u.left, m.held + u.left
        m.earned, m.unsold = m.earned + u.earned, m.unsold + u.left * value(id)
      end
    else
      row.waiting.n = row.waiting.n + 1
      row.waiting.worth = row.waiting.worth + (g.target and tonumber(g.target.worth) or 0)
    end
  end
  for _, g in ipairs(self.store.greens) do
    if (g.t or 0) >= from then
      local key = rowKey(g)
      local row = byKey[key]
      if not row then
        row = newRow(g)
        byKey[key] = row
        keys[#keys + 1] = key
      end
      add(row, g)
      add(total, g)
    end
  end
  table.sort(keys)
  local function finish(row)
    for _, m in pairs(row.mats) do
      m.earned, m.unsold = int(m.earned), int(m.unsold)
      row.earned, row.unsold = row.earned + m.earned, row.unsold + m.unsold
    end
    row.profit = row.earned + row.unsold - row.spent
    return row
  end
  for _, key in ipairs(keys) do rows[#rows + 1] = finish(byKey[key]) end
  -- The total adds up the rounded rows, so the column sums match what the rows show.
  finish(total)
  total.earned, total.unsold = 0, 0
  for _, row in ipairs(rows) do total.earned, total.unsold = total.earned + row.earned, total.unsold + row.unsold end
  total.profit = total.earned + total.unsold - total.spent
  return { rows = rows, total = total }
end

ns.SnipeProfit = SnipeProfit
return SnipeProfit
