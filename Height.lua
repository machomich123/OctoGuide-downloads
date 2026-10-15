-- Read-only height evidence. Map coordinates alone do not contain altitude.
local G,N=OctoGuide,OctoGuideNavigation
function G.HeightText(delta)
 if type(delta)~='number' or delta~=delta then return 'Height unknown' end
 if math.abs(delta)<3 then return 'Same height' end
 return (delta>0 and 'Up ' or 'Down ')..math.floor(math.abs(delta)+.5)..' yd'
end
function G.HeightCaption(delta,step)
 if delta~=nil then return G.HeightText(delta) end
 local title,body=G.Present(step)
 if string.find(body or '', 'The Apothecarium is on the lower level',1,true) then return 'Lower level' end
 return G.HeightText(nil)
end
function G.WaypointHeight(s)
 if not s or not UnitPosition or not C_Map or not C_Map.GetWorldPosFromMapPos then return nil end
 local ok,pw,pn,pz,pm=pcall(UnitPosition,'player')
 if not ok or type(pz)~='number' or type(pw)~='number' or type(pn)~='number' then return nil end
 if type(s.height)=='number' and s.worldMap==pm then return s.height-pz end
 if not s.questID or (s.action~='accept' and s.action~='turnin') then return nil end
 local q=pfDB and pfDB.quests and pfDB.quests.data and pfDB.quests.data[s.questID]
 local endpoint=q and q[s.action=='accept' and 'start' or 'end']
 if not endpoint or not endpoint.U or not UnitTokenFromName or not UnitCreatureID then return nil end
 local best,delta
 for _,id in ipairs(endpoint.U) do
  local name=pfDB.units and pfDB.units.loc and pfDB.units.loc[id]
  if type(name)=='table' then name=name[1] end
  if type(name)=='string' then
   local found,token=pcall(UnitTokenFromName,name,true)
   if found and token then
    local valid,entry=pcall(UnitCreatureID,token)
    local pos,w,n,z,m=pcall(UnitPosition,token)
    if valid and entry==id and pos and m==pm and type(z)=='number' and type(w)=='number' and type(n)=='number' then
     local distance=(w-pw)^2+(n-pn)^2
     -- Match the actual waypoint as well as the NPC id (multiple spawns exist).
     local good,map,world=pcall(C_Map.GetWorldPosFromMapPos,s.zone,{x=s.x,y=s.y})
     if good and world and map==m and (world.x-n)^2+(world.y-w)^2<80^2 and (not best or distance<best) then best=distance;delta=z-pz end
    end
   end
  end
 end
 return delta
end
local read=G.NavigationRead
function G.NavigationRead(step)
 local result,reason=read(step)
 if result then
  if result.worldHeight and UnitPosition then
   local ok,w,n,z,map=pcall(UnitPosition,'player')
   if ok and map==result.worldMap and type(z)=='number' then result.heightDelta=result.worldHeight-z end
  else
   local target=G.NavTarget()
   if target==step then result.heightDelta=G.WaypointHeight(step)
   elseif target and step and target.questID==step.questID and not target.flightFallback then
    local point={questID=step.questID,action=step.action,zone=target.zone,x=target.x,y=target.y,height=target.height,worldMap=target.worldMap}
    result.heightDelta=G.WaypointHeight(point)
   end
  end
 end
 return result,reason
end
