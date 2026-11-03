-- party_game.lua — Spelling Bee's multiplayer match, no UI (testable).
--
-- The reader lies on the table and shows the hive; everyone writes words on
-- paper until the timer runs out. Then the full answer list is shown, and
-- each player in turn taps the words they wrote. A word written by one player
-- only scores for them (the solo game's points: 1 for 4 letters, else one per
-- letter, +7 for a pangram); a word written by two players or more is
-- cancelled, as in Boggle Party. Rare bonus words and words off the list
-- score nothing, as in the solo game.
--
-- Phases of a round:
--   "playing"   the hive, the timer
--   "claiming"  the list; player `claimer` taps their words
--   "results"   the round is scored; next round
--   "over"      after the last round

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Party = require("party")
local Board = lrequire("board")

local Match = {}
Match.__index = Match

Match.ROUND_CHOICES  = { 1, 2, 3, 5 }
Match.TIME_CHOICES   = { 0, 180, 300, 480, 600 }   -- seconds, 0 = no timer
Match.DEFAULT_ROUNDS = 3
Match.DEFAULT_TIME   = 300

-- answers: the round's word list; claims[seat] = { word = true }.
-- Returns points[seat] and, per word, how many players wrote it and the seat
-- of the one who did when there is one only.
function Match.scoreRound(answers, claims, n)
    local points, count, owner = {}, {}, {}
    for seat = 1, n do points[seat] = 0 end
    for _i, w in ipairs(answers) do
        local c, who = 0, nil
        for seat = 1, n do
            if claims[seat] and claims[seat][w] then c = c + 1; who = seat end
        end
        count[w] = c
        if c == 1 then
            owner[w] = who
            points[who] = points[who] + Board.wordScore(w)
        end
    end
    return points, count, owner
end

-- opts: names, total, lang, time_limit
function Match.new(opts)
    return setmetatable({
        scores       = Party.newScores(opts.names or {}),
        total        = opts.total or Match.DEFAULT_ROUNDS,
        lang         = opts.lang or "en",
        time_limit   = opts.time_limit or 0,
        phase        = "results",   -- before the first round: nextRound() starts it
        board        = Board:new{ lang = opts.lang or "en", empty = true },
        claims       = {},
        claimer      = 1,
        time_left    = 0,
        paused       = false,
        round_points = nil,         -- points[seat] of the last round scored
        used         = {},          -- letter sets played this match
    }, Match)
end

function Match:playerCount()
    return #self.scores.names
end

function Match:isOver()
    return self.phase == "over"
end

function Match:nextRound()
    if self.phase ~= "results" then return false end
    local b = self.board
    b.lang = self.lang
    for _try = 1, 20 do
        if not b:newGame() then return false end
        if not self.used[b:getSpec()] then break end
    end
    self.used[b:getSpec()] = true
    self.claims = {}
    for seat = 1, self:playerCount() do self.claims[seat] = {} end
    self.claimer      = 1
    self.time_left    = self.time_limit
    self.paused       = false
    self.round_points = nil
    self.phase        = "playing"
    Party.nextRound(self.scores)
    return true
end

-- The screen's clock says `left` seconds remain; true when time is up.
function Match:setTimeLeft(left)
    if self.phase ~= "playing" or self.time_limit <= 0 then return false end
    self.time_left = math.max(0, math.min(self.time_limit, math.floor(left)))
    return self.time_left == 0
end

-- Pens down: the list is shown, the first player claims their words.
function Match:endRound()
    if self.phase ~= "playing" then return false end
    self.phase   = "claiming"
    self.claimer = 1
    self.paused  = false
    return true
end

function Match:isClaimed(seat, word)
    return self.claims[seat] and self.claims[seat][word] == true
end

-- How many players have claimed `word` so far.
function Match:claimCount(word)
    local c = 0
    for seat = 1, self:playerCount() do
        if self:isClaimed(seat, word) then c = c + 1 end
    end
    return c
end

-- The current claimer wrote (or did not write) `word`. Only list words count.
function Match:toggleClaim(word)
    if self.phase ~= "claiming" or not self.board.answer_set[word] then return false end
    local set = self.claims[self.claimer]
    set[word] = (not set[word]) or nil
    return true
end

function Match:nextClaimer()
    if self.phase ~= "claiming" or self.claimer >= self:playerCount() then return false end
    self.claimer = self.claimer + 1
    return true
end

function Match:prevClaimer()
    if self.phase ~= "claiming" or self.claimer <= 1 then return false end
    self.claimer = self.claimer - 1
    return true
end

-- Every player has claimed: score the round.
function Match:score()
    if self.phase ~= "claiming" then return nil end
    local points = Match.scoreRound(self.board.answers, self.claims, self:playerCount())
    for seat, p in ipairs(points) do Party.award(self.scores, seat, p) end
    self.round_points = points
    self.phase = (self.scores.round >= self.total) and "over" or "results"
    return points
end

-- Per-word outcome once scored (or so far while claiming).
function Match:outcome()
    local _p, count, owner = Match.scoreRound(self.board.answers, self.claims, self:playerCount())
    return count, owner
end

-- ---------------------------------------------------------------------------
-- Persistence (its own setting key, apart from the solo game)
-- ---------------------------------------------------------------------------

function Match:serialize()
    local claims = {}
    for seat = 1, self:playerCount() do
        local list = {}
        for w in pairs(self.claims[seat] or {}) do list[#list + 1] = w end
        table.sort(list)
        claims[seat] = list
    end
    local used = {}
    for s in pairs(self.used) do used[#used + 1] = s end
    return {
        scores       = Party.copyScores(self.scores),
        total        = self.total,
        lang         = self.lang,
        time_limit   = self.time_limit,
        phase        = self.phase,
        puzzle       = self.board:serialize(),
        claims       = claims,
        claimer      = self.claimer,
        time_left    = self.time_left,
        round_points = self.round_points,
        used         = used,
    }
end

local PHASES = { playing = true, claiming = true, results = true, over = true }

-- A restored round in play comes back paused: the table may not be ready.
function Match.load(t)
    if type(t) ~= "table" or not PHASES[t.phase] then return nil end
    local scores = Party.restoreScores(t.scores)
    if not scores then return nil end
    local m = Match.new{
        names = scores.names, total = tonumber(t.total), lang = t.lang,
        time_limit = tonumber(t.time_limit) or 0,
    }
    if not m.board:load(t.puzzle) then return nil end
    m.lang      = m.board.lang
    m.scores    = scores
    m.phase     = t.phase
    m.claimer   = math.max(1, math.min(m:playerCount(), tonumber(t.claimer) or 1))
    m.time_left = tonumber(t.time_left) or m.time_limit
    m.paused    = m.phase == "playing" and m.time_limit > 0
    for seat = 1, m:playerCount() do
        m.claims[seat] = {}
        for _i, w in ipairs(type(t.claims) == "table" and t.claims[seat] or {}) do
            if m.board.answer_set[w] then m.claims[seat][w] = true end
        end
    end
    if type(t.round_points) == "table" and #t.round_points == m:playerCount() then
        m.round_points = t.round_points
    end
    for _i, s in ipairs(type(t.used) == "table" and t.used or {}) do m.used[s] = true end
    return m
end

return Match
