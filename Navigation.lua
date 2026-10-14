-- Original OctoGuide navigation prototype. Lua 5.0. No movement or interaction.
OctoGuideNavigation={}
local N=OctoGuideNavigation
local function number(v) return type(v)=='number' and v==v and math.abs(v)<1000000000000 end
function N.Calculate(player,target,facing)
  if not player or not target or not number(player.north) or not number(player.west) or not number(target.north) or not number(target.west) then return nil,'position unavailable' end
  if player.map~=target.map then return nil,'transport required' end
  local dn,dw=target.north-player.north,target.west-player.west
  local yards=math.sqrt(dn*dn+dw*dw)
  if yards<0.01 then return {yards=0,arrived=true,angle=0} end
  if not number(facing) then return {yards=yards},'facing unavailable' end
  -- World axes: north and west. Facing increases counter-clockwise from north.
  -- Screen arrow angle increases clockwise: target east is a right arrow.
  local bearing=math.atan2(dw,dn)
  local angle=math.mod(facing-bearing+2*math.pi,2*math.pi)
  return {yards=yards,angle=angle,arrived=false}
end
function N.ReadWaypoint(waypoint)
  if type(UnitPosition)~='function' or type(GetPlayerFacing)~='function' or not C_Map or type(C_Map.GetWorldPosFromMapPos)~='function' then return nil,'navigation API unavailable' end
  if not waypoint or not number(waypoint.x) or not number(waypoint.y) or waypoint.x<0 or waypoint.x>1 or waypoint.y<0 or waypoint.y>1 then return nil,'invalid waypoint' end
  local key=tostring(waypoint.zone)..':'..waypoint.x..':'..waypoint.y
  local ok,map,world
  if N.targetCache and N.targetCache.key==key and N.targetCache.api==C_Map.GetWorldPosFromMapPos then
    ok=true;map=N.targetCache.map;world=N.targetCache.world
  else
    ok,map,world=pcall(C_Map.GetWorldPosFromMapPos,waypoint.zone,{x=waypoint.x,y=waypoint.y})
    if ok and world then N.targetCache={key=key,map=map,world=world,api=C_Map.GetWorldPosFromMapPos} end
  end
  if not ok or not world then return nil,'target coordinates unavailable' end
  local posOK,west,north,height,playerMap=pcall(UnitPosition,'player')
  if not posOK then return nil,'player coordinates unavailable' end
  local faceOK,facing=pcall(GetPlayerFacing)
  return N.Calculate({north=north,west=west,map=playerMap},{north=world.x,west=world.y,map=map},faceOK and facing or nil)
end
function N.Update(elapsed,state)
  state.elapsed=(state.elapsed or 0)+(elapsed or 0)
  if state.elapsed<0.1 then return false end
  state.elapsed=0
  state.result,state.reason=N.ReadWaypoint(state.waypoint)
  return true
end

-- Static quest-giver positions, not live NPC or pathfinding evidence.
local G=OctoGuide
if G then
local fallback={[812]={accept={npc=3190,name='Rhinag',zone=14,x=.431,y=.193},turnin={npc=3190,name='Rhinag',zone=14,x=.431,y=.193}}}
local function valid(c)
 return type(c)=='table' and type(c[1])=='number' and type(c[2])=='number' and type(c[3])=='number' and c[1]>=0 and c[1]<=100 and c[2]>=0 and c[2]<=100 and c[3]>0
end
function G.QuestNPCWaypoint(s)
 if not s or not s.questID or (s.action~='accept' and s.action~='turnin') then return nil end
 local q=pfDB and pfDB.quests and pfDB.quests.data and pfDB.quests.data[s.questID]
 if not q then
  local f=fallback[s.questID] and fallback[s.questID][s.action]
  if not f or s.zone and s.zone~=f.zone then return nil end
  return {zone=f.zone,x=f.x,y=f.y,npc=f.npc,npcName=f.name,evidence='Quest NPC (database)',questID=s.questID}
 end
 local phase=q[s.action=='accept' and 'start' or 'end'];local unique,kind,count=nil,nil,0
 for _,k in ipairs({'U','O'}) do for _,id in pairs(phase and phase[k] or {}) do count=count+1;unique=id;kind=k end end
 -- Multiple possible quest givers require an authored choice; do not guess.
 if count~=1 then return nil end
 local db=pfDB[kind=='U' and 'units' or 'objects'];local unit=db and db.data and db.data[unique]
 local found,seen={},{}
 for _,c in pairs(unit and unit.coords or {}) do
  if valid(c) and (not s.zone or c[3]==s.zone) then
   local key=c[3]..':'..c[1]..':'..c[2]
   if not seen[key] then seen[key]=true;table.insert(found,c) end
  end
 end
 if table.getn(found)~=1 then return nil end
 local c=found[1];local loc=db.loc or db.enUS or {}
 return {zone=c[3],x=c[1]/100,y=c[2]/100,npc=unique,npcName=loc[unique],evidence=kind=='U' and 'Quest NPC (pfQuest)' or 'Quest object (pfQuest)',questID=s.questID}
end

end
