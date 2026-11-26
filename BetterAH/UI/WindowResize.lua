-- The resize grip in the Better AH window's bottom-right corner (issue #51). Dragging it scales the
-- whole window (SetScale), so the layout and aspect ratio stay as they are. The scale is saved in
-- BetterAHDB.window, and so is where the player last dragged the window (issue #103); double-clicking
-- the grip resets both. The maths is in Core/WindowScale.lua.
local _, ns = ...
ns = ns or {}

local WindowResize = {}

-- Blizzard's own size grabber, as on the chat frames.
WindowResize.ART = {
  normal = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  pushed = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
  highlight = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
}
WindowResize.TOOLTIP = {
  "Resize", "Drag to make the window bigger or smaller. Double-click to reset its size and position.",
}

-- The default spot for the window's top-left corner, as offsets from the screen's top-left corner.
local DEFAULT_LEFT, DEFAULT_TOP = 16, -116

-- window is the Window; f its frame, of size width x height at scale 1. saved is the table to keep
-- the scale and the position in (BetterAHDB.window).
function WindowResize.attach(env, f, width, height, saved, tooltip)
  local Scale = ns.WindowScale
  local self = { env = env, frame = f, width = width, height = height, saved = saved }
  local parent = env.UIParent

  local function screen() return parent:GetWidth(), parent:GetHeight() end

  -- The window's top-left corner in UIParent units, or the default spot before it has a position.
  local function home()
    local _, h = screen()
    return DEFAULT_LEFT, h + DEFAULT_TOP
  end
  local function corner()
    local left, top, s = f:GetLeft(), f:GetTop(), f:GetScale()
    if left and top then return left * s, top * s end
    return home()
  end

  -- Remember where the window is now, so it opens there next time, after a /reload too. The top is
  -- kept as an offset from the top of the screen (like the default spot), so a taller screen next
  -- time doesn't move the window down.
  local function remember()
    local left, top, s = f:GetLeft(), f:GetTop(), f:GetScale()
    if left and top and s then
      local _, h = screen()
      saved.left, saved.top = left * s, top * s - h
    end
  end

  -- Fit the saved scale to the screen and put the window where it was last left (or keep it where it
  -- is when nothing was saved), on screen in case the UI scale or resolution changed since.
  local function restore()
    local left, top = Scale.loadCorner(saved)
    if left then
      local _, h = screen()
      top = h + top
    end
    self.apply(Scale.load(saved), left, top)
  end

  -- Scale the window, keeping its top-left corner where it is (and the window on screen).
  function self.apply(scale, left, top)
    local w, h = screen()
    scale = Scale.clamp(scale, width, height, w, h)
    if not left then left, top = corner() end
    left, top = Scale.place(left, top, width * scale, height * scale, w, h)
    f:SetScale(scale)
    f:ClearAllPoints()
    -- Offsets are in the window's own, scaled units.
    f:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", left / scale, top / scale)
    return scale
  end

  local function cursor()
    local x, y = env.GetCursorPosition()
    local s = parent:GetEffectiveScale()
    return x / s, y / s
  end

  local grip = env.CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture(WindowResize.ART.normal)
  grip:SetPushedTexture(WindowResize.ART.pushed)
  grip:SetHighlightTexture(WindowResize.ART.highlight)
  grip:RegisterForClicks("LeftButtonUp")
  tooltip(env, grip, WindowResize.TOOLTIP[1], WindowResize.TOOLTIP[2])
  self.grip = grip

  local drag
  -- No tooltip while dragging, even when the cursor comes back over the grip.
  local enter = grip:GetScript("OnEnter")
  grip:SetScript("OnEnter", function(...) if not drag then enter(...) end end)
  local function stop()
    if not drag then return end
    drag = nil
    grip:SetScript("OnUpdate", nil)
    saved.scale = f:GetScale()
    remember()
  end
  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if env.GameTooltip then env.GameTooltip:Hide() end
    local left, top = corner()
    local x, y = cursor()
    drag = { scale = f:GetScale(), left = left, top = top, x = x, y = y }
    grip:SetScript("OnUpdate", function()
      -- The button can come up where we don't hear it (the game lost focus mid-drag).
      if env.IsMouseButtonDown and not env.IsMouseButtonDown("LeftButton") then return stop() end
      local cx, cy = cursor()
      self.apply(Scale.fromDrag(drag.scale, drag.left, drag.top, drag.x, drag.y, cx, cy, width, height),
        drag.left, drag.top)
    end)
  end)
  grip:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then stop() end end)
  -- The window can hide mid-drag (Escape, or the auction house closing); end the drag there too.
  grip:SetScript("OnHide", stop)
  grip:SetScript("OnShow", restore)
  grip:SetScript("OnDoubleClick", function()
    stop()
    saved.scale, saved.left, saved.top = Scale.DEFAULT, nil, nil
    self.apply(Scale.DEFAULT, home())
  end)

  -- Moving the window by its title bar: save where it was dropped. Keep the client's layout cache out
  -- of it, so only our saved position decides where the window opens.
  local moving
  local dragStart, dragStop = f:GetScript("OnDragStart"), f:GetScript("OnDragStop")
  f:SetScript("OnDragStart", function(...)
    moving = true
    if dragStart then dragStart(...) end
  end)
  f:SetScript("OnDragStop", function(...)
    moving = nil
    if dragStop then dragStop(...) end
    if f.SetUserPlaced then f:SetUserPlaced(false) end
    remember()
  end)
  -- The window can hide mid-move (Escape, or the auction house closing) with no OnDragStop; end the
  -- move there so it doesn't stay stuck to the cursor, and keep the spot it got to.
  local onHide = f:GetScript("OnHide")
  f:SetScript("OnHide", function(...)
    if moving then
      moving = nil
      f:StopMovingOrSizing()
      if f.SetUserPlaced then f:SetUserPlaced(false) end
      remember()
    end
    if onHide then onHide(...) end
  end)

  restore()
  return self
end

ns.WindowResize = WindowResize
return WindowResize
