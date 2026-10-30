local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG     = Blitbuffer.COLOR_WHITE
local C_HEX    = Blitbuffer.COLOR_GRAY_E
local C_BORDER = Blitbuffer.COLOR_BLACK
local C_TEXT   = Blitbuffer.COLOR_BLACK
local C_DIM    = Blitbuffer.COLOR_GRAY_9
local C_TRACK  = Blitbuffer.COLOR_GRAY_B

local Screen = Device.screen
local SQRT3  = math.sqrt(3)

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (a max_width limit cuts the text, so the width test could never fail), ink
-- height is y_top + y_bottom, and Font:getFace scales its size by the DPI, so
-- the pixel bound is converted back first.
local function fitFace(name, sample, max_w, max_h)
    local lo = 6
    local hi = math.max(lo, math.floor(max_h * 1000 / Screen:scaleBySize(1000)) * 2)
    local best = lo
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace(name, mid), sample, true, false)
        if m.x <= max_w and m.y_top + m.y_bottom <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace(name, best)
end

local function textWidth(face, text)
    return RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false).x
end

-- Centre `text` on (cx, cy): the baseline sits half the ink height below cy.
local function drawCentered(bb, face, text, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2),
        cy + math.floor((m.y_top - m.y_bottom) / 2), face, text, true, false, color)
end

-- Left-align `text` at x, vertically centred on cy.
local function drawLeft(bb, face, text, x, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, x, cy + math.floor((m.y_top - m.y_bottom) / 2),
        face, text, true, false, color)
end

-- A flat-topped hexagon of circumradius r, filled by scanlines (the
-- blitbuffer has no polygon fill): at height dy from the centre the hexagon
-- is r - |dy|/sqrt(3) wide on each side.
local function fillHex(bb, cx, cy, r, color)
    local h = math.floor(r * SQRT3 / 2)
    for dy = -h, h do
        local half = math.floor(r - math.abs(dy) / SQRT3)
        bb:paintRect(cx - half, cy + dy, 2 * half + 1, 1, color)
    end
end

-- ---------------------------------------------------------------------------
-- SpellingBeeBoardWidget
--
-- Top to bottom: the rank ladder, the word being typed, the hive, the words
-- found. The hive takes what the rest leaves, up to a bound, so the list gets
-- the remaining height.
-- ---------------------------------------------------------------------------

local SpellingBeeBoardWidget = InputContainer:extend{
    board          = nil,
    max_width      = 300,
    max_height     = 300,
    rank_name      = nil,   -- function(rank_index) -> label
    found_label    = nil,   -- function(n) -> "N words" heading
    onHexTap       = nil,   -- function(letter)
    onListTap      = nil,   -- function() -- open the full list
}

function SpellingBeeBoardWidget:init()
    local w, h = self.max_width, self.max_height
    self.w, self.h = w, h
    self.dimen = Geom:new{ w = w, h = h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = w, h = h }

    local u = math.max(16, math.floor(math.min(h / 14, w / 9)))
    self.rank_h = u
    self.word_h = math.floor(u * 1.5)
    local gap = math.max(4, math.floor(u * 0.3))
    self.gap = gap

    -- Hive: a flat-topped centre hexagon ringed by six. It spans 5r across
    -- (plus gaps) and 3*sqrt(3)*r high; it gets at most half the height and
    -- leaves at least ~3 lines to the list.
    local hive_h_max = math.min(math.floor(h * 0.5), h - self.rank_h - self.word_h - 6 * u)
    local r = math.min((w * 0.9) / 5.3, hive_h_max / (3 * SQRT3 + 0.3))
    r = math.max(14, math.floor(r))
    self.r = r
    self.hex_gap = math.max(2, math.floor(r * 0.08))
    local step = r * SQRT3 + self.hex_gap   -- centre-to-centre distance
    self.hive_h = math.floor(2 * step + r * SQRT3) + 2

    self.rank_y = 0
    self.word_y = self.rank_h + gap
    self.hive_y = self.word_y + self.word_h + gap
    self.list_y = self.hive_y + self.hive_h + gap
    self.list_h = h - self.list_y

    -- Hex centres relative to the widget: 0 = centre, 1..6 clockwise from
    -- the top. Neighbours of a flat-topped hexagon sit at 90 +/- 60k degrees.
    local cx, cy = math.floor(w / 2), self.hive_y + math.floor(self.hive_h / 2)
    self.centres = { [0] = { cx, cy } }
    for i = 1, 6 do
        local a = math.rad(-90 + (i - 1) * 60)
        self.centres[i] = { cx + math.floor(step * math.cos(a) + 0.5),
                            cy + math.floor(step * math.sin(a) + 0.5) }
    end

    self.hex_face  = fitFace("smallinfofontbold", "W", math.floor(r * 0.9), math.floor(r * 0.8))
    self.word_face = fitFace("smallinfofontbold", "W", w, math.floor(self.word_h * 0.6))
    self.rank_face = fitFace("smallinfofontbold", "Wg", w, math.floor(u * 0.6))
    self.list_face = fitFace("smallinfofont", "Wg", w, math.floor(u * 0.5))
    self.list_bold = fitFace("smallinfofontbold", "Wg", w, math.floor(u * 0.5))
    self.line_h    = math.floor(u * 0.75)

    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

