-- Spec for the multiplayer match (party_game.lua): cancellation scoring,
-- claims, rounds, save/restore.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.loaded["i18n"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Match = assert(loadfile(DIR .. "party_game.lua"))()
local Board = assert(loadfile(DIR .. "board.lua"))()

describe("Spelling Bee party scoring", function()
    it("scores words written by one player only, cancels shared ones", function()
        local answers = { "TOAST", "TOTS", "PANGRAM" }   -- PANGRAM is not one; plain length
        local claims = {
            { TOAST = true, TOTS = true },
            { TOAST = true },
            { PANGRAM = true },
        }
        local points, count, owner = Match.scoreRound(answers, claims, 3)
        assert.are.same({ 1, 0, Board.wordScore("PANGRAM") }, points)
        assert.are.equal(2, count.TOAST)
        assert.is_nil(owner.TOAST)
        assert.are.equal(1, owner.TOTS)
    end)

    it("gives the pangram bonus as in the solo game", function()
        local points = Match.scoreRound({ "ABCDEFG" }, { { ABCDEFG = true }, {} }, 2)
        assert.are.equal(7 + 7, points[1])
        assert.are.equal(0, points[2])
    end)
end)

describe("Spelling Bee party match", function()
    local function play(names, total)
        local m = Match.new{ names = names, total = total, lang = "en", time_limit = 300 }
        assert.is_true(m:nextRound())
        return m
    end

    it("runs a round: play, claim per player, score; over after N rounds", function()
        local m = play({ "Ann", "Bob" }, 2)
        assert.are.equal("playing", m.phase)
        assert.are.equal(1, m.scores.round)
        assert.is_true(#m.board.answers >= 20)
        assert.is_false(m:toggleClaim(m.board.answers[1]))    -- not while playing
        assert.is_false(m:setTimeLeft(120))
        assert.is_true(m:setTimeLeft(0))
        assert.is_true(m:endRound())
        assert.are.equal("claiming", m.phase)

        local a, b, c = m.board.answers[1], m.board.answers[2], m.board.answers[3]
        assert.is_false(m:toggleClaim("NOTAWORDATALL"))
        m:toggleClaim(a); m:toggleClaim(b); m:toggleClaim(c); m:toggleClaim(c) -- c untapped
        assert.is_false(m:isClaimed(1, c))
        assert.is_false(m:prevClaimer())
        assert.is_true(m:nextClaimer())
        assert.is_false(m:nextClaimer())
        m:toggleClaim(a)
        assert.are.equal(2, m:claimCount(a))
        local first = m.board:getSpec()
        local pts = m:score()
        assert.are.same({ Board.wordScore(b), 0 }, pts)
        assert.are.same({ Board.wordScore(b), 0 }, m.scores.points)
        assert.are.equal("results", m.phase)

        assert.is_true(m:nextRound())
        assert.are_not.equal(first, m.board:getSpec())   -- new letters
        assert.is_nil(next(m.claims[1]))
        m:endRound(); m:nextClaimer(); m:score()
        assert.is_true(m:isOver())
        assert.is_false(m:nextRound())
    end)

    it("saves and restores every phase; a round in play comes back paused", function()
        local m = play({ "Ann", "Bob", "Cy" }, 3)
        m:setTimeLeft(77)
        local r = Match.load(m:serialize())
        assert.are.equal("playing", r.phase)
        assert.are.equal(m.board:getSpec(), r.board:getSpec())
        assert.are.same(m.board.outer, r.board.outer)
        assert.are.equal(77, r.time_left)
        assert.is_true(r.paused)

        r:endRound()
        local w = r.board.answers[5]
        r:nextClaimer(); r:toggleClaim(w)
        local c = Match.load(r:serialize())
        assert.are.equal("claiming", c.phase)
        assert.are.equal(2, c.claimer)
        assert.is_true(c:isClaimed(2, w))
        c:nextClaimer(); c:score()
        local s = Match.load(c:serialize())
        assert.are.equal("results", s.phase)
        assert.are.same(c.round_points, s.round_points)
        assert.are.same(c.scores.points, s.scores.points)
        assert.is_true(s.used[c.board:getSpec()])
    end)

    it("restores a finished match as over", function()
        local m = play({ "A", "B" }, 1)
        m:endRound(); m:nextClaimer(); m:score()
        assert.is_true(Match.load(m:serialize()):isOver())
    end)

    it("rejects broken saves", function()
        assert.is_nil(Match.load(nil))
        assert.is_nil(Match.load({ phase = "claiming" }))
        assert.is_nil(Match.load({ phase = "claiming", scores = { names = { "A" }, points = { 0 } },
            puzzle = { centre = "AB" } }))
    end)
end)
