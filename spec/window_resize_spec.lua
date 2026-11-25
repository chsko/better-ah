local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(db)
  local env = fake.new()
  local ns = helper.load("BetterAH/Core/WindowModel.lua")
  local core = { "WindowScale", "Money", "Time", "MarketKey", "MarketValue", "Disenchant", "Targets", "PriceDB",
    "CharacterRecords", "Posting", "PostQueue", "SelfTest", "Probes" }
  for _, file in ipairs(core) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Game/AuctionAPI.lua", ns)
  helper.load("BetterAH/Game/PostingAPI.lua", ns)
  helper.load("BetterAH/UI/PostView.lua", ns)
  helper.load("BetterAH/UI/DisenchantView.lua", ns)
  helper.load("BetterAH/UI/WindowResize.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  ns.db = db or {}
  ns.prices = ns.PriceDB.new({})
  ns.characters = ns.CharacterRecords.new({})
  ns.posting = ns.Posting.Settings.new({})
  ns.AuctionAPI.install(env, ns)
  ns.PostingAPI.install(env, ns)
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
  moveTo(env, left + 980 * f:GetScale(), top - 470 * f:GetScale())
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
    local grip = dragGrip(env, w, 16 + 980 * 1.2, 652 - 470 * 1.2)
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
    assert.near(1365 / 980, f:GetScale(), 1e-9)
    local left = corner(f)
    assert.near(0, left, 1e-9, "moved left to keep the window on screen")
    grip.scripts.OnMouseUp(grip, "LeftButton")
    assert.near(1365 / 980, ns.db.window.scale, 1e-9)
  end)

  it("ends the drag when the window hides", function()
    local env, w, ns = setup()
    local grip = dragGrip(env, w, 16 + 980 * 0.8, 652 - 470 * 0.8)
    grip.scripts.OnHide(grip)
    assert.is_nil(grip.scripts.OnUpdate)
    assert.near(0.8, ns.db.window.scale, 1e-9)
  end)

  it("resets to 1x on a double-click", function()
    local env, w, ns = setup({ window = { scale = 1.3 } })
    local grip = w.resize.grip
    grip.scripts.OnDoubleClick(grip, "LeftButton")
    assert.equal(1, env.BetterAHFrame:GetScale())
    assert.equal(1, ns.db.window.scale)
  end)

  it("restores the saved scale, clamped to what fits on this screen", function()
    local env = setup({ window = { scale = 1.3 } })
    assert.equal(1.3, env.BetterAHFrame:GetScale())
    env = setup({ window = { scale = 1.5 } })
    assert.near(1365 / 980, env.BetterAHFrame:GetScale(), 1e-9)
  end)

  it("doesn't overwrite the saved scale just because this screen is too small for it", function()
    local _, _, ns = setup({ window = { scale = 1.5 } })
    assert.equal(1.5, ns.db.window.scale, "a bigger screen next time gets it back")
  end)

  it("fits the saved scale to the screen again each time the window opens", function()
    local env, w = setup({ window = { scale = 1.5 } })
    local f = env.BetterAHFrame
    assert.near(1365 / 980, f:GetScale(), 1e-9)
    env.screenWidth, env.screenHeight = 2560, 1440
    w.resize.grip.scripts.OnShow(w.resize.grip)
    assert.equal(1.5, f:GetScale())
    env.screenWidth, env.screenHeight = 1000, 600
    w.resize.grip.scripts.OnShow(w.resize.grip)
    assert.near(1000 / 980, f:GetScale(), 1e-9)
    assert.same({ 0, 600 }, { corner(f) }, "and keeps it on screen")
  end)

  it("keeps the corner of a window the player moved", function()
    local env, w = setup()
    local f = env.BetterAHFrame
    f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 300, 700)
    dragGrip(env, w, 300 + 980 * 0.9, 700 - 470 * 0.9)
    assert.near(0.9, f:GetScale(), 1e-9)
    local left, top = corner(f)
    assert.near(300, left, 1e-9)
    assert.near(700, top, 1e-9)
  end)

  it("ends the drag when the button came up unheard", function()
    local env, w, ns = setup()
    local grip = dragGrip(env, w, 16 + 980 * 0.8, 652 - 470 * 0.8)
    env.mouseDown = false
    moveTo(env, 16 + 980 * 1.3, 652 - 470 * 1.3)
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
    local grip = dragGrip(env, w, 16 + 980 * 0.8, 652 - 470 * 0.8)
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
