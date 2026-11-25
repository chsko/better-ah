-- A tiny fake of the WoW frame API: enough to drive the UI adapters in specs.
local M = {}

local Frame = {}
Frame.__index = Frame

local function newFrame(kind, name, parent, template)
  return setmetatable({
    kind = kind, name = name, parent = parent, template = template,
    shown = true, alpha = 1, scale = 1, mouse = true, scripts = {}, events = {},
    highlighted = false, text = nil,
  }, Frame)
end

function Frame:SetSize() end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:SetPoint() end
function Frame:ClearAllPoints() end
function Frame:SetFrameStrata() end
function Frame:SetMovable() end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:SetClampedToScreen() end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:EnableMouseWheel() end
function Frame:SetWidth() end
function Frame:SetJustifyH() end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:LockHighlight() self.highlighted = true end
function Frame:SetAutoFocus() end
function Frame:SetNumeric(on) self.numeric = on end
-- Focus, like the client: gaining and losing it run the box's scripts.
function Frame:SetFocus()
  if self.focused then return end
  self.focused = true
  if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
end
function Frame:HasFocus() return self.focused == true end
function Frame:ClearFocus()
  if not self.focused then return end
  self.focused = false
  if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function Frame:UnlockHighlight() self.highlighted = false end
function Frame:IsShown() return self.shown end
function Frame:Show()
  if self.shown then return end
  self.shown = true
  if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
  if not self.shown then return end
  self.shown = false
  if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:CreateFontString() return newFrame("FontString") end
