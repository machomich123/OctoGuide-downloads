-- Authored flights must not assume a character has learned the destination.
local G=OctoGuide
function G.FlightDestination(s)
 if not s or s.action~='fly' then return nil end
 local _,_,name=string.find(s.text or '','^[Ff]ly to (.+)')
 if not name then return nil end
 name=string.gsub(name,'%.$','')
 local db=G.db and G.db.travel or {}
 for id,known in pairs(db.known or {}) do
  local label=db.knownNames and db.knownNames[id]
  if known and label and (label==name or string.sub(label,1,string.len(name)+1)==name..',') then return name,true end
 end
 return name,false
end
function G.FlightFallback(s)
 local name,known=G.FlightDestination(s)
 if not name or known then return nil end
 local body='Flight path not confirmed for this character. Open the flight master to record available flights.'
 local target
 if name=='Undercity' then
  body=body..' If Undercity is unavailable: from the Sepulcher follow the road north through Silverpine into Tirisfal, then follow the road to the Ruins of Lordaeron. Enter the ruins, take the elevator down and follow the tunnel into Undercity. Speak to the flight master to learn the flight path.'
  -- Use the actual taxi database destination, never the departure coordinates
  -- stored on the original Fly step. The arrow is a destination, not a safe path.
 end
 if G.Travel and G.Travel.Load() then
  for _,n in pairs(G.Travel.nodes or {}) do
   if n.name==name or n.name and string.sub(n.name,1,string.len(name)+1)==name..',' then
    if n.areaID and n.mapX and n.mapY then target={zone=n.areaID,x=n.mapX/100,y=n.mapY/100,flightFallback=true} end
    break
   end
  end
 end
 if name~='Undercity' then body=body..' Travel overland to '..name..' and learn its flight path. The destination arrow does not describe a safe walking route; follow roads and use the required boat or zeppelin for another continent.' end
 return {title='Travel to '..name,body=body,target=target or {flightFallback=true},name=name}
end
local present=G.Present
function G.Present(s,preview)
 local fallback=G.FlightFallback(s)
 if fallback then return fallback.title,fallback.body,'travel' end
 local title,body,action=present(s,preview)
 if s and (string.find(body or '','Apothecarium',1,true) or string.find(body or '','Faranell',1,true) or string.find(body or '','Zinge',1,true)) then
  body=body..'\nThe Apothecarium is on the lower level of Undercity. Follow the ramps down to the outer canal and the Apothecarium entrance; the arrow points to the destination, not the ramps.'
 end
 return title,body,action
end
local nav=G.RawNavTarget
function G.RawNavTarget()
 local s=not G.gatherTarget and G.Current()
 local fallback=G.FlightFallback(s)
 if fallback then return fallback.target end
 return nav()
end
