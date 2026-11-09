-- party_screen.lua — Spelling Bee · multiplayer: the reader lies on the
-- table and shows the hive big; everyone writes words on paper until the
-- timer runs out. Then the answer list comes up and each player in turn taps
-- the words they wrote: the reader cancels the words several players wrote
-- and adds up the rest. The match itself is party_game.lua.

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
local Font            = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextViewer      = require("ui/widget/textviewer")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local MenuHelper  = require("menu_helper")
local Party       = require("party")
local Timer       = require("timer")
local Board       = lrequire("board")
local Match       = lrequire("party_game")
local Widgets     = lrequire("party_widget")
local Mode        = lrequire("mode")
local Rules       = lrequire("rules")

local DeviceScreen = Device.screen

local STATE_KEY = "party_state"

local function timeLabel(s)
    if s <= 0 then return _("Off") end
    return T(_("%1 min"), math.floor(s / 60))
end

local function clockText(s)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local PartyScreen = ScreenBase:extend{}

function PartyScreen:init()
    self.match = Match.load(self.plugin:loadState(STATE_KEY), self.plugin)
    if not self.match then self:_newMatch() end
    self.page = 1
    ScreenBase.init(self)
    self:_startClock()
end

function PartyScreen:_newMatch()
    self.match = Match.new{
        names      = Party.loadPlayers(self.plugin, Party.loadCount(self.plugin)),
        total      = self.plugin:getSetting("party_rounds", Match.DEFAULT_ROUNDS),
        lang       = self.plugin:getLang({ "fr", "en" }),
        time_limit = self.plugin:getSetting("party_time", Match.DEFAULT_TIME),
        plugin     = self.plugin,
    }
    self.match:nextRound()
    self.page = 1
    self:_save()
end

function PartyScreen:serializeState()
    return self.match:serialize()
end

function PartyScreen:_save()
    self.plugin:saveState(self.match:serialize(), STATE_KEY)
end

-- ScreenBase:closeScreen saves under the solo game's key: keep them apart.
function PartyScreen:closeScreen()
    self:_stopClock()
    self:_save()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function PartyScreen:isRoundOver()
    return self.match:isOver()
end

