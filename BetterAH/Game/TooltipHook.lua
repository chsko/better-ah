-- Tooltip hook (#119): puts Core/TooltipPrices.lua's lines on item tooltips. Thin on purpose: it gathers
-- what the pure modules need from the client and draws their answer. Checked in game (see #119): a
-- sniped green, a stack with and without Shift, an item never scanned, and each setting in the Settings
-- tab.
--
-- Forever has TooltipDataProcessor (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua), like retail;
-- OnTooltipSetItem is the fallback for a client without it.
local _, ns = ...
ns = ns or {}

local TooltipHook = {}

TooltipHook.TITLE_COLOR = { 0.38, 0.77, 1 }
TooltipHook.LABEL_COLOR = { 0.91, 0.91, 0.91 }
TooltipHook.DIM_COLOR = { 0.62, 0.62, 0.62 }
TooltipHook.DIM = "|cff9d9d9d"
TooltipHook.GAIN = { 0.24, 0.88, 0.29 }
TooltipHook.LOSS = { 1, 0.35, 0.29 }
-- C_Item.GetItemInfo's bindType: 1 binds on pickup, 4 is a quest item. Neither can be on the auction house.
TooltipHook.UNSELLABLE = { [1] = true, [4] = true }

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
  return nil
end

function TooltipHook.new(env, addon)
  return setmetatable({ env = env, addon = addon }, { __index = TooltipHook })
end

function TooltipHook:options()
  return ns.TooltipPrices.options(self.addon.tooltipSettings)
end

-- Forever has no global GetCoinTextureString (#153): it is C_CurrencyInfo's. The global is for older clients.
function TooltipHook:moneyText(copper)
  local n, currency = math.abs(copper), self.env.C_CurrencyInfo
  return (currency and try(currency.GetCoinTextureString, n)) or try(self.env.GetCoinTextureString, n)
    or (ns.Money and ns.Money.format(n)) or tostring(n)
end

-- C_Item.GetItemInfo's returns for link: Forever has no global GetItemInfo (#153). Nothing until it is cached.
function TooltipHook:itemInfo(link)
  local items = self.env.C_Item
  if items and type(items.GetItemInfo) == "function" then return try(items.GetItemInfo, link) end
  return try(self.env.GetItemInfo, link)
end

function TooltipHook:bagCount(itemID)
  local env = self.env
  local count = env.C_Item and try(env.C_Item.GetItemCount, itemID) or try(env.GetItemCount, itemID)
  return tonumber(count) or 0
end

-- What the pure module needs about the item behind link, or nil when the link isn't an item or the
-- item can never be on the auction house and has no price.
function TooltipHook:gather(link, opts, main)
  local env, addon = self.env, self.addon
  local id, suffix = ns.Purchases.parseLink(link)
  if not id then return nil end
  local key = ns.AuctionAPI and ns.AuctionAPI.currentMarket(env)
  local now = try(env.GetServerTime) or 0
  local prices = addon.prices
  local function priceOf(itemID)
    return key and prices and (prices:marketValue(key, "i:" .. itemID, now)) or nil
  end
  local item = { value = priceOf(id), bags = self:bagCount(id) }
  -- Shift totals and their hint only on the main tooltip: Shift redraws only that one.
  item.shift = main and opts.shift and try(env.IsShiftKeyDown) and true or false
  if not main then item.bags = math.min(item.bags, 1) end
  local _, _, quality, level, _, _, _, maxStack, equip, _, _, classID, _, bindType = self:itemInfo(link)
  -- Not cached yet: draw what we have, but don't keep it (linesFor), so the next redraw gets the full block.
  item.loading = quality == nil
  if not item.value and TooltipHook.UNSELLABLE[bindType] then return nil end
  item.stackable = (tonumber(maxStack) or 1) > 1
  if opts.disenchant and quality and ns.Disenchant then
    local deOpts = ns.DisenchantView and ns.DisenchantView.options(addon) or { salvager = true }
    item.disenchant = ns.Disenchant.value({ id = id, quality = quality, classID = classID, level = level,
      equip = equip }, priceOf, deOpts)
  end
  -- Paid and profit only for the player's own copies: not on another seller's listing or a chat link.
  if opts.paid and addon.purchases and item.bags > 0 then
    item.paid = addon.purchases:paid("i:" .. id, suffix, item.bags)
  end
  return item
end

function TooltipHook:draw(tooltip, out)
  local t, l, d, dim = TooltipHook.TITLE_COLOR, TooltipHook.LABEL_COLOR, TooltipHook.DIM_COLOR, TooltipHook.DIM
  tooltip:AddLine(" ")
  tooltip:AddLine(out.title .. (out.note and (" " .. dim .. out.note .. "|r") or ""), t[1], t[2], t[3])
  if out.message then tooltip:AddLine(out.message, d[1], d[2], d[3], true) end
  for _, row in ipairs(out.rows) do
    local text, c = self:moneyText(row.money), { 1, 1, 1 }
    if row.sign then
      text = (row.money < 0 and "-" or "+") .. text
      c = row.money < 0 and TooltipHook.LOSS or TooltipHook.GAIN
    end
    tooltip:AddDoubleLine(row.label, text, l[1], l[2], l[3], c[1], c[2], c[3])
  end
  if out.hint then tooltip:AddLine(out.hint, d[1], d[2], d[3]) end
  tooltip:Show()
end

-- Only the main tooltip and a clicked link's: the comparison tooltips would repeat the block.
function TooltipHook:wanted(tooltip)
  local env = self.env
  return tooltip ~= nil and (tooltip == env.GameTooltip or tooltip == env.ItemRefTooltip)
end

-- The lines for link, kept for a second: a bag item's tooltip is drawn again several times a second.
function TooltipHook:linesFor(link, opts, main)
  local env, prices = self.env, self.addon.prices
  local stamp = table.concat({ link, tostring(try(env.GetServerTime) or 0), tostring(main),
    tostring(try(env.IsShiftKeyDown) and true or false), tostring(self:bagCount(link)),
    tostring(prices and prices.version and prices:version(ns.AuctionAPI and ns.AuctionAPI.currentMarket(env))),
    tostring(opts.show), tostring(opts.disenchant), tostring(opts.paid), tostring(opts.shift) }, "\31")
  local cache = self.cache
  if cache and cache.stamp == stamp then return cache.out end
  local item = self:gather(link, opts, main)
  local out = item and ns.TooltipPrices.lines(item, opts)
  self.cache = not (item and item.loading) and { stamp = stamp, out = out } or nil
  return out
end

function TooltipHook:onItem(tooltip)
  if not self:wanted(tooltip) or tooltip.GetItem == nil then return end
  -- A bug here must never break the game's tooltips: it costs only Better AH's lines.
  local ok, err = pcall(function()
    local opts = self:options()
    if not opts.show then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    local out = self:linesFor(link, opts, tooltip == self.env.GameTooltip)
    if out then self:draw(tooltip, out) end
  end)
  if not ok and ns.debugLog and ns.debugLog.add then
    pcall(ns.debugLog.add, ns.debugLog, "tooltip", "error: %s", tostring(err))
  end
end

-- Shift pressed or let go over an item: draw the tooltip again, with or without the bag totals.
function TooltipHook:refresh()
  local tip = self.env.GameTooltip
  if not (tip and tip:IsShown() and tip.GetItem and tip:GetItem()) then return end
  local opts = self:options()
  if not (opts.show and opts.shift) then return end
  if tip.RefreshData then
    try(tip.RefreshData, tip)
    return
  end
  local owner = tip.GetOwner and tip:GetOwner()
  local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
  if enter then try(enter, owner) end
end

function TooltipHook.install(env, addon)
  local hook = TooltipHook.new(env, addon)
  addon.tooltipHook = hook
  local processor, kinds = env.TooltipDataProcessor, env.Enum and env.Enum.TooltipDataType
  if processor and processor.AddTooltipPostCall and kinds and kinds.Item then
    processor.AddTooltipPostCall(kinds.Item, function(tooltip) hook:onItem(tooltip) end)
  elseif env.GameTooltip and env.GameTooltip.HookScript then
    for _, tip in ipairs({ env.GameTooltip, env.ItemRefTooltip }) do
      if tip then tip:HookScript("OnTooltipSetItem", function(t) hook:onItem(t) end) end
    end
  end
  local events = env.CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "MODIFIER_STATE_CHANGED")
  pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
  events:SetScript("OnEvent", function(_, event, key)
    if event == "MODIFIER_STATE_CHANGED" then
      if key == "LSHIFT" or key == "RSHIFT" then hook:refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" and addon.purchases then
      addon.purchases:prune(try(env.GetServerTime) or 0)
    end
  end)
  return hook
end

ns.TooltipHook = TooltipHook
if CreateFrame then TooltipHook.install(_G, ns) end
return TooltipHook
