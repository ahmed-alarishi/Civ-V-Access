-- Scenarios menu wrapper tests. The engine lists every installed Firaxis
-- scenario; the wrapper offers only the ones the mod supports end to end.
-- Loads the real wrapper over the real BaseMenu stack. The base screen's
-- globals (g_ScenarioList, SetSelected, OnBack) are stubbed as the external
-- boundary they are, the same way engine globals are.

local T = require("support")
local Setup = require("menu_test_setup")
local M = {}

local CIVIL_WAR = "55fd836a-72e5-4aba-bbcf-3395b05a0e70"

local selections

local function setup()
    Setup.fresh()
    T.installLocaleStrings({ TXT_KEY_LOAD_SCENARIO = "Load Scenario", TXT_KEY_BACK_BUTTON = "Back" })
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_SCREEN_SCENARIOS"] = "Scenarios"
    include = function() end
    -- Base's list, sorted by display name. The supported scenario sits
    -- between unsupported ones, so an entry that selects by its position in
    -- the offered list instead of base's index is caught.
    g_ScenarioList = {
        { DisplayName = "1066: Year of Viking Destiny", ModID = "daf6f887-3614-4169-a0e5-3ac9bd4ef82b" },
        { DisplayName = "American Civil War", DisplayDescription = "The Eastern Theater.", ModID = CIVIL_WAR },
        { DisplayName = "Fall of Rome", ModID = "76d702e9-8b28-429b-a97d-f84388f548c5" },
    }
    g_iSelected = nil
    selections = {}
    SetSelected = function(index)
        selections[#selections + 1] = index
        g_iSelected = index
    end
    OnBack = function() end
    Controls = {
        StartButton = Polyfill.makeButton(),
        BackButton = Polyfill.makeButton(),
    }
end

-- Load the wrapper. BaseMenu.install is routed to a test Context so the
-- global ContextPtr stays nil for the other suites.
local function load()
    local ctx = Setup.makeContextPtr()
    local realInstall = BaseMenu.install
    local menu
    BaseMenu.install = function(_, spec)
        menu = realInstall(ctx, spec)
        return menu
    end
    dofile("src/dlc/UI/Shared/CivVAccess_ScenarioRegistry.lua")
    dofile("src/dlc/UI/FrontEnd/CivVAccess_ScenariosMenuAccess.lua")
    BaseMenu.install = realInstall
    return menu
end

local function labels(menu)
    local out = {}
    for i, item in ipairs(menu._items) do
        out[i] = item.labelText or item.textKey
    end
    return table.concat(out, " | ")
end

function M.test_lists_only_supported_scenarios()
    setup()
    local menu = load()
    T.eq(labels(menu), "American Civil War | TXT_KEY_LOAD_SCENARIO | TXT_KEY_BACK_BUTTON")
end

function M.test_choosing_a_scenario_selects_its_base_entry()
    setup()
    local menu = load()
    menu._items[1]:activate(menu)
    T.eq(#selections, 1)
    T.eq(selections[1], 2, "base's index for the Civil War entry")
end

return M
