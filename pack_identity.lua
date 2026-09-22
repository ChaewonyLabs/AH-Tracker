-- Live-confirmed Pack correction only. No game APIs, requests or statistical changes.
AH_PRICE_WATCH_PACK_IDENTITY = {}
local P=AH_PRICE_WATCH_PACK_IDENTITY
local C=AH_PRICE_WATCH_CATALOG
local oldIds={ [9001532]=45914, [9001534]=45915 }
function P.Migrate(items,state)
    if type(items)~="table" then return {} end
    local entries,groups,clear={},{},{}
    for _,source in ipairs(items) do
        if type(source)=="table" and type(source.name)=="string" and source.name~="" then
            local item={};for k,v in pairs(source) do item[k]=v end
            local pack=C.VerifiedPack(item.name)
            local explicit=tonumber(item.id) or tonumber(item.itemType)
            local wasCorrect=pack and explicit==pack.id
            if pack and explicit==oldIds[pack.id] then
                clear[explicit]=true
                item.id=pack.id
                if item.itemType~=nil then item.itemType=pack.id end
            elseif wasCorrect and tonumber(item.itemType)==oldIds[pack.id] then
                -- A correct primary ID with a stale legacy identity field.
                clear[oldIds[pack.id]]=true;item.itemType=pack.id
            end
            local record=C.ForItem(item)
            local id=record and record.id
            local entry={item=item,id=id,correct=explicit==id}
            entries[#entries+1]=entry
            if oldIds[id] then
                local group=groups[id]
                if not group then group={entries={},winner=entry};groups[id]=group end
                group.entries[#group.entries+1]=entry
                if entry.correct and not group.winner.correct then group.winner=entry end
            end
        end
    end
    -- Correct-ID entry wins every conflict (including an explicit targetGold=0).
    -- Missing settings are inherited; placement uses the earliest slot in the group.
    for _,group in pairs(groups) do
        local winner=group.winner.item
        for _,entry in ipairs(group.entries) do
            for k,v in pairs(entry.item) do
                if winner[k]==nil and k~="id" and k~="itemType" then winner[k]=v end
            end
        end
    end
    local out,emitted={},{}
    for _,entry in ipairs(entries) do
        local group=groups[entry.id]
        if not group then out[#out+1]=entry.item
        elseif not emitted[entry.id] then
            out[#out+1]=group.winner.item;emitted[entry.id]=true
        end
    end
    -- Old series may belong to non-Pack identities: never copy them to the new IDs.
    -- Invalidate only when an explicit old-ID + exact Pack-name pair was corrected.
    if type(state)=="table" then
        for id in pairs(clear) do
            for _,field in ipairs({"marketHistory","marketSelected","marketAttempts"}) do
                if type(state[field])=="table" then state[field][id]=nil;state[field][tostring(id)]=nil end
            end
        end
    end
    return out
end
