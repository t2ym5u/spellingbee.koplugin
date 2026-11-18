-- Tapping a letter, Delete and Shuffle only refresh the board. UIManager
-- repaints top-level widgets only, so the board must mark the screen dirty:
-- marking itself dirty refreshes the old pixels and the tap looks ignored.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("board refresh", function()
    local saved = {}
    local dirty   -- widgets passed to UIManager:setDirty

    -- Any other module is a permissive stub: Class:extend{} returns its
    -- table, _("x") returns "x", everything else returns its argument.
    local function stub()
        return setmetatable({}, {
            __index = function() return function(_, o) return o or {} end end,
            __call  = function(_, s) return s end,
        })
    end

    local function stubSearcher(name)
        return function() return stub() end, name
    end

    setup(function()
        saved.loaded = {}
        for k, v in pairs(package.loaded) do saved.loaded[k] = v end
        for k in pairs(saved.loaded) do
            if type(k) == "string" and k:sub(1, #DIR) == DIR then package.loaded[k] = nil end
        end
        package.loaded["ui/uimanager"] = {
            setDirty = function(_, w) dirty[#dirty + 1] = w end,
        }
        package.loaded["device"] = { screen = stub() }
        -- Other specs may have loaded these already.
        for _, name in ipairs({ "screen_base", "menu_helper", "i18n" }) do
            package.loaded[name] = stub()
        end
        local searchers = package.searchers or package.loaders
        searchers[#searchers + 1] = stubSearcher
    end)

    teardown(function()
        local searchers = package.searchers or package.loaders
        for i = #searchers, 1, -1 do
            if searchers[i] == stubSearcher then table.remove(searchers, i) end
        end
        for k in pairs(package.loaded) do
            if saved.loaded[k] == nil then package.loaded[k] = nil end
        end
        for k, v in pairs(saved.loaded) do package.loaded[k] = v end
    end)

    it("marks the screen dirty when a letter is typed, deleted or shuffled", function()
        local Screen = dofile(DIR .. "screen.lua")
        local BoardWidget = package.loaded[DIR .. "board_widget"]
        local scr = {
            board = {
                typeLetter = function() return true end,
                deleteLetter = function() return true end,
                shuffle = function() end,
                serialize = function() return {} end,
            },
            board_widget = setmetatable({ dimen = {} }, { __index = BoardWidget }),
            plugin = { saveState = function() end },
            _clearMessage = Screen._clearMessage,
            _save = Screen._save,
        }
        for _, action in ipairs({ "onLetter", "onDelete", "onShuffle" }) do
            dirty = {}
            Screen[action](scr, "A")
            assert.are.equal(1, #dirty, action)
            assert.are.equal(scr, dirty[1], action .. " must mark the screen dirty")
        end
    end)
end)