function PartyScreen:getRoundOverButtons()
    local rows = {}
    if self:_pageRow() then rows[#rows + 1] = self:_pageRow() end
    rows[#rows + 1] = {
        { text = _("New game"), callback = function() self:onNewGame() end },
        { text = _("Details"),  callback = function() self:showDetails() end },
    }
    return rows
end

-- ---------------------------------------------------------------------------
-- Clock: once a second, only the countdown line is repainted.
-- ---------------------------------------------------------------------------

function PartyScreen:_startClock()
    self:_stopClock()
    local m = self.match
    if m.phase ~= "playing" or m.time_limit <= 0 or m.paused then return end
    self.clock = Timer:new()
    self.clock:load{ elapsed = m.time_limit - m.time_left, was_running = true }
    local gen = self._clock_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function PartyScreen:_stopClock()
    self._clock_gen = (self._clock_gen or 0) + 1
    self.clock = nil
end

function PartyScreen:_onTick(gen)
    if gen ~= self._clock_gen or not self.clock then return end
    local m = self.match
    if m:setTimeLeft(m.time_limit - self.clock:getElapsed()) then
        self:_stopClock()
        self:_endRound()
        return
    end
    if self.timer_widget then self.timer_widget:setText(clockText(m.time_left), self) end
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function PartyScreen:_menuItems()
    local m = self.match
    return {
        { text = _("New game"), callback = function() self:onNewGame() end },
        { text = T(_("Players: %1"), m:playerCount()),
          callback = function() Party.pickCount(self.plugin, function() self:onNewGame() end, self) end },
        { text = _("Player names"), callback = function()
            Party.editPlayers(self.plugin, m.scores.names, function()
                self:_save()
                self:_redraw()
            end, self)
        end },
        { text = T(_("Rounds: %1"), m.total), callback = function() self:openRoundsMenu() end },
        { text = T(_("Timer: %1"), timeLabel(m.time_limit)), callback = function() self:openTimeMenu() end },
        { text = T(_("Language: %1"), m.lang:upper()), callback = function() self:openLangMenu() end },
        { text = Mode.label(self.plugin), callback = function() Mode.openMenu(self) end },
        { text = _("Scores"), callback = function() Party.showScoreboard(m.scores) end },
        self:makeModeRulesButtonConfig(Rules),
    }
end

function PartyScreen:_pageRow()
    if not self.list_widget or self.list_widget.page_count <= 1 then return nil end
    local lw = self.list_widget
    return {
        { text = "‹", enabled = self.page > 1, callback = function() self:onPage(-1) end },
        { text = T("%1/%2", self.page, lw.page_count), enabled = false, callback = function() end },
        { text = "›", enabled = self.page < lw.page_count, callback = function() self:onPage(1) end },
    }
end

function PartyScreen:_actionRows()
    local m = self.match
    local rows = {}
    if m.phase == "playing" then
        local row = { { text = _("Shuffle"), callback = function() self:onShuffle() end } }
        if m.time_limit > 0 then
            row[#row + 1] = { text = m.paused and _("Resume") or _("Pause"),
                              callback = function() self:onPause() end }
        end
        row[#row + 1] = { text = _("End round"), callback = function() self:onEndRound() end }
        return { row }
    end
    rows[#rows + 1] = self:_pageRow()
    if m.phase == "claiming" then
        local row = {}
        if m.claimer > 1 then
            row[#row + 1] = { text = _("Previous player"), callback = function() self:onPrevPlayer() end }
        end
        if m.claimer < m:playerCount() then
            row[#row + 1] = { text = _("Next player"), callback = function() self:onNextPlayer() end }
        else
            row[#row + 1] = { text = _("Done"), callback = function() self:onScore() end }
        end
        rows[#rows + 1] = row
    else
        rows[#rows + 1] = {
            { text = _("Details"),    callback = function() self:showDetails() end },
            { text = _("Next round"), callback = function() self:onNextRound() end },
        }
    end
    return rows
end

function PartyScreen:_scoresText()
    local m = self.match
    local rp = (m.phase == "results" or m.phase == "over") and m.round_points or nil
    local parts = {}
    for i, name in ipairs(m.scores.names) do
        local s = name .. " " .. (m.scores.points[i] or 0)
        if rp then s = s .. " (+" .. (rp[i] or 0) .. ")" end
        parts[i] = s
    end
    return table.concat(parts, " · ")
end

-- The list's word states, see WordList in party_widget.lua.
function PartyScreen:_wordState(word)
    local m = self.match
    if m.phase == "claiming" then
        if m:isClaimed(m.claimer, word) then return "mine" end
        if m:claimCount(word) > 0 then return "others" end
        return nil
    end
    local c = m:claimCount(word)
    if c == 1 then return "scored" elseif c > 1 then return "cancelled" end
    return nil
end

function PartyScreen:_listTitle()
    local m = self.match
    if m.phase == "claiming" then
        return T(_("%1: tap the words you wrote"), m.scores.names[m.claimer] or "?")
    elseif m.phase == "over" then
        local leaders = Party.leaders(m.scores)
        return #leaders == 1 and T(_("%1 wins!"), m.scores.names[leaders[1]]) or _("It's a tie!")
    end
    return _("Round results")
end

function PartyScreen:buildLayout()
    local is_landscape = self:isLandscape()
    local m = self.match
    local title_bar = self:buildTitleBar(_("Spelling Bee"), function() return self:_menuItems() end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{ align = "center" }
    self.timer_widget = nil
    if m.phase == "playing" and m.time_limit > 0 then
        local short = math.min(self.dimen.w, self.dimen.h)
        self.timer_widget = Widgets.BigText:new{
            text   = clockText(m.time_left),
            width  = controls_w,
            height = math.floor(short * (is_landscape and 0.2 or 0.15)),
        }
        table.insert(controls, self.timer_widget)
        table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })
    end
    table.insert(controls, TextBoxWidget:new{
        text      = self:_scoresText(),
        face      = Font:getFace("infofont"),
        width     = controls_w,
        alignment = "center",
    })
    table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_default })
    table.insert(controls, self.status_text)
    table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })

    -- The list is built before the bar (the bar's page row needs its page
    -- count), sized for a bar with a page row; a one-page list then gets the
    -- room of that row too, which is harmless.
    local content
    self.list_widget = nil
    if m.phase ~= "playing" then
        local probe = VerticalGroup:new{ align = "center" }
        for i = 1, #controls do probe[i] = controls[i] end
        probe[#probe + 1] = self:buildActionBar({ { { text = "‹" } }, { { text = "›" } } })
        local bw, bh = self:getBoardBudget(title_bar, probe)
        self.list_widget = Widgets.WordList:new{
            words      = m.board.answers,
            title      = self:_listTitle(),
            page       = self.page,
            scored     = m.phase ~= "claiming",
            max_width  = math.max(bw, 120),
            max_height = math.max(bh, 120),
            heading    = function(len)
                if len == Board.MIN_LEN then return T(_("%1 letters · 1 point"), len) end
                return T(_("%1 letters · %2 points"), len, len)
            end,
            label      = function(word)
                if Board.isPangram(word) then
                    return T(_("%1 +%2"), word, Board.wordScore(word) - #word)
                end
                return word
            end,
            state      = function(word) return self:_wordState(word) end,
            onWordTap  = function(word) self:onWordTap(word) end,
        }
        self.page = self.list_widget.page
        content = self.list_widget
    end
    table.insert(controls, self:buildActionBar(self:_actionRows()))

    if not content then
        local bw, bh = self:getBoardBudget(title_bar, controls)
        content = Widgets.Hive:new{ board = m.board, max_width = math.max(bw, 120), max_height = math.max(bh, 120) }
    end

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function PartyScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function PartyScreen:updateStatus(msg)
    local m = self.match
    local round = m.phase ~= "over" and T(_("Round %1/%2"), m.scores.round, m.total) or nil
    local part = msg
    if not part then
        if m.phase == "playing" then
            part = m.paused and _("Paused") or nil
        elseif m.phase == "claiming" then
            part = T(_("Player %1/%2"), m.claimer, m:playerCount())
            if self.times_up and m.claimer == 1 then part = self:joinStatus(_("Time's up!"), part) end
        elseif m.phase == "over" then
            part = _("Final scores")
        end
    end
    ScreenBase.updateStatus(self, self:joinStatus(round, part))
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function PartyScreen:onShuffle()
    self.match.board:shuffle()
    self:_save()
    self:_redraw()
end

function PartyScreen:onPause()
    local m = self.match
    if m.phase ~= "playing" or m.time_limit <= 0 then return end
    if not m.paused and self.clock then
        m:setTimeLeft(m.time_limit - self.clock:getElapsed())
    end
    m.paused = not m.paused
    self:_save()
    self:_redraw()
    self:_startClock()
end

function PartyScreen:onEndRound()
    UIManager:show(ConfirmBox:new{
        text        = _("End the round now?"),
        ok_text     = _("End round"),
        ok_callback = function()
            self.times_up = false
            self:_endRound()
        end,
    })
end

function PartyScreen:_endRound()
    if self.match.phase ~= "playing" then return end
    self.times_up = self.match.time_limit > 0 and self.match.time_left == 0
    self:_stopClock()
    self.match:endRound()
    self.page = 1
    self:_save()
    self:_redraw()
end

-- Claiming: toggle a word for the current player, repaint the list only.
-- Once scored: say who wrote it.
function PartyScreen:onWordTap(word)
    local m = self.match
    if m.phase == "claiming" then
        if m:toggleClaim(word) then
            self:_save()
            self.list_widget:refresh(self)
        end
        return
    end
    local who = {}
    for seat, name in ipairs(m.scores.names) do
        if m:isClaimed(seat, word) then who[#who + 1] = name end
    end
    self:showMessage(T(_("%1: %2"), word, #who > 0 and table.concat(who, ", ") or _("Nobody")), 3)
end

function PartyScreen:onPage(delta)
    self.page = self.page + delta
    self:_redraw()
end

function PartyScreen:onNextPlayer()
    if self.match:nextClaimer() then
        self.page = 1
        self:_save()
        self:_redraw()
    end
end

function PartyScreen:onPrevPlayer()
    if self.match:prevClaimer() then
        self.page = 1
        self:_save()
        self:_redraw()
    end
end

function PartyScreen:onScore()
    if not self.match:score() then return end
    self.page = 1
    self:_save()
    self:_redraw()
    if self.match:isOver() then
        Party.showScoreboard(self.match.scores, { final = true })
    end
end

function PartyScreen:onNextRound()
    if not self.match:nextRound() then return end
    self.times_up = false
    self:_save()
    self:_redraw()
    self:_startClock()
end

function PartyScreen:onNewGame()
    self:_stopClock()
    self.times_up = false
    self:_newMatch()
    self:_redraw()
    self:_startClock()
end

-- Each player's words for the round: the ones that scored, then the
-- cancelled ones.
function PartyScreen:showDetails()
    local m = self.match
    local count = m:outcome()
    local lines = {}
    local points = m.round_points or Match.scoreRound(m.board.answers, m.claims, m:playerCount())
    for seat, name in ipairs(m.scores.names) do
        local kept, gone = {}, {}
        for _i, w in ipairs(m.board.answers) do
            if m:isClaimed(seat, w) then
                if count[w] == 1 then
                    kept[#kept + 1] = w .. " " .. Board.wordScore(w)
                else
                    gone[#gone + 1] = w
                end
            end
        end
        lines[#lines + 1] = T(_("%1 +%2"), name, points[seat] or 0)
        lines[#lines + 1] = #kept > 0 and table.concat(kept, ", ") or "—"
        if #gone > 0 then lines[#lines + 1] = T(_("Cancelled: %1"), table.concat(gone, ", ")) end
        lines[#lines + 1] = ""
    end
    UIManager:show(TextViewer:new{
        title  = _("Details"),
        text   = table.concat(lines, "\n"),
        width  = math.floor(DeviceScreen:getWidth() * 0.9),
        height = math.floor(DeviceScreen:getHeight() * 0.8),
    })
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PartyScreen:openRoundsMenu()
    local items = {}
    for _i, n in ipairs(Match.ROUND_CHOICES) do items[#items + 1] = { id = n, text = tostring(n) } end
    MenuHelper.openPickerMenu{
        title = _("Rounds"), items = items, current_id = self.match.total, parent = self,
        on_select = function(n)
            self.plugin:saveSetting("party_rounds", n)
            self:onNewGame()
        end,
    }
end

-- Takes effect at once: a round in play starts its countdown over.
function PartyScreen:openTimeMenu()
    local items = {}
    for _i, s in ipairs(Match.TIME_CHOICES) do items[#items + 1] = { id = s, text = timeLabel(s) } end
    MenuHelper.openPickerMenu{
        title = _("Timer"), items = items, current_id = self.match.time_limit, parent = self,
        on_select = function(s)
            self.plugin:saveSetting("party_time", s)
            local m = self.match
            m.time_limit = s
            if m.phase == "playing" then m.time_left, m.paused = s, false end
            self:_save()
            self:_redraw()
            self:_startClock()
        end,
    }
end

function PartyScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title = _("Language"),
        items = { { id = "en", text = _("English") }, { id = "fr", text = "Français" } },
        current_id = self.match.lang, parent = self,
        on_select = function(lang)
            self.plugin:setLang(lang)
            self:onNewGame()
        end,
    }
end

-- The word lists are only needed while a game is open: drop them when the
-- screen closes (the next game reads its language's lists again).
function PartyScreen:onCloseWidget()
    Board.release()
end

return PartyScreen
