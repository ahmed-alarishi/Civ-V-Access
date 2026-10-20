-- ShadowedTextPopupAnnounce tests. A mod that ships its own TextPopup.lua (the
-- restyled Firaxis scenarios do) shadows our hooked copy, so its text popups
-- open with no hook: the box takes Enter and Esc itself and nothing tells the
-- player it is up. Unless the hook's liveness probe says TextPopupAccess owns
-- the popup, the announcer buffers the message and opens the same dismiss menu
-- the reward popups get (the message, then a Close button), and closes it when
-- the box reports itself processed. Real modules dofiled over the shared menu
-- harness: SpeechPipeline (capturing through _speakAction), TextFilter, Text,
-- BaseMenu, HandlerStack, MessageBuffer, RewardReview,
-- ShadowedTextPopupAnnounce, and TextPopupAccess for the probe it publishes.
-- Seams: the popup events (their listeners are captured so tests fire
-- synthetic popups), the box's Context lookup, UIManager, and the game text.

local T = require("support")
local Setup = require("menu_test_setup")
local M = {}

local speaks = Setup.speaks

local WM_KEYDOWN = 256
local MOD_ALT = 4

local TEXT_POPUP = 0
local OTHER_POPUP = 46

local EVENT_TEXT = "PRO-UNION EVENT: Emancipation Proclamation[NEWLINE][NEWLINE]Freedom proclaimed."

local popupListeners, processedListeners, dequeued

