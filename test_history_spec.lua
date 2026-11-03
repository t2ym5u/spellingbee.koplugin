-- Letter sets are not repeated: solo games and party matches draw through one
-- history per language kept in the plugin settings (game-common
-- seen_history.lua), keyed by the seven letters whatever the centre, so the
-- same hive does not come back with another centre letter until every set
-- was played. The daily puzzle stays the same for everyone.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.loaded["i18n"] = package.loaded["i18n"] or function(s) return s end
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Match = assert(loadfile(DIR .. "party_game.lua"))()
local Board = assert(loadfile(DIR .. "board.lua"))()

local function fakePlugin(store)
    store = store or {}
    return {
        store = store,
        getSetting  = function(_self, k, d) local v = store[k]; if v == nil then return d end; return v end,
        saveSetting = function(_self, k, v) store[k] = v end,
    }
end

local function distinctSets(lang)
    local set, n = {}, 0
    for _i, spec in ipairs(Board.loadLang(lang).puzzles) do
        local k = Board.letterSet(spec)
        if not set[k] then set[k] = true; n = n + 1 end
    end
    return n
end

describe("letter-set history", function()
    it("fr: every letter set once before any comes back, across two sessions", function()
        local n = distinctSets("fr")
        local store, seen = {}, {}
        for session = 1, 2 do
            local b = Board:new{ lang = "fr", empty = true, plugin = fakePlugin(store) }
            local games = session == 1 and math.floor(n / 2) or n - math.floor(n / 2)
            for _g = 1, games do
                assert.is_true(b:newGame())
                local k = Board.letterSet(b:getSpec())
                assert.is_nil(seen[k], k)
                seen[k] = true
            end
        end
        assert.are.equal(n, #store.seen_letters_fr)
        -- All played: the next one is a set seen before, and the cycle restarts.
        local b = Board:new{ lang = "fr", empty = true, plugin = fakePlugin(store) }
        assert.is_true(b:newGame())
        assert.is_true(seen[Board.letterSet(b:getSpec())])
        assert.are.equal(1, #store.seen_letters_fr)
    end)

    it("the daily puzzle ignores the history, then counts as played", function()
        local plain = Board:new{ lang = "en", empty = true }
        plain:newDailyGame(20000)
        local store = {}
        local b = Board:new{ lang = "en", empty = true, plugin = fakePlugin(store) }
        for _g = 1, 50 do b:newGame() end
        b:newDailyGame(20000)
        assert.are.equal(plain:getSpec(), b:getSpec())
        local list = store.seen_letters_en
        assert.are.equal(Board.letterSet(b:getSpec()), list[#list])
    end)

    it("party: no letter set twice in a match, saved and restored", function()
        local plugin = fakePlugin()
        local m = Match.new{ names = { "A", "B" }, total = 5, lang = "en", plugin = plugin }
        local sets = {}
        for _r = 1, 5 do
            assert.is_true(m:nextRound())
            local k = Board.letterSet(m.board:getSpec())
            assert.is_nil(sets[k], k)
            sets[k] = true
            m:endRound()
            m:score()
            if m.phase == "over" then break end
            m = Match.load(m:serialize(), plugin)
        end
        assert.are.equal(5, #plugin.store.seen_letters_en)
    end)

    it("party: the match's sets are left out even once the history is used up", function()
        local puzzles = Board.loadLang("en").puzzles
        local a, z = Board.letterSet(puzzles[1]), Board.letterSet(puzzles[#puzzles])
        local m = Match.new{ names = { "A", "B" }, total = 3, lang = "en" }
        for _i, spec in ipairs(puzzles) do
            local k = Board.letterSet(spec)
            if k ~= a and k ~= z then m.used[k] = true end
        end
        local got = {}
        for _r = 1, 2 do
            assert.is_true(m:nextRound())
            got[Board.letterSet(m.board:getSpec())] = true
            m:endRound()
            m:score()
        end
        assert.is_true(got[a] and got[z])
    end)
end)

describe("puzzle lists", function()
    for _i, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": seven distinct letters per puzzle, no duplicate spec", function()
            local seen = {}
            for _j, spec in ipairs(Board.loadLang(lang).puzzles) do
                assert.is_truthy(spec:match("^%u%u%u%u%u%u%u$"), spec)
                local k = Board.letterSet(spec)
                assert.is_nil(k:match("(%u)%1"), spec)
                assert.is_nil(seen[spec], spec)
                seen[spec] = true
            end
            assert.is_true(distinctSets(lang) > (lang == "fr" and 700 or 1300))
        end)
    end
end)