-- The hive position under (lx, ly), widget-relative, or nil. Hexagons are
-- tested by their inscribed circle plus the gap, so the whole hexagon taps
-- and the gaps between them go to the nearest one.
function SpellingBeeBoardWidget:hexAt(lx, ly)
    local best, best_d
    for i = 0, 6 do
        local c = self.centres[i]
        local d = (lx - c[1]) ^ 2 + (ly - c[2]) ^ 2
        if not best_d or d < best_d then best, best_d = i, d end
    end
    if best_d and best_d <= (self.r + self.hex_gap) ^ 2 then return best end
    return nil
end

function SpellingBeeBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return true end
    local lx = ges.pos.x - self.paint_rect.x
    local ly = ges.pos.y - self.paint_rect.y
    if ly >= self.list_y then
        if self.onListTap then self.onListTap() end
        return true
    end
    local pos = self:hexAt(lx, ly)
    if pos and self.onHexTap then
        local letter = self.board:letterAt(pos)
        if letter then self.onHexTap(letter) end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

-- Rank ladder: the rank's name on the left, then a track with one node per
-- rank; ranks reached are filled, the current one is a larger disc holding
-- the score.
function SpellingBeeBoardWidget:_paintRank(bb, x, y)
    local board = self.board
    local cy = y + math.floor(self.rank_h / 2)
    local rank = board:getRank()
    local name = self.rank_name and self.rank_name(rank) or tostring(rank)
    drawLeft(bb, self.rank_face, name, x, cy, C_TEXT)

    local n = #board.RANK_PCT
    local big = math.floor(self.rank_h * 0.48)
    local small = math.max(3, math.floor(self.rank_h * 0.14))
    local x0 = x + math.max(textWidth(self.rank_face, name) + 2 * big,
                            math.floor(self.w * 0.32))
    local x1 = x + self.w - big - 1
    if x1 <= x0 then return end
    bb:paintRect(x0, cy - 1, x1 - x0, 2, C_TRACK)
    local score_face = fitFace("smallinfofontbold", tostring(board:getScore()),
        math.floor(big * 1.5), math.floor(big * 0.9))
    for i = 1, n do
        local nx = x0 + math.floor((x1 - x0) * (i - 1) / (n - 1))
        if i == rank then
            bb:paintCircle(nx, cy, big, C_BORDER)
            drawCentered(bb, score_face, tostring(board:getScore()), nx, cy, C_BG)
        elseif i < rank then
            bb:paintCircle(nx, cy, small, C_BORDER)
        else
            bb:paintCircle(nx, cy, small, C_BG)
            bb:paintCircle(nx, cy, small, C_TRACK, 2)
        end
    end
end

-- The word being typed, with a caret-like underline; the centre letter is
-- underlined too, so a word missing it is visible before Enter.
function SpellingBeeBoardWidget:_paintWord(bb, x, y)
    local board = self.board
    local cx, cy = x + math.floor(self.w / 2), y + math.floor(self.word_h / 2)
    local word = board:getCurrent()
    local face = self.word_face
    if textWidth(face, word) > self.w then
        face = fitFace("smallinfofontbold", word, self.w, math.floor(self.word_h * 0.6))
    end
    local base = y + self.word_h - 2
    if board:isOver() then return end
    if word == "" then
        local bar = math.floor(self.r * 0.6)
        bb:paintRect(cx - bar, base, 2 * bar, 2, C_DIM)
        return
    end
    local wpx = textWidth(face, word)
    local lx = cx - math.floor(wpx / 2)
    drawLeft(bb, face, word, lx, cy, C_TEXT)
    -- Underline each centre letter.
    for k = 1, #word do
        local ch = word:sub(k, k)
        if ch == board.centre then
            local off = k > 1 and textWidth(face, word:sub(1, k - 1)) or 0
            bb:paintRect(lx + off, base, textWidth(face, ch), 3, C_TEXT)
        end
    end
