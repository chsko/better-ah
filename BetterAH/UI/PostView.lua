-- The Post view (spec #8): the post queue, the one-click Post button, and the detail panel that explains
-- each item's price and edits its posting profile and floor price. The rules live in Core/Posting.lua and
-- Core/PostQueue.lua, the game calls in Game/PostingAPI.lua; this file only draws and wires them.
-- Layout follows the mockup linked from issue #8.
local _, ns = ...
ns = ns or {}

local PostView = {}
PostView.__index = PostView

PostView.COLUMNS = {
  { "Item", 4, 186 }, { "In bags", 192, 56 }, { "Post at", 250, 92 }, { "Floor", 344, 92 }, { "Status", 440, 96 },
}
PostView.FILTERS = { { "all", "All items" }, { "mats", "Disenchant mats" } }
PostView.FILTER_HEIGHT = 26
local DURATION_LABELS = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }
local DURATION_FALLBACK = { "2 hours", "8 hours", "24 hours" } -- Forever's, if the client gives no labels

local function money(copper)
  return copper and ns.Money.format(copper) or "-"
end

function PostView.durationLabel(env, index)
  local label = env[DURATION_LABELS[index] or ""]
  return type(label) == "string" and label ~= "" and label or DURATION_FALLBACK[index] or tostring(index)
end

-- The Status column for a row.
function PostView.statusText(row)
  local plan = row.plan
  if row.state == "checking" then return "Checking..." end
  if row.state == "failed" then return "Not checked" end
  if row.state == "setup" then return "Needs setup" end
  if row.state == "ready" then return string.format("Ready: %d x %d", plan.posts, plan.quantity) end
  if row.skipped == "you" then return "Skipped" end
  if row.skipped == "kept" then return "Leftover" end
  if plan.reason == "below-floor" then return "Below floor" end
  if plan.reason == "no-floor" then return "No market value" end
  return "None left"
end

local function matName(id)
  local m = ns.Disenchant and ns.Disenchant.BY_ID[id]
  return m and m.name or ("item " .. tostring(id))
end

local function percent(share)
  return string.format("%d%%", math.floor(share * 100 + 0.5))
end

-- Where a disenchant material's floor came from (a MatFloors.floor result).
function PostView.matFloorSource(mf)
  if mf.convert then
    local c = mf.convert
    if c.ratio < 1 then
      return string.format("a third of %s's floor of %s, since three of these make one", matName(c.id),
        money(c.floor))
    end
    return string.format("three times %s's floor of %s, since this splits into three", matName(c.id),
      money(c.floor))
  end
  if mf.source == "breakeven" then
    return string.format("%s of the %s market value: break-even for your snipes at a %s profit",
      percent(mf.share), money(mf.marketValue), percent(mf.profit))
  end
  return string.format("%s of the %s market value, the floor rule for all mats", percent(mf.share),
    money(mf.marketValue))
end

local function floorSource(ownFloor, marketValue, matFloor)
  if ownFloor then return "your own floor" end
  if matFloor then return PostView.matFloorSource(matFloor) end
  return string.format("%d%% of the %s market value", ns.Posting.FLOOR_SHARE * 100, money(marketValue))
end

