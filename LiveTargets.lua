-- Read-only navigation. Never change the player's selection to scan units.
local G=OctoGuide
local N=OctoGuideNavigation
local work={complete=true,objective=true,collect=true,use=true}
local function targetKey(step)
 local key=G.Key(step)
 if step.sourceGuide and G.state and step.sourceGuide~=G.state.guide.id then return step.sourceGuide..':'..key end
 return key
end
local fixedTokens={'target','mouseover','pettarget','party1target','party2target','party3target','party4target','focus'}
local function observation()
 local scope=G.runtimeReads
 if scope then
  local c=scope.observation
  if c and c.revision==G.readRevision and c.questRevision==G.questLookupRevision then return c end
 end
 local c={units={},names={},closest={},objects={},revision=G.readRevision,questRevision=G.questLookupRevision}
 if scope then scope.observation=c end
 return c
end
local function unit(c,token)
 local r=c.units[token];if r then return r end
 local ok,id=pcall(UnitCreatureID,token);r={identityOK=ok,id=id};c.units[token]=r;return r
end
local function tokensFor(c,id)
 if not c.byID then
  c.byID={};local tokens={};for _,t in ipairs(fixedTokens) do table.insert(tokens,t) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
   local ok,plates=pcall(C_NamePlate.GetNamePlates)
   if ok and type(plates)=='table' then for i=1,math.min(40,table.getn(plates)) do table.insert(tokens,'nameplate'..i) end end
  end
  for _,t in ipairs(tokens) do local r=unit(c,t)
   if r.identityOK and type(r.id)=='number' and r.id>0 then c.byID[r.id]=c.byID[r.id] or {};table.insert(c.byID[r.id],t) end
  end
 end
 return c.byID[id] or {}
end
function G.TargetEntries(step)
 local result={};local seen={}
 local function add(id,kind)
  if type(id)~='number' or id<=0 then return end
  if type(kind)~='string' then return end
  local key=kind..':'..id;if seen[key] then return end;seen[key]=true
  if kind=='item' then
   local item=pfDB and pfDB.items and pfDB.items.data and pfDB.items.data[id]
   if item then for unit in pairs(item.U or {}) do add(unit,'monster') end;for object in pairs(item.O or {}) do add(object,'object') end end
  elseif kind=='monster' or kind=='object' then table.insert(result,{id=id,kind=kind}) end
 end
 for _,o in ipairs(G.Objectives(step)) do
  if not o.done and (not step.objective or step.objective==o.index) then add(o.id,o.idKind or o.kind) end
 end
 if step and step.lootGoal and step.itemID then add(step.itemID,'item') end
 return result
