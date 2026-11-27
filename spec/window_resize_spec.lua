local helper = require("spec.helper")
local fake = require("spec.fake_client")
-- The window's width at 1x (Window.WIDTH).
local W = 1060

-- The files that need the real client at load time.
-- SellTimes.lua is the optional data file the companion app downloads (#220).
local CLIENT_ONLY = { ["Core/Init.lua"] = true, ["Core/Commands.lua"] = true, ["SellTimes.lua"] = true }

-- Loads every addon file the .toc lists (but those), so this spec keeps up with
-- new views, and installs the game adapters on the fake client.
local function setup(db)
  local env = fake.new()
  local ns = {}
  local adapters = {}
  for raw in io.lines("BetterAH/BetterAH.toc") do
    local line = raw:gsub("%s+$", "")
    if line:match("%.lua$") and not CLIENT_ONLY[line] then
      helper.load("BetterAH/" .. line, ns)
      local adapter = line:match("^Game/(%w+)%.lua$")
      if adapter then adapters[#adapters + 1] = adapter end
    end
  end
  ns.db = db or {}
  ns.prices = ns.PriceDB.new({})
  ns.characters = ns.CharacterRecords.new({})
  ns.posting = ns.Posting.Settings.new({})
  for _, adapter in ipairs(adapters) do
    if adapter ~= "CharacterTracker" then ns[adapter].install(env, ns) end
  end
  local w = ns.Window.install(env, ns)
  env.openAuctionHouse()
  return env, w, ns
end

-- The window's top-left corner in UIParent units.
local function corner(f) return f:GetLeft() * f:GetScale(), f:GetTop() * f:GetScale() end

-- Move the cursor to (x, y) in UIParent units, as screen pixels like GetCursorPosition gives them.
local function moveTo(env, x, y) env.cursorX, env.cursorY = x * env.uiScale, y * env.uiScale end

local function dragGrip(env, w, x, y)
  local grip = w.resize.grip
  local f = env.BetterAHFrame
  local left, top = corner(f)
  moveTo(env, left + W * f:GetScale(), top - 470 * f:GetScale())
  grip.scripts.OnMouseDown(grip, "LeftButton")
  moveTo(env, x, y)
  grip.scripts.OnUpdate(grip, 0)
  return grip
end

describe("Window resize grip", function()
  it("sits in the bottom-right corner with Blizzard's size grabber art and a tooltip", function()
    local _, w = setup()
    local grip = w.resize.grip
    assert.equal("BOTTOMRIGHT", grip.point[1])
    assert.equal("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up", grip.normalTexture)
    assert.equal("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down", grip.pushedTexture)
    assert.equal("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", grip.highlightTexture)
    assert.is_function(grip.scripts.OnEnter)
    assert.is_function(grip.scripts.OnLeave)
  end)

  it("opens at 1x in the default spot when nothing is saved", function()
    local env = setup()
    local f = env.BetterAHFrame
    assert.equal(1, f:GetScale())
    assert.same({ 16, 768 - 116 }, { corner(f) })
  end)

  it("scales the window while dragging, keeping its top-left corner, and saves the scale", function()
    local env, w, ns = setup()
    local f = env.BetterAHFrame
    local grip = dragGrip(env, w, 16 + W * 1.2, 652 - 470 * 1.2)
    assert.near(1.2, f:GetScale(), 1e-9)
    local left, top = corner(f)
    assert.near(16, left, 1e-9)
    assert.near(652, top, 1e-9)
    assert.is_nil(ns.db.window.scale, "saved when the drag ends")
    grip.scripts.OnMouseUp(grip, "LeftButton")
    assert.near(1.2, ns.db.window.scale, 1e-9)
    assert.is_nil(grip.scripts.OnUpdate, "the drag stops")
  end)

  it("stays between 0.7x and what fits on screen", function()
    local env, w, ns = setup()
    local f = env.BetterAHFrame
    local grip = dragGrip(env, w, 20, 650)
    assert.equal(0.7, f:GetScale())
    moveTo(env, 5000, -5000)
    grip.scripts.OnUpdate(grip, 0)
    assert.near(1365 / W, f:GetScale(), 1e-9)
    local left = corner(f)
    assert.near(0, left, 1e-9, "moved left to keep the window on screen")
    grip.scripts.OnMouseUp(grip, "LeftButton")
    assert.near(1365 / W, ns.db.window.scale, 1e-9)
  end)

  it("ends the drag when the window hides", function()
    local env, w, ns = setup()
    local grip = dragGrip(env, w, 16 + W * 0.8, 652 - 470 * 0.8)
    grip.scripts.OnHide(grip)
    assert.is_nil(grip.scripts.OnUpdate)
    assert.near(0.8, ns.db.window.scale, 1e-9)
  end)

  it("resets to 1x in the default spot on a double-click", function()
    local env, w, ns = setup({ window = { scale = 1.25, left = 400, top = -168 } })
    local grip = w.resize.grip
    grip.scripts.OnDoubleClick(grip, "LeftButton")
    local f = env.BetterAHFrame
    assert.equal(1, f:GetScale())
    assert.same({ 16, 768 - 116 }, { corner(f) })
    assert.equal(1, ns.db.window.scale)
    assert.is_nil(ns.db.window.left)
    assert.is_nil(ns.db.window.top)
  end)

  describe("position", function()
    -- Drag the window by its title bar so its top-left corner ends at (left, top) in UIParent units.
    local function moveWindow(env, left, top)
      local f = env.BetterAHFrame
      f.scripts.OnDragStart(f, "LeftButton")
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", left / f:GetScale(), top / f:GetScale())
      f.scripts.OnDragStop(f)
    end

    it("saves where the player drags the window", function()
      local env, _, ns = setup()
      moveWindow(env, 400, 600)
      assert.same({ 400, 600 - 768 }, { ns.db.window.left, ns.db.window.top }, "the top from the screen's top")
      assert.is_false(env.BetterAHFrame.userPlaced, "kept out of the client's layout cache")
    end)

    it("saves it in UIParent units when the window is scaled", function()
      local env, _, ns = setup({ window = { scale = 1.25 } })
      moveWindow(env, 100, 700)
      assert.near(100, ns.db.window.left, 1e-9)
      assert.near(700 - 768, ns.db.window.top, 1e-9)
    end)

    it("opens where it was left after a reload, at the saved scale", function()
      local env = setup({ window = { scale = 0.8, left = 400, top = -168 } })
      local f = env.BetterAHFrame
      assert.equal(0.8, f:GetScale())
      local left, top = corner(f)
      assert.near(400, left, 1e-9)
      assert.near(600, top, 1e-9)
    end)

    it("goes back there each time the window opens", function()
      local env, w = setup()
      moveWindow(env, 200, 600)
      local f = env.BetterAHFrame
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 16, 652)
      w.resize.grip.scripts.OnShow(w.resize.grip)
      assert.same({ 200, 600 }, { corner(f) })
    end)

    it("keeps a saved spot on a screen that got smaller, without forgetting it", function()
      local env, w, ns = setup({ window = { left = 900, top = -8 } })
      local f = env.BetterAHFrame
      assert.same({ 1365 - W, 760 }, { corner(f) })
      env.screenWidth, env.screenHeight = 1200, 500
      w.resize.grip.scripts.OnShow(w.resize.grip)
      assert.same({ 1200 - W, 492 }, { corner(f) }, "pulled in from the right")
      assert.same({ 900, -8 }, { ns.db.window.left, ns.db.window.top })
    end)

    it("saves the spot after a resize that had to move the window", function()
      local env, w, ns = setup()
      local grip = dragGrip(env, w, 5000, -5000)
      grip.scripts.OnMouseUp(grip, "LeftButton")
      local left, top = corner(env.BetterAHFrame)
      assert.near(left, ns.db.window.left, 1e-9)
      assert.near(top - 768, ns.db.window.top, 1e-9)
    end)

    it("stays the same distance from the top on a taller screen", function()
      local env, w = setup()
      moveWindow(env, 200, 700)
      env.screenWidth, env.screenHeight = 2560, 1440
      w.resize.grip.scripts.OnShow(w.resize.grip)
      assert.same({ 200, 1440 - 68 }, { corner(env.BetterAHFrame) })
    end)

    it("ends a move and keeps the spot when the window hides mid-move", function()
      local env, _, ns = setup()
      local f = env.BetterAHFrame
      f.scripts.OnDragStart(f, "LeftButton")
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 250, 650)
      f.scripts.OnHide(f)
      assert.equal(1, f.stoppedMoving)
      assert.is_false(f.userPlaced)
      assert.same({ 250, 650 - 768 }, { ns.db.window.left, ns.db.window.top })
    end)

    it("leaves the position alone when the window hides without a move", function()
      local env, _, ns = setup()
      local f = env.BetterAHFrame
      f.scripts.OnHide(f)
      assert.is_nil(f.stoppedMoving)
      assert.is_nil(ns.db.window.left)
    end)

    it("ignores a broken saved spot", function()
      local env = setup({ window = { left = "x", top = 0 / 0 } })
      assert.same({ 16, 768 - 116 }, { corner(env.BetterAHFrame) })
    end)
  end)

  it("restores the saved scale, clamped to what fits on this screen", function()
    local env = setup({ window = { scale = 1.25 } })
    assert.equal(1.25, env.BetterAHFrame:GetScale())
    env = setup({ window = { scale = 1.5 } })
    assert.near(1365 / W, env.BetterAHFrame:GetScale(), 1e-9)
  end)

  it("doesn't overwrite the saved scale just because this screen is too small for it", function()
    local _, _, ns = setup({ window = { scale = 1.5 } })
    assert.equal(1.5, ns.db.window.scale, "a bigger screen next time gets it back")
  end)

  it("fits the saved scale to the screen again each time the window opens", function()
    local env, w = setup({ window = { scale = 1.5 } })
    local f = env.BetterAHFrame
    assert.near(1365 / W, f:GetScale(), 1e-9)
    env.screenWidth, env.screenHeight = 2560, 1440
    w.resize.grip.scripts.OnShow(w.resize.grip)
    assert.equal(1.5, f:GetScale())
    env.screenWidth, env.screenHeight = 1000, 600
    w.resize.grip.scripts.OnShow(w.resize.grip)
    assert.near(1000 / W, f:GetScale(), 1e-9)
    assert.same({ 0, 600 }, { corner(f) }, "and keeps it on screen")
  end)

  it("keeps the corner of a window the player moved", function()
    local env, w = setup()
    local f = env.BetterAHFrame
    f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 300, 700)
    dragGrip(env, w, 300 + W * 0.9, 700 - 470 * 0.9)
    assert.near(0.9, f:GetScale(), 1e-9)
    local left, top = corner(f)
    assert.near(300, left, 1e-9)
    assert.near(700, top, 1e-9)
  end)

  it("ends the drag when the button came up unheard", function()
    local env, w, ns = setup()
    local grip = dragGrip(env, w, 16 + W * 0.8, 652 - 470 * 0.8)
    env.mouseDown = false
    moveTo(env, 16 + W * 1.25, 652 - 470 * 1.25)
    grip.scripts.OnUpdate(grip, 0)
    assert.is_nil(grip.scripts.OnUpdate)
    assert.near(0.8, env.BetterAHFrame:GetScale(), 1e-9)
    assert.near(0.8, ns.db.window.scale, 1e-9)
  end)

  it("keeps dragging through another button's release, and hides the tooltip meanwhile", function()
    local env, w = setup()
    local shown = 0
    env.GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end,
      Show = function() shown = shown + 1 end, Hide = function() end }
    local grip = dragGrip(env, w, 16 + W * 0.8, 652 - 470 * 0.8)
    grip.scripts.OnMouseUp(grip, "RightButton")
    assert.is_function(grip.scripts.OnUpdate)
    grip.scripts.OnEnter(grip)
    assert.equal(0, shown)
    grip.scripts.OnMouseUp(grip, "LeftButton")
    grip.scripts.OnEnter(grip)
    assert.equal(1, shown)
  end)

  it("ignores other mouse buttons", function()
    local _, w = setup()
    local grip = w.resize.grip
    grip.scripts.OnMouseDown(grip, "RightButton")
    assert.is_nil(grip.scripts.OnUpdate)
  end)
end)
