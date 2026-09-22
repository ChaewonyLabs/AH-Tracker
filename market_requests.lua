-- Production single-flight coordinator. Only the injected send function contacts Auction.
local M=AH_PRICE_WATCH_MARKET
function M.Requests(context)
    local self={context=context,elapsed=0,nextSend=0,pending=nil,event=nil,ready=false,day=nil,wireDays={},passAttempts={},passCount=0}
    -- Reset only at an independent native scan start; never from timeout/failure.
    function self:BeginPass()
        if self.pending then return false end
        self.passAttempts,self.wireDays,self.passCount={},{},0
        return true
    end
    function self:Busy() return self.pending~=nil end
    function self:CanSearch() return not self.pending and self.elapsed>=self.nextSend end
    function self:MarkSearch() self.nextSend=math.max(self.nextSend,self.elapsed+1250) end
    function self:Cancel(success)
        if self.pending then
            local deadline=not success and self.pending.deadline or 0
            self.nextSend=math.max(self.nextSend,self.elapsed+1250,(deadline or 0)+1250)
        end
        self.pending,self.event=nil,nil
    end
    function self:Offer(candidate)
        local today=context.day()
        if not self.ready or self.pending or not today or not candidate then return false end
        local id,grade=candidate.id,candidate.grade
        if type(id)~="number" or type(grade)~="number" or not M.Id(id) or not M.Integer(grade) or
            type(candidate.name)~="string" or type(candidate.names)~="table" then return false end
        if M.HasSuccess(context.state,id,grade,today) then return false end
        local key=id.."/"..grade
        if self.passAttempts[key] or self.passCount>=2048 then return false end
        local wire=candidate.name.."/"..grade
        if self.wireDays[wire]==today then return false end
        self.passAttempts[key]=true;self.passCount=self.passCount+1
        self.wireDays[wire]=today -- same name/grade cannot be retried within this pass
        self.pending={id=id,grade=grade,name=candidate.name,names=candidate.names,day=today,wire=wire}
        return true
    end
    function self:Receive(name,grade,ui,payload)
        local p=self.pending
        if not p or not p.sent or self.elapsed>=p.deadline or self.event or ui~=true or grade~=p.grade or not p.names[name] then return end
        -- Bounded primitive copy only, no persistence, file I/O or serialization in callback.
        local copy={};local valid=type(payload)=="table";local count=0
        if valid then for key in next,payload do
            count=count+1;if count>14 or type(key)~="number" or key<1 or key>14 or key~=math.floor(key) then valid=false;break end
        end end
        if count~=14 then valid=false end
        if valid then for i=1,14 do
            local row=rawget(payload,i)
            if type(row)~="table" then valid=false;break end
            copy[i]={}
            for _,key in ipairs({"dailyAvg","weeklyAvg","maxPrice","minPrice","volume"}) do
                local v=rawget(row,key)
                if type(v)~="number" and (type(v)~="string" or #v>32) then valid=false;break end
                copy[i][key]=v
            end
            if not valid then break end
        end end
        self.event={request=p,payload=valid and copy or false}
    end
    function self:Tick(dt,allowed)
        dt=tonumber(dt) or 0;if dt~=dt or dt<0 or dt==math.huge then dt=0 end
        self.elapsed=self.elapsed+dt
        local today=context.day()
        if self.day and today and today<self.day then self:Cancel();return end -- clock rollback: no guessed date
        if self.day~=today then self.day=today;self.wireDays={};M.Prune(context.state,today) end
        if not allowed or not today then self:Cancel();return end
        local p=self.pending;if not p then return end
        if p.day~=today then self:Cancel();return end
        if self.event then
            local event=self.event;self.event=nil
            local ok,merged=false,false
            if event.request==p and event.payload then ok,merged=pcall(M.Merge,context.state,p.id,p.grade,today,event.payload) end
            local success=ok and merged==true
            if success then
                local grades=context.state.marketAttempts[p.id] or {}
                context.state.marketAttempts[p.id]=grades;grades[p.grade]=today -- successful merge day only
                pcall(context.save);context.refresh()
            end
            self:Cancel(success);return
        end
        if p.sent then
            if self.elapsed>=p.deadline then self:Cancel() end
            return
        end
        if self.elapsed<self.nextSend then return end
        local saved,result=pcall(context.save)
        if not saved or result==false then self:Cancel();return end
        p.sent=true;p.deadline=self.elapsed+8000
        self.nextSend=self.elapsed+1250
        local ok,result=pcall(context.send,p.id,p.grade)
        if not ok or result==false then self:Cancel() end
    end
    return self
end
