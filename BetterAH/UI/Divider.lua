local _, ns = ...

-- A divider to drag between two panes (#236), as Browse has between its results and the search history
-- (#129, #213): a thin dark line the height of the panes, lit up gold under the mouse. Dragging it left
-- widens the pane on its right. The width is saved when the drag ends; a double-click puts the default
-- back.
local Divider = {}
ns.Divider = Divider
Divider.WIDTH = 8

-- opts:
--   height        the line's height
--   window        the frame whose scale the cursor is measured in (the Better AH window)
--   get()         the right pane's width now
--   set(width)    lays the panes out for a dragged width (called as the mouse moves)
--   clamp(width)  a width kept in range
--   save(width, context)  the drag ended at a new width (nil after a double-click: forget the saved
--                 width); context is what begin returned when the drag started
--   begin()       optional: called as a drag starts; its result is passed to save
--   reset()       a double-click: lay the panes out at the default
--   title, text   the tooltip
function Divider.new(env, parent, opts)
  local d = env.CreateFrame("Button", nil, parent)
  d:SetSize(Divider.WIDTH, opts.height)
  local line = d:CreateTexture(nil, "ARTWORK")
  line:SetSize(1, opts.height)
  line:SetPoint("TOPLEFT", d, "TOPLEFT", math.floor(Divider.WIDTH / 2), 0) -- on a whole pixel
  line:SetColorTexture(0.24, 0.19, 0.13, 1)
  local highlight = d:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetSize(2, opts.height)
  highlight:SetPoint("CENTER", d, "CENTER", 0, 0)
  highlight:SetColorTexture(0.79, 0.64, 0.23, 0.5)
  d.line = line
  if ns.Window and ns.Window.tooltip then ns.Window.tooltip(env, d, opts.title or "Resize", opts.text) end

  local function cursorX()
    local x = env.GetCursorPosition()
    local ui = env.UIParent and env.UIParent:GetEffectiveScale() or 1
    local frame = opts.window
    local scale = frame and frame:GetScale() or 1
    return x / ui / scale
  end
  local function stop()
    local drag = d.dragging
    if not drag then return end
    d.dragging = nil
    d:SetScript("OnUpdate", nil)
    -- A click without a drag saves nothing, so a view never resized keeps following the default.
    local width = opts.get()
    if width ~= drag.width then opts.save(width, drag.context) end
  end
  d:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if env.GameTooltip then env.GameTooltip:Hide() end
    d.dragging = { x = cursorX(), width = opts.get(), context = opts.begin and opts.begin() }
    d:SetScript("OnUpdate", function()
      -- The button can come up where we don't hear it (the game lost focus mid-drag).
      if env.IsMouseButtonDown and not env.IsMouseButtonDown("LeftButton") then return stop() end
      local drag = d.dragging
      if not drag then return end
      local width = opts.clamp(drag.width - (cursorX() - drag.x))
      if width ~= opts.get() then opts.set(width) end
    end)
  end)
  d:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then stop() end end)
  d:SetScript("OnHide", stop)
  d.stop = stop -- ends a drag in progress, saving it (the window does on a view change)
  d:SetScript("OnDoubleClick", function()
    d.dragging = nil
    d:SetScript("OnUpdate", nil)
    opts.save(nil, opts.begin and opts.begin())
    opts.reset()
  end)
  return d
end
