-- party_widget.lua — the multiplayer table's widgets:
--   Hive     the seven letters, as big as the room allows
--   WordList the round's answers grouped by length, tappable (claims) and
--            marked once scored; paged when they don't fit
--   BigText  a fixed-size line (the countdown) that repaints only itself

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")
local Widget         = require("ui/widget/widget")

local C_BG     = Blitbuffer.COLOR_WHITE
local C_HEX    = Blitbuffer.COLOR_GRAY_E
local C_MARK   = Blitbuffer.COLOR_GRAY_D
local C_BORDER = Blitbuffer.COLOR_BLACK
local C_TEXT   = Blitbuffer.COLOR_BLACK
local C_DIM    = Blitbuffer.COLOR_GRAY_7
local C_RULE   = Blitbuffer.COLOR_GRAY_9

local Screen = Device.screen
local SQRT3  = math.sqrt(3)

-- Same measures as board_widget.lua: largest face whose ink fits, ink height
-- y_top + y_bottom, DPI scaling undone.
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

local function drawCentered(bb, face, text, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2),
        cy + math.floor((m.y_top - m.y_bottom) / 2), face, text, true, false, color)
end

local function drawLeft(bb, face, text, x, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, x, cy + math.floor((m.y_top - m.y_bottom) / 2),
        face, text, true, false, color)
end

local function fillHex(bb, cx, cy, r, color)
    local h = math.floor(r * SQRT3 / 2)
    for dy = -h, h do
        local half = math.floor(r - math.abs(dy) / SQRT3)
        bb:paintRect(cx - half, cy + dy, 2 * half + 1, 1, color)
    end
end

-- ---------------------------------------------------------------------------
-- BigText
-- ---------------------------------------------------------------------------

local BigText = Widget:extend{ text = "", width = 100, height = 40, sample = "00:00" }

function BigText:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.face = fitFace("cfont", self.sample, math.floor(self.width * 0.95), math.floor(self.height * 0.8))
end

function BigText:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function BigText:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, C_BG)
    drawCentered(bb, self.face, self.text, x + math.floor(self.width / 2),
        y + math.floor(self.height / 2), C_TEXT)
end

function BigText:setText(text, refresh_parent)
    if text == self.text then return end
    self.text = text
    if refresh_parent then
        UIManager:setDirty(refresh_parent, function()
            return "fast", Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.width, h = self.height }
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Hive
-- ---------------------------------------------------------------------------

local Hive = Widget:extend{ board = nil, max_width = 300, max_height = 300 }

function Hive:init()
    local w, h = self.max_width, self.max_height
    -- 5.3 radii across, 3*sqrt(3) + a little high (see board_widget.lua).
    local r = math.floor(math.min(w * 0.95 / 5.3, h * 0.95 / (3 * SQRT3 + 0.3)))
    self.r = math.max(14, r)
    self.hex_gap = math.max(2, math.floor(self.r * 0.08))
    self.step = self.r * SQRT3 + self.hex_gap
    self.w = math.min(w, math.floor(5.3 * self.r))
    self.h = math.min(h, math.floor(2 * self.step + self.r * SQRT3) + 4)
    self.dimen = Geom:new{ w = self.w, h = self.h }
    self.face = fitFace("smallinfofontbold", "W", math.floor(self.r * 0.95), math.floor(self.r * 0.85))
end

function Hive:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function Hive:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.w, self.h, C_BG)
    local cx, cy = x + math.floor(self.w / 2), y + math.floor(self.h / 2)
    local r, t = self.r, math.max(2, math.floor(self.r / 18))
    for i = 0, 6 do
        local hx, hy = cx, cy
        if i > 0 then
            local a = math.rad(-90 + (i - 1) * 60)
            hx = cx + math.floor(self.step * math.cos(a) + 0.5)
            hy = cy + math.floor(self.step * math.sin(a) + 0.5)
        end
        local letter = self.board:letterAt(i) or ""
        fillHex(bb, hx, hy, r, C_BORDER)
        if i == 0 then
            drawCentered(bb, self.face, letter, hx, hy, C_BG)
        else
            fillHex(bb, hx, hy, r - math.ceil(t * 2 / SQRT3), C_HEX)
            drawCentered(bb, self.face, letter, hx, hy, C_TEXT)
        end
    end
end

