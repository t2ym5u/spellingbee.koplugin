-- Run from the plugin dir: busted
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")

local function type_word(b, w)
    for k = 1, #w do b:typeLetter(w:sub(k, k)) end
end

-- A fixed, known puzzle: centre A, outer DEGHIN (found in the English data).
local SPEC = "ADEGHIN"

local function fresh(lang, spec)
    local b = Board:new{ lang = lang or "en", empty = true }
    b:setPuzzle(spec or SPEC)
    return b
end

describe("scoring", function()
    it("scores 1 for four letters, the length above, +7 for a pangram", function()
        assert.equals(1, Board.wordScore("DEAN"))
        assert.equals(5, Board.wordScore("AIDED"))
        assert.equals(7, Board.wordScore("HANDING"))      -- 6 distinct letters
        assert.equals(7 + 7, Board.wordScore("HEADING"))  -- pangram
    end)

    it("recognises pangrams by distinct letters", function()
        assert.is_true(Board.isPangram("HEADING"))
        assert.is_true(Board.isPangram("HEADINGG"))
        assert.is_false(Board.isPangram("HANDING"))
    end)
end)

describe("data files", function()
    for _, lang in ipairs(Board.LANG_ORDER) do
        local lists = Board.loadLang(lang)

        it(lang .. ": word lists are A-Z, 4+ letters, no S", function()
            assert.is_true(#lists.core > 1000)
            assert.is_true(#lists.extra > 1000)
            for _, list in ipairs{ lists.core, lists.extra } do
                for _, w in ipairs(list) do
                    assert.is_truthy(w:match("^[A-RT-Z]+$"), w)
                    assert.is_true(#w >= 4, w)
                end
            end
        end)

        it(lang .. ": no blocklisted word ships", function()
            local all = {}
            for _, w in ipairs(lists.core) do all[w] = true end
            for _, w in ipairs(lists.extra) do all[w] = true end
            for line in io.lines("tools/blocklist_" .. lang .. ".txt") do
                if line ~= "" and line:sub(1, 1) ~= "#" then
                    assert.is_nil(all[line], line)
                end
            end
        end)

        it(lang .. ": sampled puzzles have a pangram and 20..55 valid answers", function()
            local puzzles = lists.puzzles
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
                for _, w in ipairs(b.answers) do
                    assert.is_truthy(w:find(b.centre, 1, true), w)
                    for k = 1, #w do assert.is_true(letters[w:sub(k, k)], w) end
                end
            end
        end)
    end
end)

describe("submitting words", function()
    it("rejects short words, words without the centre, unknown words", function()
        local b = fresh()
        type_word(b, "AID")
        assert.equals("short", (b:submit()))
        type_word(b, "DINE")
        assert.equals("no_centre", (b:submit()))
        type_word(b, "AAAAAA")
        assert.equals("unknown", (b:submit()))
        assert.equals("", b:getCurrent())
        assert.equals(0, b:getScore())
    end)

    it("accepts an answer once and scores it", function()
        local b = fresh()
        assert.is_true(b.answer_set.HEADING)
        type_word(b, "HEADING")
        local r, w, pts = b:submit()
        assert.equals("found", r)
        assert.equals("HEADING", w)
        assert.equals(14, pts)
        assert.equals(14, b:getScore())
        type_word(b, "HEADING")
        assert.equals("already", (b:submit()))
        assert.equals(14, b:getScore())
    end)

    it("accepts rare words as bonus words worth nothing", function()
        local b = fresh()
        local rare = next(b.extra_set)
        assert.is_truthy(rare)
        type_word(b, rare)
        assert.equals("bonus", (b:submit()))
        assert.equals(0, b:getScore())
        assert.equals(1, #b.bonus)
        type_word(b, rare)
        assert.equals("already", (b:submit()))
    end)

    it("deletes the last letter", function()
        local b = fresh()
        type_word(b, "HEAD")
        assert.is_true(b:deleteLetter())
        assert.equals("HEA", b:getCurrent())
    end)
end)

describe("ranks and the end of a round", function()
    it("climbs the ladder to Queen Bee when every answer is found", function()
        local b = fresh()
        assert.equals(1, b:getRank())
        local last_rank = 1
        for _, w in ipairs(b.answers) do
            type_word(b, w)
            assert.equals("found", (b:submit()))
            assert.is_true(b:getRank() >= last_rank)
            last_rank = b:getRank()
        end
        assert.equals(b.max_score, b:getScore())
        assert.equals(#Board.RANK_PCT, b:getRank())
        assert.is_true(b:isComplete())
        assert.is_true(b:isOver())
        assert.is_false(b:typeLetter("A"))
    end)

    it("ranks follow the percentage thresholds", function()
        local b = fresh()
        assert.equals(0, b:rankThreshold(1))
        assert.equals(b.max_score, b:rankThreshold(#Board.RANK_PCT))
        assert.equals(math.floor(b.max_score * 0.7 + 0.5), b:rankThreshold(9))
    end)

    it("reveal ends the round and lists the missing words", function()
        local b = fresh()
        type_word(b, "HEADING")
        b:submit()
        b:reveal()
        assert.is_true(b:isOver())
        assert.equals(#b.answers - 1, #b:getMissing())
        type_word(b, "AGED")
        assert.equals("", b:getCurrent())
    end)
end)

describe("hints", function()
    it("names the first missing word, then reveals it for no points", function()
        local b = fresh()
        local step = b:findHint()
        assert.equals(b.answers[1], step.word)
        assert.is_true(b:applyHint(step))
        b:noteHintUsed()
        assert.equals("hint", b.found_set[step.word])
        assert.equals(0, b:getScore())
        assert.equals(1, b:getHintsUsed())
        assert.equals(b.answers[2], b:findHint().word)
        -- the revealed word cannot be applied twice
        assert.is_false(b:applyHint(step))
    end)

    it("has nothing to offer once the round is over", function()
        local b = fresh()
        b:reveal()
        local step, reason = b:findHint()
        assert.is_nil(step)
        assert.equals("complete", reason)
    end)
end)

describe("shuffle", function()
    it("keeps the centre and the same six letters", function()
        local b = fresh()
        local before = b:getSpec()
        for _ = 1, 10 do b:shuffle() end
        assert.equals("A", b.centre)
        assert.equals(before, b:getSpec())
    end)
end)

describe("new games and the daily puzzle", function()
    it("newGame draws a listed puzzle", function()
        local b = Board:new{ lang = "fr" }
        local listed = {}
        for _, p in ipairs(Board.loadLang("fr").puzzles) do listed[p] = true end
        assert.is_true(listed[b:getSpec()])
        assert.is_nil(b.daily)
    end)

    it("the daily puzzle depends on the day and the language only", function()
        local a = Board:new{ lang = "en", empty = true }
        local b = Board:new{ lang = "en", empty = true }
        a:newDailyGame(2026303)
        math.random(); math.random()
        b:newDailyGame(2026303)
        assert.equals(a:getSpec(), b:getSpec())
        assert.equals(2026303, a.daily)
        local distinct = {}
        for d = 2026001, 2026030 do distinct[a:dailyIndex(d)] = true end
        local n = 0
        for _ in pairs(distinct) do n = n + 1 end
        assert.is_true(n >= 25)
    end)
end)

describe("persistence", function()
    it("round-trips found, hinted and bonus words, the letter order and flags", function()
        local b = fresh()
        type_word(b, "HEADING"); b:submit()
        b:applyHint(b:findHint()); b:noteHintUsed()
        local rare = next(b.extra_set)
        type_word(b, rare); b:submit()
        b.daily = 2026303
        local state = b:serialize()

        local c = Board:new{ lang = "fr", empty = true }
        assert.is_true(c:load(state))
        assert.equals("en", c.lang)
        assert.equals(b.centre .. table.concat(b.outer), c.centre .. table.concat(c.outer))
        assert.same(b.found, c.found)
        assert.equals("hint", c.found_set[b.found[2]])
        assert.equals(b:getScore(), c:getScore())
        assert.same(b.bonus, c.bonus)
        assert.equals(1, c:getHintsUsed())
        assert.equals(2026303, c.daily)
        assert.is_false(c.revealed)
    end)

    it("drops saved words the lists no longer accept, and rejects garbage", function()
        local b = fresh()
        local state = b:serialize()
        state.found = { { w = "HEADING" }, { w = "ZZZZ" } }
        local c = Board:new{ empty = true }
        assert.is_true(c:load(state))
        assert.same({ "HEADING" }, c.found)
        assert.is_false(Board:new{ empty = true }:load(nil))
        assert.is_false(Board:new{ empty = true }:load({ centre = "A", outer = { "B" } }))
    end)
end)
