-- Floor prices for disenchant materials (#71). Pure: the Post view hands in market values, the snipe
-- targets and the player's rule, and gets each material's floor back, with how it was worked out.
--
-- The rule is one of
--   "breakeven"  the share of market value at which a sniped green's materials sell for what the snipe
--                paid. A target pays at most its worth less its profit, and its worth is its materials at
--                market value after the cut, so selling them at (1 - profit share) of market value gets
--                the price back. With several targets, the one with the smallest profit share sets it,
--                so no target's buys sell at a loss. With no target, it falls back to the percent.
--   "percent"    a fixed percent of market value (80 unless the player set another).
-- With convert on, essences also never go under what they convert to: three lesser make a greater
-- and a greater splits into three lesser, so a lesser's floor is at least a third of the greater's
-- and a greater's at least three lessers'. A floor the player set on one material wins over all this.
local _, ns = ...
ns = ns or {}

local MatFloors = {}

MatFloors.DEFAULT_PERCENT = 80

-- The settings kept in BetterAHDB.posting.mats, with defaults filled in.
function MatFloors.rule(saved)
  saved = type(saved) == "table" and saved or {}
  local percent = tonumber(saved.percent)
  if not (percent and percent > 0 and percent <= 1000) then percent = MatFloors.DEFAULT_PERCENT end
  return {
    kind = saved.kind == "percent" and "percent" or "breakeven",
    percent = percent,
    convert = saved.convert ~= false,
  }
end

-- Whether an item key ("i:10940") is one of the 24 disenchant materials. Returns its material entry.
function MatFloors.material(item)
  local id = type(item) == "string" and tonumber(item:match("^i:(%d+)$")) or tonumber(item)
  return id and ns.Disenchant.BY_ID[id] or nil, id
end

-- The break-even share (0-1] from the sniped targets, and the profit share that set it; nil without a
-- target to go by. worthOf(target) gives the copper a target's band is worth after the cut, needed only
-- for a profit in gold.
function MatFloors.breakEven(targets, worthOf)
  local best
  for _, t in ipairs(targets or {}) do
    if t.enabled then
      local p, profit = t.profit or {}, nil
      if p.kind == "percent" then
        profit = (tonumber(p.amount) or 0) / 100
      else
        local worth = worthOf and tonumber(worthOf(t))
        if worth and worth > 0 then profit = (tonumber(p.amount) or 0) / worth end
      end
      if profit and profit < 1 and (not best or profit < best) then best = math.max(0, profit) end
    end
  end
  if not best then return nil end
  return 1 - best, best
end

-- The share of market value the rule gives, and where it came from: "breakeven" (with the profit
-- share) or "percent".
function MatFloors.share(rule, targets, worthOf)
  if rule.kind == "breakeven" then
    local share, profit = MatFloors.breakEven(targets, worthOf)
    if share then return share, "breakeven", profit end
  end
  return rule.percent / 100, "percent"
end

local LESSER = {}
for lesser, greater in pairs(ns.Disenchant.GREATER) do LESSER[greater] = lesser end

-- A material's floor and how it was worked out:
--   { floor, share, source = "breakeven" | "percent", profit, base = share of its own market value,
--     marketValue, convert = { id, ratio, floor } when the essence it converts to set the floor }
-- nil when the item isn't a material or nothing is known to set a floor from.
-- marketValueOf(id) gives a material's market value or nil.
function MatFloors.floor(item, rule, marketValueOf, targets, worthOf)
  local mat, id = MatFloors.material(item)
  if not mat then return nil end
  local share, source, profit = MatFloors.share(rule, targets, worthOf)
  local function base(of)
    local value = tonumber(marketValueOf(of))
    -- Through a rounded share, so 150 at 82% is 123, not 124 from 0.82's float error.
    if value and value > 0 then return math.ceil(value * math.floor(share * 10000 + 0.5) / 10000 - 1e-9), value end
    return nil
  end
  local own, value = base(id)
  local out = { share = share, source = source, profit = profit, base = own, marketValue = value }
  local floor = own
  if rule.convert then
    local other, ratio
    if ns.Disenchant.GREATER[id] then other, ratio = ns.Disenchant.GREATER[id], 1 / 3 end
    if LESSER[id] then other, ratio = LESSER[id], 3 end
    local otherBase = other and base(other)
    if otherBase then
      local converted = math.ceil(otherBase * ratio)
      if not floor or converted > floor then
        floor = converted
        out.convert = { id = other, ratio = ratio, floor = otherBase }
      end
    end
  end
  if not floor then return nil end
  out.floor = floor
  return out
end

ns.MatFloors = MatFloors
return MatFloors
