-- Local walking/swimming directions belong to the next quest, not a Done step.
local G=OctoGuide
local register=G.RegisterGuide
function G.RegisterGuide(meta,steps)
 register(meta,steps)
 for i,s in ipairs(steps) do
  local text=string.lower(s.text or '')
  local simple=string.find(text,'^swim ') or string.find(text,'^walk ') or string.find(text,'^run ') or string.find(text,'^head ') or string.find(text,'^go ') or string.find(text,'^travel to ')
  if s.action=='travel' and simple and not s.questID and not s.path and not s.requiresDeath and s.zone and s.x and s.y then
   for j=i+1,math.min(i+8,table.getn(steps)) do
    local target=steps[j]
    if target.questID and not target.background and not target.informational then
     if not target.background and not target.informational and (target.zone==s.zone or not target.zone and text=='swim to the main island') and (target.action=='accept' or target.action=='complete' or target.action=='objective' or target.action=='turnin') then
      s.travelFor=target;target.travelLeadins=target.travelLeadins or {};table.insert(target.travelLeadins,s)
     end
     break
    elseif not target.background and not target.informational and target.action~='note' and target.action~='travel' then break end
   end
  end
 end
end
function G.TravelFallback(s)
 if not s or s.zone then return nil end
 for i=table.getn(s.travelLeadins or {}),1,-1 do
  local t=s.travelLeadins[i];if G.Allowed(t) and G.SourceEligible(t) then return t end
 end
end
function G.FoldedTravel(s)
 return s and s.travelFor and G.Allowed(s.travelFor) or false
end
function G.TravelInstructions(s)
 local result={}
 for _,t in ipairs(s and s.travelLeadins or {}) do
  if G.Allowed(t) and G.SourceEligible(t) then table.insert(result,t.text) end
 end
 return result
end
function G.TravelLeadTarget(s)
 for _,t in ipairs(s and s.travelLeadins or {}) do
  if G.Allowed(t) and G.SourceEligible(t) and not G.db.progress[G.Key(t)] then
   local nav=OctoGuideNavigation and OctoGuideNavigation.ReadWaypoint(t)
   if nav and type(nav.yards)=='number' and nav.yards<=math.max(15,t.radius or 25) then
    G.db.progress[G.Key(t)]='observed'
    if G.InvalidateRuntimeReads then G.InvalidateRuntimeReads() end
   else return t end
  end
 end
end