-- The detail panel text for a row. ownFloor and marketValue explain where the floor came from; step is
-- the client's price step (100 when prices go in whole silver).
function PostView.detailText(row, ownFloor, marketValue, step)
  local plan = row.plan
  if row.state == "checking" then return "Looking up the current listings..." end
  if row.state == "failed" then return "Couldn't check the price: " .. tostring(row.reason) .. "." end
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  local under = step and step >= 100 and "a silver" or "1 copper"
  if row.skipped == "you" then
    add("You skipped this item. It stays in your bags until you next open the auction house.")
  elseif row.skipped == "kept" then
    add("These are the leftovers from posting this item, too few for a full stack. They stay in your bags "
      .. "until you next open the auction house.")
  elseif plan.reason == "none-left" then
    add("None left in your bags.")
  elseif plan.reason == "no-floor" then
    add("There is no market value for this item yet: "
      .. (plan.price and "too few other listings to judge a price from" or "nobody else has it listed")
      .. ", and no scan has seen it in the last 14 days. So there is no floor price to protect you. "
      .. "Set a floor price below to post it.")
  elseif plan.reason == "below-floor" then
    add(string.format("Posting under the cheapest other listing would take it to %s, below your floor of %s (%s), "
      .. "so it stays in your bags.", money(plan.price), money(plan.floor),
      floorSource(ownFloor, marketValue, row.matFloor)))
    local c = not ownFloor and row.matFloor and row.matFloor.convert
    if c and c.ratio < 1 and (row.have or 0) >= 3 then
      add("")
      add(string.format("Combine them in threes into %s instead.", matName(c.id)))
    end
  else
    if row.state == "setup" then
      add("This is the first time you post this item. Choose a stack size and duration below; "
        .. "Better AH remembers them.")
      add("")
    end
    if plan.undercut then
      add(string.format("The cheapest other listing is %s each, so this posts at %s, %s under it.",
        money(math.ceil(plan.undercut)), money(plan.price), under))
    else
      add(string.format("Nobody else is selling this, so it posts at %s.", money(plan.price)))
    end
    add(string.format("Your floor is %s (%s).", money(plan.floor), floorSource(ownFloor, marketValue, row.matFloor)))
    if row.state == "ready" then
      add("")
      local stacks = plan.posts == 1 and "1 stack" or (plan.posts .. " stacks")
      add(string.format("%s of %d post%s.", stacks, plan.quantity, plan.posts == 1 and "s" or ""))
      if plan.remainder > 0 then add(string.format("The %d left over stay in your bags.", plan.remainder)) end
    end
  end
  return table.concat(lines, "\n")
end

-- window: the Window this view lives in (frame, detail panel, buildRows); addon: the namespace.
function PostView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, offset = 0 }, PostView)
end

function PostView:build(f, x, y, width, height)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.panel = panel

  -- Which items to show (#71): all of them, or the disenchant materials only.
  self.filterButtons = {}
  for i, filter in ipairs(PostView.FILTERS) do
    local b = ns.Window.entryButton(env, panel, 140)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * 144, 0)
    b:SetScript("OnClick", function() self:setFilter(filter[1]) end)
    self.filterButtons[filter[1]] = b
  end
  ns.Window.tooltip(env, self.filterButtons.mats, "Disenchant mats",
    "Show and post only the 24 disenchant materials. Post next and Skip skip everything else.")
  local rule = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  rule:SetSize(110, 20)
  rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, 0)
  rule:SetText("Floor rule")
  rule:SetScript("OnClick", function() self:showRule() end)
  ns.Window.tooltip(env, rule, "Floor rule", "How the floor price of every disenchant material is worked out.")
  self.ruleButton = rule

  -- The list sits below the filter row, as the Disenchant view's tabs sit above theirs.
  local list = env.CreateFrame("Frame", nil, panel)
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -PostView.FILTER_HEIGHT)
  list:SetSize(width, height - PostView.FILTER_HEIGHT)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 3) end)
  self.list = list

  local status = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6)
  status:SetWidth(width)
  status:SetJustifyH("LEFT")
  self.status = status
  self.loading = ns.Loading.attach(env, list, status, { "TOPLEFT", list, "TOPLEFT", 0, -6, width })
  self.rows = self.window:buildRows(list, PostView.COLUMNS, function(index) self:selectRow(index) end,
    function(offset) self.offset = offset; self:render() end)

  local post = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  post:SetSize(width - 96, 26)
  post:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
  post:SetScript("OnClick", function() self:postNext() end)
  self.postButton = post
  local skip = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  skip:SetSize(90, 26)
  skip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  skip:SetText("Skip")
  skip:SetScript("OnClick", function() self:skipNext() end)
  ns.Window.tooltip(env, skip, "Skip", "Leave the item the Post button would post next in your bags until you next "
    .. "open the auction house.")
  self.skipButton = skip

  self:buildEditor()
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function() self:refresh() end)
  pcall(self.events.RegisterEvent, self.events, "BAG_UPDATE_DELAYED")
  return panel
end

