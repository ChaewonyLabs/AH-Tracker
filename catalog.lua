-- Static Wiki names and pure Lua lookup only. No game/network APIs.
AH_PRICE_WATCH_CATALOG = {}
local C = AH_PRICE_WATCH_CATALOG
local rows = AH_PRICE_WATCH_ITEM_CATALOG or {}
local byId, exactEN, exactKO, folded = {}, {}, {}, {}
local function fold(text) return string.lower(tostring(text or "")) end
local function add(index, name, item)
    local key = fold(name)
    index[key] = index[key] or {}
    index[key][#index[key] + 1] = item
end
for _, item in ipairs(rows) do
    byId[item.id] = item
    add(exactEN, item.en, item)
    add(exactKO, item.ko, item)
    folded[item.id] = fold(item.en)
end
function C.ById(id) return byId[tonumber(id)] end
-- Exact Pack names have live-confirmed AH identities; other catalog IDs remain intact.
local verifiedPacks = { ["solar temper pack"]=9001532, ["lunar temper pack"]=9001534 }
function C.VerifiedPack(text)
    return C.ById(verifiedPacks[fold(text):match("^%s*(.-)%s*$")])
end
function C.Display(item, language)
    if language == "KO" and type(item.ko) == "string" and item.ko:match("%S") then return item.ko end
    return item.en
end
function C.Exact(text, language)
    return (language == "KO" and exactKO or exactEN)[fold(text)] or {}
end
function C.ForItem(item)
    if not item then return nil end
    local record = C.ById(item.id) or C.ById(item.itemType)
    if record then return record end -- Valid catalog ID takes precedence over saved aliases.
    local pack = C.VerifiedPack(item.name)
    if pack and item.id==nil and item.itemType==nil then return pack end
    local matches = C.Exact(item.name, "EN")
    if #matches == 1 then return matches[1] end
end
function C.Hydrate(items)
    for _, item in ipairs(items) do
        local record = C.ForItem(item)
        if record then item.id = record.id end
    end
end
function C.QueryName(item, searchLanguage)
    local record = C.ForItem(item)
    return searchLanguage == "KO" and record and C.Display(record,"KO") or item.name
end
function C.ItemDisplayName(item, language)
    local record = C.ForItem(item)
    return language == "KO" and record and C.Display(record,"KO") or item.name
end
function C.Matches(item, name, itemType)
    local record = C.ForItem(item)
    local expectedId = record and record.id or tonumber(item.id) or tonumber(item.itemType)
    -- A numeric result ID proves identity independently of decorated display names.
    if itemType ~= nil and expectedId then
        return type(itemType) == "number" and itemType > 0 and itemType < math.huge and itemType % 1 == 0 and itemType == expectedId
    end
    if item.name == name then return true end
    if not record then return false end
    if name == record.en then return itemType ~= nil or #C.Exact(name, "EN") == 1 end
    if name == record.ko then return itemType ~= nil or #C.Exact(name, "KO") == 1 end
    return false
end
function C.Search(text, language, limit, preferred)
    local query = fold(text):match("^%s*(.-)%s*$")
    if query == "" then return {} end
    local hits, seen = {}, {}
    local function include(item)
        if not item or seen[item.id] then return end
        local pack = C.VerifiedPack(item.en)
        if pack and pack.id ~= item.id then return end
        local haystack = language == "KO" and fold(C.Display(item,"KO")) or folded[item.id]
        if string.find(haystack, query, 1, true) then
            hits[#hits + 1] = item; seen[item.id] = true
        end
    end
    -- Put known watchlist IDs first, without claiming AH eligibility for others.
    for _, item in ipairs(preferred or {}) do include(C.ForItem(item)) end
    for _, item in ipairs((AH_PRICE_WATCH_CONFIG or {}).items or {}) do include(C.ForItem(item)) end
    for _, item in ipairs(C.Exact(query, language)) do include(item) end
    for _, item in ipairs(rows) do
        if #hits >= (limit or 6) then break end
        include(item)
    end
    while #hits > (limit or 6) do table.remove(hits) end
    return hits
end
function C.Resolve(text, language, selectedId)
    local name = tostring(text or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil, "emptyName" end
    local pack = C.VerifiedPack(name)
    if pack then return pack end
    local selected = C.ById(selectedId)
    if selected and (fold(name) == fold(C.Display(selected, language)) or fold(name) == fold(selected.en)) then
        return selected
    end
    local matches = C.Exact(name, language)
    if #matches == 0 then matches = C.Exact(name, "EN") end
    if #matches == 1 then return matches[1] end
    if #matches > 1 then return nil, "catalogAmbiguous" end
    return nil, "catalogSelect"
end
