-- Scanner targets category: TargetPlots enumeration through the targets
-- backend, the per-entry recheck, and how the category behaves in
-- ScannerNav (left alone on picker entry, forced auto-move once reached). A wrong list here is a silent failure in the worst place --
-- the player commits an attack or a gift on what the scanner said was a
-- valid target -- so the gate wiring, search radius, and stacked-unit pick
-- are each pinned.

local T = require("support")
local M = {}

local MODE_RANGE = InterfaceModeTypes.INTERFACEMODE_RANGE_ATTACK
local MODE_GIFT_UNIT = InterfaceModeTypes.INTERFACEMODE_GIFT_UNIT
local MODE_GIFT_IMPROVEMENT = InterfaceModeTypes.INTERFACEMODE_GIFT_TILE_IMPROVEMENT

local _mode
local _cursorX, _cursorY

-- Unit fixture covering what TargetPlots (resolve, range, gates) and
-- ScannerBackendUnits.unitItemName (type row, religion, name) read.
local function makeUnit(opts)
    local u = {}
    function u:GetID()
        return opts.id
    end
    function u:GetOwner()
        return opts.owner
    end
    function u:IsDead()
        return false
    end
    function u:GetUnitType()
        return opts.unitType or 1
    end
    function u:GetReligion()
        return -1
    end
    function u:HasName()
        return false
    end
    function u:GetPlot()
        return opts.plot
    end
    function u:GetX()
        return opts.plot:GetX()
    end
    function u:GetY()
        return opts.plot:GetY()
    end
    function u:Range()
        return opts.range or 2
    end
    function u:CanRangeStrikeAt(x, y, needWar, noncombat)
        u.lastStrikeArgs = { needWar, noncombat }
        return opts.strikable ~= nil and opts.strikable[x .. "," .. y] == true
    end
    function u:CanDistanceGift(_toPlayer)
        return opts.giftable == true
    end
    return u
end