end
function G.ReadObservedTarget(step)
 if not step or not work[step.action] or (not step.lootGoal and not G.QuestIndex(step.questID)) or G.Satisfied(step) then return nil end
 if not UnitPosition or not GetPlayerFacing then return nil end
 local ok,pw,pn,pz,map=pcall(UnitPosition,'player');if not ok or not pw or not pn then return nil end
 local entries=G.TargetEntries(step);local best;local previous;local prior=G.livePoll and G.livePoll.key==G.Key(step) and G.livePoll.result
 local context=observation();local facing=GetPlayerFacing()
 for _,entry in ipairs(entries) do
  if entry.kind=='monster' and OctoGuideClosestLivingUnit and not G.RequiredTargetAura(step) then
   local sample=context.closest[entry.id]
   if not sample then local ok,w,n,d,guid=pcall(OctoGuideClosestLivingUnit,entry.id,0);sample={ok=ok,w=w,n=n,d=d,guid=guid};context.closest[entry.id]=sample end
   local posOK,w,n,d,guid=sample.ok,sample.w,sample.n,sample.d,sample.guid
   if posOK and type(w)=='number' and type(n)=='number' and guid then
    local r=N.Calculate({north=pn,west=pw,map=map},{north=n,west=w,map=map},facing)
    if r and (not best or r.yards<best.yards) then r.worldWest=w;r.worldNorth=n;r.worldMap=map;best=r;best.entry=entry.id;best.guid=guid;best.label=step.questID==5441 and 'Observed sleeping peon' or 'Live quest target' end
   end
  end
  -- ClosestUnitPosition does not expose a corpse filter or identity. Only
  -- units whose current life state can be checked are eligible here.
  if entry.kind=='monster' and UnitCreatureID and UnitIsDeadOrGhost and UnitHealth then
   local tokens={};for _,token in ipairs(tokensFor(context,entry.id)) do table.insert(tokens,token) end
   if UnitTokenFromName then
    local name=pfDB and pfDB.units and pfDB.units.loc and pfDB.units.loc[entry.id]
    if type(name)=='table' then name=name[1] end
    if type(name)=='string' then
     local sample=context.names[name]
     if not sample then local ok,token=pcall(UnitTokenFromName,name,true);sample={ok=ok,token=token};context.names[name]=sample end
     if sample.ok and sample.token then table.insert(tokens,sample.token) end
    end
   end
   if prior and (prior.token or prior.guid) then table.insert(tokens,prior.token or prior.guid) end
   for _,token in ipairs(tokens) do
    local sample=unit(context,token)
    if sample.identityOK and sample.id==entry.id then
     if not sample.read then
      sample.read=true;sample.deadOK,sample.dead=pcall(UnitIsDeadOrGhost,token);sample.healthOK,sample.health=pcall(UnitHealth,token)
      sample.posOK,sample.w,sample.n,sample.z,sample.map=pcall(UnitPosition,token)
     end
     local w,n,z,m=sample.w,sample.n,sample.z,sample.map
     if sample.deadOK and not sample.dead and sample.healthOK and type(sample.health)=='number' and sample.health>0 and sample.posOK and w and n and m==map and G.UnitEligibleForStep(step,token) then
      local r=N.Calculate({north=pn,west=pw,map=map},{north=n,west=w,map=m},facing)
      if r then
       r.worldHeight=z;r.worldWest=w;r.worldNorth=n;r.worldMap=m;r.entry=entry.id;r.token=token;r.label='Live quest target'
       if prior and (prior.token==token or prior.guid==token) and prior.entry==entry.id then previous=r end
       if not best or r.yards<best.yards then best=r end
      end
     end
    end
   end
  elseif entry.kind=='object' and ClosestGameObjectPosition then
   local sample=context.objects[entry.id]
   if not sample then local ok,n,w,d=pcall(ClosestGameObjectPosition,entry.id);sample={ok=ok,n=n,w=w,d=d};context.objects[entry.id]=sample end
   local posOK,n,w,d=sample.ok,sample.n,sample.w,sample.d
   if posOK and type(w)=='number' and type(n)=='number' then
    local r=N.Calculate({north=pn,west=pw,map=map},{north=n,west=w,map=map},facing)
    if r and type(d)=='number' and d>=0 and r.yards<=d+2 and (not best or r.yards<best.yards) then r.worldWest=w;r.worldNorth=n;r.worldMap=map;best=r;best.entry=entry.id;best.label='Observed quest object' end
   end
  end
 end
 if previous and best and previous.yards<=best.yards*1.15+2 then return previous end
 return best
end
function G.NavigationRead(step)
 local pickup=G.PickupCircuitWaypoint and G.PickupCircuitWaypoint(step)
 if step and ((not pickup and G.PathTarget and G.PathTarget(step)) or (G.Travel and G.Travel.Plan(G.RawNavTarget()))) then
  G.navigationEvidence='Route waypoint';G.livePoll=nil;return N.ReadWaypoint(G.NavTarget())
 end
 local now=GetTime and GetTime() or 0
 local key=step and G.Key(step)
 if not G.livePoll or G.livePoll.key~=key or now-G.livePoll.time>=.12 then
  G.livePoll={key=key,time=now,result=G.ReadObservedTarget(step)}
 end
 local live=G.livePoll.result
 if live then G.navigationEvidence=live.label;return G.RefreshObserved(live) end
 local target=G.NavTarget();G.navigationEvidence=target and target.evidence or (step and work[step.action] and 'Quest area' or 'Route waypoint')
 -- Database coordinates are possible spawns, never evidence of life.
 -- Stay within the author's local quest area and respect travel/path targets.
 if target==step and step and work[step.action] and step.x and step.y then
  local nearest,distance
  if G.areaPoll and G.areaPoll.key==key and G.areaPoll.db==pfDB and now-G.areaPoll.time<.12 then nearest=G.areaPoll.target else
   for _,entry in ipairs(G.TargetEntries(step)) do
   local db=pfDB and pfDB[entry.kind=='monster' and 'units' or 'objects']
   local data=db and db.data and db.data[entry.id]
   for _,p in ipairs(data and data.coords or {}) do
    if p[3]==step.zone and (p[1]/100-step.x)^2+(p[2]/100-step.y)^2<=.12*.12 then
     local waypoint={zone=p[3],x=p[1]/100,y=p[2]/100};local r=N.ReadWaypoint(waypoint)
     if r and (not distance or r.yards<distance) then nearest=waypoint;distance=r.yards end
    end
   end
   end
   G.areaPoll={key=key,db=pfDB,time=now,target=nearest}
  end
  if nearest then target=nearest;G.navigationEvidence='Possible quest spawn' end
 end
 return N.ReadWaypoint(target)
