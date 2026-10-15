-- Update positions only from a loaded, identity-checked quest giver.
local G=OctoGuide
local base=G.QuestNPCWaypoint
G.DatabaseQuestNPCWaypoint=base
function G.QuestNPCWaypoint(s)
 local point=base(s)
 if not point or not point.npc or not UnitTokenFromName or not UnitCreatureID or not UnitPosition or not C_Map or not C_Map.GetMapPosFromWorldPos then return point end
 local K=G.knowledge;local now=GetTime and GetTime() or 0
 local key=tostring(s.questID)..':'..tostring(s.action)
 local cached=K.positions[key]
 if cached and now-cached.time<.2 then return cached.point or point end
 local live
 local name=point.npcName;if type(name)=='table' then name=name[1] end
 if type(name)=='string' then
  local ok,token=pcall(UnitTokenFromName,name,true)
  if ok and token then
   local valid,id=pcall(UnitCreatureID,token)
   local pos,w,n,z,map=pcall(UnitPosition,token)
   local own,pw,pn,pz,pm=pcall(UnitPosition,'player')
   if valid and id==point.npc and pos and own and pm==map and type(w)=='number' and type(n)=='number' and type(z)=='number' then
    local converted,zone,p=pcall(C_Map.GetMapPosFromWorldPos,map,{x=n,y=w},point.zone)
    if converted and zone==point.zone and p and type(p.x)=='number' and type(p.y)=='number' and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 then
     live={zone=zone,x=p.x,y=p.y,npc=id,npcName=name,questID=s.questID,height=z,worldMap=map,liveToken=token,evidence='Observed quest giver position'}
    end
   end
  end
 end
 K.positions[key]={time=now,point=live}
 return live or point
end
