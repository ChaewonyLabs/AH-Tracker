-- Local confirmed Current observations. Pure Lua; no requests, callbacks or I/O.
AH_PRICE_WATCH_OBSERVATIONS = {}
local O = AH_PRICE_WATCH_OBSERVATIONS
O.FIELD, O.SOURCE, O.POLICY = "currentObservations", "local_current_page1", "two_generations_hourly_v1"
O.HOUR, O.MAX_BUCKETS, O.MAX_INTEGER = 3600, 721, 9007199254740991
local function integer(v, low, high)
    return type(v)=="number" and v==v and v==math.floor(v) and v>=low and v<=high
end
function O.Time(v) return integer(v,1,253402300799) and v or nil end
function O.Hour(v) return O.Time(v) and math.floor(v/O.HOUR) or nil end
local function frame(value)
    return type(value)=="table" and value.schema==1 and value.source==O.SOURCE and
        value.policy==O.POLICY and type(value.groups)=="table"
end
local function bucket(hour, row)
    if not integer(hour,0,math.floor(253402300799/O.HOUR)) or type(row)~="table" or row.confirmed~=true or
        not O.Time(row.firstTime) or not O.Time(row.lastTime) or row.lastTime<row.firstTime or
        O.Hour(row.firstTime)~=hour or O.Hour(row.lastTime)~=hour or
        not integer(row.sampleUnit,1,O.MAX_INTEGER) or not integer(row.maxUnit,row.sampleUnit,O.MAX_INTEGER) or
        not integer(row.observationCount,2,O.MAX_INTEGER) then return nil end
    return {firstTime=row.firstTime,lastTime=row.lastTime,sampleUnit=row.sampleUnit,maxUnit=row.maxUnit,
        observationCount=row.observationCount,confirmed=true}
end
local function fresh(key)
    return {schema=1,source=O.SOURCE,policy=O.POLICY,groups={[key]={buckets={}}}}