-- ---------------------------------------------------------------------------
-- WordList
--
-- One heading line per length ("5 letters · 5 points"), then its words in
-- columns. The line height is the largest that fits every word on one page,
-- down to a minimum that stays easy to tap; below that the list is paged.
-- Word states (from the screen's `state(word)`):
--   "mine"      claimed by the player claiming now: black, white text
--   "others"    claimed by earlier players: grey box
--   "scored"    written by one player only: bold black
--   "cancelled" written by several: struck through
--   nil         plain (unclaimed: grey once scored)
-- ---------------------------------------------------------------------------

local WordList = InputContainer:extend{
    words      = nil,    -- answers, sorted
    heading    = nil,    -- function(len) -> "5 letters · 5 points"
    title      = "",     -- the line on top ("Ann: tap the words you wrote")
    label      = nil,    -- function(word) -> text drawn (pangram suffix)
    state      = nil,    -- function(word) -> see above
    scored     = false,  -- results view: unclaimed words grey
    page       = 1,
    max_width  = 300,
    max_height = 300,
    onWordTap  = nil,
}

function WordList:init()
    local w, h = self.max_width, self.max_height
    self.w, self.h = w, h
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }

    local by_len, lens = {}, {}
    for _i, word in ipairs(self.words) do
        local l = #word
        if not by_len[l] then by_len[l] = {}; lens[#lens + 1] = l end
        table.insert(by_len[l], word)
    end
    table.sort(lens)
    self.by_len, self.lens = by_len, lens

    self.title_h = math.floor(math.min(h * 0.09, Screen:scaleBySize(44)))
    self.title_face = fitFace("smallinfofontbold", (self.title ~= "" and self.title or "Wg") .. "g",
        math.floor(w * 0.98), math.floor(self.title_h * 0.55))
    local list_h = h - self.title_h
    local min_lh = Screen:scaleBySize(30)
    local max_lh = Screen:scaleBySize(64)
    local chosen
    for lh = max_lh, min_lh, -2 do
        chosen = self:_layout(lh)
        if #chosen.pages <= 1 then break end
    end
    self.lay = chosen
    self.page_count = #chosen.pages
    self.page = math.max(1, math.min(self.page or 1, self.page_count))
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

-- Lines and pages for a line height: { lh, face, bold, colw, cols, pages }.
-- A page is a list of lines; a line is { head = len } or { words = {...} }.
function WordList:_layout(lh)
    local w = self.w
    local face = fitFace("smallinfofont", "Wg", w, math.floor(lh * 0.55))
    local bold = fitFace("smallinfofontbold", "Wg", w, math.floor(lh * 0.55))
    local widest = 0
    for _i, word in ipairs(self.words) do
        widest = math.max(widest, textWidth(bold, self.label and self.label(word) or word))
    end
    local pad = math.floor(lh * 0.6)
    local cols = math.max(1, math.floor(w / (widest + pad)))
    local lines = {}
    for _i, l in ipairs(self.lens) do
        lines[#lines + 1] = { head = l }
        local list = self.by_len[l]
        for k = 1, #list, cols do
            local row = {}
            for j = k, math.min(k + cols - 1, #list) do row[#row + 1] = list[j] end
            lines[#lines + 1] = { words = row }
        end
    end
    local per_page = math.max(2, math.floor((self.h - self.title_h) / lh))
    local pages, page = {}, {}
    for i, line in ipairs(lines) do
        -- A heading never ends a page.
        if #page >= per_page or (line.head and #page == per_page - 1) then
            pages[#pages + 1] = page; page = {}
        end
        page[#page + 1] = line
        if i == #lines then pages[#pages + 1] = page end
    end
    return { lh = lh, face = face, bold = bold, cols = cols, colw = math.floor(w / cols), pages = pages }
end

function WordList:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function WordList:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.w, self.h, C_BG)
    drawCentered(bb, self.title_face, self.title, x + math.floor(self.w / 2),
        y + math.floor(self.title_h / 2), C_TEXT)
    local lay = self.lay
    local lh = lay.lh
    self.cells = {}
    local ly = y + self.title_h
    for _i, line in ipairs(lay.pages[self.page] or {}) do
        local cy = ly + math.floor(lh / 2)
        if line.head then
            drawLeft(bb, lay.bold, self.heading and self.heading(line.head) or tostring(line.head),
                x, cy, C_TEXT)
            bb:paintRect(x, ly + lh - 2, self.w, 1, C_RULE)
        else
            for j, word in ipairs(line.words) do
                local cx = x + (j - 1) * lay.colw
                local st = self.state and self.state(word)
                local text = self.label and self.label(word) or word
                local bx, by, bw, bh = cx + 2, ly + 3, lay.colw - 4, lh - 6
                local color, face = C_TEXT, lay.face
                if st == "mine" then
                    bb:paintRect(bx, by, bw, bh, C_BORDER)
                    color, face = C_BG, lay.bold
                elseif st == "others" then
                    bb:paintRect(bx, by, bw, bh, C_MARK)
                elseif st == "scored" then
                    face = lay.bold
                elseif st == "cancelled" or (self.scored and not st) then
                    color = C_DIM
                end
                local pad = math.floor(lh * 0.25)
                drawLeft(bb, face, text, cx + pad, cy, color)
                if st == "cancelled" then
                    bb:paintRect(cx + pad, cy, textWidth(face, text), math.max(2, math.floor(lh / 16)), C_TEXT)
                end
                self.cells[#self.cells + 1] = { x = cx, y = ly, w = lay.colw, h = lh, word = word }
            end
        end
        ly = ly + lh
    end
end

function WordList:onTap(_, ges)
    if not (ges and ges.pos and self.cells and self.onWordTap) then return true end
    for _i, c in ipairs(self.cells) do
        if ges.pos.x >= c.x and ges.pos.x < c.x + c.w and ges.pos.y >= c.y and ges.pos.y < c.y + c.h then
            self.onWordTap(c.word)
            return true
        end
    end
    return true
end

function WordList:refresh(parent)
    UIManager:setDirty(parent or self, function()
        return "ui", Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.w, h = self.h }
    end)
end

return { BigText = BigText, Hive = Hive, WordList = WordList }
