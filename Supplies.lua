-- Normalize source blocks at registration, including already installed route packs.
-- Keep every stable step ID so old per-character progress remains meaningful.
local G=OctoGuide
local register=G.RegisterGuide
local food={[159]=true,[117]=true,[4540]=true,[1205]=true,[1645]=true,[1708]=true,[8766]=true,[2288]=true,[3770]=true,[4599]=true,[8952]=true,[4604]=true,[4605]=true,[4606]=true,[4607]=true,[4608]=true}
local function sameProfiles(a,b)
 local x,y=a.profiles or {},b.profiles or {};if table.getn(x)~=table.getn(y) then return false end
 local seen={};for _,v in ipairs(x) do seen[v]=true end;for _,v in ipairs(y) do if not seen[v] then return false end end;return true
end
function G.RegisterGuide(meta,steps)
 if meta.routeFamily=='rxp' then
  for _,s in ipairs(steps) do
   if s.action=='use' and s.sourceBlock then
    for _,v in ipairs(steps) do
     if v.sourceBlock==s.sourceBlock and v.questID and (v.action=='complete' or v.action=='objective') and sameProfiles(s,v) then
      s.mergedUse=v.id;break
     end
    end
   end
  end
  for _,s in ipairs(steps) do
   if s.action=='collect' and not s.questID and not s.goalQuestID then
    local buy=false
    for _,n in ipairs((meta.blockNotes or {})[s.sourceBlock] or {}) do if string.find(string.lower(n.text or ''),'buy',1,true) then buy=true end end
    if buy then
     s.text='Buy supplies'
     if food[s.itemID] then s.optionalSupply=true;s.text='Optional food and drinks' end
    elseif string.find(s.text or '', '^Perform collect ') then s.text='Collect required items' end
    local vendor
    for _,v in ipairs(steps) do if v.action=='vendor' and v.sourceBlock==s.sourceBlock and sameProfiles(s,v) then vendor=v;break end end
    if vendor then
     if buy then
      s.mergedVendor=vendor.id;vendor.text='Vendor visit';vendor.manual=true
      if food[s.itemID] then vendor.optionalSupply=true;vendor.text='Optional food and drinks' end
     end
    end
   end
  end
 end
 return register(meta,steps)
end
local allowed=G.Allowed
function G.Allowed(s)
 if s.mergedVendor or s.mergedUse then return false end
 return allowed(s)
end
local present=G.Present
-- Presentation.lua installs this later; UI uses this explicit annotation instead.
function G.SupplyHint(s)
 return s and s.optionalSupply and 'Optional: buy food or drinks only if you need them. You can skip this visit.' or nil
end
