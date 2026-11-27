-- Better AH's one drop-down (#189): Blizzard's own, as the game's Settings panel draws it. A button that
-- shows the current value (WowStyle2DropdownTemplate) opens a dark bordered list, the chosen entry in
-- yellow. Built on Blizzard_Menu (DropdownButton:SetupMenu and the menu descriptions it hands out), which
-- Forever ships in Interface/AddOns/Blizzard_Menu. Every drop-down in the addon goes through here, so they
-- all look and behave the same.
local _, ns = ...
ns = ns or {}

local Dropdown = {}

Dropdown.TEMPLATE = "WowStyle2DropdownTemplate"
-- A small arrow button beside an edit box (the To boxes in the Mailbox), with the same list.
Dropdown.ARROW_TEMPLATE = "WowStyle1ArrowDropdownTemplate"
Dropdown.HEIGHT = 22
-- A list longer than this many entries scrolls.
Dropdown.MAX_ENTRIES = 20
Dropdown.ENTRY = 20

-- Like Window.tooltip, but hooked: the drop-down's own OnEnter and OnLeave draw its hover state.
function Dropdown.tooltip(env, b, title, text)
  if not title then return end
  b:HookScript("OnEnter", function(self)
    local tip = env.GameTooltip
    if not tip or (self.IsMenuOpen and self:IsMenuOpen()) then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetText(title, 1, 1, 1)
    tip:AddLine(text, nil, nil, nil, true)
    tip:Show()
  end)
  b:HookScript("OnLeave", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
end

-- A pick goes in the debug log (#99), as a click on one of our buttons does.
function Dropdown.log(title, label)
  local l = ns.debugLog
  if l and l:isOn() then l:add("ui", "pick %q in %s", tostring(label), tostring(title or "drop-down")) end
end

-- Lets a long list scroll instead of running off the screen.
function Dropdown.limit(description, count)
  if count > Dropdown.MAX_ENTRIES and description.SetScrollMode then
    description:SetScrollMode(Dropdown.MAX_ENTRIES * Dropdown.ENTRY)
  end
end

-- A drop-down whose menu is whatever build(root) puts in it.
-- opts: width, title and tip (its tooltip), build(root) adds the entries (root:CreateRadio,
-- root:CreateCheckbox, ... from Blizzard_Menu), text() gives what the button shows,
-- arrow = true for the small arrow button, anchor = a frame to open the list under.
-- Returns the DropdownButton, with refresh() to draw it again after the value changed elsewhere.
function Dropdown.create(env, parent, opts)
  local arrow = opts.arrow
  local b = env.CreateFrame("DropdownButton", nil, parent, arrow and Dropdown.ARROW_TEMPLATE or Dropdown.TEMPLATE)
  if arrow then
    b:SetSize(opts.width or 24, opts.height or 24)
    -- The arrow button's own list style differs; use the Settings one everywhere.
    if env.MenuStyle2Mixin then b.menuMixin = env.MenuStyle2Mixin end
  else
    b:SetSize(opts.width or 120, opts.height or Dropdown.HEIGHT)
  end
  if opts.anchor and env.AnchorUtil and b.SetMenuAnchor then
    b:SetMenuAnchor(env.AnchorUtil.CreateAnchor("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, -2))
  end
  Dropdown.tooltip(env, b, opts.title, opts.tip)
  -- Blizzard's list belongs to UIParent, so it doesn't hide with our panels: close it when the button hides
  -- (its view switched, an editor closed, or the window went away).
  b:HookScript("OnHide", function(self) self:CloseMenu() end)
  -- The tooltip would sit over the list it opens.
  b:HookScript("OnMouseDown", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
  local text = opts.text
  b:SetupMenu(function(_, root) opts.build(root) end)
  -- The list is built again only while closed: rebuilding it inside a click on one of its entries would
  -- pull it out from under the menu. Entries read their selected state live, so an open list stays right.
  function b.refresh()
    if b.GenerateMenu and not (b.IsMenuOpen and b:IsMenuOpen()) then b:GenerateMenu() end
    if text and not arrow then
      local t = text()
      if t then b:OverrideText(t) end
    end
  end
  b.refresh()
  return b
end

-- A drop-down of one choice. opts as for create, plus options = { { value, label }, ... } (or a function
-- giving them), get() the chosen value, set(value) picks one.
function Dropdown.radio(env, parent, opts)
  local function options()
    local o = opts.options
    if type(o) == "function" then o = o() end
    return o or {}
  end
  local b
  local function label()
    local chosen = opts.get()
    for _, o in ipairs(options()) do
      if o[1] == chosen then return o[2] end
    end
    return opts.empty or ""
  end
  b = Dropdown.create(env, parent, {
    width = opts.width, height = opts.height, title = opts.title, tip = opts.tip, arrow = opts.arrow,
    anchor = opts.anchor, text = label,
    build = function(root)
      local list = options()
      Dropdown.limit(root, #list)
      for _, o in ipairs(list) do
        local value = o[1]
        root:CreateRadio(o[2], function() return opts.get() == value end, function()
          Dropdown.log(opts.title, o[2])
          opts.set(value)
          if b.refresh then b.refresh() end
        end, value)
      end
    end,
  })
  return b
end

ns.Dropdown = Dropdown
return Dropdown
