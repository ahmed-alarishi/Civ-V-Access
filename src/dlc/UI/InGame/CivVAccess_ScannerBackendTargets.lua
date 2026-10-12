-- Scanner backend: valid targets of the open map picker. TargetPlots owns
-- the enumeration and the engine gates; this file is just the scanner
-- shape. Emits nothing unless a picker has published a scope and the
-- engine is still in that picker's interface mode, so outside a pick the
-- category is empty and Nav's categoryHasItems filter skips it.
--
-- Naming:
--   * strike a city      the city's name, under the cities sub
--   * strike a unit      the unit's scanner name ("Roman Warrior"), under
--                        the units sub; same-type targets collapse into one
--                        item whose instances Alt+PageUp/Down steps through
--   * gift a unit        the unit's own-units scanner name, into `all`
--   * gift improvement   the plot's resource, into `all`
-- Unit names come from ScannerBackendUnits so a target reads exactly as the
-- same unit does in the units categories.

ScannerBackendTargets = {
    name = "targets",
}

local function entryFor(scope, target, activeTeam)
    local plot = target.plot
    local name, sub
    if target.city ~= nil then
        name = Text.key(target.city:GetNameKey())
        sub = "cities"
    elseif target.unit ~= nil then
        if scope.kind == TargetPlots.KIND_GIFT_UNIT then
            name = ScannerBackendUnits.unitItemName(target.unit, "units_my", false)
            sub = "all"
        else
            name = ScannerBackendUnits.unitItemName(target.unit, "units_enemy", false)
            sub = "units"
        end
    else
        -- Gift-improvement plots always carry a resource: the engine gate
        -- rejects plots without one.
        local row = GameInfo.Resources[plot:GetResourceType(activeTeam)]
        if row ~= nil then
            name = Text.key(row.Description)
        end
        sub = "all"
    end
    if name == nil or name == "" then
        Log.warn(
            "ScannerBackendTargets: no name for "
                .. tostring(scope.kind)
                .. " target at "
                .. plot:GetX()
                .. ","
                .. plot:GetY()
        )
        return nil
    end
    local plotIndex = plot:GetPlotIndex()
    return {
        plotIndex = plotIndex,
        backend = ScannerBackendTargets,
        data = { kind = scope.kind },
        category = "targets",
        subcategory = sub,
        itemName = name,
        key = "targets:" .. plotIndex,
        sortKey = 0,
    }
end

function ScannerBackendTargets.Scan(_activePlayer, activeTeam)
    local scope = TargetPlots.activeScope()
    if scope == nil then
        return {}
    end
    local out = {}
    for _, target in ipairs(TargetPlots.list(scope)) do
        local entry = entryFor(scope, target, activeTeam)
        if entry ~= nil then
            out[#out + 1] = entry
        end
    end
    return out
end

-- Re-run the engine gate right before speech: a target killed, moved off,
-- or put out of reach since the rebuild drops instead of being announced.
-- The kind check catches a different picker having opened in between.
function ScannerBackendTargets.ValidateEntry(entry, _cursorPlotIndex)
    local scope = TargetPlots.activeScope()
    if scope == nil or scope.kind ~= entry.data.kind then
        return false
    end
    return TargetPlots.isValid(scope, Map.GetPlotByIndex(entry.plotIndex))
end

-- itemName is resolved per Scan, and every scanner keystroke rebuilds from
-- a fresh Scan, so it is current at announce time.
function ScannerBackendTargets.FormatName(entry)
    return entry.itemName
end

ScannerCore.registerBackend(ScannerBackendTargets)
