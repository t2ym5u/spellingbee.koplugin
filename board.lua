local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local DailySeed = require("daily_seed")

-- ---------------------------------------------------------------------------
-- Word lists
-- ---------------------------------------------------------------------------

-- Two generated files per language (tools/build_words.py):
--   words_<lang>.lua    -- { core = "...", extra = "..." }: comma-separated
--                          words. Core words are common ones and make up a
--                          puzzle's answers; extra words are rare but valid and
--                          count as bonus words, worth no points.
--   puzzles_<lang>.lua  -- letter sets, centre letter first ("NGIMOTU").
-- Loaded lazily, once per language: a player who never switches language
-- never pays for the other one.

local _lists = {}

local function splitWords(raw)
    local out = {}
    for w in (raw or ""):gmatch("%u+") do out[#out + 1] = w end
    return out
end

local function loadLang(lang)
    local entry = _lists[lang]
    if entry then return entry end
    local words_fn   = loadfile(_dir .. "words_" .. lang .. ".lua")
    local puzzles_fn = loadfile(_dir .. "puzzles_" .. lang .. ".lua")
    local words = (words_fn and words_fn()) or {}
    entry = {
        core    = splitWords(words.core),
        extra   = splitWords(words.extra),
        puzzles = (puzzles_fn and puzzles_fn()) or {},
    }
    _lists[lang] = entry
    return entry
end

-- Words of `list` made only of the letters in `allowed` (byte -> true) and
-- containing the centre byte. A plain byte loop: on the ~25k words of a
-- language it takes a few milliseconds, so a puzzle's answers are worked out
-- when it starts instead of being stored for each of thousands of puzzles.
local function collect(list, allowed, centre)
    local out = {}
    local byte = string.byte
    for i = 1, #list do
        local w = list[i]
        local ok, has_centre = true, false
        for k = 1, #w do
            local b = byte(w, k)
            if not allowed[b] then ok = false break end
            if b == centre then has_centre = true end
        end
        if ok and has_centre then out[#out + 1] = w end
    end
    return out
end

local LANG_ORDER = { "en", "fr" }
local MIN_LEN    = 4
local PANGRAM_BONUS = 7

-- The NYT ladder: the share of the puzzle's maximum score each rank needs.
-- Names live in screen.lua (the board stays free of UI strings).
local RANK_PCT = { 0, 2, 5, 8, 15, 25, 40, 50, 70, 100 }

-- ---------------------------------------------------------------------------
-- SpellingBeeBoard
-- ---------------------------------------------------------------------------

local Board = {}
Board.__index = Board

Board.LANG_ORDER = LANG_ORDER
Board.MIN_LEN    = MIN_LEN
Board.RANK_PCT   = RANK_PCT
Board.loadLang   = loadLang

function Board:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        lang       = opts.lang or "en",
        centre     = "",     -- the mandatory letter
        outer      = {},     -- the six other letters, in display order
        current    = {},     -- letters typed so far
        answers    = {},     -- core words, sorted
        answer_set = {},     -- word -> true
        extra_set  = {},     -- rare valid words -> true
        found      = {},     -- core words found, in order found
        found_set  = {},     -- word -> "found" | "hint"
        bonus      = {},     -- rare words found
        bonus_set  = {},
        revealed   = false,  -- the player asked for the answers: round over
        daily      = nil,    -- DailySeed.today() of a daily puzzle, else nil
        hints_used = 0,
        max_score  = 0,
    }, self)
    if not opts.empty then obj:newGame() end
    return obj
end

