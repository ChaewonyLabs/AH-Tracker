-- Local data operations only; no game APIs.
AH_PRICE_WATCH_FEATURES = {}
local F = AH_PRICE_WATCH_FEATURES

function F.CopyItems(items)
    local copy = {}
    if type(items)~="table" then return copy end
    for _, item in ipairs(items) do
        if type(item)=="table" and type(item.name)=="string" and item.name~="" then
            local entry={}
            for key,value in pairs(item) do entry[key]=value end
            local target=tonumber(entry.targetGold)
            if not target or target~=target or target<0 or target==math.huge then entry.targetGold=0 end
            copy[#copy+1]=entry
        end
    end
    return copy
end

function F.ItemName(value)
    local name = tostring(value or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil, "emptyName" end
    if #name > 64 or name:find("[^ -~]") then return nil, "englishName" end
    return name
end

function F.TargetCopper(gold, silver, copper)
    local parts = { gold, silver, copper }
    for i = 1, 3 do
        local text = tostring(parts[i] or ""):match("^%s*(.-)%s*$")
        if text == "" then text = "0" end
        if not text:match("^%d+$") or #text > 8 then return nil, "invalidPrice" end
        parts[i] = tonumber(text)
    end
    if parts[1] > 99999999 or parts[2] > 99 or parts[3] > 99 then return nil, "invalidPrice" end
    return parts[1] * 10000 + parts[2] * 100 + parts[3]
end

function F.ValidateItems(items)
    local seen = {}
    for _, item in ipairs(items) do
        local known = AH_PRICE_WATCH_CATALOG and AH_PRICE_WATCH_CATALOG.ForItem(item)
        local name, err
        if known then name = item.name else name, err = F.ItemName(item.name) end
        if not name then return false, err end
        local key = string.lower(name)
        if seen[key] then return false, "duplicateName" end
        seen[key] = true
        local target = tonumber(item.targetGold)
        if not target or target ~= target or target < 0 or target > 99999999.9999 then
            return false, "invalidPrice"
        end
    end
    return true
end

local rank = { BUY = 1, GREAT = 2, TARGET = 3 }
function F.Alert(book, name, signal, price, now, cooldown)
    local entry = book[name] or { notified = {} }
    book[name] = entry
    entry.notified = entry.notified or {}
    local previousRank = rank[entry.signal] or 0
    local currentRank = rank[signal] or 0
    local upgrade = previousRank > 0 and currentRank > previousRank
    entry.signal, entry.price = signal, price
    if currentRank == 0 then return false end
    local previous = entry.notified[signal]
    -- Reopening AH with the last notified price/signal never repeats it, even
    -- after the cooldown. A stronger observed signal bypasses the cooldown.
    local notify = upgrade or not previous or
        (previous.price ~= price and now - previous.time >= cooldown)
    if not notify then return false end
    entry.notified[signal] = { price = price, time = now }
    return true
end