local function setup()
    Setup.fresh()
    T.installLocaleStrings({
        TXT_KEY_TEST_BRIEFING = "Brother against brother.",
        TXT_KEY_CLOSE = "Close",
    })
    include = function() end
    ButtonPopupTypes = ButtonPopupTypes or {}
    ButtonPopupTypes.BUTTONPOPUP_TEXT = TEXT_POPUP
    popupListeners, processedListeners, dequeued = {}, {}, {}
    Events.SerialEventGameMessagePopup = {
        Add = function(fn)
            popupListeners[#popupListeners + 1] = fn
        end,
    }
    Events.SerialEventGameMessagePopupProcessed = {
        Add = function(fn)
            processedListeners[#processedListeners + 1] = fn
        end,
    }
    UIManager = UIManager or {}
    UIManager.DequeuePopup = function(_, ctx)
        dequeued[#dequeued + 1] = ctx
    end
    civvaccess_shared.textPopupHookProbe = nil
    dofile("src/dlc/UI/InGame/CivVAccess_MessageBuffer.lua")
    MessageBuffer._reset()
    dofile("src/dlc/UI/InGame/Popups/CivVAccess_RewardReview.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_ShadowedTextPopupAnnounce.lua")
    ShadowedTextPopupAnnounce.install()
end

local function firePopup(popupInfo)
    for _, fn in ipairs(popupListeners) do
        fn(popupInfo)
    end
end

local function fireProcessed(popupType)
    for _, fn in ipairs(processedListeners) do
        fn(popupType, 0)
    end
end

local function buffered()
    local state = MessageBuffer._snapshot()
    return state and state.entries or {}
end

local function spoken()
    local out = {}
    for i, s in ipairs(speaks) do
        out[i] = s.text
    end
    return table.concat(out, " | ")
end

-- A stand-in for the map handler the box opens over.
local function pushMap()
    HandlerStack.push(BaseMenu.create({
        name = "Map",
        displayName = "Map",
        items = { BaseMenuItems.Text({ labelText = "map" }) },
    }))
end

function M.test_opens_a_close_menu_for_a_shadowed_text_popup()
    setup()
    firePopup({ Type = TEXT_POPUP, Data1 = 500, Data2 = 1, Text = EVENT_TEXT })
    local menu = HandlerStack.active()
    T.eq(menu.name, "ShadowedTextPopup")
    T.eq(menu.displayName, "Notification", "named like the hooked text popup")
    T.eq(#menu._items, 1, "one dismiss button")
    T.eq(menu._items[1].labelText, "Close")
    T.eq(menu._items[1].verboseKindKey, "TXT_KEY_CIVVACCESS_KIND_BUTTON", "announced as a button")
    local said = spoken()
    T.truthy(said:find("Emancipation Proclamation", 1, true), "speaks the popup's message")
    T.truthy(said:find("Freedom proclaimed.", 1, true))
    T.truthy(said:find("Close", 1, true), "lands on Close")
    T.eq(said:find("[NEWLINE]", 1, true), nil, "markup is stripped before speech")
    T.eq(#buffered(), 1)
    T.eq(buffered()[1].text, EVENT_TEXT)
    T.eq(buffered()[1].category, "notification")
end

function M.test_closing_the_box_returns_to_the_map()
    setup()
    pushMap()
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    T.eq(HandlerStack.active().name, "ShadowedTextPopup")
    fireProcessed(TEXT_POPUP)
    T.eq(HandlerStack.active().name, "Map", "Enter or Esc on the box closes the menu with it")
end

function M.test_another_popup_closing_leaves_the_menu_open()
    setup()
    pushMap()
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    fireProcessed(OTHER_POPUP)
    T.eq(HandlerStack.active().name, "ShadowedTextPopup")
end

function M.test_close_closes_the_box_the_way_its_button_does()
    setup()
    local box = { name = "scenario text popup Context" }
    local lookedUp
    ContextPtr = {
        LookUpControl = function(_, path)
            lookedUp = path
            return box
        end,
    }
    local ok, err = pcall(function()
        firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
        local menu = HandlerStack.active()
        menu._items[1]:activate(menu)
    end)
    ContextPtr = nil
    T.truthy(ok, tostring(err))
    T.eq(lookedUp, "/InGame/TextPopup")
    T.eq(#dequeued, 1)
    T.eq(dequeued[1], box)
end

function M.test_alt_down_reviews_the_message_line_by_line()
    setup()
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    InputRouter.dispatch(Keys.VK_DOWN, MOD_ALT, WM_KEYDOWN)
    T.eq(speaks[#speaks].text, "PRO-UNION EVENT: Emancipation Proclamation")
end

function M.test_stays_silent_while_the_hook_is_alive()
    setup()
    civvaccess_shared.textPopupHookProbe = function()
        return true
    end
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    T.eq(HandlerStack.active(), nil, "TextPopupAccess opens its own menu instead")
    T.eq(#speaks, 0)
    T.eq(#buffered(), 0)
end

function M.test_opens_when_the_hooks_env_is_gone()
    setup()
    civvaccess_shared.textPopupHookProbe = function()
        return false
    end
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    T.eq(
        HandlerStack.active().name,
        "ShadowedTextPopup",
        "a probe left over from an earlier game no longer vouches for the hook"
    )
end

function M.test_opens_when_the_hook_probe_throws()
    setup()
    civvaccess_shared.textPopupHookProbe = function()
        error("attempt to index a nil value")
    end
    firePopup({ Type = TEXT_POPUP, Text = EVENT_TEXT })
    T.eq(HandlerStack.active().name, "ShadowedTextPopup")
    T.eq(#Setup.errors, 1, "the probe failure is logged")
end

function M.test_ignores_other_popup_types()
    setup()
    firePopup({ Type = OTHER_POPUP, Data1 = 1, Data2 = -1 })
    T.eq(HandlerStack.active(), nil)
    T.eq(#speaks, 0)
    T.eq(#buffered(), 0)
end

function M.test_resolves_a_text_key_the_way_the_popup_does()
    setup()
    firePopup({ Type = TEXT_POPUP, Text = "TXT_KEY_TEST_BRIEFING" })
    T.eq(HandlerStack.active().preamble, "Brother against brother.")
    T.eq(buffered()[1].text, "Brother against brother.")
end

-- The probe TextPopupAccess publishes reads its own Context's env: alive while
-- that env stands, dead once the engine wipes it on game exit or load.
function M.test_text_popup_access_publishes_a_live_probe()
    setup()
    Controls = {
        DescriptionLabel = Polyfill.makeLabel("A message."),
        CloseButton = Polyfill.makeButton(),
    }
    InputHandler = function() end
    ShowHideHandler = function() end
    OnCloseButtonClicked = function() end
    local ctx = Setup.makeContextPtr()
    local realInstall = BaseMenu.install
    BaseMenu.install = function(_, spec)
        return realInstall(ctx, spec)
    end
    dofile("src/dlc/UI/InGame/Popups/CivVAccess_TextPopupAccess.lua")
    BaseMenu.install = realInstall
    local probe = civvaccess_shared.textPopupHookProbe
    T.truthy(probe ~= nil and probe(), "alive while its env stands")
    local baseMenu = BaseMenu
    BaseMenu = nil
    local alive = probe()
    BaseMenu = baseMenu
    T.falsy(alive, "dead once the env's globals are gone")
end

return M
