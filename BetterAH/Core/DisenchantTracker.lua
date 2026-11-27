-- Disenchant tracker (#256): pairs a Disenchant cast with the item it was cast on and the loot window
-- that follows, so Snipe profit knows what each green gave. Pure: Game/DisenchantWatch.lua hands in the
-- clicks, casts and loot slots it sees; nothing here calls the WoW API. Specs in
-- spec/disenchant_tracker_spec.lua.
--
-- The order in the client: Disenchant waits for a target, the player clicks a bag item (used), the cast
-- starts (started: the target item is locked in the bags for the cast, so the adapter can name it there),
-- finishes (succeeded), then the loot window opens with the mats (loot). Casts are told apart by their
-- cast GUID, so a second press that fails ("another action is in progress") leaves the first alone. The
-- item, best first: the loot's own source item when the game says, the item locked when the cast started,
-- the bag item used just before the cast started.
local _, ns = ...
ns = ns or {}

local DisenchantTracker = {}
DisenchantTracker.__index = DisenchantTracker

DisenchantTracker.SPELL = 13262 -- Disenchant
DisenchantTracker.WINDOW = 5 -- seconds from the end of the cast to the loot window

function DisenchantTracker.new()
  return setmetatable({}, DisenchantTracker)
end

local function parse(link)
  if not ns.Purchases then return nil end
  return ns.Purchases.parseLink(link)
end

DisenchantTracker.MAX_CAST = 5 -- seconds a Disenchant cast can take, for a cast whose start was missed

local function isDisenchant(spellID) return tonumber(spellID) == DisenchantTracker.SPELL end

-- The player used or picked up a bag item (link) at t. Hooks see it after the call, when targeting has
-- already ended, so every use is kept and the cast decides whether it was its target.
function DisenchantTracker:used(t, link)
  if type(link) == "string" then self.use = { t = tonumber(t) or 0, link = link } end
end

-- A cast (guid) of spellID started at t; locked: the link of the bag item locked for it, when one is.
function DisenchantTracker:started(t, guid, spellID, locked)
  if not isDisenchant(spellID) then return end
  self.casts = self.casts or {}
  self.casts[guid or "?"] = { t = tonumber(t) or 0, link = type(locked) == "string" and locked or nil }
end

-- A cast (guid) of spellID finished at t.
function DisenchantTracker:succeeded(t, guid, spellID)
  if not isDisenchant(spellID) then return end
  t = tonumber(t) or 0
  local casts = self.casts or {}
  local c = casts[guid or "?"]
  casts[guid or "?"] = nil
  local link = c and c.link
  local use = self.use
  local from = (c and c.t or t - DisenchantTracker.MAX_CAST) - 1
  if not link and use and use.t >= from and use.t <= t then link = use.link end
  self.use = nil
  self.cast = { t = t, link = link }
end

-- A cast (guid) of spellID failed or was interrupted: that cast's item isn't disenchanted.
function DisenchantTracker:failed(guid, spellID)
  if isDisenchant(spellID) and self.casts then self.casts[guid or "?"] = nil end
end

-- The loot window opened at t with slots ({ { link, count }, ... }); source is the link of the item the
-- loot came from, when the game says. Returns { item, suffix, link, mats = { [matID] = count } } for a
-- disenchant's loot, or nil and why ("no cast", "no item", "no mats").
function DisenchantTracker:loot(t, slots, source)
  local cast = self.cast
  t = tonumber(t) or 0
  if not cast or t < cast.t or t - cast.t > DisenchantTracker.WINDOW then
    self.cast = nil
    return nil, "no cast"
  end
  self.cast = nil
  local link = (type(source) == "string" and parse(source)) and source or cast.link
  local item, suffix = parse(link)
  if not item then return nil, "no item" end
  local mats, any = {}, false
  for _, s in ipairs(slots or {}) do
    local id = parse(s.link)
    local n = math.floor(tonumber(s.count) or 0)
    if id and n > 0 and ns.Disenchant and ns.Disenchant.BY_ID[id] then
      mats[id], any = (mats[id] or 0) + n, true
    end
  end
  if not any then return nil, "no mats" end
  return { item = item, suffix = suffix, link = link, mats = mats }
end

ns.DisenchantTracker = DisenchantTracker
return DisenchantTracker
