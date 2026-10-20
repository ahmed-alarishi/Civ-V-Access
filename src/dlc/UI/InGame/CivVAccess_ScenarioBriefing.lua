-- Scenario briefing reader: Shift+B on the map, and a row in the Shift+Tab
-- launch bar, in a game running a scenario ScenarioRegistry knows. The
-- briefing (scenario description, victory conditions, special rules) lives
-- behind the scenario's mouse-only Briefing button; this lists the same text
-- split at the game's own line breaks, one heading or paragraph per item, so
-- the player can arrow to the part they need. Speech only: the scenario's
-- popup is not opened. Built on every open, and absent (no chord, no help
-- entry, no launch bar row) in games without a supported scenario.

ScenarioBriefing = {}

local MOD_SHIFT = 1

local MENU_NAME = "ScenarioBriefing"

function ScenarioBriefing.available()
    return ScenarioRegistry.active() ~= nil
end

-- The scenario's own Briefing button label, naming the launch bar row.
function ScenarioBriefing.nameKey()
    return ScenarioRegistry.active().briefingLabel
end

function ScenarioBriefing.open()
    local scenario = ScenarioRegistry.active()
    local paragraphs = {}
    BaseMenuItems.addSections(paragraphs, Text.key(scenario.briefingText))
    local items = {}
    for i, paragraph in ipairs(paragraphs) do
        items[i] = BaseMenuItems.Text({ labelText = paragraph })
    end
    HandlerStack.removeByName(MENU_NAME, false)
    HandlerStack.push(BaseMenu.create({
        name = MENU_NAME,
        displayName = Text.key(scenario.briefingLabel),
        items = items,
        capturesAllInput = true,
        escapePops = true,
        escapeAnnounce = Text.key("TXT_KEY_CIVVACCESS_CANCELED"),
    }))
end

-- Shift+B for BaselineHandler, opened through GameScreens so the chord and
-- the launch bar row can't drift apart. The engine binds only plain B
-- (ranged attack, found city, Brazilwood camp), and no mod chord takes
-- Shift+B.
function ScenarioBriefing.getBindings()
    if not ScenarioBriefing.available() then
        return { bindings = {}, helpEntries = {} }
    end
    return {
        bindings = {
            HandlerStack.bind(Keys.B, MOD_SHIFT, GameScreens.opener("briefing"), "Read scenario briefing"),
        },
        helpEntries = {
            {
                keyLabel = "TXT_KEY_CIVVACCESS_BRIEFING_HELP_KEY",
                description = "TXT_KEY_CIVVACCESS_BRIEFING_HELP_DESC",
            },
        },
    }
end
