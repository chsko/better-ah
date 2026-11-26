-- What the Better AH window shows, without any frames. The Window adapter
-- renders this state; specs drive it directly.
local _, ns = ...
ns = ns or {}

local SECTIONS = {
  { title = "Sell", entries = {
    { id = "post", label = "Post" },
    { id = "auctions", label = "My auctions" },
  } },
  { title = "Buy", entries = {
    { id = "browse", label = "Browse" },
    { id = "disenchant", label = "Disenchant snipe" },
    { id = "deals", label = "Deals below market" },
    { id = "shopping", label = "Shopping lists" },
  } },
  { title = "Make", entries = {
    { id = "crafting", label = "Crafting profit" },
  } },
  { title = "Data", entries = {
    { id = "prices", label = "Prices and history" },
    { id = "alts", label = "Alts and inventory" },
  } },
  { title = "Addon", entries = {
    { id = "settings", label = "Settings" },
  } },
}

local known = {}
for _, section in ipairs(SECTIONS) do
  for _, entry in ipairs(section.entries) do known[entry.id] = entry end
end

local WindowModel = { SECTIONS = SECTIONS, known = known }
WindowModel.__index = WindowModel

-- mode is "closed" (no auction house), "better" (our window) or "blizzard".
function WindowModel.new()
  return setmetatable({ view = SECTIONS[1].entries[1].id, mode = "closed" }, WindowModel)
end

function WindowModel:sections()
  return self.SECTIONS
end

function WindowModel:label(id)
  return self.known[id] and self.known[id].label
end

function WindowModel:select(id)
  if not self.known[id] then return false end
  self.view = id
  return true
end

function WindowModel:auctionOpened()
  self.mode = "better"
end

function WindowModel:auctionClosed()
  self.mode = "closed"
end

function WindowModel:toggle()
  if self.mode == "better" then
    self.mode = "blizzard"
  elseif self.mode == "blizzard" then
    self.mode = "better"
  end
end

ns.WindowModel = WindowModel
return WindowModel