-- Posting profile and floor price fields, under the detail text.
function PostView:buildEditor()
  local env, w = self.env, self.window
  -- On the detail panel's text layer, so the fields draw above the panel art.
  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  box:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  box:SetSize(196, 150)
  self.editor = box

  local function label(text, y)
    local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    l:SetText(text)
    return l
  end
  local function input(y, x)
    local e = env.CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    e:SetSize(70, 20)
    e:SetPoint("TOPLEFT", box, "TOPLEFT", x or 6, y)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    return e
  end
  local function button(text, width, y, x, onClick)
    local b = env.CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetPoint("TOPLEFT", box, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  self.profileLabel = label("Posting profile", 0)
  self.stackLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.stackLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -20)
  self.stackLabel:SetText("Stack size")
  self.stackInput = input(-16, 70)
  self.stackInput:SetNumeric(true)
  self.stackInput:SetScript("OnEnterPressed", function() self:saveProfile() end)
  self.durationButtons = {}
  for i = 1, 3 do
    self.durationButtons[i] = button(PostView.durationLabel(env, i), 64, -42, (i - 1) * 66, function()
      self.duration = i
      self:renderEditor()
    end)
  end
  self.saveButton = button("Save", 64, -66, 0, function() self:saveProfile() end)
  ns.Window.tooltip(env, self.saveButton, "Save posting profile",
    "Remember this stack size and duration for this item. You can change them later here.")

  self.floorLabel = label("Floor price", -96)
  self.floorInput = input(-112)
  self.floorInput:SetScript("OnEnterPressed", function() self:saveFloor() end)
  self.floorButton = button("Set floor", 80, -112, 84, function() self:saveFloor() end)
  ns.Window.tooltip(env, self.floorButton, "Set floor",
    "The lowest price per item you'll sell for on this market, like 20s or 1g 5s. Leave it empty to use "
    .. "80% of market value, or for a disenchant material the floor rule for all mats.")
  self:buildRuleEditor()
  self.editorStatus = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.editorStatus:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -136)
  self.editorStatus:SetWidth(196)
  self.editorStatus:SetJustifyH("LEFT")
  box:Hide()
end

-- The floor rule for all disenchant materials (#71), on the detail panel when Floor rule is pressed.
function PostView:buildRuleEditor()
  local env, w = self.env, self.window
  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  box:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  box:SetSize(196, 110)
  self.ruleEditor = box
  local function check(y, text, onClick, tip)
    local c = env.CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", box, "TOPLEFT", -4, y)
    c:SetScript("OnClick", onClick)
    local label = c.Text
    if not label then
      label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    end
    label:SetWidth(170)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    c.label = label
    ns.Window.tooltip(env, c, text, tip)
    return c
  end
  self.ruleBreakEven = check(0, "Break-even for my snipes", function() self:saveRule("kind", "breakeven") end,
    "Never sell a material for less than your snipes paid for it: the share of market value your "
    .. "smallest snipe profit leaves.")
  self.rulePercent = check(-26, "", function()
    -- A percent typed but not entered yet counts too.
    local typed = self.rulePercentInput:GetText()
    if typed ~= "" then self:saveRule("percent", typed) end
    self:saveRule("kind", "percent")
  end, "A fixed share of each material's market value.")
  ns.Window.tooltip(env, self.rulePercent, "Percent of market value", "A fixed share of each material's market value.")
  local input = env.CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  input:SetSize(40, 20)
  input:SetPoint("LEFT", self.rulePercent, "RIGHT", 6, 0)
  input:SetAutoFocus(false)
  input:SetNumeric(true)
  input:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
  input:SetScript("OnEnterPressed", function(edit)
    edit:ClearFocus()
    if self:saveRule("percent", edit:GetText()) then
      self:saveRule("kind", "percent")
      self.ruleStatus:SetText("")
    else
      self.ruleStatus:SetText("Type a whole percent from 1 to 1000.")
      self:render()
    end
  end)
  self.rulePercentInput = input
  local suffix = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  suffix:SetPoint("LEFT", input, "RIGHT", 4, 0)
  suffix:SetText("% of market value")
  self.ruleConvert = check(-56, "Never under what the essence converts to", function(c)
    self:saveRule("convert", c:GetChecked() and true or false)
  end, "Three lesser essences make a greater one, and a greater splits into three lesser. So a lesser never "
    .. "sells under a third of the greater's floor, and a greater never under three lessers'.")
  self.ruleStatus = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.ruleStatus:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -86)
  self.ruleStatus:SetWidth(196)
  self.ruleStatus:SetJustifyH("LEFT")
  self.ruleStatus:SetText("")
  box:Hide()
end

