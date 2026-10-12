-- Travel estimates use actual client taxi geometry and observed reachability.
-- No movement, spell casting or taxi selection is automated.
local G=OctoGuide
G.Travel={}
local T=G.Travel
local function distance(a,b)
 if not a or not b or a.map~=b.map then return nil end
 return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
local function world(p)
 if not p or not C_Map or not C_Map.GetWorldPosFromMapPos then return end
 local ok,map,w=pcall(C_Map.GetWorldPosFromMapPos,p.zone,{x=p.x,y=p.y})
 if ok and w then return {map=map,x=w.x,y=w.y} end
end
local function player()
 if not UnitPosition then return end
 local west,north,_,map=UnitPosition('player')
 if west and north and map then return {map=map,x=north,y=west} end
end
local function point(n)
 if n.areaID and n.mapX and n.mapY then return {zone=n.areaID,x=n.mapX/100,y=n.mapY/100} end
end
function T.Load()
 if T.nodes then return true end
 if not C_TaxiMap or not C_TaxiMap.GetTaxiNodesForMap or not C_TaxiMap.GetTaxiPaths or not C_TaxiMap.GetTaxiPathWaypoints then return false end
 T.nodes={};T.edges={}
 local horde=Enum and Enum.FlightPathFaction and Enum.FlightPathFaction.Horde
 local neutral=Enum and Enum.FlightPathFaction and Enum.FlightPathFaction.Neutral
 if not horde or not neutral then T.nodes=nil;return false end
 for _,n in ipairs(C_TaxiMap.GetTaxiNodesForMap() or {}) do
  if (n.faction==horde or n.faction==neutral) and point(n) then T.nodes[n.nodeID]=n end
 end
 for _,e in ipairs(C_TaxiMap.GetTaxiPaths() or {}) do
  if T.nodes[e.fromNodeID] and T.nodes[e.toNodeID] then
   local wp=C_TaxiMap.GetTaxiPathWaypoints(e.pathID) or {};local length=0
   for i=2,table.getn(wp) do local a,b=wp[i-1],wp[i];length=length+math.sqrt((b.x-a.x)^2+(b.y-a.y)^2+((b.z or 0)-(a.z or 0))^2) end
   if length>0 then T.edges[e.fromNodeID]=T.edges[e.fromNodeID] or {};table.insert(T.edges[e.fromNodeID],{to=e.toNodeID,seconds=length/32,cost=e.cost or 0}) end
  end
 end
 return true
end
function T.ObserveTaxi()
 if not G.db or not T.Load() or not C_TaxiMap.GetAllTaxiNodes then return end
 local entries=C_TaxiMap.GetAllTaxiNodes() or {};local state=Enum and Enum.FlightPathState
 if not state then return end
 local from;local reachable={}
 for _,n in ipairs(entries) do
  if n.state==state.Current then from=n.nodeID end
  if n.state==state.Reachable then reachable[n.nodeID]=true end
 end
 if from and T.nodes[from] then
  G.db.travel=G.db.travel or {known={},reachable={}}
  local db=G.db.travel;db.known=db.known or {};db.reachable=db.reachable or {};db.knownNames=db.knownNames or {};db.known[from]=true
  db.reachable[from]=reachable
  for id in pairs(reachable) do db.known[id]=true end
  for _,n in ipairs(entries) do if db.known[n.nodeID] and n.name then db.knownNames[n.nodeID]=n.name end end
  T.cache=nil
 end
end
local function shortest(from,to,known)
 local best={[from]=0};local money={[from]=0};local used={}
 for _=1,200 do
  local id,cost
  for n,v in pairs(best) do if not used[n] and (not cost or v<cost) then id,cost=n,v end end
  if not id then return end
  if id==to then return cost,money[id] end
  used[id]=true
  for _,e in ipairs(T.edges[id] or {}) do if known[e.to] then
   local v=cost+e.seconds
   if not best[e.to] or v<best[e.to] then best[e.to]=v;money[e.to]=money[id]+e.cost end
  end end
 end
