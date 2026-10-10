-- OctoGuide map overlays for the Vanilla 1.12 client.
-- Map pins are ordered guide checkpoints, never a terrain/pathfinding route.
OctoGuideMap = OctoGuideMap or {}
local M = OctoGuideMap
local G = OctoGuide

M.MAX_CHECKPOINTS = 8
M.cache = {}
M.worldPins, M.worldLines, M.miniPins, M.miniLines = {}, {}, {}, {}

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1000000000000 end
local function validPoint(p)
  return type(p)=="table" and finite(p.x) and finite(p.y) and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 and finite(p.zone)
end
local function optionDefaults()
  if not G.db then return end
  G.db.mapOptions=G.db.mapOptions or {}
  local o=G.db.mapOptions
  if o.targets==nil then o.targets=true end
  if o.routes==nil then o.routes=true end
  if o.checkpoints==nil then o.checkpoints=true end
  if o.minimap==nil then o.minimap=true end
end
function G.MapOptions()
  optionDefaults()
  return G.db and G.db.mapOptions or {targets=true,routes=true,checkpoints=true,minimap=true}
end
function G.SetMapOption(key,value)
  if key~="targets" and key~="routes" and key~="checkpoints" and key~="minimap" then return false end
  optionDefaults(); if not G.db then return false end
  G.db.mapOptions[key]=value==true;if G.UpdateMaps then G.UpdateMaps(true) end;return true
end

-- Convert zone coordinates through ClassicAPI's world-coordinate pair. The
-- API returns (continentID, worldPos) then (mapID, mapPos), where mapPos is a
-- Vector2DMixin or {x,y}; the target map can be a zone or negative continent ID.
function M.Project(point,mapID)
  if not validPoint(point) then return nil,"invalid waypoint" end
  if point.zone==mapID then return {x=point.x,y=point.y,zone=mapID} end
  local key=tostring(point.zone)..":"..tostring(mapID)..":"..point.x..":"..point.y
  if M.cache[key]~=nil then local v=M.cache[key];return type(v)=="table" and v or nil,"projection unavailable" end
  local fn=C_Map and C_Map.GetWorldPosFromMapPos
  local reverse=C_Map and C_Map.GetMapPosFromWorldPos
  if type(fn)~="function" or type(reverse)~="function" then M.cache[key]=false;return nil,"projection unavailable" end
  local ok,continent,world=pcall(fn,point.zone,{x=point.x,y=point.y})
  if not ok or not continent or type(world)~="table" or not finite(world.x) or not finite(world.y) then M.cache[key]=false;return nil,"projection unavailable" end
  local rok,projectedMap,pos=pcall(reverse,continent,world,mapID)
  if not rok or projectedMap~=mapID or type(pos)~="table" then M.cache[key]=false;return nil,"projection unavailable" end
  local x,y=pos.x,pos.y
  if not finite(x) or not finite(y) or x<0 or x>1 or y<0 or y>1 then M.cache[key]=false;return nil,"projection unavailable" end
  local projected={x=x,y=y,zone=mapID};M.cache[key]=projected;return projected
end

function M.Points(steps,startIndex,limit)
  local result={}; limit=limit or M.MAX_CHECKPOINTS
  for i=startIndex or 1,table.getn(steps or {}) do
    local s=steps[i]
    if s and validPoint(s) then
      table.insert(result,{x=s.x,y=s.y,zone=s.zone,step=s,index=i,current=(i==(startIndex or 1))})
      if table.getn(result)>=limit then break end
    end
  end
  return result
end
function M.ProjectPoints(points,mapID,projector)
  local out={}; projector=projector or M.Project
  for _,p in ipairs(points or {}) do
    local q=projector(p,mapID)
    if q then table.insert(out,{x=q.x,y=q.y,zone=mapID,step=p.step,index=p.index,current=p.current,origin=p.origin}) end
  end
  return out
end
function M.Legs(points)
  local out={}
  for i=1,table.getn(points or {})-1 do
    local a,b=points[i],points[i+1]
    if a.zone==b.zone and b.index==a.index+1 then table.insert(out,{from=a,to=b}) end
  end
  return out
end

local function hide(list)
  for _,v in ipairs(list) do if v.Hide then v:Hide() end end
end
local function texture(parent,list,index)
  local t=list[index]
  if not t then t=parent:CreateTexture(nil,"OVERLAY");list[index]=t end
  t:ClearAllPoints();return t
end
local function pin(parent,list,index,x,y,label,current)
  local f=list[index]
  if not f then
    f=CreateFrame('Frame',nil,parent);list[index]=f
    f.icon=f:CreateTexture(nil,'OVERLAY');f.icon:SetAllPoints(f)
    f.label=f:CreateFontString(nil,'OVERLAY');f.label:SetFont('Fonts\\FRIZQT__.TTF',11,'OUTLINE');f.label:SetPoint('CENTER',f,'CENTER',0,0)
  end
  f:ClearAllPoints();f:SetWidth(current and 26 or 21);f:SetHeight(current and 26 or 21)
  f.icon:SetTexture(current and 'Interface\\GossipFrame\\AvailableQuestIcon' or 'Interface\\Buttons\\UI-Quickslot2')
  f.label:SetText(current and '' or (label or ''));f.label:SetTextColor(.45,.9,1)
  f:SetPoint('CENTER',parent,'TOPLEFT',x*parent:GetWidth(),-y*parent:GetHeight());f:Show();return f
