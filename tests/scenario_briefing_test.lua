-- Scenario briefing reader (Shift+B, and a launch bar row). A supported
-- scenario's mouse-only Briefing button shows its briefing text; the reader
-- lists the same text, one heading or paragraph per item. Drives the real
-- ScenarioBriefing, ScenarioRegistry, GameScreens and LaunchBar through
-- BaseMenu and InputRouter; the engine side (the game's activated mods, the
-- scenario's text) is stubbed.

local T = require("support")
local Setup = require("menu_test_setup")
local M = {}

local WM_KEYDOWN = 256
local MOD_SHIFT = 1

local CIVIL_WAR = "55fd836a-72e5-4aba-bbcf-3395b05a0e70"

local BRIEFING = "SCENARIO DESCRIPTION[NEWLINE]April the 12th, 1861.[NEWLINE][NEWLINE]"
    .. "VICTORY CONDITIONS[NEWLINE]Win by capturing your opponent's capital.[NEWLINE][NEWLINE]"
    .. "SPECIAL RULES[NEWLINE]City razing and settlers are off."

local activeMods

local function setup()
    Setup.fresh()
    T.installLocaleStrings({
        TXT_KEY_CIVIL_WAR_SCENARIO_BRIEFING_BUTTON = "Briefing",
        TXT_KEY_CIVIL_WAR_SCENARIO_CIV5_DAWN_TEXT = BRIEFING,
    })
    activeMods = {}
    Modding.GetActivatedMods = function()
        return activeMods
    end
    -- The rest of the registry's screens, as an ordinary single player game.
    Game.IsOption = function()
        return false
    end
    Game.IsNetworkMultiPlayer = function()
        return false
    end
    Game.IsCustomModOption = nil
    Game.GetNumActiveLeagues = function()
        return 0
    end
    Game.GetActivePlayer = function()
        return 0
    end
    Players[0] = {
        GetEndTurnBlockingType = function()
            return EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE
        end,
    }
    dofile("src/dlc/UI/Shared/CivVAccess_ScenarioRegistry.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_ScenarioBriefing.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_Turn.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_GameScreens.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_LaunchBar.lua")
end

local function playCivilWar()
    activeMods = { { ID = CIVIL_WAR, Version = 1 } }
end

local function itemLabels(menu)
    local out = {}
    for i, item in ipairs(menu._items) do
        out[i] = item.labelText
    end
    return table.concat(out, " | ")
end

function M.test_lists_the_briefing_one_heading_or_paragraph_per_item()
    setup()
    playCivilWar()
    ScenarioBriefing.open()
    local menu = HandlerStack.active()
    T.eq(menu.name, "ScenarioBriefing")
    T.eq(menu.displayName, "Briefing", "named by the scenario's own button label")
    T.eq(
        itemLabels(menu),
        "SCENARIO DESCRIPTION | April the 12th, 1861. | VICTORY CONDITIONS"
            .. " | Win by capturing your opponent's capital. | SPECIAL RULES"
            .. " | City razing and settlers are off."
    )
end

function M.test_shift_b_opens_the_briefing_in_a_supported_scenario()
    setup()
    playCivilWar()
    local briefing = ScenarioBriefing.getBindings()
    T.eq(#briefing.bindings, 1)
    T.eq(briefing.bindings[1].key, Keys.B)
    T.eq(briefing.bindings[1].mods, MOD_SHIFT)
    T.eq(#briefing.helpEntries, 1, "listed in help")
    briefing.bindings[1].fn()
    T.eq(HandlerStack.active().name, "ScenarioBriefing")
end

function M.test_games_without_a_supported_scenario_have_no_briefing()
    setup()
    activeMods = { { ID = "some-other-mod", Version = 1 } }
    local briefing = ScenarioBriefing.getBindings()
    T.eq(#briefing.bindings, 0, "Shift+B stays unbound")
    T.eq(#briefing.helpEntries, 0, "help doesn't advertise it")
    for _, entry in ipairs(GameScreens.list()) do
        T.truthy(entry.id ~= "briefing", "no launch bar row")
    end
end

function M.test_launch_bar_lists_the_briefing_with_its_key()
    setup()
    playCivilWar()
    local rows = {}
    for i, item in ipairs(LaunchBar.buildItems()) do
        rows[i] = item:announce(HandlerStack.active())
    end
    T.truthy(table.concat(rows, " | "):find("Briefing, Shift plus B", 1, true), "row named and keyed")
end

function M.test_esc_closes_the_briefing()
    setup()
    playCivilWar()
    ScenarioBriefing.open()
    InputRouter.dispatch(Keys.VK_ESCAPE, 0, WM_KEYDOWN)
    T.eq(HandlerStack.active(), nil, "back on the map")
    T.eq(Setup.speaks[#Setup.speaks].text, "canceled")
end

return M