end
function T.HearthReady()
 if not GetContainerNumSlots or not GetContainerItemLink or not GetContainerItemCooldown then return false end
 for bag=0,4 do for slot=1,GetContainerNumSlots(bag) do
  local link=GetContainerItemLink(bag,slot)
  if link and string.find(link,'item:6948:',1,true) then
   local start,duration,enabled=GetContainerItemCooldown(bag,slot)
   return enabled==1 and (duration==0 or (start or 0)+(duration or 0)<=GetTime())
  end
 end end
 return false
end
function T.RecordBind()
 if not G.db or not GetBindLocation or not GetSubZoneText then return end
 local sub=GetSubZoneText();local bind=GetBindLocation()
 -- Only save after a binder confirmation and a matching inn name.
 if T.pendingBind and T.pendingBind.inn==sub and sub~='' and bind==sub then
  G.db.travel=G.db.travel or {known={},reachable={}}
  G.db.travel.hearth=T.pendingBind;G.db.travel.hearth.name=bind;T.pendingBind=nil;T.cache=nil
 end
end
function T.Plan(target)
 if not G.db or not target or G.gatherTarget or not T.Load() then return end
 local now=GetTime and GetTime() or 0
 local key=tostring(target)..':'..tostring(GetBindLocation and GetBindLocation())
 if T.cache and T.cache.key==key and now-T.cache.time<1 then return T.cache.plan end
 local pos,dest=player(),world(target);local direct=distance(pos,dest)
 if not direct or direct<600 then return end
 local speed=7
 if GetUnitSpeed then local v=GetUnitSpeed('player');if v and v>speed then speed=v end end
 local baseline=direct/speed;local best=baseline;local plan
 local db=G.db.travel or {};local known=db.known or {}
 for id in pairs(known) do local n=T.nodes[id];local a=n and world(point(n));local walk=distance(pos,a)
  if walk and walk<1200 then
   for to in pairs((db.reachable or {})[id] or {}) do local endNode=T.nodes[to];local b=endNode and world(point(endNode));local last=distance(b,dest)
    if last then local seconds,cost=shortest(id,to,known)
     if seconds and (not GetMoney or cost<=GetMoney()) then
      local total=walk/speed+seconds+last/speed+10
      if total<best*.85 then
       best=total;local p=point(n);p.travelHint='Go to '..n.name..'. Fly to '..endNode.name..'.';p.index=2;p.current=true
       plan={mode='flight',target=p,seconds=total,hint=p.travelHint..' Estimated faster travel.',points={}}
       local zone=C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
       local here=zone and C_Map.GetPlayerMapPosition(zone,'player')
       if here then table.insert(plan.points,{zone=zone,x=here.x,y=here.y,index=1,origin=true}) end
       table.insert(plan.points,p)
      end
     end
    end
   end
  end
 end
 local hearth=db.hearth
 if hearth and GetBindLocation and hearth.name==GetBindLocation() and T.HearthReady() then
  local last=distance(world(hearth),dest)
  if last and 10+last/speed<best*.85 then
   plan={mode='hearth',seconds=10+last/speed,hint='Use your Hearthstone to '..hearth.name..', then continue to the objective. Estimated faster travel.',points={{zone=target.zone,x=target.x,y=target.y,index=2,current=true}}}
  end
 end
 T.cache={key=key,time=now,plan=plan};return plan
end
if CreateFrame then
 local f=CreateFrame('Frame')
 for _,eventName in ipairs({'TAXIMAP_OPENED','CONFIRM_BINDER','BAG_UPDATE','PLAYER_ENTERING_WORLD'}) do pcall(function() f:RegisterEvent(eventName) end) end
 f:SetScript('OnEvent',function()
  if event=='TAXIMAP_OPENED' then T.ObserveTaxi();if G.ready then G.Render() end
  elseif event=='CONFIRM_BINDER' then
   local zone=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player');local p=zone and C_Map.GetPlayerMapPosition(zone,'player')
   if p then T.pendingBind={zone=zone,x=p.x,y=p.y,inn=GetSubZoneText and GetSubZoneText()} end
  else T.RecordBind();T.cache=nil end
 end)
end
