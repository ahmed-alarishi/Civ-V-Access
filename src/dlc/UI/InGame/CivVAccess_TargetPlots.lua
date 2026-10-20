-- Valid-target enumeration for the map pickers whose choices are few: unit
-- ranged attack / air strike (UnitTargetMode), city bombard
-- (CityRangeStrikeMode), gift unit and gift tile improvement (GiftMode).
-- Each kind mirrors the base game's own highlight pass for that interface
-- mode -- the same search area and the same engine gate -- so the list is
-- exactly what a sighted player sees marked on entry:
--   unit ranged       Bombardment.lua RangedStrikeHighlight / AirStrike-
--                     Highlight: plots within Range() passing
--                     CanRangeStrikeAt (bNeedWar=true -- at-war targets
--                     only, the ValidFireTargetBorder layer)
--   city ranged       the same, from the city with its strike range
--   gift unit         InGame.lua HighlightGiftUnits: own units passing
--                     CanDistanceGift, narrowed to the unit a click on that
--                     plot would actually gift (giftUnitAt)
--   gift improvement  InGame.lua HighlightImprovableCityStatePlots: plots
--                     within MINOR_CIV_RESOURCE_SEARCH_RADIUS of the
--                     city-state's capital passing CanMajorGiftTile-
--                     ImprovementAtPlot
--
-- A scope names one picker's targeting context by IDs only ({ kind, mode,
-- ownerID + unitID / cityID, or toPlayerID }); every read resolves the
-- actor and re-runs the engine gates live, so nothing here outlives the
-- query that produced it. The picker publishes its scope with begin() and
-- withdraws it with finish(); activeScope() additionally requires the
-- engine to still be in the scope's interface mode, so a scope stranded by
-- an exit path that skipped finish() reads as no scope rather than as
-- targets for a picker that is gone.

TargetPlots = {}

TargetPlots.KIND_UNIT_RANGED = "unit_ranged"
TargetPlots.KIND_CITY_RANGED = "city_ranged"
TargetPlots.KIND_GIFT_UNIT = "gift_unit"
TargetPlots.KIND_GIFT_IMPROVEMENT = "gift_improvement"

local _scope = nil

local function resolveUnit(scope)
    local owner = Players[scope.ownerID]
    if owner == nil then
        return nil
    end
    local unit = owner:GetUnitByID(scope.unitID)
    if unit == nil or unit:IsDead() then
        return nil
    end
    return unit
end

local function resolveCity(scope)
    local owner = Players[scope.ownerID]
    if owner == nil then
        return nil
    end
    return owner:GetCityByID(scope.cityID)
end

local function recipientCapital(scope)
    local recipient = Players[scope.toPlayerID]
    if recipient == nil then
        return nil
    end
    return recipient:GetCapitalCity()
end

-- Every plot within hex distance r of (cx, cy), center included.
-- PlotXYWithRangeCheck returns nil for offsets outside the hex radius and
-- off-map, so the square loop needs no distance filter of its own.
local function eachPlotInRange(cx, cy, r, fn)
    for dx = -r, r do
        for dy = -r, r do
            local plot = Map.PlotXYWithRangeCheck(cx, cy, dx, dy, r)
            if plot ~= nil then
                fn(plot)
            end
        end
    end
end

-- The active player's unit a gift-unit click on `plot` would gift. Mirrors
-- InGame.lua GiftUnit's loop, which overwrites on each match, so the last
-- own unit on the plot wins -- and only that unit's CanDistanceGift
-- decides whether the plot is a valid pick.
function TargetPlots.giftUnitAt(plot)
    if plot == nil then
        return nil
    end
    local activePlayer = Game.GetActivePlayer()
    local pUnit = nil
    for i = 0, plot:GetNumUnits() - 1 do
        local pFoundUnit = plot:GetUnit(i)
        if pFoundUnit ~= nil and pFoundUnit:GetOwner() == activePlayer then
            pUnit = pFoundUnit
        end
    end
    return pUnit
end

