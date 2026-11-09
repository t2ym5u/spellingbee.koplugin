-- Difficulty guarantees (docs/dev/TESTING.md, "Difficulty specs").
--
-- Spelling Bee has no levels: its difficulty is the band every shipped puzzle
-- sits in (puzzles_<lang>.lua header, tools/build_words.py): 20-55 core
-- answers containing the centre letter, a core score of at most 240, at
-- least one core pangram and at most 120 rare bonus words. This checks the
-- band on a sample of both banks, that the rank ladder climbs, and that a
-- seed (or a day, for the daily puzzle) gives the same letters.
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")

describe("Spelling Bee difficulty", function()
    teardown(function()
        Board.release()
    end)

    for _, lang in ipairs(Board.LANG_ORDER) do
        -- moved from test_board_spec.lua ("data files"); the bonus-word cap
        -- is new. The whole bank was measured clean on 2026-11-09 (en 5636,
        -- fr 2214 puzzles: answers 20..55, score <= 240, bonus <= 120).
        it(lang .. ": sampled puzzles have a pangram, 20..55 answers, score <= 240, <= 120 bonus words", function()
            local puzzles = Board.loadLang(lang).puzzles
            assert.is_true(#puzzles > 1000)
            local b = Board:new{ lang = lang, empty = true }
            local step = math.max(1, math.floor(#puzzles / 300))
            for i = 1, #puzzles, step do
                local spec = puzzles[i]
                assert.equals(7, #spec)
                local letters = {}
                for k = 1, 7 do
                    local c = spec:sub(k, k)
                    assert.is_nil(letters[c], spec)
                    assert.are_not.equal("S", c)
                    letters[c] = true
                end
                b:setPuzzle(spec)
                assert.is_true(#b.answers >= 20 and #b.answers <= 55, spec)
                assert.is_true(#b:getPangrams() >= 1, spec)
                assert.is_true(b.max_score <= 240, spec)
                local bonus = 0
                for _ in pairs(b.extra_set) do bonus = bonus + 1 end
                assert.is_true(bonus <= 120, spec .. ": " .. bonus .. " bonus words")
                for _, w in ipairs(b.answers) do
                    assert.is_truthy(w:find(b.centre, 1, true), w)
                    for k = 1, #w do assert.is_true(letters[w:sub(k, k)], w) end
                end
            end
        end)
    end

    it("the rank ladder climbs from 0 to 100 % and its thresholds are distinct on the smallest puzzle", function()
        for i = 2, #Board.RANK_PCT do
            assert.is_true(Board.RANK_PCT[i - 1] < Board.RANK_PCT[i])
        end
        assert.are.equal(0, Board.RANK_PCT[1])
        assert.are.equal(100, Board.RANK_PCT[#Board.RANK_PCT])
        -- the smallest score a puzzle can have: 20 answers, one a pangram
        -- (4-letter words score 1, a 7-letter pangram 14): 19 + 14 = 33
        local b = Board:new{ lang = "en", empty = true }
        b.max_score = 33
        for i = 2, #Board.RANK_PCT do
            assert.is_true(b:rankThreshold(i - 1) < b:rankThreshold(i), "rank " .. i)
        end
    end)

    it("a seed draws the same puzzle", function()
        for _, lang in ipairs(Board.LANG_ORDER) do
            for seed = 1, 5 do
                math.randomseed(seed)
                local a = Board:new{ lang = lang }
                math.randomseed(seed)
                local b = Board:new{ lang = lang }
                assert.are.equal(a:getSpec(), b:getSpec())
                assert.are.same(a.outer, b.outer)
            end
        end
    end)

    it("the daily puzzle depends on the day and the language only", function()
        for _, lang in ipairs(Board.LANG_ORDER) do
            local a = Board:new{ lang = lang, empty = true }
            local b = Board:new{ lang = lang, empty = true }
            for day = 20000, 20004 do
                math.randomseed(day)  -- the global RNG plays no part
                local i = a:dailyIndex(day)
                math.randomseed(day + 1)
                assert.are.equal(i, b:dailyIndex(day))
            end
        end
    end)

    it("never reads the clock to draw a random puzzle", function()
        local src = assert(io.open("board.lua")):read("*a")
        assert.is_nil(src:find("os%.time"))
        assert.is_nil(src:find("os%.clock"))
        assert.is_nil(src:find("ui/time", 1, true))
    end)
end)