end
function G.SecondaryTarget(step)
 if not G.db.secondaryArrow or not step or not work[step.action] then return nil end
 local now=GetTime and GetTime() or 0;local key=G.Key(step)
 if G.secondaryChoice and G.secondaryChoice.key==key and now-G.secondaryChoice.time<.12 then return G.secondaryChoice.step end
 local best,distance,priorResult,priorStep
 for _,other in ipairs(G.Concurrent(step)) do
  local r=G.SecondaryRead(other)
  if G.secondaryChoice and other==G.secondaryChoice.step and not G.Satisfied(other) and G.QuestIndex(other.questID) then priorStep=other;priorResult=r end
  local observed=r and (r.guid or r.token or r.label=='Observed quest object')
  local current=best and G.SecondaryRead(best);local currentObserved=current and (current.guid or current.token or current.label=='Observed quest object')
  if r and (not best or (observed and not currentObserved) or ((not not observed)==(not not currentObserved) and r.yards<distance)) then best=other;distance=r.yards end
 end
 if best and priorStep and priorResult then
  local picked=G.SecondaryRead(best);local a=priorResult.guid or priorResult.token or priorResult.label=='Observed quest object';local b=picked and (picked.guid or picked.token or picked.label=='Observed quest object')
  if (not not a)==(not not b) and priorResult.yards<=distance*1.20+2 then best=priorStep end
 end
 G.secondaryChoice={key=key,time=now,step=best};return best
end
function G.SecondaryRead(step)
 local key=targetKey(step);local now=GetTime and GetTime() or 0
 G.secondaryPoll=G.secondaryPoll or {};local cached=G.secondaryPoll[key]
 if cached and now-cached.time<.12 then return G.RefreshObserved(cached.result) end
 local result=G.ResolveSecondary(step)
 -- Bound UNIQUE keys, never flush all active targets every 100 refreshes.
 if not cached then
  G.secondaryPollCount=(G.secondaryPollCount or 0)+1
  if G.secondaryPollCount>100 then
   local oldest,time;for k,v in pairs(G.secondaryPoll) do if not time or v.time<time then oldest=k;time=v.time end end
   if oldest then G.secondaryPoll[oldest]=nil end;G.secondaryPollCount=100
  end
 end
 G.secondaryPoll[key]={time=now,result=result}
 return G.RefreshObserved(result)
end
function G.ResolveSecondary(step)
 local r=G.ReadObservedTarget(step);if r then return r end
 local best
 for _,entry in ipairs(G.TargetEntries(step)) do
  local db=pfDB and pfDB[entry.kind=='monster' and 'units' or 'objects']
  local data=db and db.data and db.data[entry.id]
  for _,p in ipairs(data and data.coords or {}) do
   if p[3]==step.zone and step.x and step.y and (p[1]/100-step.x)^2+(p[2]/100-step.y)^2<=.12*.12 then
    local candidate=N.ReadWaypoint({zone=p[3],x=p[1]/100,y=p[2]/100});if candidate and (not best or candidate.yards<best.yards) then best=candidate;best.label='Possible spawn' end
   end
  end
 end
 if best then return best end
 r=N.ReadWaypoint(step);if r then r.label='Quest area' end;return r
end

function G.RefreshObserved(r)
 if not r or not r.worldNorth then return r end
 local ok,w,n,z,map=pcall(UnitPosition,'player');local facingOK,facing=pcall(GetPlayerFacing)
 if not ok or not facingOK then return nil end
 local fresh=N.Calculate({north=n,west=w,map=map},{north=r.worldNorth,west=r.worldWest,map=r.worldMap},facing)
 if not fresh then return nil end
 for k,v in pairs(r) do if k~='angle' and k~='yards' and k~='arrived' then fresh[k]=v end end
 return fresh
end

-- Explicit target-state requirements can be reused by future item-use quests.
function G.RequiredTargetAura(step)
 return step and (step.targetAura or (step.questID==5441 and 17743))
end
function G.UnitEligibleForStep(step,token)
 local required=G.RequiredTargetAura(step)
 if not required then return true end
 local known=false
 if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
  for _,filter in ipairs({'HELPFUL','HARMFUL'}) do
   for i=1,40 do
    local ok,a=pcall(C_UnitAuras.GetAuraDataByIndex,token,i,filter)
    if ok then known=true end
    if not ok or not a then break end
    if a.spellId==required or a.spellID==required then return true end
   end
  end
 end
 if known then return false end
 local fallback=step.targetStandState or (step.questID==5441 and 3)
 if fallback and UnitStandState then local ok,state=pcall(UnitStandState,token);return ok and state==fallback end
 return false
end
