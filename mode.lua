-- mode.lua — the in-game "Mode: Solo / Multiplayer" setting. Switching closes
-- this screen and opens the other mode's (PluginBase:showGame), which starts
-- or resumes that mode's own game.

local MenuHelper = require("menu_helper")
local _          = require("i18n")
local T          = require("ffi/util").template

local Mode = {}

function Mode.label(plugin)
    return T(_("Mode: %1"), plugin.launch_mode == "party" and _("Multiplayer") or _("Solo"))
end

function Mode.openMenu(screen)
    local plugin = screen.plugin
    MenuHelper.openPickerMenu{
        title      = _("Mode"),
        items      = { { id = "solo", text = _("Solo") }, { id = "party", text = _("Multiplayer") } },
        current_id = plugin.launch_mode == "party" and "party" or "solo",
        parent     = screen,
        on_select  = function(mode)
            if mode == (plugin.launch_mode or "solo") then return end
            screen:closeScreen()
            plugin:showGame(mode)
        end,
    }
end

return Mode