-- Saves part of the floor rule and redraws. Returns whether it took the value.
function PostView:saveRule(field, value)
  local settings = self.addon.posting
  if not (settings and settings.setMatRule) then return false end
  local ok = settings:setMatRule(field, value)
  if ok then self:dropConfirm() end
  self:render()
  return ok
end

-- Shows the floor rule on the detail panel, in place of an item.
function PostView:showRule()
  self.selected, self.ruleShown = nil, true
  self.ruleStatus:SetText("")
  self:render()
end

function PostView:setFilter(filter)
  local settings = self.addon.posting
  if settings and settings.setFilter then settings:setFilter(filter) end
  self.offset = 0
  self:dropConfirm()
  if self.queue then self.queue:setFilter(filter) end
  self:refresh()
  self:render()
end

function PostView:filter()
  local settings = self.addon.posting
  return settings and settings.filter and settings:filter() or "all"
end

-- The sniped targets and their bands' worth, for the break-even floor.
function PostView:targets()
  local d = self.addon.disenchant
  return d and d.targets or {}
end

-- What one green of the target's band is worth after the cut, from this market's prices. For the
-- break-even the highest of its classes counts: the snipe pays against each class's own worth, so
-- the class worth most leaves the smallest profit share. Band values are worked out once a second.
function PostView:targetWorth(target)
  local D = ns.DisenchantView
  if not (D and D.rows and D.options) then return nil end
  local now, key = self:now(), self.key
  if not (self.bands and self.bands.now == now and self.bands.key == key) then
    local list = D.rows(function(id) return self:marketValue("i:" .. id) end, D.options(self.addon))
    self.bands = { now = now, key = key, list = list }
  end
  for _, row in ipairs(self.bands.list) do
    if row.band.min == target.band then
      local worth
      for class in pairs(ns.Targets.classes(target)) do
        local net = row[class] and row[class].net
        if net and (not worth or net > worth) then worth = net end
      end
      return worth
    end
  end
  return nil
end

-- A disenchant material's floor from the rule (a MatFloors.floor result), or nil for other items.
function PostView:matFloor(item)
  local settings = self.addon.posting
  if not (ns.MatFloors and settings and settings.matRule) then return nil end
  return ns.MatFloors.floor(item, settings:matRule(), function(id) return self:marketValue("i:" .. id) end,
    self:targets(), function(t) return self:targetWorth(t) end)
end