end
local function line(parent,list,index,a,b,color)
  if parent==Minimap then
    local vx,vy=b.x-a.x,b.y-a.y;local ax,ay=a.x-.5,a.y-.5
    local aa=vx*vx+vy*vy;local bb=2*(ax*vx+ay*vy);local cc=ax*ax+ay*ay-.21
    if aa<.000001 then return index-1 end
    local disc=bb*bb-4*aa*cc;if disc<0 then return index-1 end
    local lo=math.max(0,(-bb-math.sqrt(disc))/(2*aa));local hi=math.min(1,(-bb+math.sqrt(disc))/(2*aa))
    if lo>hi then return index-1 end
    b={x=a.x+vx*hi,y=a.y+vy*hi};a={x=a.x+vx*lo,y=a.y+vy*lo}
  end
  local w,h=parent:GetWidth(),parent:GetHeight();local dx=(b.x-a.x)*w;local dy=(a.y-b.y)*h
  local length=math.sqrt(dx*dx+dy*dy)
  if length<2 then return index-1 end
  -- Vanilla textures have no SetRotation. Small route dots remain correct at
  -- every angle, and the cap bounds the number of native texture objects.
  local count=math.min(180,math.max(2,math.ceil(length/5)))
  for i=1,count do
    local t=texture(parent,list,index+i-1);t:SetTexture(pfQuestConfig and pfQuestConfig.path and (pfQuestConfig.path..'\\img\\route') or 'Interface\\Buttons\\WHITE8X8');t:SetWidth(4);t:SetHeight(4)
    if t.SetVertexColor then t:SetVertexColor(color[1],color[2],color[3],.85) end
    local ratio=(i-1)/(count-1);local xx=a.x+(b.x-a.x)*ratio;local yy=a.y+(b.y-a.y)*ratio;t:SetPoint('CENTER',parent,'TOPLEFT',(a.x+(b.x-a.x)*ratio)*w,-(a.y+(b.y-a.y)*ratio)*h);if parent==Minimap and ((xx-.5)^2+(yy-.5)^2)>.21 then t:Hide() else t:Show() end
  end
  return index+count-1
end
local function draw(parent,points,pins,lines,o)
  hide(pins);hide(lines)
  local n=0
  if o.routes then
    -- Points are already projected onto this same map. Invalid/remote legs
    -- are never joined, so a ferry or continent crossing is not implied.
    for _,leg in ipairs(M.Legs(points)) do n=line(parent,lines,n+1,leg.from,leg.to,{.95,.78,.22}) end
  end
  for i,p in ipairs(points) do
    local isTarget=p.current
    if not p.origin and (parent~=Minimap or ((p.x-.5)^2+(p.y-.5)^2)<.20) and ((isTarget and o.targets) or (not isTarget and o.checkpoints)) then
      pin(parent,pins,i,p.x,p.y,tostring(p.index),isTarget)
    end
  end
end

function G.BuildMaps()
  optionDefaults();if not CreateFrame then return false end
  if WorldMapButton and not M.worldHost then
    M.worldHost=CreateFrame("Frame",nil,WorldMapButton);M.worldHost:SetAllPoints(WorldMapButton)
    M.label=WorldMapButton:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    M.label:SetPoint("TOPLEFT",WorldMapButton,"TOPLEFT",8,-8);M.label:SetText("Waypoint route")
  end
  if Minimap and not M.miniHost then M.miniHost=CreateFrame("Frame",nil,Minimap);M.miniHost:SetAllPoints(Minimap) end
  if M.driver then return true end
  M.driver=CreateFrame("Frame");M.driver.elapsed=0
  M.driver:SetScript("OnUpdate",function() this.elapsed=(this.elapsed or 0)+(arg1 or 0);if this.elapsed>=.5 then this.elapsed=0;G.UpdateMaps(false) end end)
  return true
end

local function currentMap()
  if type(GetCurrentMapContinent)=="function" and type(GetCurrentMapZone)=="function" then
    local c,z=GetCurrentMapContinent(),GetCurrentMapZone()
    if finite(c) and finite(z) and z>0 and pfMap and type(pfMap.GetMapID)=="function" then
      local ok,id=pcall(pfMap.GetMapID,pfMap,c,z);if ok and finite(id) then return id,c,z end
    elseif finite(c) and c>0 and z==0 and C_Map and type(C_Map.GetMapChildrenInfo)=="function" and type(C_Map.GetFallbackWorldMapID)=="function" then
      local continents=C_Map.GetMapChildrenInfo(C_Map.GetFallbackWorldMapID()) or {}
      local names={GetMapContinents()};local wanted=names[c]
      for _,info in ipairs(continents) do if info.name==wanted then return info.mapID,c,z end end
    elseif c==0 and z==0 and C_Map and type(C_Map.GetFallbackWorldMapID)=="function" then
      return C_Map.GetFallbackWorldMapID(),c,z
    end
    return nil,c,z
  end
