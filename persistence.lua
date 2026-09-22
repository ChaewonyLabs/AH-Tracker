-- v073 bounded persistence. No game requests, file I/O or UI dependencies.
AH_PRICE_WATCH_STORAGE = {}
local P = AH_PRICE_WATCH_STORAGE
P.PREFIX = "ah_price_watch_v073_"
P.BUDGET, P.CHUNK_BYTES, P.MAX_CHUNKS = 4096, 1536, 4096
P.MAX_BYTES, P.MAX_NODES = 16777216, 1000000
P.COMPONENTS = {"c", "w", "l", "d", "a", "m", "t", "s"}
local fields = {w="watchItems", l="last", d="daily", a="alerts",
    m="marketHistory", t="marketAttempts", s="marketSelected"}
P.LEGACY = {"v072","v071","v070","v066","v064","v063","v062","v061","v060","v050"}
local function integer(n,low,high)
    return type(n)=="number" and n==math.floor(n) and n>=low and n<=high
end
local function numberText(n)
    assert(type(n)=="number" and n==n and math.abs(n)<math.huge, "nonfinite number")
    return string.format("%.17g",n)
end
local function hash(s)
    local a,b=1,0
    for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end
    return b*65536+a
end
P.Hash=hash
-- Native SaveData rounded the first index's uint32 checksum to float32.
-- Keep checksums as decimal ASCII; accept exact old numeric checksums on read.
local function hashText(s) return string.format("%.0f",hash(s)) end
local function matchesHash(value,s)
    local n=hash(s)
    return value==n or value==string.format("%.0f",n)
end
local function validHash(value)
    if type(value)=="string" then
        local n=tonumber(value)
        return #value<=10 and value:match("^%d+$") and integer(n,0,4294967295)
            and value==string.format("%.0f",n)
    end
    return integer(value,0,4294967295)