-- Plot with a fixed best defender (the engine's GetBestDefender answer).
local function makePlot(x, y, idx, opts)
    opts = opts or {}
    local p = T.fakePlot({
        x = x,
        y = y,
        plotIndex = idx,
        units = opts.units,
        isCity = opts.city ~= nil,
        city = opts.city,
        resource = opts.resource,
    })
    function p:GetBestDefender()
        return opts.defender
    end
    return p
end

local function makeCity(owner, x, y, name)
    local c = T.fakeCity({ owner = owner, name = name })
    function c:GetNameKey()
        return name
    end
    function c:GetX()
        return x
    end
    function c:GetY()
        return y
    end
    return c
end

local function installPlayers(units0, units1, extra1)
    local p0 = T.fakePlayer({ units = units0, adj = "Mine" })
    local p1 = T.fakePlayer({ units = units1, adj = "Roman", team = 1 })
    for k, v in pairs(extra1 or {}) do
        p1[k] = v
    end
    Players = { [0] = p0, [1] = p1 }
    Teams = { [0] = T.fakeTeam({ atWar = { [1] = true } }), [1] = T.fakeTeam() }
end

local function setup()
    dofile("src/dlc/UI/Shared/CivVAccess_HandlerStack.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    SpeechPipeline._reset()
    SpeechPipeline._speakAction = function() end
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TypeAheadSearch.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_MessageBuffer.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_UnitSpeech.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_UnitControlSelection.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_UnitControlCombat.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_UnitControlMovement.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_UnitControlCore.lua")
    ScannerCore = nil
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerCore.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerSnap.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerSearch.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerBackendUnits.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_TargetPlots.lua")
    -- Only the targets backend scans: the real units backend registered
    -- above would also emit the fixture units into the units categories.
    ScannerCore.BACKENDS = {}
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerBackendTargets.lua")
    civvaccess_shared = {}
    ScannerFavorites = nil
    _cursorX, _cursorY = 9, 9
    Cursor = {
        position = function()
            return _cursorX, _cursorY
        end,
        jumpTo = function(x, y)
            _cursorX, _cursorY = x, y
            return ""
        end,
    }
    ScannerInput = { open = function() end }
    dofile("src/dlc/UI/InGame/CivVAccess_ScannerNav.lua")
    ScannerNav._reset()
    _mode = MODE_RANGE
    UI.GetInterfaceMode = function()
        return _mode
    end
    Game.GetActivePlayer = function()
        return 0
    end
    Game.GetActiveTeam = function()
        return 0
    end
    Game.IsDebugMode = function()
        return false
    end
    GameInfo = {
        Units = { [1] = { Description = "Warrior" }, [2] = { Description = "Archer" } },
        Resources = { [5] = { Description = "Iron" } },
    }
    Log.warn = function() end
    Log.error = function() end
end

local function scanByKey()
    local out = {}
    for _, e in ipairs(ScannerBackendTargets.Scan(0, 0)) do
        out[e.plotIndex] = e
    end
    return out
end

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Archer at (0,0), range 2. (1,0) enemy unit and (2,0) enemy city are
-- strikable; (1,1) holds an enemy the engine refuses; (3,0) is past the
-- range even though the gate would accept it, so it must never be asked.
local function rangedFixture()
    local enemy = makeUnit({ id = 7, owner = 1, unitType = 1 })
    local enemyCity = makeCity(1, 2, 0, "Antium")
    local origin = makePlot(0, 0, 0)
    local pUnit = makePlot(1, 0, 1, { defender = enemy })
    local pCity = makePlot(2, 0, 2, { city = enemyCity })
    local pRefused = makePlot(1, 1, 3, { defender = enemy })
    local pFar = makePlot(3, 0, 4, { defender = enemy })
    T.installMap({ origin, pUnit, pCity, pRefused, pFar })
    local archer = makeUnit({
        id = 3,
        owner = 0,
        unitType = 2,
        plot = origin,
        range = 2,
        strikable = { ["1,0"] = true, ["2,0"] = true, ["3,0"] = true },
    })
    installPlayers({ archer }, { enemy })
    return archer
end

local function rangedScope()
    return { kind = TargetPlots.KIND_UNIT_RANGED, mode = MODE_RANGE, ownerID = 0, unitID = 3 }
end

function M.test_unit_ranged_lists_strikable_plots_in_range_split_by_kind()
    setup()
    local archer = rangedFixture()
    TargetPlots.begin(rangedScope())
    local byIdx = scanByKey()
    T.eq(count(byIdx), 2, "only the two strikable in-range plots")
    T.eq(byIdx[1].subcategory, "units")
    T.eq(byIdx[1].itemName, "Roman Warrior")
    T.eq(byIdx[2].subcategory, "cities")
    T.eq(byIdx[2].itemName, "Antium")
    T.eq(byIdx[4], nil, "a plot past Range() is outside the search area")
    -- At-war targets only, civilians included: the sighted highlight's gate.
    T.eq(archer.lastStrikeArgs[1], true, "bNeedWar")
    T.eq(archer.lastStrikeArgs[2], true, "bNoncombatAllowed")
end

function M.test_scan_is_empty_without_a_scope_or_after_the_mode_changes()
    setup()
    rangedFixture()
    T.eq(#ScannerBackendTargets.Scan(0, 0), 0, "no picker open")
    TargetPlots.begin(rangedScope())
    _mode = InterfaceModeTypes.INTERFACEMODE_SELECTION
    T.eq(#ScannerBackendTargets.Scan(0, 0), 0, "engine left the picker's mode")
    _mode = MODE_RANGE
    TargetPlots.finish()
    T.eq(#ScannerBackendTargets.Scan(0, 0), 0, "picker closed")
end

function M.test_validate_drops_a_target_the_engine_no_longer_accepts()
    setup()
    local archer = rangedFixture()
    TargetPlots.begin(rangedScope())
    local entry = scanByKey()[1]
    T.truthy(ScannerBackendTargets.ValidateEntry(entry, nil))
    archer.CanRangeStrikeAt = function()
        return false
    end
    T.falsy(ScannerBackendTargets.ValidateEntry(entry, nil), "target killed or out of reach since the rebuild")
end

function M.test_gift_unit_lists_only_the_unit_a_click_would_gift()
    setup()
    local stackPlot = makePlot(1, 0, 1)
    local lonePlot = makePlot(2, 0, 2)
    -- Stack: the engine's click loop gifts the LAST own unit on the plot,
    -- so only that one's CanDistanceGift counts, and the plot lists once.
    local under = makeUnit({ id = 1, owner = 0, unitType = 2, plot = stackPlot, giftable = true })
    local top = makeUnit({ id = 2, owner = 0, unitType = 1, plot = stackPlot, giftable = true })
    stackPlot._units = { under, top }
    local refused = makeUnit({ id = 3, owner = 0, unitType = 1, plot = lonePlot, giftable = false })
    lonePlot._units = { refused }
    local capital = makeCity(1, 0, 0, "Geneva")
    T.installMap({ makePlot(0, 0, 0), stackPlot, lonePlot })
    installPlayers({ under, top, refused }, {}, { _capital = capital })
    _mode = MODE_GIFT_UNIT
    TargetPlots.begin({ kind = TargetPlots.KIND_GIFT_UNIT, mode = MODE_GIFT_UNIT, toPlayerID = 1 })
    local byIdx = scanByKey()
    T.eq(count(byIdx), 1, "one entry for the stack, none for the refused unit")
    T.eq(byIdx[1].itemName, "Warrior", "the top unit, named as an own unit")
    T.eq(byIdx[1].subcategory, "all")
end

function M.test_gift_improvement_searches_around_the_city_state_capital()
    setup()
    GameDefines.MINOR_CIV_RESOURCE_SEARCH_RADIUS = 1
    local near = makePlot(11, 10, 1, { resource = 5 })
    local far = makePlot(12, 10, 2, { resource = 5 })
    T.installMap({ makePlot(10, 10, 0), near, far })
    local capital = makeCity(1, 10, 10, "Geneva")
    installPlayers({}, {}, {
        _capital = capital,
        CanMajorGiftTileImprovementAtPlot = function(_self, _from, _x, _y)
            return true
        end,
    })
    _mode = MODE_GIFT_IMPROVEMENT
    TargetPlots.begin({ kind = TargetPlots.KIND_GIFT_IMPROVEMENT, mode = MODE_GIFT_IMPROVEMENT, toPlayerID = 1 })
    local byIdx = scanByKey()
    GameDefines.MINOR_CIV_RESOURCE_SEARCH_RADIUS = nil
    T.truthy(byIdx[1] ~= nil, "plot inside the search radius")
    T.eq(byIdx[1].itemName, "Iron", "named for its resource")
    T.eq(byIdx[2], nil, "plot past the radius")
end

function M.test_nearest_picks_the_closest_target_to_the_actor()
    setup()
    rangedFixture()
    local plot = TargetPlots.nearest(rangedScope())
    T.eq(plot:GetPlotIndex(), 1, "(1,0) is one step from the archer, the city two")
end

-- ===== Scanner navigation =====

-- A stub cities backend so the player has a normal category to be on.
local function registerCitiesStub()
    ScannerCore.registerBackend({
        name = "stub",
        Scan = function()
            return { T.mkEntry("cities", "my", "Rome", 0, { backend = ScannerCore.BACKENDS[2] }) }
        end,
        ValidateEntry = function()
            return true
        end,
        FormatName = function(e)
            return e.itemName
        end,
    })
end

local function currentCategoryKey()
    local catIdx = ScannerNav._indices()
    return ScannerNav._snapshot().categories[catIdx].key
end

function M.test_opening_a_picker_leaves_the_scanner_where_it_was()
    setup()
    rangedFixture()
    registerCitiesStub()
    ScannerNav.cycleCategory(0)
    T.eq(currentCategoryKey(), "cities")
    TargetPlots.begin(rangedScope())
    ScannerNav.cycleItem(1)
    T.eq(currentCategoryKey(), "cities", "the picker must not pull the scanner onto targets")
end

function M.test_cycling_into_targets_moves_the_cursor_with_auto_move_off()
    setup()
    rangedFixture()
    registerCitiesStub()
    civvaccess_shared.scannerAutoMove = false
    _cursorX, _cursorY = 0, 0
    ScannerNav.cycleCategory(0)
    TargetPlots.begin(rangedScope())
    ScannerNav.cycleCategory(1)
    T.eq(currentCategoryKey(), "targets", "populated, so the category cycle reaches it")
    T.eq(_cursorX, 1, "landing moved the cursor onto the nearest target")
    T.eq(_cursorY, 0)
    ScannerNav.cycleItem(1)
    T.eq(_cursorX, 2, "and on to the next")
    -- Leaving the category restores the player's own setting.
    ScannerNav.cycleCategory(1)
    T.eq(currentCategoryKey(), "cities")
    T.eq(_cursorX, 2, "cities landing does not move the cursor with auto-move off")
end

return M