-- Points for a word: 1 for 4 letters, else its length; +7 for a pangram.
function Board.wordScore(word)
    local s = (#word == MIN_LEN) and 1 or #word
    if Board.isPangram(word) then s = s + PANGRAM_BONUS end
    return s
end

-- True when the word uses 7 different letters (the set's whole hive).
function Board.isPangram(word)
    local seen, n = {}, 0
    for k = 1, #word do
        local c = word:sub(k, k)
        if not seen[c] then seen[c] = true n = n + 1 end
    end
    return n >= 7
end

-- ---------------------------------------------------------------------------
-- Puzzle setup
-- ---------------------------------------------------------------------------

-- Install the letter set `spec` (centre letter first) and work out its answers.
function Board:setPuzzle(spec)
    self.centre = spec:sub(1, 1)
    self.outer = {}
    for k = 2, #spec do self.outer[#self.outer + 1] = spec:sub(k, k) end
    self.current, self.found, self.found_set = {}, {}, {}
    self.bonus, self.bonus_set = {}, {}
    self.revealed, self.hints_used = false, 0

    local allowed = { [spec:byte(1)] = true }
    for k = 2, #spec do allowed[spec:byte(k)] = true end
    local lists = loadLang(self.lang)
    self.answers = collect(lists.core, allowed, spec:byte(1))
    table.sort(self.answers)
    self.answer_set, self.max_score = {}, 0
    for _, w in ipairs(self.answers) do
        self.answer_set[w] = true
        self.max_score = self.max_score + Board.wordScore(w)
    end
    self.extra_set = {}
    for _, w in ipairs(collect(lists.extra, allowed, spec:byte(1))) do
        self.extra_set[w] = true
    end
end

-- The letter set as stored: centre first, outer letters sorted (the display
-- order is a shuffle and does not identify the puzzle).
function Board:getSpec()
    local outer = {}
    for i, c in ipairs(self.outer) do outer[i] = c end
    table.sort(outer)
    return self.centre .. table.concat(outer)
end

function Board:newGame()
    local puzzles = loadLang(self.lang).puzzles
    if #puzzles == 0 then return false end
    self:setPuzzle(puzzles[math.random(#puzzles)])
    self:shuffle()
    self.daily = nil
    return true
end

-- Today's puzzle for this language: the same letters on every device all day.
function Board:dailyIndex(day)
    local puzzles = loadLang(self.lang).puzzles
    if #puzzles == 0 then return nil end
    local h = 0
    for k = 1, #self.lang do h = h * 31 + self.lang:byte(k) end
    local rng = DailySeed.rng((day or DailySeed.today()) * 101 + h)
    rng() -- the first draw of a Park-Miller LCG barely moves with the seed
    return math.floor(rng() * #puzzles) + 1
end

function Board:newDailyGame(day)
    day = day or DailySeed.today()
    local idx = self:dailyIndex(day)
    if not idx then return false end
    self:setPuzzle(loadLang(self.lang).puzzles[idx])
    self:shuffle()
    self.daily = day
    return true
end

-- Shuffle the six outer letters (the centre never moves).
function Board:shuffle()
    local t = self.outer
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- ---------------------------------------------------------------------------
-- Typing
-- ---------------------------------------------------------------------------

-- Hive positions: 0 is the centre, 1..6 the outer letters in display order.
function Board:letterAt(pos)
    if pos == 0 then return self.centre end
    return self.outer[pos]
end

function Board:typeLetter(ch)
    if self:isOver() or not ch or ch == "" then return false end
    -- A word longer than the longest in the lists can't be right; this also
    -- keeps the word line from overflowing.
    if #self.current >= 19 then return false end
    self.current[#self.current + 1] = ch
    return true
end

function Board:deleteLetter()
    if #self.current == 0 then return false end
    self.current[#self.current] = nil
    return true
end

function Board:clearCurrent()
    self.current = {}
end

function Board:getCurrent()
    return table.concat(self.current)
end

-- Check the typed word and clear it. Returns result, word, points:
--   "short"     fewer than 4 letters
--   "no_centre" the centre letter is missing
--   "already"   found before (core or bonus)
--   "found"     a new answer; points = its score
--   "bonus"     a rare valid word; no points
--   "unknown"   not in the word list
--   "over"      the round is over
function Board:submit()
    local word = self:getCurrent()
    if self:isOver() then return "over", word, 0 end
    if word == "" then return "empty", word, 0 end
    self.current = {}
    if #word < MIN_LEN then return "short", word, 0 end
    if not word:find(self.centre, 1, true) then return "no_centre", word, 0 end
    if self.found_set[word] or self.bonus_set[word] then return "already", word, 0 end
    if self.answer_set[word] then
        self.found[#self.found + 1] = word
        self.found_set[word] = "found"
        return "found", word, Board.wordScore(word)
    end
    if self.extra_set[word] then
        self.bonus[#self.bonus + 1] = word
        self.bonus_set[word] = true
        return "bonus", word, 0
    end
    return "unknown", word, 0
end

-- ---------------------------------------------------------------------------
-- Score and rank
-- ---------------------------------------------------------------------------

-- Words revealed by a hint count as found but score nothing: the rank says
-- what the player found alone.
function Board:getScore()
    local s = 0
    for _, w in ipairs(self.found) do
        if self.found_set[w] == "found" then s = s + Board.wordScore(w) end
    end
    return s
end

-- Points needed for rank i (1 = Beginner .. #RANK_PCT = Queen Bee).
function Board:rankThreshold(i)
    return math.floor(self.max_score * RANK_PCT[i] / 100 + 0.5)
end

-- Index of the rank reached, 1..#RANK_PCT.
function Board:getRank()
    local score, rank = self:getScore(), 1
    for i = 1, #RANK_PCT do
        if score >= self:rankThreshold(i) then rank = i end
    end
    return rank
end

function Board:isComplete()
    return #self.answers > 0 and #self.found >= #self.answers
end

function Board:isOver()
    return self.revealed or self:isComplete()
end

-- End the round and show every answer.
function Board:reveal()
    self.current = {}
    self.revealed = true
end

function Board:getPangrams()
    local out = {}
    for _, w in ipairs(self.answers) do
        if Board.isPangram(w) then out[#out + 1] = w end
    end
    return out
end

-- Answers not found yet, alphabetical.
function Board:getMissing()
    local out = {}
    for _, w in ipairs(self.answers) do
        if not self.found_set[w] then out[#out + 1] = w end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Hints -- the ScreenBase:onHint protocol (findHint / applyHint /
-- noteHintUsed / getHintsUsed). A step names a missing word; r carries the
-- word so ScreenBase can tell a second tap on the same hint from a new one.
-- Deterministic on purpose: the first missing word, alphabetically.
-- ---------------------------------------------------------------------------

function Board:findHint()
    if self:isOver() then return nil, "complete" end
    local word = self:getMissing()[1]
    if not word then return nil, "complete" end
    return { r = word, c = 0, kind = "word", word = word }
end

function Board:applyHint(step)
    local word = step and step.word
    if not word or not self.answer_set[word] or self.found_set[word] then return false end
    self.found[#self.found + 1] = word
    self.found_set[word] = "hint"
    return true
end

function Board:noteHintUsed()
    self.hints_used = self.hints_used + 1
end

function Board:getHintsUsed()
    return self.hints_used
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function Board:serialize()
    local found = {}
    for i, w in ipairs(self.found) do
        found[i] = { w = w, h = (self.found_set[w] == "hint") or nil }
    end
    local bonus = {}
    for i, w in ipairs(self.bonus) do bonus[i] = w end
    local outer = {}
    for i, c in ipairs(self.outer) do outer[i] = c end
    return {
        lang       = self.lang,
        centre     = self.centre,
        outer      = outer,
        found      = found,
        bonus      = bonus,
        revealed   = self.revealed,
        daily      = self.daily,
        hints_used = self.hints_used,
    }
end

-- Restore a saved game. The answers are recomputed from the shipped lists;
-- a saved word those lists no longer accept (after a data update) is dropped
-- rather than counted.
function Board:load(state)
    if type(state) ~= "table" or type(state.centre) ~= "string" or #state.centre ~= 1
            or type(state.outer) ~= "table" or #state.outer ~= 6 then
        return false
    end
    self.lang = state.lang or self.lang
    self:setPuzzle(state.centre .. table.concat(state.outer))
    for _, f in ipairs(state.found or {}) do
        local w = type(f) == "table" and f.w or f
        if self.answer_set[w] and not self.found_set[w] then
            self.found[#self.found + 1] = w
            self.found_set[w] = (type(f) == "table" and f.h) and "hint" or "found"
        end
    end
    for _, w in ipairs(state.bonus or {}) do
        if self.extra_set[w] and not self.bonus_set[w] then
            self.bonus[#self.bonus + 1] = w
            self.bonus_set[w] = true
        end
    end
    self.revealed   = state.revealed and true or false
    self.daily      = state.daily
    self.hints_used = tonumber(state.hints_used) or 0
    return #self.answers > 0
end

return Board