end
function P.Encode(value)
    local parts,active,bytes,nodes={},{},0,0
    local function add(s)
        bytes=bytes+#s;assert(bytes<=P.MAX_BYTES,"storage byte limit")
        parts[#parts+1]=s
    end
    local function scalar(v)
        local kind=type(v)
        if kind=="nil" then return "Z" end
        if kind=="boolean" then return v and "B1" or "B0" end
        if kind=="number" then local s=numberText(v);return "N"..#s..":"..s end
        if kind=="string" then return "S"..#v..":"..v end
        error("unsupported storage scalar: "..kind)
    end
    local function visit(v,depth)
        nodes=nodes+1;assert(nodes<=P.MAX_NODES and depth<=32,"storage structure limit")
        if type(v)~="table" then add(scalar(v));return end
        assert(not active[v],"cyclic storage table");active[v]=true
        local keys={}
        for k in next,v do
            assert(type(k)=="string" or type(k)=="number" or type(k)=="boolean","unsupported storage key")
            keys[#keys+1]={key=k,text=scalar(k)}
            assert(#keys<=P.MAX_NODES,"storage key limit")
        end
        table.sort(keys,function(a,b)return a.text<b.text end)
        add("T"..#keys..":")
        for _,k in ipairs(keys) do
            nodes=nodes+1;assert(nodes<=P.MAX_NODES,"storage structure limit")
            add(k.text);visit(rawget(v,k.key),depth+1)
        end
        active[v]=nil
    end
    visit(value,0);return table.concat(parts)
end
function P.Decode(s)
    assert(type(s)=="string" and #s<=P.MAX_BYTES,"invalid storage stream")
    local pos,nodes=1,0
    local function length()
        local e=s:find(":",pos,true);assert(e and e-pos<=8,"invalid length")
        local text=s:sub(pos,e-1);assert(text:match("^%d+$"),"invalid length")
        local n=tonumber(text);assert(n<=P.MAX_BYTES,"length limit");pos=e+1;return n
    end
    local function read(depth)
        nodes=nodes+1;assert(nodes<=P.MAX_NODES and depth<=32,"decode structure limit")
        local tag=s:sub(pos,pos);pos=pos+1
        if tag=="Z" then return nil end
        if tag=="B" then
            local b=s:sub(pos,pos);pos=pos+1;assert(b=="0" or b=="1","invalid boolean");return b=="1"
        end
        assert(tag=="S" or tag=="N" or tag=="T","invalid tag")
        local n=length()
        if tag=="T" then
            assert(n<=P.MAX_NODES,"table length limit")
            local t={}
            for i=1,n do
                local k=read(depth+1)
                assert(type(k)=="string" or type(k)=="number" or type(k)=="boolean","invalid table key")
                assert(rawget(t,k)==nil,"duplicate table key")
                local v=read(depth+1);assert(v~=nil,"nil table value");t[k]=v
            end
            return t
        end
        assert(pos+n-1<=#s,"truncated stream")
        local v=s:sub(pos,pos+n-1);pos=pos+n
        if tag=="S" then return v end
        local num=tonumber(v);assert(num and numberText(num)==v,"invalid number");return num
    end
    local v=read(0);assert(pos==#s+1,"trailing storage bytes");return v
end
local hexChars="0123456789abcdef"
local function hex(s)
    return (s:gsub(".",function(c)
        local n=c:byte();return hexChars:sub(math.floor(n/16)+1,math.floor(n/16)+1)..hexChars:sub(n%16+1,n%16+1)
    end))
end
local function unhex(s)
    assert(type(s)=="string" and #s<=P.CHUNK_BYTES*2 and #s%2==0 and not s:find("[^0-9a-f]"),"invalid chunk")
    return (s:gsub("..",function(c)return string.char(tonumber(c,16)) end))
end
-- Flat ASCII-only envelopes avoid unknown nesting/escaping overhead in SaveData.
-- 256 fixed bytes plus 64 per field is deliberately above observed text framing.
function P.EnvelopeSize(record)
    assert(type(record)=="table","invalid envelope")
    local size=256
    for k,v in pairs(record) do
        assert(type(k)=="string" and k:match("^[a-z]+$"),"invalid envelope key")
        local text
        if type(v)=="number" then text=numberText(v)
        else assert(type(v)=="string" and v:match("^[a-z0-9]*$"),"invalid envelope value");text=v end
        size=size+#k+#text+64
    end
    assert(size<=P.BUDGET,"persistence envelope exceeds budget")
    return size
end
local function sealed(t)
    t.check=hashText(P.Encode(t));P.EnvelopeSize(t);return t
end
local function verified(t)
    P.EnvelopeSize(t)
    local copy={};for k,v in pairs(t) do if k~="check" then copy[k]=v end end
    assert(matchesHash(t.check,P.Encode(copy)) and t.schema==73,"metadata checksum/schema")
    return t
end
local function clone(t) local n={};for k,v in pairs(t or {}) do n[k]=v end;return n end
local function key(kind,bank) return P.PREFIX..kind.."_"..bank end
function P.ChunkKey(c,bank,n)
    assert((c=="c" or fields[c]) and (bank=="a" or bank=="b") and integer(n,1,P.MAX_CHUNKS),"invalid chunk address")
    return key(c,bank).."_"..n
end
local function inventory(t)
    verified(t);assert(integer(t.g,1,16777215),"inventory generation")
    for _,c in ipairs(P.COMPONENTS) do
        for _,b in ipairs({"a","b"}) do assert(integer(t[c..b],0,P.MAX_CHUNKS),"inventory count") end
    end
    return t
end
local function root(t)
    verified(t);assert(integer(t.g,1,16777215),"root generation")
    local total=0
    for _,c in ipairs(P.COMPONENTS) do
        assert(t[c.."b"]=="a" or t[c.."b"]=="b","component bank")
        assert(integer(t[c.."n"],1,P.MAX_CHUNKS),"component count")
        assert(integer(t[c.."l"],1,P.MAX_CHUNKS*P.CHUNK_BYTES),"component length")
        assert(t[c.."n"]==math.ceil(t[c.."l"]/P.CHUNK_BYTES),"component extent")
        assert(validHash(t[c.."h"]),"component checksum")
        total=total+t[c.."l"]
    end
    assert(total<=P.MAX_BYTES,"total storage limit");return t
end
local function empty(v) return v==nil or (type(v)=="table" and next(v)==nil) end
function P.New(api)
    local self={api=api,loaded=false,cache={}}
    local function get(k) return api:LoadData(k) end
    local function put(k,v)
        P.EnvelopeSize(v)
        api:ClearData(k);api:SaveData(k,v)
        assert(P.Encode(get(k))==P.Encode(v),"persistence readback failed")
    end
    local function readRoot(r)
        root(r);local state,cache={},{}
        for _,c in ipairs(P.COMPONENTS) do
            local parts={}
            for n=1,r[c.."n"] do
                local piece=get(P.ChunkKey(c,r[c.."b"],n));verified(piece)
                local raw=unhex(piece.data)
                assert(#raw==math.min(P.CHUNK_BYTES,r[c.."l"]-(n-1)*P.CHUNK_BYTES),"chunk length")
                parts[n]=raw
            end
            local bytes=table.concat(parts)
            assert(#bytes==r[c.."l"] and matchesHash(r[c.."h"],bytes),"component checksum")
            cache[c]=bytes;local value=P.Decode(bytes)
            if c=="c" then assert(type(value)=="table","invalid core");for k,v in pairs(value) do state[k]=v end
            else state[fields[c]]=value end
        end
        return state,cache
    end
    function self:Load()
        assert(not self.loaded,"storage already loaded");self.loaded=true
        local candidates,anyNew={},false
        local invs={}
        for _,b in ipairs({"a","b"}) do
            local ok,v=pcall(get,key("root",b))
            if not ok then self.blocked="root read failed"
            elseif not empty(v) then
                anyNew=true
                local valid=pcall(root,v)
                if valid then candidates[#candidates+1]={value=v,bank=b} end
            end
            local good,i=pcall(get,key("index",b))
            if not good then self.blocked="index read failed"
            elseif not empty(i) then
                anyNew=true
                if pcall(inventory,i) then invs[#invs+1]={value=i,bank=b}
                else self.blocked="corrupt storage inventory" end
            end
        end
        table.sort(invs,function(a,b)return a.value.g>b.value.g end)
        if invs[1] then self.index=clone(invs[1].value);self.indexBank=invs[1].bank end
        -- Union both valid inventories: interrupted saves must remain discoverable.
        if invs[2] then
            for _,c in ipairs(P.COMPONENTS) do for _,b in ipairs({"a","b"}) do
                self.index[c..b]=math.max(self.index[c..b],invs[2].value[c..b])
            end end
        end
        table.sort(candidates,function(a,b)return a.value.g>b.value.g end)
        for _,entry in ipairs(candidates) do
            local ok,state,cache=pcall(readRoot,entry.value)
            if ok then
                self.root,self.rootBank,self.cache=entry.value,entry.bank,cache
                if not self.index then self.blocked="missing storage inventory"
                else for _,c in ipairs(P.COMPONENTS) do
                    if self.index[c..entry.value[c.."b"]]<entry.value[c.."n"] then self.blocked="incomplete storage inventory" end
                end end
                return state,self.blocked
            end
        end
        if anyNew then self.blocked=self.blocked or "no complete storage commit" end
        -- Top-level recovery only. Never fabricate fields lost by LoadData.
        local recovered={}
        for _,suffix in ipairs(P.LEGACY) do
            local ok,old=pcall(get,"ah_price_watch_state_"..suffix)
            if not ok then self.blocked=self.blocked or "legacy read failed"
            elseif type(old)=="table" then
                for k,v in pairs(old) do if recovered[k]==nil then recovered[k]=v end end
            end
        end
        return recovered,self.blocked
    end
    function self:Save(state)
        if not self.loaded or self.blocked then return false,self.blocked or "storage not loaded" end
        local ok,encoded=pcall(function()
            local core=clone(state);local out={};local total=0
            for c,field in pairs(fields) do out[c]=P.Encode(state[field]);core[field]=nil end
            out.c=P.Encode(core)
            for _,c in ipairs(P.COMPONENTS) do
                assert(#out[c]<=P.MAX_CHUNKS*P.CHUNK_BYTES,"component storage limit")
                total=total+#out[c]
            end
            assert(total<=P.MAX_BYTES,"total storage limit");return out
        end)
        if not ok then return false,encoded end
        local changed={}
        for _,c in ipairs(P.COMPONENTS) do if encoded[c]~=self.cache[c] then changed[#changed+1]=c end end
        if #changed==0 then return true end
        local nextRoot=clone(self.root);nextRoot.schema=73;nextRoot.g=(nextRoot.g or 0)+1;nextRoot.check=nil
        local idx=clone(self.index);idx.schema=73;idx.g=(idx.g or 0)+1;idx.check=nil
        for _,c in ipairs(P.COMPONENTS) do for _,b in ipairs({"a","b"}) do idx[c..b]=idx[c..b] or 0 end end
        local growth=not self.index
        for _,c in ipairs(changed) do
            local b=nextRoot[c.."b"]=="a" and "b" or "a"
            local n=math.ceil(#encoded[c]/P.CHUNK_BYTES)
            nextRoot[c.."b"],nextRoot[c.."n"],nextRoot[c.."l"],nextRoot[c.."h"]=b,n,#encoded[c],hashText(encoded[c])
            if n>idx[c..b] then idx[c..b]=n;growth=true end
        end
        -- Also normalize descriptors reused from an exact, old numeric commit.
        for _,c in ipairs(P.COMPONENTS) do
            if type(nextRoot[c.."h"])=="number" then nextRoot[c.."h"]=string.format("%.0f",nextRoot[c.."h"]) end
        end
        -- Validate every envelope/descriptor before mutating storage.
        local ready,reason=pcall(function() root(sealed(nextRoot));inventory(sealed(idx)) end)
        if not ready then return false,reason end
        local rootBank=self.rootBank=="a" and "b" or "a"
        local indexBank=self.indexBank=="a" and "b" or "a"
        local written,err=pcall(function()
            if growth then put(key("index",indexBank),idx) end
            for _,c in ipairs(changed) do
                for n=1,nextRoot[c.."n"] do
                    local raw=encoded[c]:sub((n-1)*P.CHUNK_BYTES+1,n*P.CHUNK_BYTES)
                    put(P.ChunkKey(c,nextRoot[c.."b"],n),sealed({schema=73,data=hex(raw)}))
                end
            end
            put(key("root",rootBank),nextRoot) -- The only commit point.
        end)
        if not written then self.blocked=tostring(err);return false,self.blocked end
        self.root,self.rootBank,self.cache=nextRoot,rootBank,encoded
        if growth then self.index,self.indexBank=idx,indexBank end
        -- Only inactive-bank tails are obsolete; never erase the previous commit.
        for _,c in ipairs(changed) do
            local b=nextRoot[c.."b"]
            for n=nextRoot[c.."n"]+1,self.index[c..b] do
                pcall(function() api:ClearData(P.ChunkKey(c,b,n)) end)
            end
        end
        return true
    end
    return self
end
-- Reset-only discovery; returns an iterator, not an unbounded key list.
-- No data is changed here. Corrupt/missing inventory fails closed.
function P.ResetKeys(api)
    local counts,seen={},false
    for _,b in ipairs({"a","b"}) do
        local v=api:LoadData(key("index",b))
        if not empty(v) then
            inventory(v);seen=true
            for _,c in ipairs(P.COMPONENTS) do for _,bank in ipairs({"a","b"}) do
                counts[c..bank]=math.max(counts[c..bank] or 0,v[c..bank])
            end end
        end
        local r=api:LoadData(key("root",b))
        if not empty(r) then
            root(r)
            for _,c in ipairs(P.COMPONENTS) do
                counts[c..r[c.."b"]]=math.max(counts[c..r[c.."b"]] or 0,r[c.."n"])
            end
        end
    end
    assert(seen or next(counts)==nil,"reset needs storage inventory")
    local ci,bi,n,fixed=1,1,0,0;local banks={"a","b"}
    local fixedKeys={key("root","a"),key("root","b"),key("index","a"),key("index","b")}
    return function()
        while ci<=#P.COMPONENTS do
            local c,b=P.COMPONENTS[ci],banks[bi];n=n+1
            if n<=(counts[c..b] or 0) then return P.ChunkKey(c,b,n) end
            n=0;bi=bi+1;if bi>2 then bi=1;ci=ci+1 end
        end
        fixed=fixed+1;return fixedKeys[fixed]
    end
end
