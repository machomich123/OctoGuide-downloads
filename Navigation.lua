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