end
function M.JourneyPoints()
  if not G.state then return {} end
  local current=G.Current();local target=G.NavTarget and G.NavTarget()
  if not current or not validPoint(target) then return {} end
  local dest={zone=target.zone,x=target.x,y=target.y,index=2,current=true,step=current}
  local result=OctoGuideNavigation and OctoGuideNavigation.ReadWaypoint(target)
  -- Short local tasks retain a target only. A long journey starts at the
  -- player and uses only explicit authored checkpoints for this action.
  if not result or result.yards<600 then return {dest} end
  local journey=G.Travel and G.Travel.Plan(G.RawNavTarget and G.RawNavTarget() or current)
  if journey and journey.points then return journey.points end
  if not current.checkpoints or table.getn(current.checkpoints)==0 then return {dest} end
  local zone=(pfMap and GetRealZoneText and pfMap:GetMapIDByName(GetRealZoneText())) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player'))
  local pos=zone and C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(zone,'player')
  if not pos or not validPoint({zone=zone,x=pos.x,y=pos.y}) then return {dest} end
  local out={{zone=zone,x=pos.x,y=pos.y,index=1,origin=true}}
  for _,p in ipairs(current.checkpoints or {}) do if validPoint(p) then table.insert(out,{zone=p.zone,x=p.x,y=p.y,index=table.getn(out)+1}) end end
  dest.index=table.getn(out)+1;table.insert(out,dest);return out
end
local function currentGuidePoints() return M.JourneyPoints() end
function G.UpdateMaps(force)
  optionDefaults();local o=G.MapOptions()
  local points=type(G.Current)=="function" and currentGuidePoints() or {}
  if WorldMapButton and M.worldHost then
    local mapID=currentMap();local mapped=mapID and M.ProjectPoints(points,mapID) or {}
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
      M.worldHost:Show();draw(WorldMapButton,M.worldPins and mapped or {},M.worldPins,M.worldLines,o)
      if M.label then if o.routes and table.getn(mapped)>1 then M.label:Show() else M.label:Hide() end end
    else M.worldHost:Hide();hide(M.worldPins);hide(M.worldLines);if M.label then M.label:Hide() end end
  end
  if Minimap and M.miniHost then
    local enabled=o.minimap and o.targets or o.minimap and o.checkpoints or o.minimap and o.routes
    local mapID=(type(GetRealZoneText)=="function" and pfMap and pfMap.GetMapIDByName and pfMap:GetMapIDByName(GetRealZoneText())) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player'))
    local localPoints={}
    if enabled and finite(mapID) and C_Map and C_Map.GetPlayerMapPosition and pfMap then
      local pos=C_Map.GetPlayerMapPosition(mapID,'player')
      local px,py=pos and pos.x,pos and pos.y
      local zoom=Minimap.GetZoom and Minimap:GetZoom()
      local sizes=pfMap.minimap_sizes and pfMap.minimap_sizes[mapID]
      local zooms=pfMap.minimap_zoom and pfMap.minimap_indoor and pfMap.minimap_zoom[pfMap.minimap_indoor()]
      local mapZoom=zooms and zooms[zoom]
      if finite(px) and finite(py) and not (px==0 and py==0) and sizes and finite(sizes[1]) and finite(sizes[2]) and finite(mapZoom) and mapZoom>0 then
        local xDraw=Minimap:GetWidth()/(mapZoom/sizes[1])/100
        local yDraw=Minimap:GetHeight()/(mapZoom/sizes[2])/100
        for _,p in ipairs(points) do if p.zone==mapID then
          local dx,dy=(p.x-px)*100*xDraw,(p.y-py)*100*yDraw
          local rotates=(pfQuestCompat and pfQuestCompat.rotateMinimap)==true
          if rotates and type(GetPlayerFacing)=="function" then
            -- World north is up; a rotating minimap turns the map by player facing.
            local a=GetPlayerFacing();local rx=dx*math.cos(a)-dy*math.sin(a);dy=dx*math.sin(a)+dy*math.cos(a);dx=rx
          end
          local radius=math.sqrt(dx*dx+dy*dy)
          local q={x=.5+dx/Minimap:GetWidth(),y=.5+dy/Minimap:GetHeight(),zone=mapID,step=p.step,index=p.index,current=p.current,origin=p.origin}
          table.insert(localPoints,q)
        end end
      end
    end
    if enabled and table.getn(localPoints)>0 then M.miniHost:Show();draw(Minimap,localPoints,M.miniPins,M.miniLines,o)
    else M.miniHost:Hide();hide(M.miniPins);hide(M.miniLines) end
  end
end
