-- Civilopedia stat-frame harvest. The Great People frame's title is not the
-- static XML label: the pedia overwrites GPTitle per building with the
-- specialist's GreatPeopleTitle ("Great Merchant Points:"), and that is the
-- only place the article names which great person the points go toward.

local T = require("support")
local M = {}

local function frame(hidden)
    return {
        IsHidden = function()
            return hidden
        end,
    }
end

local function label(text)
    return {
        GetText = function()
            return text
        end,
    }
end

local function setup()
    Log.warn = function() end
    Log.error = function() end
    Log.info = function() end
    Log.debug = function() end
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    SpeechPipeline._reset()
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_HandlerStack.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuItems.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_CivilopediaCore.lua")
end

local function harvest()
    local leaves = {}
    Civilopedia._harvestInto(leaves, nil, 0)
    local out = {}
    for i, leaf in ipairs(leaves) do
        out[i] = leaf.labelText
    end
    return out
end

function M.test_great_people_frame_speaks_live_specialist_title()
    setup()
    Controls = {
        GreatPeopleFrame = frame(false),
        GPTitle = label("Great Merchant Points:"),
        GreatPeopleLabel = label("1 [ICON_GREAT_PEOPLE]"),
    }
    local leaves = harvest()
    T.eq(#leaves, 1)
    T.eq(leaves[1], "Great Merchant Points: 1")
end

function M.test_great_people_frame_falls_back_to_static_label()
    setup()
    Controls = {
        GreatPeopleFrame = frame(false),
        GPTitle = label(""),
        GreatPeopleLabel = label("2 [ICON_GREAT_PEOPLE]"),
    }
    local leaves = harvest()
    T.eq(#leaves, 1)
    T.eq(leaves[1], Text.key("TXT_KEY_PEDIA_GP_LABEL") .. ": 2")
end

return M
