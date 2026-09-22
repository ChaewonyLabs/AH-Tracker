-- RC Market History: pure bounded data/calendar operations, no game APIs or I/O.
AH_PRICE_WATCH_MARKET = {}
local M = AH_PRICE_WATCH_MARKET
M.MAX_INTEGER = 9007199254740991
local fields = { "dailyAvg", "weeklyAvg", "maxPrice", "minPrice", "volume" }
function M.Integer(v)
    if type(v)=="string" then
        v=v:match("^%s*(%d+)%s*$")
        if not v or #v>16 then return nil end
        v=tonumber(v)
    end
    if type(v)~="number" or v~=v or v<0 or v>M.MAX_INTEGER or v~=math.floor(v) then return nil end
    return v
end
function M.Id(v) local n=M.Integer(v); return n and n>0 and n or nil end
local function monthDays(y,m)
    if m==2 then return (y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28 end
    return ({31,28,31,30,31,30,31,31,30,31,30,31})[m]
end
function M.Date(v)
    local n=M.Integer(v)
    if not n then return nil end
    local y=math.floor(n/10000);local m=math.floor(n/100)%100;local d=n%100
    if y<1970 or y>9999 or m<1 or m>12 or d<1 or d>monthDays(y,m) then return nil end
    return n,y,m,d
end
function M.Shift(key, offset)
    local _,y,m,d=M.Date(key)
    if not y or type(offset)~="number" or offset~=math.floor(offset) or math.abs(offset)>366 then return nil end
    local step=offset<0 and -1 or 1
    for i=1,math.abs(offset) do
        d=d+step
        if d<1 then m=m-1;if m<1 then y=y-1;m=12 end;d=monthDays(y,m)
        elseif d>monthDays(y,m) then d=1;m=m+1;if m>12 then y=y+1;m=1 end end
    end
    return M.Date(y*10000+m*100+d)
end
function M.Today()
    -- User confirmed the Market graph's latest date matches local calendar date.
    local ok,key=pcall(function() return os.date("%Y%m%d", os.time()) end)
    return ok and M.Date(key) or nil
end
function M.Row(row)
    if type(row)~="table" then return nil end
    local out={}
    for _,key in ipairs(fields) do out[key]=M.Integer(rawget(row,key));if out[key]==nil then return nil end end
    if out.minPrice>out.maxPrice then return nil end
    return out
end
function M.Parse(payload)
    if type(payload)~="table" then return nil end
    local count=0
    for k in next,payload do
        count=count+1
        if count>14 or type(k)~="number" or k<1 or k>14 or k~=math.floor(k) then return nil end
    end
    if count~=14 then return nil end
    local rows,nonzero={},false
    for i=1,14 do
        local row=M.Row(rawget(payload,i));if not row then return nil end
        rows[i]=row
        for _,key in ipairs(fields) do if row[key]>0 then nonzero=true end end
    end
    return nonzero and rows or nil
end
function M.Prune(state,today)
    local cutoff=today and M.Shift(today,-31)
    for id,grades in pairs(state.marketHistory) do
        for grade,days in pairs(grades) do
            local keys={}
            for day in pairs(days) do
                if cutoff and (day<cutoff or day>today) then days[day]=nil else keys[#keys+1]=day end
            end
            table.sort(keys)
            for i=1,math.max(0,#keys-32) do days[keys[i]]=nil end
            if next(days)==nil then grades[grade]=nil end
        end
        if next(grades)==nil then state.marketHistory[id]=nil end
    end
    for id,grades in pairs(state.marketAttempts) do
        for grade,day in pairs(grades) do
            if today and day~=today then grades[grade]=nil end
        end
        if next(grades)==nil then state.marketAttempts[id]=nil end
    end
end
-- A saved complete, valid, nonzero 14-day window ending today proves a merge.
function M.HasSuccess(state,id,grade,today)
    if not M.Date(today) then return false end
    local days=state.marketHistory[id] and state.marketHistory[id][grade]
    if type(days)~="table" then return false end
    local rows={}
    for i=1,14 do rows[i]=days[M.Shift(today,i-14)];if not rows[i] then return false end end
    return M.Parse(rows)~=nil
end
function M.Migrate(state,today)
    local history,attempts,selected={},{},{}
    local buckets=0
    if type(state.marketHistory)=="table" then
        for id,grades in pairs(state.marketHistory) do
            local item=M.Id(id)
            if item and type(grades)=="table" then
                for g,days in pairs(grades) do
                    local grade=M.Integer(g)
                    if grade and type(days)=="table" and buckets<2048 then
                        buckets=buckets+1;local valid={}
                        for day,row in pairs(days) do
                            local key=M.Date(day);local record=M.Row(row)
                            if key and record then valid[key]=record end
                        end
                        history[item]=history[item] or {};history[item][grade]=valid
                    end
                end
            end
        end
    end
    if type(state.marketAttempts)=="table" then
        for id,grades in pairs(state.marketAttempts) do
            local item=M.Id(id)
            if item and type(grades)=="table" then
                for g,day in pairs(grades) do
                    local grade,key=M.Integer(g),M.Date(day)
                    if grade and key and today==key then attempts[item]=attempts[item] or {};attempts[item][grade]=key end
                end
            end
        end
    end
    if type(state.marketSelected)=="table" then
        for id,entry in pairs(state.marketSelected) do
            local item=M.Id(id)
            if item and type(entry)=="table" and M.Integer(entry.grade) and M.Integer(entry.price) then
                selected[item]={grade=M.Integer(entry.grade),price=M.Integer(entry.price)}
            end
        end
    end
    state.marketHistory,state.marketAttempts,state.marketSelected=history,attempts,selected
    -- Legacy attempt-only locks are not evidence of success. Keep all valid history.
    for id,grades in pairs(attempts) do
        for grade,day in pairs(grades) do
            if not M.HasSuccess(state,id,grade,day) then grades[grade]=nil end
        end
        if next(grades)==nil then attempts[id]=nil end
    end
    state.marketSchema=1
    M.Prune(state,today)
end
function M.Merge(state,id,grade,today,payload)
    if not M.Id(id) or not M.Integer(grade) or not M.Date(today) then return false end
    local rows=M.Parse(payload);if not rows then return false end
    local keys={}
    for i=1,14 do keys[i]=M.Shift(today,i-14);if not keys[i] then return false end end
    local days=state.marketHistory[id] and state.marketHistory[id][grade] or {}
    for i,row in ipairs(rows) do days[keys[i]]=row end
    state.marketHistory[id]=state.marketHistory[id] or {};state.marketHistory[id][grade]=days
    M.Prune(state,today)
    return true
end
local function window(days,today,length)
    local sum,volume,high,overflow=0,0,0,false
    for i=0,length-1 do
        local row=days[M.Shift(today,-i)]
        if not row then return nil,nil end
        local product=row.dailyAvg*row.volume
        if product>M.MAX_INTEGER or sum>M.MAX_INTEGER-product or volume>M.MAX_INTEGER-row.volume then overflow=true end
        if not overflow then sum=sum+product;volume=volume+row.volume end
        high=math.max(high,row.maxPrice)
    end
    return not overflow and volume>0 and math.floor(sum/volume+0.5) or nil,high
end
function M.Stats(state,id,grade,today)
    local out={}
    if not M.Date(today) then return out end
    local days=state.marketHistory[id] and state.marketHistory[id][grade]
    if not days then return out end
    out.avg14,out.high14=window(days,today,14)
    out.avg30,out.high30=window(days,today,30)
    local _,high7=window(days,today,7);out.high7=high7
    out.avg7=days[today] and days[today].weeklyAvg or nil
    local latest=days[M.Shift(today,-1)];local volumes={}
    for i=2,8 do local row=days[M.Shift(today,-i)];if not row then return out end;volumes[#volumes+1]=row.volume end
    table.sort(volumes);local baseline=volumes[4]
    if latest and baseline>0 then
        out.volume=latest.volume>=baseline*1.5 and "High" or (latest.volume<baseline*0.6 and "Low" or "Normal")
    end
    return out
end
-- Recover malformed legacy containers without re-keying any valid history or settings.
function M.RepairLegacy(state)
    for _,key in ipairs({"last","daily","alerts"}) do if type(state[key])~="table" then state[key]={} end end
    if type(state.position)~="table" then state.position={x=300,y=220} end
    if type(state.auto)~="boolean" then state.auto=false end
    for name,last in pairs(state.last) do
        if type(last)~="table" then state.last[name]=nil
        else
            for _,key in ipairs({"price","previousPrice","time","lastSampleTime"}) do
                if last[key]~=nil and not M.Integer(last[key]) then last[key]=nil end
            end
            if type(last.alertSignal)~="string" then last.alertSignal=nil end
        end
    end
    for name,list in pairs(state.daily) do
        local valid={}
        local changed=type(list)~="table"
        if type(list)=="table" then for _,row in ipairs(list) do
            if type(row)=="table" and type(row.key)=="string" and M.Integer(row.count) and M.Integer(row.sum) and M.Integer(row.lastTime) then valid[#valid+1]=row else changed=true end
        end end
        if changed then state.daily[name]=valid end
    end
    for name,alert in pairs(state.alerts) do
        if type(alert)~="table" then state.alerts[name]=nil
        else
            if type(alert.notified)~="table" then alert.notified={} end
            for signal,entry in pairs(alert.notified) do
                if type(entry)~="table" or not M.Integer(entry.price) or not M.Integer(entry.time) then alert.notified[signal]=nil end
            end
        end
    end
    for _,key in ipairs({"x","y"}) do
        local n=tonumber(state.position[key])
        if not n or n~=n or math.abs(n)==math.huge then state.position[key]=key=="x" and 300 or 220 end
    end
end
