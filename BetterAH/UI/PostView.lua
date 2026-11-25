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

local function floorSource(ownFloor, marketValue)
  if ownFloor then return "your own floor" end
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
    add("There is no market value for this item yet, so there is no floor price to protect you. "
      .. "Scan the auction house first, or set a floor price below.")
  elseif plan.reason == "below-floor" then
    add(string.format("Posting under the cheapest other listing would take it to %s, below your floor of %s (%s), "
      .. "so it stays in your bags.", money(plan.price), money(plan.floor), floorSource(ownFloor, marketValue)))
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
    add(string.format("Your floor is %s (%s).", money(plan.floor), floorSource(ownFloor, marketValue)))
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

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -6)
  status:SetWidth(width)
  status:SetJustifyH("LEFT")
  self.status = status
  self.rows = self.window:buildRows(panel, PostView.COLUMNS, function(index) self:selectRow(index) end)

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
    .. "80% of market value.")
  self.editorStatus = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.editorStatus:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -136)
  self.editorStatus:SetWidth(196)
  self.editorStatus:SetJustifyH("LEFT")
  box:Hide()
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
  })
  self.selected, self.offset, self.message, self.searching, self.busy = nil, 0, nil, {}, nil
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
    self.editorStatus:SetText(copper == 0 and "Floor set back to 80% of market value."
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
  if self.unavailable then
    self.status:SetText("Posting isn't available on this client: " .. self.unavailable .. ".")
  elseif total == 0 then
    self.status:SetText("Nothing in your bags can be posted.")
  elseif done < total then
    self.status:SetText(string.format("Checking prices: %d of %d items", done, total))
  else
    self.status:SetText(self.message or string.format("%d %s in your bags.", total, total == 1 and "item" or "items"))
  end
  local ROWS = #self.rows
  self.offset = math.max(0, math.min(self.offset, math.max(0, #rows - ROWS)))
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
  if selected then
    w.detailTitle:SetText(selected.name or selected.item)
    local own = self.addon.posting and self.addon.posting:floor(self.key, selected.item)
    w.detailBody:SetText(PostView.detailText(selected, own, self:marketValue(selected.item), self.queue.step))
  else
    self.selected = nil
    w.detailTitle:SetText("")
    w.detailBody:SetText(total > 0 and "Select an item to see how its price was worked out, or to change its "
      .. "stack size, duration and floor price." or "")
  end
  self:renderEditor(selected)
end

ns.PostView = PostView
return PostView
