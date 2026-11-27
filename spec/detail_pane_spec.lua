local helper = require("spec.helper")

describe("DetailPane", function()
  local DetailPane
  before_each(function()
    DetailPane = helper.load("BetterAH/Core/DetailPane.lua").DetailPane
  end)

  describe("width", function()
    it("starts at 300 and keeps a width between 240 and 420", function()
      assert.equal(300, DetailPane.DEFAULT)
      assert.equal(300, DetailPane.width(nil))
      assert.equal(300, DetailPane.width("junk"))
      assert.equal(300, DetailPane.width(0 / 0))
      assert.equal(240, DetailPane.width(10))
      assert.equal(420, DetailPane.width(9000))
      assert.equal(301, DetailPane.width(300.6))
      assert.equal(350, DetailPane.width("350"))
    end)
  end)

  describe("listWidth", function()
    it("gives the left list what the pane gives up, 540 at the default", function()
      assert.equal(540, DetailPane.listWidth(300))
      assert.equal(600, DetailPane.listWidth(240))
      assert.equal(420, DetailPane.listWidth(420))
      assert.equal(540, DetailPane.listWidth(nil))
    end)
  end)

  describe("columns", function()
    local cols = {
      { "Item", 4, 186 }, { "In bags", 192, 56 }, { "Post at", 250, 92, "LEFT" },
    }

    it("leaves columns laid out for 540 as they are", function()
      assert.same(cols, DetailPane.columns(cols, 540))
    end)

    it("stretches the first column and moves the ones right of it", function()
      local wide = DetailPane.columns(cols, 600)
      assert.same({ { "Item", 4, 246 }, { "In bags", 252, 56 }, { "Post at", 310, 92, "LEFT" } }, wide)
      local narrow = DetailPane.columns(cols, 420)
      assert.same({ { "Item", 4, 66 }, { "In bags", 72, 56 }, { "Post at", 130, 92, "LEFT" } }, narrow)
    end)

    it("can stretch another column, leaving the ones left of it in place", function()
      local wide = DetailPane.columns(cols, 560, 2)
      assert.same({ { "Item", 4, 186 }, { "In bags", 192, 76 }, { "Post at", 270, 92, "LEFT" } }, wide)
    end)

    it("moves a column drawn out of order only when it sits right of the stretched one", function()
      local odd = { { "Item", 4, 140 }, { "Target", 148, 116 }, { "Listed", 264, 38 }, { "Max", 304, 68 } }
      local wide = DetailPane.columns(odd, 560, 2)
      assert.same({ { "Item", 4, 140 }, { "Target", 148, 136 }, { "Listed", 284, 38 }, { "Max", 324, 68 } }, wide)
    end)

    it("never squeezes the stretched column below 40", function()
      local narrow = DetailPane.columns(cols, 100)
      assert.equal(40, narrow[1][3])
      assert.equal(46, narrow[2][2])
    end)

    it("does not change the columns it was given", function()
      DetailPane.columns(cols, 600)
      assert.equal(186, cols[1][3])
    end)
  end)

  describe("saved widths", function()
    it("keeps one width per view", function()
      local store = {}
      DetailPane.save(store, "post", 360)
      DetailPane.save(store, "ledger", 250.4)
      assert.equal(360, DetailPane.saved(store, "post"))
      assert.equal(250, DetailPane.saved(store, "ledger"))
      assert.equal(300, DetailPane.saved(store, "auctions"))
    end)

    it("forgets a view's width when it is reset", function()
      local store = { post = 360 }
      DetailPane.save(store, "post", nil)
      assert.is_nil(store.post)
      assert.equal(300, DetailPane.saved(store, "post"))
    end)

    it("reads a junk or out of range saved width as a usable one", function()
      assert.equal(300, DetailPane.saved({ post = "x" }, "post"))
      assert.equal(420, DetailPane.saved({ post = 999 }, "post"))
      assert.equal(300, DetailPane.saved(nil, "post"))
      DetailPane.save(nil, "post", 300) -- no store yet: nothing to save to, and no error
    end)

    it("knows which views can be resized", function()
      for _, id in ipairs({ "post", "auctions", "browse", "bids", "ledger", "prices", "alts" }) do
        assert.is_true(DetailPane.resizable(id), id)
      end
      assert.is_false(DetailPane.resizable("settings"))
      assert.is_false(DetailPane.resizable("deals"))
    end)
  end)
end)
