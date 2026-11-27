-- Essence swap (#234): whether an essence earns more posted as it is, or converted to its other form.
-- Three lesser essences combine into one greater, and a greater splits into three lesser; dust, shards
-- and Nexus Crystals can't be converted. Pure: the post queue hands in the prices Post would post each
-- form at, and gets the comparison back.
--
-- Both totals are after the auction house's cut (Disenchant.net). Deposits are left out: essences vendor
-- for about a copper, so converting changes the deposit by a copper or two. Converting is advised only
-- when the converted post would go up (not below the other form's floor) and earns at least MIN_GAIN
-- more than posting as is.
local _, ns = ...
ns = ns or {}

local EssenceSwap = {}

EssenceSwap.MIN_GAIN = 0.01 -- share of the as-is total that converting must beat it by to be advised
EssenceSwap.RATIO = 3

local LESSER = {}
for lesser, greater in pairs(ns.Disenchant.GREATER) do LESSER[greater] = lesser end

local function id(item)
  return type(item) == "string" and tonumber(item:match("^i:(%d+)$")) or nil
end

-- An essence's other form as an item key, and "combine" (a lesser) or "split" (a greater); nil for
-- anything else.
function EssenceSwap.counterpart(item)
  local n = id(item)
  if not n then return nil end
  if ns.Disenchant.GREATER[n] then return "i:" .. ns.Disenchant.GREATER[n], "combine" end
  if LESSER[n] then return "i:" .. LESSER[n], "split" end
  return nil
end

-- How many of the other form converting have units gives, and how many are left over as they are.
function EssenceSwap.converted(direction, have)
  have = math.max(0, math.floor(tonumber(have) or 0))
  if direction == "split" then return have * EssenceSwap.RATIO, 0 end
  return math.floor(have / EssenceSwap.RATIO), have % EssenceSwap.RATIO
end

-- args: { item, have = units in the bags, price = what Post posts the item at (per unit),
--         otherPrice = what Post would post the other form at (per unit),
--         otherPosts = true when that post would go up (not below its floor),
--         otherReason = why it wouldn't (a Posting plan reason), or nil }
-- Returns nil when there is nothing to compare (not an essence, a price missing, too few to combine),
-- else { direction, other = item key, otherName, price, otherPrice, otherPosts, otherReason, units = of the
-- other form, left = units left as they are, asIs = copper after the cut, convert = copper after the cut,
-- gain = convert - asIs, better = true when converting is advised }.
function EssenceSwap.compare(args)
  local other, direction = EssenceSwap.counterpart(args.item)
  local price, otherPrice = tonumber(args.price), tonumber(args.otherPrice)
  if not (other and price and price > 0 and otherPrice and otherPrice > 0) then return nil end
  local have = math.max(0, math.floor(tonumber(args.have) or 0))
  local units, left = EssenceSwap.converted(direction, have)
  if units <= 0 then return nil end
  local asIs = ns.Disenchant.net(have * price)
  local convert = ns.Disenchant.net(units * otherPrice + left * price)
  local gain = convert - asIs
  local mat = ns.Disenchant.BY_ID[id(other)]
  return {
    direction = direction, other = other, otherName = mat and mat.name, units = units, left = left,
    price = price, otherPrice = otherPrice, otherPosts = args.otherPosts == true,
    otherReason = args.otherReason,
    asIs = asIs, convert = convert, gain = gain,
    better = args.otherPosts == true and gain > 0 and gain >= asIs * EssenceSwap.MIN_GAIN,
  }
end

ns.EssenceSwap = EssenceSwap
return EssenceSwap