-- What a valid strike on `plot` would hit. A city tile is attacked as the
-- city (a garrison only defends it), matching UnitTargetMode's
-- combatPreviewAt; otherwise the engine's best at-war defender, civilians
-- included the way CanRangeStrikeAt includes them.
local function strikeTarget(plot, attacker)
    local city = UnitControl.enemyCityAt(plot)
    if city ~= nil then
        return { plot = plot, city = city }
    end
    local unit =
        EngineData.bestDefender(plot, Game.GetActivePlayer(), attacker, { testAtWar = true, noncombatAllowed = true })
    if unit ~= nil then
        return { plot = plot, unit = unit }
    end
    Log.warn("TargetPlots: strikable plot " .. plot:GetX() .. "," .. plot:GetY() .. " has no city or defender")
    return nil
end

-- Why the engine rejected a unit ranged strike on a visible `plot`, named
-- by the reasons the player can't otherwise perceive: the attacker's
-- in-domain-only restriction (a submarine aiming at land or into a lake),
-- then distance, then blocked line of sight. Domain goes first because
-- moving closer can't fix it. nil when none of these explains the refusal
-- (no target there, unit-level limits); callers decide what to say then.
-- Shared by the cursor's targetability prefix and UnitTargetMode's Space
-- preview and commit reasons so the three never disagree.
function TargetPlots.unitStrikeBlockReason(attacker, plot)
    if EngineData.strikeOutsideDomain(attacker, plot) then
        if plot:IsWater() then
            return Text.key("TXT_KEY_CIVVACCESS_TARGET_OTHER_WATERS")
        end
        return Text.key("TXT_KEY_CIVVACCESS_TARGET_SEA_ONLY")
    end
    local attackerPlot = attacker:GetPlot()
    if Map.PlotDistance(attackerPlot:GetX(), attackerPlot:GetY(), plot:GetX(), plot:GetY()) > attacker:Range() then
        return Text.key("TXT_KEY_CIVVACCESS_UNIT_PREVIEW_OUT_OF_RANGE")
    end
    local ignoresLoS = attacker:GetDomainType() == DomainTypes.DOMAIN_AIR or attacker:IsRangeAttackIgnoreLOS()
    if not ignoresLoS and not EngineData.hasLineOfSight(attackerPlot, plot, attacker:GetTeam(), attacker) then
        return Text.key("TXT_KEY_CIVVACCESS_TARGET_UNSEEN")
    end
    return nil
end

-- Per-kind engine gate, against an already-resolved actor.
local function validFor(scope, actor, plot)
    local kind = scope.kind
    if kind == TargetPlots.KIND_UNIT_RANGED then
        return actor:CanRangeStrikeAt(plot:GetX(), plot:GetY(), true, true)
    elseif kind == TargetPlots.KIND_CITY_RANGED then
        return actor:CanRangeStrikeAt(plot:GetX(), plot:GetY())
    elseif kind == TargetPlots.KIND_GIFT_UNIT then
        local unit = TargetPlots.giftUnitAt(plot)
        return unit ~= nil and unit:CanDistanceGift(scope.toPlayerID)
    elseif kind == TargetPlots.KIND_GIFT_IMPROVEMENT then
        local recipient = Players[scope.toPlayerID]
        return recipient ~= nil
            and recipient:CanMajorGiftTileImprovementAtPlot(Game.GetActivePlayer(), plot:GetX(), plot:GetY())
    end
    Log.error("TargetPlots: unknown scope kind " .. tostring(kind))
    return false
end

