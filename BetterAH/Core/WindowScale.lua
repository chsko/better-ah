-- Scaling the Better AH window (issue #51). Pure: positions and sizes are in UIParent units, with
-- y growing upwards like the client's. The window keeps its layout and aspect ratio; only its
-- scale changes, so the text scales with it.
local _, ns = ...
ns = ns or {}

local WindowScale = {}

WindowScale.MIN, WindowScale.MAX, WindowScale.DEFAULT = 0.7, 1.5, 1

-- The scales a window of width x height may take on a screen of screenWidth x screenHeight: from MIN up
-- to MAX, or less when that would not fit. A screen too small even for MIN still allows MIN.
function WindowScale.limits(width, height, screenWidth, screenHeight)
  local max = WindowScale.MAX
  if screenWidth and screenWidth > 0 then max = math.min(max, screenWidth / width) end
  if screenHeight and screenHeight > 0 then max = math.min(max, screenHeight / height) end
  return WindowScale.MIN, math.max(WindowScale.MIN, max)
end

function WindowScale.clamp(scale, width, height, screenWidth, screenHeight)
  local min, max = WindowScale.limits(width, height, screenWidth, screenHeight)
  if type(scale) ~= "number" or scale ~= scale then return math.min(WindowScale.DEFAULT, max) end
  return math.max(min, math.min(max, scale))
end

-- The saved scale, or DEFAULT when nothing usable was saved.
function WindowScale.load(saved)
  if type(saved) ~= "table" or type(saved.scale) ~= "number" or saved.scale ~= saved.scale then
    return WindowScale.DEFAULT
  end
  return math.max(WindowScale.MIN, math.min(WindowScale.MAX, saved.scale))
end

-- The scale while the grip is dragged. The window's top-left corner (left, top) stays put; the drag
-- started at (startX, startY) with the window at startScale, and the cursor is now at (x, y). The cursor
-- is measured along the window's diagonal, so the corner follows it whichever way it moves, and the
-- ratio keeps the grip under the cursor without a jump when the drag starts. Not clamped.
function WindowScale.fromDrag(startScale, left, top, startX, startY, x, y, width, height)
  local function along(cx, cy) return (cx - left) * width + (top - cy) * height end
  local base = along(startX, startY)
  if base <= 0 then return startScale end
  return startScale * along(x, y) / base
end

-- Where the top-left corner goes so that a window of scaledWidth x scaledHeight stays on screen.
function WindowScale.place(left, top, scaledWidth, scaledHeight, screenWidth, screenHeight)
  left = math.max(0, math.min(left, screenWidth - scaledWidth))
  top = math.min(screenHeight, math.max(top, scaledHeight))
  return left, top
end

ns.WindowScale = WindowScale
return WindowScale
