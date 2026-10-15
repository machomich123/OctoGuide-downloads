-- Reuse pure reads within ONE client callback. Nothing survives to the next
-- frame/event; progression writes and nested quest events invalidate reads.
local G=OctoGuide
function G.InvalidateRuntimeReads()G.readRevision=(G.readRevision or 0)+1 end
local function same(c,state,db,revision,questRevision)
 return c and c.state==state and c.progress==(db and db.progress) and c.mode==(db and db.mode) and c.pause==G.pauseAuto and c.review==(state and state.reviewIndex) and c.start==(state and state.startIndex) and c.index==(state and state.index) and c.gather==G.gatherTarget and c.revision==revision and c.questRevision==questRevision
end
local function memo(name,fn,arg,extra)
 local scope=G.runtimeReads
 if not scope then if name=='Current' then G.currentRead=nil end;return fn(arg,extra) end
 local state=G.state;local db=G.db
 local bucket=scope[name]
 if not bucket then bucket={entries={},slots={},next=0};scope[name]=bucket end
 if bucket.generation~=scope.generation then
  for key in pairs(bucket.entries) do bucket.entries[key]=nil end
  bucket.generation=scope.generation;bucket.next=0
 end
 local key=arg or scope;local c=bucket.entries[key]
 local revision=G.readRevision;local questRevision=G.questLookupRevision
 if same(c,state,db,revision,questRevision) then return c.a,c.b,c.c end
 local now=GetTime and GetTime()
 if name=='Current' and now then
  c=G.currentRead
  if same(c,state,db,revision,questRevision) and now>=c.time and now-c.time<.12 then bucket.entries[key]=c;return c.a end
 end
 local started=name=='Current' and G.PerformanceClock and G.PerformanceClock()
 local a,b,d=fn(arg,extra)
 if name=='Current' and G.PerformanceRecord then G.PerformanceRecord('stage route',started) end
 if revision~=G.readRevision or questRevision~=G.questLookupRevision then return a,b,d end
 state=G.state;db=G.db
 c=bucket.entries[key]
 if not c then
  if bucket.next>=128 then return a,b,d end
  bucket.next=bucket.next+1;c=bucket.slots[bucket.next] or {};bucket.slots[bucket.next]=c;bucket.entries[key]=c
 end
 c.a=a;c.b=b;c.c=d;c.state=state;c.progress=db and db.progress;c.mode=db and db.mode;c.pause=G.pauseAuto;c.review=state and state.reviewIndex;c.start=state and state.startIndex;c.index=state and state.index;c.gather=G.gatherTarget;c.revision=G.readRevision;c.questRevision=G.questLookupRevision
 if name=='Current' and now then G.currentRead=c;c.time=now end
 return a,b,d
end
for _,name in ipairs({'Current','RawNavTarget','NavTarget','Concurrent','TargetEntries','PickupAvailability'}) do
 local tag=name;local fn=G[tag]
 if fn then G[tag]=function(arg)local value=memo(tag,fn,arg);return value end end
end
local present=G.Present
function G.Present(s,preview)return memo(preview and 'PresentPreview' or 'Present',present,s,preview)end
-- Keys are immutable for a given selected guide/mode and step identity.
-- Cache them on that selection, not globally across routes or mode switches.
local key=G.Key
function G.Key(s)
 local state=G.state;if not state then return key(s) end
 local mode=G.Mode();local cache=state.keyCache
 if not cache or state.keyMode~=mode or state.keyGuide~=state.guide.id then cache={};state.keyCache=cache;state.keyMode=mode;state.keyGuide=state.guide.id end
 local value=cache[s]
 if not value or value.id~=s.id or value.action~=s.action or value.mode~=s.mode or value.branch~=s.branch or value.death~=s.requiresDeath or value.modes~=s.modes or value.normal~=(s.modes and s.modes.normal) or value.hardcore~=(s.modes and s.modes.hardcore) then
  value={key=key(s),id=s.id,action=s.action,mode=s.mode,branch=s.branch,death=s.requiresDeath,modes=s.modes,normal=s.modes and s.modes.normal,hardcore=s.modes and s.modes.hardcore};cache[s]=value
 end
 return value.key
end
