local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ConfirmBox      = require("ui/widget/confirmbox")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextViewer      = require("ui/widget/textviewer")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local MenuHelper  = require("menu_helper")
local Board       = lrequire("board")
local BoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- SpellingBeeScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Spelling Bee — Rules

Make words from the seven letters of the hive.

• Words have at least 4 letters.
• Every word must contain the centre letter (the black one).
• Letters can be used more than once.
• Every puzzle has at least one pangram: a word using all seven letters.

Tap the letters to type, then Enter. Shuffle mixes the outer letters to help you see new words.

Scoring: a 4-letter word is worth 1 point, a longer word one point per letter, and a pangram 7 points more. Your rank climbs from Beginner to Genius as your score grows; Queen Bee means every word found.

The answers are common words. Rarer words the dictionary knows are accepted as bonus words: they appear in grey, lowercase, and score nothing. Hint first gives the start and length of a missing word, then reveals it (worth no points). Reveal answers ends the puzzle and shows the words you missed.

Daily Challenge gives everyone the same letters for the day.
]])

local GAME_RULES_FR = [[
Spelling Bee — Règles

Formez des mots avec les sept lettres de la ruche.

• Les mots ont au moins 4 lettres.
• Chaque mot doit contenir la lettre centrale (la noire).
• Une lettre peut servir plusieurs fois.
• Chaque grille a au moins un pangramme : un mot qui utilise les sept lettres.

Touchez les lettres pour écrire, puis Entrée. Mélanger change la place des lettres extérieures pour aider à voir de nouveaux mots. Les accents sont ignorés : É s'écrit E.

Points : un mot de 4 lettres vaut 1 point, un mot plus long un point par lettre, et un pangramme 7 points de plus. Votre rang monte de Débutant à Génie avec le score ; Reine des abeilles veut dire tous les mots trouvés.

Les réponses sont des mots courants. Les mots plus rares du dictionnaire sont acceptés comme mots bonus : ils s'affichent en gris, en minuscules, et ne rapportent rien. Astuce donne d'abord le début et la longueur d'un mot manquant, puis le révèle (sans points). Voir les réponses termine la grille et montre les mots manqués.

Le Défi du jour donne les mêmes lettres à tout le monde pour la journée.
]]

-- Rank names, in Board.RANK_PCT order.
local RANK_NAMES = {
    _("Beginner"), _("Good Start"), _("Moving Up"), _("Good"), _("Solid"),
    _("Nice"), _("Great"), _("Amazing"), _("Genius"), _("Queen Bee"),
}

local SpellingBeeScreen = ScreenBase:extend{}

function SpellingBeeScreen:init()
    local state    = self.plugin:loadState()
    local sys_lang = require("i18n").lang()
    local lang     = self.plugin:getSetting("lang", (sys_lang == "fr") and "fr" or "en")
    self.board = Board:new{ lang = lang, empty = true }
    if not self.board:load(state) then
        self.board.lang = lang
        self.board:newGame()
    end
    ScreenBase.init(self)
end

function SpellingBeeScreen:serializeState()
    return self.board:serialize()
end

function SpellingBeeScreen:isRoundOver()
    return self.board:isOver()
end

function SpellingBeeScreen:getRoundOverButtons()
    return {
        { text = _("New game"),  callback = function() self:onNewGame() end },
        { text = _("Word list"), callback = function() self:showWordList() end },
    }
end

function SpellingBeeScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Spelling Bee"), function()
        return {
            { text = _("New game"),        callback = function() self:onNewGame() end },
            { text = _("Daily Challenge"), callback = function() self:onDailyGame() end },
            { text = T(_("Language: %1"), self.board.lang:upper()),
              callback = function() self:openLangMenu() end },
            { text = _("Word list"),       callback = function() self:showWordList() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_actionRows(is_landscape)),
    }

    local frame_pad = Size.padding.default
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BoardWidget:new{
        board       = self.board,
        max_width   = math.max(budget_w - 2 * frame_pad, 120),
        max_height  = math.max(budget_h - 2 * frame_pad, 160),
        rank_name   = function(i) return RANK_NAMES[i] or "" end,
        found_label = function(n, bonus)
            local s = n == 1 and _("1 word found") or T(_("%1 words found"), n)
            if bonus > 0 then s = s .. "  ·  " .. T(_("Bonus: %1"), bonus) end
            return s
        end,
        onHexTap    = function(letter) self:onLetter(letter) end,
        onListTap   = function() self:showWordList() end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

-- Typing keys first, then the help. The narrow landscape side panel cannot
-- fit three labels plus "Reveal answers" in two rows, so there it gets three.
function SpellingBeeScreen:_actionRows(is_landscape)
    local delete  = { text = _("Delete"),  callback = function() self:onDelete() end }
    local shuffle = { text = _("Shuffle"), callback = function() self:onShuffle() end }
    local enter   = { text = _("Enter"),   callback = function() self:onEnter() end }
    local hint    = { text = _("Hint"),    callback = function() self:onHint() end }
    local reveal  = { text = _("Reveal answers"), callback = function() self:onReveal() end }
    if is_landscape then
        return { { delete, enter }, { shuffle, hint }, { reveal } }
    end
    return { { delete, shuffle, enter }, { hint, reveal } }
end

function SpellingBeeScreen:_save()
    self.plugin:saveState(self.board:serialize())
end

-- Typing only repaints the board; the status line is only touched when it
-- still shows the previous word's message, so a tap costs one small refresh.
function SpellingBeeScreen:_clearMessage()
    if self.showing_msg then self:updateStatus() end
end

function SpellingBeeScreen:onLetter(letter)
    if not self.board:typeLetter(letter) then return end
    self.hint_cell = nil
    self.board_widget:refresh()
    self:_clearMessage()
end

function SpellingBeeScreen:onDelete()
    if not self.board:deleteLetter() then return end
    self.board_widget:refresh()
    self:_clearMessage()
end

function SpellingBeeScreen:onShuffle()
    self.board:shuffle()
    self.board_widget:refresh()
    self:_save()
end

function SpellingBeeScreen:onEnter()
    local result, word, points = self.board:submit()
    if result == "empty" or result == "over" then return end
    local msg
    if result == "short" then
        msg = _("Word too short!")
    elseif result == "no_centre" then
        msg = T(_("Missing the centre letter %1."), self.board.centre)
    elseif result == "already" then
        msg = T(_("Already found: %1"), word)
    elseif result == "unknown" then
        msg = _("Not in word list!")
    elseif result == "bonus" then
        msg = T(_("%1: bonus word, no points."), word)
    elseif result == "found" then
        if self.board:isComplete() then
            msg = nil -- the round-over status says it
        elseif Board.isPangram(word) then
            msg = T(_("Pangram! %1 +%2"), word, points)
        else
            msg = T(_("%1 +%2"), word, points)
        end
    end
    self.hint_cell = nil
    self:_save()
    self.board_widget:refresh()
    self:updateStatus(msg)
    self:refreshActionBar()
end

function SpellingBeeScreen:onReveal()
    if self.board:isOver() then return end
    UIManager:show(ConfirmBox:new{
        text = _("Show every answer? This ends the puzzle."),
        ok_text = _("Reveal"),
        ok_callback = function()
            self.board:reveal()
            self.hint_cell = nil
            self:_save()
            self.board_widget:refresh()
            self:updateStatus()
            self:refreshActionBar()
        end,
    })
end

-- Hints name a word, not a cell (see ScreenBase:onHint for the two taps).
function SpellingBeeScreen:describeHintStep(step, level)
    local word = step.word or ""
    if level == 1 then
        return T(_("A %1-letter word starting with %2 is missing. Tap Hint again to reveal it."),
            #word, word:sub(1, 2))
    end
    return T(_("%1, no points."), word)
end

function SpellingBeeScreen:onNewGame()
    self.board.lang = self.plugin:getSetting("lang", self.board.lang)
    self.board:newGame()
    self.hint_cell = nil
    self:_save()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Today's letters for the current language. Replaying it after a different
-- puzzle starts it over: one saved game at a time.
function SpellingBeeScreen:onDailyGame()
    self.board.lang = self.plugin:getSetting("lang", self.board.lang)
    self.board:newDailyGame()
    self.hint_cell = nil
    self:_save()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SpellingBeeScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "en", text = _("English") }, { id = "fr", text = "Français" } },
        current_id = self.board.lang,
        parent     = self,
        on_select  = function(lang)
            self.plugin:saveSetting("lang", lang)
            self:onNewGame()
        end,
    }
end

-- The full list: found words, then (once revealed) the missed ones, then the
-- bonus words. The board only shows what fits.
function SpellingBeeScreen:showWordList()
    local b = self.board
    local found, missed = {}, b:getMissing()
    for _i, w in ipairs(b.answers) do
        if b.found_set[w] then
            found[#found + 1] = (b.found_set[w] == "hint") and (w .. " (" .. _("Hint") .. ")") or w
        end
    end
    local lines = { T(_("Words: %1/%2"), #b.found, #b.answers), "" }
    lines[#lines + 1] = #found > 0 and table.concat(found, ", ") or "—"
    if b.revealed and #missed > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = T(_("Missed (%1):"), #missed)
        lines[#lines + 1] = table.concat(missed, ", ")
    end
    if b:isOver() then
        lines[#lines + 1] = ""
        lines[#lines + 1] = T(_("Pangrams: %1"), table.concat(b:getPangrams(), ", "))
    end
    if #b.bonus > 0 then
        local bonus = {}
        for i, w in ipairs(b.bonus) do bonus[i] = w end
        table.sort(bonus)
        lines[#lines + 1] = ""
        lines[#lines + 1] = T(_("Bonus: %1"), #bonus)
        lines[#lines + 1] = table.concat(bonus, ", ")
    end
    UIManager:show(TextViewer:new{
        title  = _("Word list"),
        text   = table.concat(lines, "\n"),
        width  = math.floor(DeviceScreen:getWidth() * 0.9),
        height = math.floor(DeviceScreen:getHeight() * 0.8),
    })
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function SpellingBeeScreen:updateStatus(msg)
    self.showing_msg = msg ~= nil
    local b = self.board
    local status = msg
    if not status then
        if b:isComplete() then
            status = T(_("Every word found! %1"), RANK_NAMES[b:getRank()])
        elseif b.revealed then
            status = T(_("Found %1 of %2."), #b.found, #b.answers)
        else
            status = self:joinStatus(
                b.daily and _("Daily Challenge") or nil,
                T(_("Words: %1/%2"), #b.found, #b.answers),
                T(_("Score: %1"), b:getScore()),
                b.hints_used > 0 and T(_("Hints used: %1"), b.hints_used) or nil)
        end
    end
    ScreenBase.updateStatus(self, status)
end

return SpellingBeeScreen