end

function SpellingBeeBoardWidget:_paintHive(bb, x, y)
    local board = self.board
    local r, t = self.r, math.max(2, math.floor(self.r / 18))
    for i = 0, 6 do
        local c = self.centres[i]
        local hx, hy = x + c[1], y + c[2]
        local letter = board:letterAt(i) or ""
        if i == 0 then
            -- The mandatory letter: solid black, white letter.
            fillHex(bb, hx, hy, r, C_BORDER)
            drawCentered(bb, self.hex_face, letter, hx, hy, C_BG)
        else
            fillHex(bb, hx, hy, r, C_BORDER)
            fillHex(bb, hx, hy, r - math.ceil(t * 2 / SQRT3), C_HEX)
            drawCentered(bb, self.hex_face, letter, hx, hy, C_TEXT)
        end
    end
end

-- The list entries: the words found (or, once revealed, every answer; the
-- missed ones grey), pangrams in bold, hinted words grey; bonus words after.
function SpellingBeeBoardWidget:_listEntries()
    local board, out = self.board, {}
    local words = board.revealed and board.answers or {}
    if not board.revealed then
        for _, w in ipairs(board.found) do words[#words + 1] = w end
        table.sort(words)
    end
    for _, w in ipairs(words) do
        local state = board.found_set[w]
        out[#out + 1] = {
            text = w,
            bold = board.isPangram(w),
            dim  = state ~= "found",
        }
    end
    local bonus = {}
    for _, w in ipairs(board.bonus) do bonus[#bonus + 1] = w end
    table.sort(bonus)
    for _, w in ipairs(bonus) do
        out[#out + 1] = { text = w:lower(), dim = true }
    end
    return out
end

function SpellingBeeBoardWidget:_paintList(bb, x, y)
    local board = self.board
    local lh = self.line_h
    -- Heading with a rule under it.
    local heading = self.found_label and self.found_label(#board.found, #board.bonus) or ""
    drawLeft(bb, self.list_bold, heading, x, y + math.floor(lh / 2), C_TEXT)
    bb:paintRect(x, y + lh, self.w, 1, C_DIM)

    local entries = self:_listEntries()
    if #entries == 0 then return end
    local top = y + lh + math.floor(lh / 3)
    local rows = math.max(1, math.floor((y + self.list_h - top) / lh))
    local colw = 0
    for _, e in ipairs(entries) do
        local ew = textWidth(e.bold and self.list_bold or self.list_face, e.text)
        if ew > colw then colw = ew end
    end
    colw = colw + math.floor(lh * 0.8)
    local cols = math.max(1, math.floor(self.w / colw))
    colw = math.floor(self.w / cols)
    local fits = rows * cols
    local shown = #entries
    if shown > fits then shown = fits - 1 end
    for i = 1, shown do
        local e = entries[i]
        local col = math.floor((i - 1) / rows)
        local row = (i - 1) % rows
        drawLeft(bb, e.bold and self.list_bold or self.list_face, e.text,
            x + col * colw, top + row * lh + math.floor(lh / 2), e.dim and C_DIM or C_TEXT)
    end
    if shown < #entries then
        local i = fits
        local col = math.floor((i - 1) / rows)
        local row = (i - 1) % rows
        drawLeft(bb, self.list_bold, "+" .. (#entries - shown) .. " …",
            x + col * colw, top + row * lh + math.floor(lh / 2), C_TEXT)
    end
end

function SpellingBeeBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    bb:paintRect(x, y, self.w, self.h, C_BG)
    self:_paintRank(bb, x, y + self.rank_y)
    self:_paintWord(bb, x, y + self.word_y)
    self:_paintHive(bb, x, y)
    self:_paintList(bb, x, y + self.list_y)
end

function SpellingBeeBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

return SpellingBeeBoardWidget