function Frame:CreateTexture(_, layer)
  local t = newFrame("Texture")
  t.layer = layer
  self.textures = self.textures or {}
  self.textures[#self.textures + 1] = t
  return t
end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:SetAllPoints() end
function Frame:SetSpacing() end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetBlendMode() end
function Frame:SetColorTexture(...) self.color = { ... } end
function Frame:SetFontObject(font) self.font = font end
function Frame:SetFontString(fs) self.fontString = fs end
function Frame:GetFontString() return self.fontString end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:SetChecked(on) self.checked = on and true or false end
function Frame:GetChecked() return self.checked == true end
-- Like the client, a click on a check button flips it before OnClick runs.
function Frame:Click()
  if self.kind == "CheckButton" then self.checked = not self.checked end
  if self.scripts.OnClick then self.scripts.OnClick(self) end
end

-- Blizzard's ScrollBarMixin, as much as the lists use: setting the scroll percentage fires OnScroll
-- (the client does that too, for the owner's own calls as well as the player's), and with
-- SetHideIfUnscrollable the bar hides while everything is visible. bar:drag(p) is the player moving it.
function M.scrollBar(f)
  f.scroll, f.visible, f.pan, f.callbacks = 0, 0, 0, {}
  function f.SetHideIfUnscrollable(bar, on)
    bar.hideIfUnscrollable = on
    if on then bar:SetShown(bar.visible > 0 and bar.visible < 1) end
  end
  function f.RegisterCallback(bar, event, fn, owner) bar.callbacks[event] = { fn, owner } end
  function f.SetPanExtentPercentage(bar, p) bar.pan = p end
  function f.SetVisibleExtentPercentage(bar, p)
    bar.visible = math.max(0, math.min(1, p))
    if bar.hideIfUnscrollable then bar:SetShown(bar.visible > 0 and bar.visible < 1) end
  end
  function f.GetVisibleExtentPercentage(bar) return bar.visible end
  function f.GetScrollPercentage(bar) return bar.scroll end
  function f.SetScrollPercentage(bar, p)
    bar.scroll = math.max(0, math.min(1, p))
    local cb = bar.callbacks.OnScroll
    if cb then cb[1](cb[2], bar.scroll) end
  end
  function f.drag(bar, p) bar:SetScrollPercentage(p) end
  -- A wheel notch over the bar, like ScrollControllerMixin (default scalar 2).
  function f.wheel(bar, delta) bar:SetScrollPercentage(bar.scroll - delta * bar.pan * (bar.wheelPanScalar or 2)) end
end

-- opts.template picks the shape of PortraitFrameTemplate's close button:
--   "forever" (default) like Forever's SharedUIPanelTemplates.xml: parent key CloseButton and global
--     $parentCloseButton
--   "named" with only the global name
--   "bare" with no close button at all
-- opts.missingArt lists atlases C_Texture.GetAtlasInfo doesn't know; opts.noAtlasInfo removes C_Texture.
function M.new(opts)
  opts = opts or {}
  local shape = opts.template or "forever"
  local env = { frames = {}, closed = 0, UISpecialFrames = {}, timers = {} }
  if not opts.noAtlasInfo then
    local missing = {}
    for _, atlas in ipairs(opts.missingArt or {}) do missing[atlas] = true end
    env.C_Texture = {
      GetAtlasInfo = function(atlas) if not missing[atlas] then return { width = 1, height = 1 } end end,
    }
  end
  env.UIParent = newFrame("Frame", "UIParent")
  -- Timers run once due. runTimers(seconds) moves the clock (env.now) forward
  -- by that many seconds, one second at a time, and runs every timer that is due.
  env.now = 1000000
  env.C_Timer = { After = function(delay, fn) env.timers[#env.timers + 1] = { at = env.now + delay, fn = fn } end }
  local function runDue()
    local ran = true
    while ran do
      ran = false
      for i, t in ipairs(env.timers) do
        if t.at <= env.now then
          table.remove(env.timers, i)
          t.fn()
          ran = true
          break
        end
      end
    end
  end
  env.runTimers = function(seconds)
    runDue()
    for _ = 1, seconds or 0 do
      env.now = env.now + 1
      runDue()
    end
  end
  env.CreateFrame = function(kind, name, parent, template)
    local f = newFrame(kind, name, parent, template)
    if template == "PortraitFrameTemplate" then
      f.SetTitle = function(frame, text) frame.title = text end
      f.SetPortraitToAsset = function(frame, path) frame.portrait = path end
      if shape ~= "bare" then
        local close = newFrame("Button", name and (name .. "CloseButton"), f)
        close:SetScript("OnClick", function() f:Hide() end)
        if name then env[name .. "CloseButton"] = close end
        if shape == "forever" then f.CloseButton = close end
      end
    end
    if template == "MinimalScrollBar" then M.scrollBar(f) end
    env.frames[#env.frames + 1] = f
    if name then env[name] = f end
    return f
  end
  -- Like the client: closing fires AUCTION_HOUSE_CLOSED once, and the
  -- client hides Blizzard's window, whose OnHide closes the AH again (a no-op).
  env.open = false
  env.CloseAuctionHouse = function()
    env.closed = env.closed + 1
    if not env.open then return end
    env.open = false
    env.fire("AUCTION_HOUSE_CLOSED")
    env.AuctionFrame:Hide()
  end
  -- Blizzard's legacy window, shown by the client on AUCTION_HOUSE_SHOW.
  env.AuctionFrame = newFrame("Frame", "AuctionFrame", env.UIParent)
  env.AuctionFrame.shown = false
  env.AuctionFrame:SetScript("OnHide", function() env.CloseAuctionHouse() end)
  env.openAuctionHouse = function()
    env.open = true
    env.AuctionFrame:Show()
    env.fire("AUCTION_HOUSE_SHOW")
    env.runTimers()
  end
  -- Escape: the client hides UI panels first, then UISpecialFrames.
  env.pressEscape = function()
    env.AuctionFrame:Hide()
    for _, name in ipairs(env.UISpecialFrames) do env[name]:Hide() end
  end
  -- Market identity, as the Forever client reported it (ADR 0004).
  env.GetServerTime = function() return env.now end
  env.GetRealmName = function() return "" end
  env.UnitFactionGroup = function() return env.faction or "Horde" end
  env.C_GameRules = { GetActiveGameMode = function() return env.gameMode or 1 end }
  -- Full scans: ReplicateItems answers on the next timer tick with env.auctions, unless
  -- env.replicateSilent is set. Each auction is { name, count, buyout, itemID, owner, hasAllInfo }.
  env.auctions = {}
  env.replicateCalls = 0
  env.C_AuctionHouse = {
    ReplicateItems = function()
      env.replicateCalls = env.replicateCalls + 1
      env.replicateReady = true
      if not env.replicateSilent then
        env.C_Timer.After(0, function() env.fire("REPLICATE_ITEM_LIST_UPDATE") end)
      end
    end,
    GetNumReplicateItems = function() return env.replicateReady and #env.auctions or 0 end,
    GetReplicateItemInfo = function(i)
      local a = env.auctions[i + 1]
      if not a then return nil end
      return a.name, nil, a.count, 1, true, 1, 0, 0, 0, a.buyout, 0, false, nil, a.owner, nil, 0, a.itemID,
        a.hasAllInfo ~= false
    end,
  }
  -- The player and their containers. env.containers[bag] is an array of slots, each nil (empty) or
  -- { itemID, count, name }. env.owned is the player's auctions: { itemID, quantity, status }.
  env.playerName = "Thrall"
  env.UnitName = function() return env.playerName end
  env.guid = "Player-6841-0A1B2C3D"
  env.UnitGUID = function() return env.guid end
  env.containers = { [0] = {} }
  env.C_Container = {
    GetContainerNumSlots = function(bag) return env.containers[bag] and #env.containers[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local it = env.containers[bag] and env.containers[bag][slot]
      if not it then return nil end
      return { itemID = it.itemID, stackCount = it.count, itemName = it.name, hyperlink = "", isBound = it.bound,
        isLocked = it.locked }
    end,
  }
  env.owned = {}
  env.ownedComplete = true
  env.C_AuctionHouse.HasFullOwnedAuctionResults = function() return env.ownedComplete end
  env.C_AuctionHouse.QueryOwnedAuctions = function()
    env.ownedQueries = (env.ownedQueries or 0) + 1
    env.C_Timer.After(0, function() env.fire("OWNED_AUCTIONS_UPDATED") end)
  end
  env.C_AuctionHouse.GetNumOwnedAuctions = function() return #env.owned end
  env.C_AuctionHouse.GetOwnedAuctionInfo = function(i)
    local a = env.owned[i]
    return a and { auctionID = i, itemKey = { itemID = a.itemID }, quantity = a.quantity, status = a.status or 0 }
  end
  -- Posting. A container slot can say { soulbound = true } (the AH refuses it) or { item = true } (not a
  -- commodity). env.listings[itemID] is what a search finds: commodity rows { unitPrice, quantity,
  -- numOwnerItems } or item rows { buyoutAmount, quantity, containsOwnerItem }. env.posts records posts.
  env.ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
  }
  local function slotAt(loc) return env.containers[loc.bag] and env.containers[loc.bag][loc.slot] end
  local ah = env.C_AuctionHouse
  ah.IsSellItemValid = function(loc) local it = slotAt(loc) return it and not it.soulbound or false end
  ah.MakeItemKey = function(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  end
  ah.GetItemKeyFromItem = function(loc)
    local it = slotAt(loc)
    return { itemID = it.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  end
  ah.GetItemCommodityStatus = function(loc)
    local it = slotAt(loc)
    if it.unknown then return 0 end
    return it.item and 1 or 2
  end
  env.throttled, env.copperValues = false, true
  ah.IsThrottledMessageSystemReady = function() return not env.throttled end
  ah.SupportsCopperValues = function() return env.copperValues end
  env.listings, env.searches, env.posts, env.searchSilent = {}, {}, {}, false
  env.fullResults = true
  ah.SendSearchQuery = function(itemKey, sorts, separateOwnerItems)
    env.searches[#env.searches + 1] = { itemKey = itemKey, sorts = sorts, separate = separateOwnerItems }
    if env.searchSilent or not env.open then return end
    env.C_Timer.After(0, function()
      local rows = env.listings[itemKey.itemID] or {}
      -- The client answers items with its own key, which can carry a level the query's key didn't.
      if rows.item then env.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = itemKey.itemID,
        itemLevel = rows.level or itemKey.itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 }) else
        env.fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemKey.itemID) end
    end)
  end
  ah.GetNumCommoditySearchResults = function(id) return #(env.listings[id] or {}) end
  ah.GetCommoditySearchResultInfo = function(id, i)
    local r = (env.listings[id] or {})[i]
    return r and { itemID = id, unitPrice = r.unitPrice, quantity = r.quantity, numOwnerItems = r.numOwnerItems or 0 }
  end
  ah.HasFullCommoditySearchResults = function() return env.fullResults end
  ah.GetNumItemSearchResults = function(key)
    local rows = env.listings[key.itemID] or {}
    if rows.level and key.itemLevel ~= rows.level then return 0 end
    return #rows
  end
  -- Item details: env.uncached[itemID] until C_Item.RequestLoadItemDataByID loads them.
  env.uncached = {}
  ah.GetItemKeyInfo = function(key)
    if env.uncached[key.itemID] then return nil end
    return { itemID = key.itemID, isCommodity = not (env.listings[key.itemID] or {}).item }
  end
  env.C_Item = { RequestLoadItemDataByID = function(id)
    if not env.uncached[id] then return end
    env.C_Timer.After(0, function()
      env.uncached[id] = nil
      env.fire("ITEM_KEY_ITEM_INFO_RECEIVED", id)
    end)
  end }
  ah.GetItemSearchResultInfo = function(key, i)
    local r = (env.listings[key.itemID] or {})[i]
    return r and { itemKey = key, buyoutAmount = r.buyoutAmount, quantity = r.quantity or 1,
      containsOwnerItem = r.containsOwnerItem or false, auctionID = r.auctionID, itemLink = r.itemLink }
  end
  ah.HasFullItemSearchResults = function() return env.fullResults end
  env.needsConfirmation = false
  -- Like the client, a post needs the item at the location; a warning asks for a confirmation.
  -- A post the client takes fires AUCTION_HOUSE_AUCTION_CREATED once the server answers.
  local function created() env.C_Timer.After(0, function() env.fire("AUCTION_HOUSE_AUCTION_CREATED", 1) end) end
  local function holds(loc)
    if not slotAt(loc) then error("item not found", 0) end
    if env.needsConfirmation then
      env.C_Timer.After(0, function() env.fire("AUCTION_HOUSE_POST_WARNING") end)
    else
      created()
    end
  end
  ah.PostCommodity = function(loc, duration, quantity, unitPrice, extra)
    assert(extra == nil, "PostCommodity takes four arguments")
    holds(loc)
    env.posts[#env.posts + 1] = { kind = "commodity", loc = loc, duration = duration, quantity = quantity,
      price = unitPrice }
    return env.needsConfirmation
  end
  ah.PostItem = function(loc, duration, quantity, bid, buyout)
    holds(loc)
    env.posts[#env.posts + 1] = { kind = "item", loc = loc, duration = duration, quantity = quantity, bid = bid,
      price = buyout }
    return env.needsConfirmation
  end
  ah.ConfirmPostCommodity = function(loc, duration, quantity, unitPrice)
    env.posts[#env.posts + 1] = { kind = "confirm commodity", loc = loc, duration = duration, quantity = quantity,
      price = unitPrice }
    created()
  end
  ah.ConfirmPostItem = function(loc, duration, quantity, _, buyout)
    env.posts[#env.posts + 1] = { kind = "confirm item", loc = loc, duration = duration, quantity = quantity,
      price = buyout }
    created()
  end
  -- Browsing: env.browseResults answer each SendBrowseQuery on the next tick, unless env.browseSilent.
  env.browseResults, env.browses = {}, {}
  ah.SendBrowseQuery = function(query)
    env.browses[#env.browses + 1] = query
    if env.browseSilent or not env.open then return end
    env.C_Timer.After(0, function() env.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
  end
  ah.GetBrowseResults = function() return env.browseResults end
  -- Buying: PlaceBid answers with AUCTION_HOUSE_PURCHASE_COMPLETED on the next tick, or with
  -- AUCTION_HOUSE_SHOW_ERROR when env.bidFails. env.money is the character's gold.
  env.bids, env.money = {}, 1000000
  ah.PlaceBid = function(auctionID, amount)
    env.bids[#env.bids + 1] = { auctionID = auctionID, amount = amount }
    env.C_Timer.After(0, function()
      if env.bidFails then
        env.fire("AUCTION_HOUSE_SHOW_ERROR", 1)
      else
        env.money = env.money - amount
        env.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
      end
    end)
  end
  env.GetMoney = function() return env.money end
  env.sounds = {}
  env.SOUNDKIT = { AUCTION_WINDOW_OPEN = 5274 }
  env.PlaySound = function(id) env.sounds[#env.sounds + 1] = id end
  -- Fire an event at every frame registered for it.
  env.fire = function(event, ...)
    for _, f in ipairs(env.frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
  end
  return env
end

return M