-- The live actor whose gate decides validity: the attacking unit or city,
-- or for gifts the recipient city-state (non-nil stands for "the gift
-- target still exists"). nil means the picker's subject is gone.
local function resolveActor(scope)
    local kind = scope.kind
    if kind == TargetPlots.KIND_UNIT_RANGED then
        return resolveUnit(scope)
    elseif kind == TargetPlots.KIND_CITY_RANGED then
        return resolveCity(scope)
    end
    return Players[scope.toPlayerID]
end

-- (x, y) the targets are measured from: the attacker's plot, or the
-- recipient city-state's capital for gifts. nil when it can't be resolved.
function TargetPlots.origin(scope)
    local kind = scope.kind
    local anchor
    if kind == TargetPlots.KIND_UNIT_RANGED then
        anchor = resolveUnit(scope)
    elseif kind == TargetPlots.KIND_CITY_RANGED then
        anchor = resolveCity(scope)
    else
        anchor = recipientCapital(scope)
    end
    if anchor == nil then
        return nil, nil
    end
    return anchor:GetX(), anchor:GetY()
end

-- Every valid target for `scope`, as { plot, unit?, city? } records: `city`
-- set for a city to strike, `unit` for a unit to strike or gift, neither for
-- a gift-improvement plot. Order is search order, not distance; callers
-- sort. Empty when the actor is gone.
function TargetPlots.list(scope)
    local out = {}
    local actor = resolveActor(scope)
    if actor == nil then
        return out
    end
    local kind = scope.kind
    if kind == TargetPlots.KIND_UNIT_RANGED or kind == TargetPlots.KIND_CITY_RANGED then
        local range
        if kind == TargetPlots.KIND_UNIT_RANGED then
            range = actor:Range()
        else
            range = EngineData.cityStrikeRange(actor)
        end
        local attacker = (kind == TargetPlots.KIND_UNIT_RANGED) and actor or nil
        eachPlotInRange(actor:GetX(), actor:GetY(), range, function(plot)
            if validFor(scope, actor, plot) then
                local target = strikeTarget(plot, attacker)
                if target ~= nil then
                    out[#out + 1] = target
                end
            end
        end)
    elseif kind == TargetPlots.KIND_GIFT_UNIT then
        local player = Players[Game.GetActivePlayer()]
        if player == nil then
            return out
        end
        -- One entry per plot: stacked own units still gift only the one a
        -- click picks, so a second unit on the same plot is never a target.
        local seen = {}
        for unit in player:Units() do
            local plot = unit:GetPlot()
            if plot ~= nil then
                local idx = plot:GetPlotIndex()
                if not seen[idx] then
                    seen[idx] = true
                    local giftUnit = TargetPlots.giftUnitAt(plot)
                    if giftUnit ~= nil and giftUnit:CanDistanceGift(scope.toPlayerID) then
                        out[#out + 1] = { plot = plot, unit = giftUnit }
                    end
                end
            end
        end
    elseif kind == TargetPlots.KIND_GIFT_IMPROVEMENT then
        local capital = recipientCapital(scope)
        if capital == nil then
            return out
        end
        local radius = GameDefines.MINOR_CIV_RESOURCE_SEARCH_RADIUS or 5
        eachPlotInRange(capital:GetX(), capital:GetY(), radius, function(plot)
            if validFor(scope, actor, plot) then
                out[#out + 1] = { plot = plot }
            end
        end)
    else
        Log.error("TargetPlots.list: unknown scope kind " .. tostring(kind))
    end
    return out
end

-- Whether `plot` is still a valid target for `scope`. The scanner's
-- just-before-speech recheck; a gone actor fails.
function TargetPlots.isValid(scope, plot)
    if plot == nil then
        return false
    end
    local actor = resolveActor(scope)
    if actor == nil then
        return false
    end
    return validFor(scope, actor, plot)
end

-- The valid target nearest the scope's origin, or nil. Pickers land the
-- cursor here on entry. Ties keep search order.
function TargetPlots.nearest(scope)
    local ox, oy = TargetPlots.origin(scope)
    if ox == nil then
        return nil
    end
    local best, bestDist = nil, nil
    for _, target in ipairs(TargetPlots.list(scope)) do
        local d = Map.PlotDistance(ox, oy, target.plot:GetX(), target.plot:GetY())
        if bestDist == nil or d < bestDist then
            best, bestDist = target.plot, d
        end
    end
    return best
end

-- The published scope, or nil when no picker is open or the engine has left
-- the picker's interface mode.
function TargetPlots.activeScope()
    if _scope == nil then
        return nil
    end
    if UI.GetInterfaceMode() ~= _scope.mode then
        return nil
    end
    return _scope
end

-- Publish a picker's scope, which populates the scanner's targets category.
-- The scanner's position is left alone; the player reaches the category with
-- the normal category cycle. Called after the picker's HandlerStack.push
-- succeeds.
function TargetPlots.begin(scope)
    _scope = scope
end

-- Withdraw the scope, emptying the targets category. Safe to call when
-- begin() never ran (move-mode UnitTargetMode).
function TargetPlots.finish()
    _scope = nil
end