-- The detail text while the floor rule shows.
function PostView:ruleText()
  local settings = self.addon.posting
  local rule = settings:matRule()
  local share, source, profit = ns.MatFloors.share(rule, self:targets(), function(t) return self:targetWorth(t) end)
  local lines = { "Every disenchant material's floor comes from this rule, unless you set the material's own." }
  lines[#lines + 1] = ""
  if rule.kind == "breakeven" and source == "breakeven" then
    lines[#lines + 1] = string.format("Your smallest snipe profit is %s, so your snipes break even when their "
      .. "materials sell for %s of market value. That is the floor.", percent(profit), percent(share))
  elseif rule.kind == "breakeven" then
    lines[#lines + 1] = string.format("No snipe target to break even on, so the floor is %s of market value.",
      percent(share))
  else
    lines[#lines + 1] = string.format("The floor is %s of market value.", percent(share))
  end
  return table.concat(lines, "\n")
end

function PostView:renderRule()
  local shown = self.ruleShown and not self.selected and self.addon.posting ~= nil and ns.MatFloors ~= nil
  self.ruleEditor:SetShown(shown and true or false)
  if not shown then return false end
  local rule = self.addon.posting:matRule()
  self.ruleBreakEven:SetChecked(rule.kind == "breakeven")
  self.rulePercent:SetChecked(rule.kind == "percent")
  local typing = self.rulePercentInput.HasFocus and self.rulePercentInput:HasFocus()
  if not typing and (self.ruleStatus:GetText() or "") == "" then
    self.rulePercentInput:SetText(tostring(rule.percent))
  end
  self.ruleConvert:SetChecked(rule.convert)
  local w = self.window
  w.detailTitle:SetText("Floor rule for all mats")
  w.detailBody:SetText(self:ruleText())
  return true
end

-- The market key and its parts (both, so no "and" here: that would keep only the key).
function PostView:market()
  if not ns.AuctionAPI then return nil end
  return ns.AuctionAPI.currentMarket(self.env)
end

function PostView:now()
  local api = self.addon.auctionAPI
  return api and api:now() or 0
end

function PostView:marketValue(item)
  local prices, key = self.addon.prices, self.key
  return prices and key and prices:marketValue(key, item, self:now()) or nil
end

-- Called when the view is shown: a fresh queue for this visit, then look up each item.
function PostView:open()
  local key, parts = self:market()
  local api = self.addon.postingAPI
  self.key = key
  -- Floors set before rulesets had names were kept under the numbered key (ADR 0005).
  local settings = self.addon.posting
  if key and settings and type(parts) == "table" and not parts.ruleset:match("^%d+$") then
    settings:adoptFloors(ns.MarketKey.build({ realm = "", ruleset = "1", faction = parts.faction }), key)
  end
  self.queue = ns.PostQueue.new({
    settings = self.addon.posting, key = key, step = api and ns.PostingAPI.priceStep(self.env) or 1,
    marketValue = function(item) return self:marketValue(item) end,
    matFloor = function(item) return self:matFloor(item) end,
  })
  self.queue.filter = self:filter()
  self.ruleShown = nil
  self.selected, self.offset, self.message, self.searching, self.busy = nil, 0, nil, {}, nil
  self.recorded = {}
  self:dropConfirm()
  if api then
    api.onPosted = function(ok) self:posted(ok) end
    -- Blizzard's window shows its own confirmation popup too; ours is the Confirm button.
    api.onPostWarning = function()
      if self.confirming and type(self.env.StaticPopup_Hide) == "function" then
        pcall(self.env.StaticPopup_Hide, "AUCTION_HOUSE_POST_WARNING")
      end
    end
  end
  self:refresh()
end

-- Called whenever the view is shown: a new queue on the first showing of each auction house visit.
function PostView:show()
  if self.queue then self:refresh() else self:open() end
end

-- The auction house closed: the next visit starts a new queue (and forgets skipped items).
function PostView:reset()
  self:dropConfirm()
  self.queue, self.busy = nil, nil
  if self.editor then self.editor:Hide() end
  if self.ruleEditor then self.ruleEditor:Hide() end
end

-- Forget a post the client asked to confirm: the item, its price or the settings changed.
function PostView:dropConfirm()
  self.confirming = nil
  local api = self.addon.postingAPI
  if api then api.pending = nil end
end

-- Re-reads the bags and looks up any item not looked up yet (or whose lookup failed).
function PostView:refresh()
  if not (self.queue and self.panel and self.panel:IsShown()) then return end
  -- A post is done once the game took it and the bags show it gone.
  if self.busy and self.busy.posted then self.busy = nil end
  local api = self.addon.postingAPI
  local entries, why = ns.PostingAPI.readBags(self.env)
  self.unavailable = not entries and why or nil
  local need = self.queue:setEntries(entries or {})
  if api then
    for _, e in ipairs(need) do
      if not self.searching[e.item] then
        self.searching[e.item] = true
        local queue = self.queue
        api:search(e, function(listings, reason)
          if queue ~= self.queue then return end -- from an earlier visit
          self.searching[e.item] = nil
          -- What the search saw counts toward the item's market value (reason is true for full results).
          local prices = self.addon.prices
          -- Once per item per visit, so re-checks between posts don't outweigh the day's other points.
          -- Not for gear with a random suffix: its search sees one variant, but prices are per item ID.
          local key = e.itemKey
          local variant = not e.commodity and type(key) == "table" and (key.itemSuffix or 0) ~= 0
          if listings and reason == true and prices and self.key and not variant and not self.recorded[e.item] then
            -- Only once it counted, so a later check that sees more listings can still count.
            self.recorded[e.item] = prices:recordSearch(self.key, self:now(), e.item, listings, e.name) or nil
          end
          if listings then queue:setListings(e.item, listings) else queue:setListings(e.item, nil, reason) end
          self:render()
        end)
      end
    end
  end
  self:render()
end

function PostView:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function PostView:selectRow(r)
  local row = self.shown and self.shown[r + self.offset]
  if not row then return end
  self.selected = row.item
  self.ruleShown = nil
  self.duration = nil
  local profile = self.addon.posting and self.addon.posting:profile(row.item)
  local suggested = row.plan and row.plan.suggested
  self.stackInput:SetText(tostring(profile and profile.stack or suggested and suggested.stack or ""))
  local floor = self.addon.posting and self.addon.posting:floor(self.key, row.item)
  self.floorInput:SetText(floor and ns.Money.format(floor) or "")
  self.editorStatus:SetText("")
  self:render()
end

function PostView:selectedRow()
  for _, row in ipairs(self.shown or {}) do
    if row.item == self.selected then return row end
  end
  return nil
end

function PostView:saveProfile()
  local row, settings = self:selectedRow(), self.addon.posting
  if not (row and settings) then return end
  local profile = settings:profile(row.item)
  local duration = self.duration or profile and profile.duration or ns.Posting.DEFAULT_DURATION
  if settings:setProfile(row.item, self.stackInput:GetText(), duration) then
    self:dropConfirm()
    self.stackInput:ClearFocus()
    self.editorStatus:SetText("Saved.")
  else
    self.editorStatus:SetText("Stack size must be a whole number of 1 or more.")
  end
  self:render()
end

function PostView:saveFloor()
  local row, settings = self:selectedRow(), self.addon.posting
  if not (row and settings) then return end
  if not self.key then
    self.editorStatus:SetText("Can't tell which market this is yet, so the floor can't be saved.")
    return
  end
  local text = self.floorInput:GetText() or ""
  local copper = text:match("^%s*$") and 0 or ns.Money.parse(text)
  if copper and settings:setFloor(self.key, row.item, copper) then
    self:dropConfirm()
    self.floorInput:ClearFocus()
    self.floorInput:SetText(copper > 0 and ns.Money.format(copper) or "")
    local back = ns.MatFloors and ns.MatFloors.material(row.item) and "the floor rule for all mats"
      or "80% of market value"
    self.editorStatus:SetText(copper == 0 and "Floor set back to " .. back .. "."
      or "Floor set to " .. ns.Money.format(copper) .. ".")
  else
    self.editorStatus:SetText("Type a price like 20s or 1g 5s, or leave it empty.")
  end
  self:render()
end

-- The Post button: post the next ready item (or confirm the post the client asked about). One click
-- is one auction, because the game needs a click for every post.
function PostView:postNext()
  local api = self.addon.postingAPI
  if not (api and self.queue) then return end
  if self.busy then return end
  local result, why, row
  if self.confirming then
    row = self.confirming
    result, why = api:confirm()
    self.confirming = nil
  else
    row = self.queue:nextPost()
    if not row then return end
    result, why = api:post(row.entry, row.plan)
    if result == "confirm" then self.confirming = row end
  end
  if result == "sent" then
    self.message = nil
    -- Wait for the game and the bags before the next post, so it never posts from a stale row.
    local busy = { item = row.item }
    self.busy = busy
    self.queue:sent(row.item, row.plan)
    local timer = self.env.C_Timer
    if timer and timer.After then
      timer.After(5, function()
        if self.busy == busy then
          self.busy = nil
          self:refresh()
        end
      end)
    end
  elseif result ~= "confirm" then
    self.message = why
    self:refresh()
  end
  self:render()
end

function PostView:skipNext()
  local row = self.confirming or (self.queue and self.queue:nextPost())
  if not row then return end
  self.confirming = nil
  self.queue:skip(row.item)
  self:render()
end

function PostView:posted(ok)
  self:dropConfirm()
  local busy = self.busy
  if busy and self.queue then
    -- Look the item up again before its next post: someone may have undercut it meanwhile.
    self.queue:forget(busy.item)
    busy.posted = true
  end
  if not ok then
    self.message = "The auction house didn't take that post. Check the chat for why."
    self.busy = nil
  end
  self:refresh()
end

function PostView:renderEditor(row)
  row = row or self:selectedRow()
  local editable = row and row.state ~= "checking" and row.state ~= "failed" and self.addon.posting
  self.editor:SetShown(editable and true or false)
  if not editable then return end
  local profile = self.addon.posting:profile(row.item)
  if (self.stackInput:GetText() or "") == "" then
    local suggested = row.plan and row.plan.suggested
    local stack = profile and profile.stack or suggested and suggested.stack
    if stack then self.stackInput:SetText(tostring(stack)) end
  end
  local current = self.duration or profile and profile.duration or ns.Posting.DEFAULT_DURATION
  for i, b in ipairs(self.durationButtons) do
    if i == current then b:LockHighlight() else b:UnlockHighlight() end
  end
end

function PostView:render()
  -- The detail panel is shared with the other views: draw only while the Post view is on screen.
  if not (self.panel and self.queue and self.panel:IsShown()) then return end
  local rows = self.queue:rows()
  self.shown = rows
  local done, total = self.queue:progress()
  if not self.unavailable and done < total then self.loading:show(done, total) else self.loading:clear() end
  if self.unavailable then
    self.status:SetText("Posting isn't available on this client: " .. self.unavailable .. ".")
  elseif total == 0 then
    self.status:SetText(self.queue.filter == "mats" and "No disenchant materials in your bags."
      or "Nothing in your bags can be posted.")
  elseif done < total then
    self.status:SetText(string.format("Checking prices: %d of %d items", done, total))
  else
    local mats = self.queue.filter == "mats"
    self.status:SetText(self.message or string.format("%d %s in your bags.", total,
      mats and (total == 1 and "disenchant material" or "disenchant materials") or (total == 1 and "item" or "items")))
  end
  local mats, all = self.queue:counts()
  self.ruleButton:SetShown(self.queue.filter == "mats" and ns.MatFloors ~= nil)
  if self.queue.filter ~= "mats" then self.ruleShown = nil end
  for id, b in pairs(self.filterButtons) do
    ns.Window.markSelected(b, id == self.queue.filter)
    b:SetText(string.format("%s (%d)", id == "mats" and "Disenchant mats" or "All items", id == "mats" and mats or all))
  end
  local ROWS = #self.rows
  self.offset = math.max(0, math.min(self.offset, math.max(0, #rows - ROWS)))
  ns.Window.syncScrollBar(self.rows.scrollBar, self.offset, #rows)
  for r, cells in ipairs(self.rows) do
    local row = rows[r + self.offset]
    if row then
      local plan = row.plan or {}
      cells[1]:SetText(row.name or row.item)
      cells[2]:SetText(tostring(row.have))
      cells[3]:SetText(plan.price and (row.state == "ready" or row.state == "setup") and money(plan.price) or "")
      cells[4]:SetText(plan.floor and money(plan.floor) or "")
      cells[5]:SetText(PostView.statusText(row))
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.item == self.selected)
  end

  -- A confirmation only stands while the item still plans the same post.
  if self.confirming then
    local now = self.queue:row(self.confirming.entry)
    local a, b = self.confirming.plan, now.plan
    if now.state ~= "ready" or a.price ~= b.price or a.quantity ~= b.quantity then self:dropConfirm() end
  end
  local nextRow = self.confirming or self.queue:nextPost()
  if self.busy then
    self.postButton:SetText("Posting...")
    self.postButton:Disable()
  elseif self.confirming then
    self.postButton:SetText(string.format("Confirm post: %s, %d for %s each", nextRow.name or nextRow.item,
      nextRow.plan.quantity, money(nextRow.plan.price)))
    self.postButton:Enable()
  elseif nextRow then
    local plan = nextRow.plan
    self.postButton:SetText(string.format("Post next: %s, %d for %s each", nextRow.name or nextRow.item,
      plan.quantity, money(plan.price)))
    self.postButton:Enable()
  else
    self.postButton:SetText(done < total and "Checking prices..." or "Nothing ready to post")
    self.postButton:Disable()
  end
  if nextRow then self.skipButton:Enable() else self.skipButton:Disable() end

  local w, selected = self.window, self:selectedRow()
  if not selected and self:renderRule() then
    self.editor:Hide()
    return
  end
  if selected then
    w.detailTitle:SetText(selected.name or selected.item)
    local own = self.addon.posting and self.addon.posting:floor(self.key, selected.item)
    w.detailBody:SetText(PostView.detailText(selected, own, self:marketValue(selected.item), self.queue.step))
    self.ruleEditor:Hide()
  else
    self.selected = nil
    w.detailTitle:SetText("")
    w.detailBody:SetText(total > 0 and "Select an item to see how its price was worked out, or to change its "
      .. "stack size, duration and floor price." or "")
    self.ruleEditor:Hide()
  end
  self:renderEditor(selected)
end

ns.PostView = PostView
return PostView