end
function O.Normalize(value,key)
    if value==nil then return nil,false end
    -- Future feature formats remain opaque to this version, including on resave.
    if type(value)=="table" and integer(value.schema,2,O.MAX_INTEGER) then return nil,true end
    if not frame(value) then return nil,false end
    local out=fresh(key);local group=value.groups[key]
    if type(group)~="table" or type(group.buckets)~="table" then return out,false end
    local valid,keys,count={},{},0
    for hour,row in pairs(group.buckets) do
        count=count+1;if count>4096 then return out,false end
        local b=bucket(hour,row)
        if b then valid[hour]=b;keys[#keys+1]=hour end
    end
    table.sort(keys)
    for i=math.max(1,#keys-O.MAX_BUCKETS+1),#keys do out.groups[key].buckets[keys[i]]=valid[keys[i]] end
    return out,false
end
function O.Has(value,key)
    if not frame(value) then return false end
    local group=value.groups[key]
    if type(group)~="table" or type(group.buckets)~="table" then return false end
    for hour,row in pairs(group.buckets) do if bucket(hour,row) then return true end end
    return false
end
local function mean(values)
    local n=#values;if n==0 then return nil end
    -- Divide before accumulation to keep exact integer arithmetic within the limit.
    local quotient,remainder=0,0
    for _,p in ipairs(values) do
        local q=math.floor(p/n);quotient=quotient+q;remainder=remainder+(p-q*n)
    end
    return quotient+math.floor(remainder/n+0.5)
end
function O.Stats(value,key,now)
    local out={source="LOCAL",coverage7=0,coverage14=0,coverage30=0}
    local hour=O.Hour(now);if not hour or not frame(value) then return out end
    local group=value.groups[key]
    if type(group)~="table" or type(group.buckets)~="table" then return out end
    local rows,count={},0
    for h,row in pairs(group.buckets) do
        count=count+1;if count>O.MAX_BUCKETS then return out end
        local b=bucket(h,row)
        if b then
            if b.lastTime>now then return out end -- Clock rollback: do not display guessed windows.
            rows[#rows+1]={hour=h,row=b}
        end
    end
    for _,days in ipairs({7,14,30}) do
        local values,high={},nil
        for _,entry in ipairs(rows) do
            if entry.hour>=hour-days*24 and entry.hour<hour then
                values[#values+1]=entry.row.sampleUnit
                high=high and math.max(high,entry.row.maxUnit) or entry.row.maxUnit
            end
        end
        out["coverage"..days]=#values;out["avg"..days]=mean(values);out["high"..days]=high
    end
    return out
end
function O.New(state,group,save)
    local key=group and group.key
    assert(type(key)=="string" and type(group.allowedIds)=="table" and type(save)=="function")
    local clean,opaque=O.Normalize(state[O.FIELD],key)
    if state[O.FIELD]~=nil and not opaque then state[O.FIELD]=clean end
    local self={state=state,group=group,key=key,save=save,disabled=opaque,active=nil,
        latestGeneration=0,lastClock=0,hours={},saveFailed=false}
    if clean then for _,row in pairs(clean.groups[key].buckets) do self.lastClock=math.max(self.lastClock,row.lastTime) end end
    function self:Time(now)
        if not O.Time(now) or now<self.lastClock then return false end
        self.lastClock=now;return true
    end
    function self:Abort() self.active=nil end
    function self:Begin(generation,now)
        self:Abort()
        if self.disabled or self.saveFailed or not integer(generation,1,O.MAX_INTEGER) or
            generation<=self.latestGeneration or not self:Time(now) then return false end
        self.latestGeneration=generation
        local h=O.Hour(now)
        for hour in pairs(self.hours) do if hour<h then self.hours[hour]=nil end end
        self.active={generation=generation,startedAt=now};return true
    end
    function self:Stage(generation,groupValue,winner,now)
        local p=self.active
        if not p or p.generation~=generation or p.observation or groupValue~=self.group or
            type(winner)~="table" or winner.scanGeneration~=generation or winner.logicalKey~=key or
            not integer(winner.itemType,1,O.MAX_INTEGER) or self.group.allowedIds[winner.itemType]~=true or
            not integer(winner.itemGrade,0,O.MAX_INTEGER) or not integer(winner.price,1,O.MAX_INTEGER) or
            not self:Time(now) or now<p.startedAt then return false end
        -- Only bounded primitive scan evidence is staged. Nothing is saved here.
        p.observation={time=now,unit=winner.price,id=winner.itemType,grade=winner.itemGrade}
        return true
    end
    function self:Complete(generation,success,now)
        local p=self.active;self:Abort()
        if not p or p.generation~=generation or success~=true or not p.observation or
            self.disabled or self.saveFailed or not self:Time(now) then return false end
        local obs=p.observation;local hour=O.Hour(obs.time)
        if obs.time>now or hour<O.Hour(now)-720 then return false end
        local stored=self.state[O.FIELD]
        local saved=frame(stored) and stored.groups[key] and stored.groups[key].buckets[hour]
        local current=self.hours[hour]
        if not current then
            current={count=0,baseCount=saved and saved.observationCount or 0,
                firstTime=saved and saved.firstTime or obs.time,sampleUnit=saved and saved.sampleUnit or obs.unit,
                maxUnit=saved and saved.maxUnit or obs.unit,lastGeneration=0}
            self.hours[hour]=current
        end
        if current.lastGeneration==generation then return false end
        current.lastGeneration=generation;current.count=current.count+1
        current.maxUnit=math.max(current.maxUnit,obs.unit);current.lastTime=obs.time
        -- Session-local confirmation never uses restored observationCount as fresh evidence.
        if current.count<2 or (saved and current.maxUnit<=saved.maxUnit) then return false end
        local candidate=O.Normalize(stored,key) or fresh(key)
        local buckets=candidate.groups[key].buckets
        buckets[hour]={firstTime=current.firstTime,lastTime=current.lastTime,sampleUnit=current.sampleUnit,
            maxUnit=current.maxUnit,observationCount=math.min(O.MAX_INTEGER,current.baseCount+current.count),confirmed=true}
        local cutoff=O.Hour(now)-720
        for h in pairs(buckets) do if h<cutoff then buckets[h]=nil end end
        self.state[O.FIELD]=candidate
        local ok,result=pcall(self.save)
        if not ok or result~=true then
            self.state[O.FIELD]=stored;self.saveFailed=true;return false
        end
        return true
    end
    function self:Prune(now)
        if self.disabled or self.saveFailed or not self:Time(now) then return false end
        local stored=self.state[O.FIELD];if not frame(stored) then return false end
        local candidate=O.Normalize(stored,key);local buckets=candidate.groups[key].buckets
        local changed=false;local cutoff=O.Hour(now)-720
        for hour in pairs(buckets) do if hour<cutoff then buckets[hour]=nil;changed=true end end
        if not changed then return false end
        self.state[O.FIELD]=candidate
        local ok,result=pcall(self.save)
        if not ok or result~=true then self.state[O.FIELD]=stored;self.saveFailed=true;return false end
        return true
    end
    function self:Stats(now) return O.Stats(self.state[O.FIELD],key,now) end
    function self:Has() return O.Has(self.state[O.FIELD],key) end
    return self
end
