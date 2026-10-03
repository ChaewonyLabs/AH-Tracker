-- Explicit, approved Item ID groups. Pure Lua; no Auction calls or saved data.
AH_PRICE_WATCH_VARIANTS = {}
local V = AH_PRICE_WATCH_VARIANTS
local C = AH_PRICE_WATCH_CATALOG

local definitions = {
    {
        key = "wrapped_serendipity_stone",
        en = "Wrapped Serendipity Stone",
        anchors = {8001000, 9001920},
        allowed = {8001000, 9001920},
    },
}

-- Current approval and Market callback collisions are separate identity sets.
local marketCollisionIds = {
    [39424] = true,
    [8001000] = true,
    [8001875] = true,
    [9001920] = true,
    -- Intentional non-auctionable Bound exception: shares 8001000's KO callback name.
    -- This exact ID is not a Current variant; no generic Bound-prefix rule is used.
    [46682] = true,
}
local blockedMarketNames = {}
-- Phase 1 Current-only fallback: no callback token or safe stale-drain proof.
for id in pairs(marketCollisionIds) do
    local record = C.ById(id)
    assert(record, "invalid Market collision ID")
    -- Exact callback aliases of explicitly blocked IDs; never discover new block IDs.
    blockedMarketNames[record.en], blockedMarketNames[record.ko] = true, true
end

local byAnchor = {}
for _,group in ipairs(definitions) do
    local allowed = {}
    for _,id in ipairs(group.allowed) do
        local record = C.ById(id)
        assert(record and record.en == group.en and not allowed[id], "invalid variant ID")
        allowed[id] = true
    end
    group.allowedIds = allowed
    for _,id in ipairs(group.anchors) do
        local record = C.ById(id)
        assert(record and record.en == group.en and not byAnchor[id], "invalid variant anchor")
        byAnchor[id] = group
    end
end

function V.ForItem(item, searchLanguage)
    if searchLanguage ~= "EN" or type(item) ~= "table" then return nil end
    local record = C.ForItem(item)
    return record and byAnchor[record.id] or nil
end

-- Static across scans, time, and addon reinitialization; never released by a callback.
function V.MarketNameBlocked(name)
    return type(name) == "string" and blockedMarketNames[name] == true
end

function V.MarketBlocked(item)
    if type(item) ~= "table" then return false end
    -- Match the catalog's explicit-ID precedence, without name-only resolution.
    -- An unrelated/unknown ID never joins the block through its EN/KO aliases.
    local record = C.ById(rawget(item, "id")) or C.ById(rawget(item, "itemType"))
    return record ~= nil and marketCollisionIds[record.id] == true
end

function V.Matches(group, itemType)
    return group ~= nil and type(itemType) == "number" and
        itemType > 0 and itemType < math.huge and itemType % 1 == 0 and
        group.allowedIds[itemType] == true
end

function V.MatchesListing(group, itemType, name)
    if not V.Matches(group, itemType) or type(name) ~= "string" then return false end
    local record = C.ById(itemType)
    return record ~= nil and (name == record.en or name == record.ko)
end
