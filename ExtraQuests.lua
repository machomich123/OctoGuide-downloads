-- Verified OctoWoW additions, optional and attached to existing route visits.
local G=OctoGuide
local definitions={
 {id=80384,name='Pinch of Salt',min=6,anchor=818,start={zone=14,x=.532,y=.816},work={zone=14,x=.54,y=.82},hint='Collect 8 Crab Shells while working along the coast. Use the existing Echo Isles trip; skip if this would require a separate detour.'},
 {id=70052,name="Trader's Misfortune",min=12,anchor=887,start={zone=17,x=.634,y=.385},work={zone=17,x=.631,y=.443},hint='Look for Tazan while killing the Southsea pirates. Skip this addition if he is absent; avoid waiting or a separate hunt.'},
 {id=40389,name="Zalazane's Fall",min=7,prerequisite=826,afterReward=826,delivery=831,start={zone=14,x=.56,y=.746},finish={zone=1637,x=.343,y=.363},hint='Carry the head to Vol\'jin during the planned Grommash Hold visit. Do not make a separate Orgrimmar trip just for this delivery.'}
}
G.extraDefinitions=definitions
local function make(d,action,parent,point)
 local s={id='octo-extra-'..d.id..'-'..action..'-'..parent.id,action=action,questID=d.id,text=(action=='accept' and 'Optional: accept ' or action=='turnin' and 'Optional: turn in ' or 'Optional: complete ')..d.name..'.',minlevel=d.min,optionalExtra=true,extraPrerequisite=d.prerequisite,extraHint=d.hint,profiles=parent.profiles,classes=parent.classes,races=parent.races,sourceGuide=parent.sourceGuide,sourceBlock=parent.sourceBlock,page=parent.page,expectedLevel=parent.expectedLevel}
 if point then s.zone=point.zone;s.x=point.x;s.y=point.y end
 return s
end
function G.InstallExtras()
for _,id in ipairs(G.order) do
 local guide=G.guides[id];local steps={}
 if not guide.extrasInstalled then
 for _,s in ipairs(guide.steps) do
  table.insert(steps,s)
  for _,d in ipairs(definitions) do
   if d.anchor and s.questID==d.anchor then
    if s.action=='accept' then table.insert(steps,make(d,'accept',s,d.start))
    elseif s.action=='complete' or s.action=='objective' then
     local work=make(d,'complete',s,d.work);work.background=true;work.parallelUntil=(s.sourceBlock or 0)+10000
     work.sourceBlock=(s.sourceBlock or 1)-.01;table.insert(steps,work)
    elseif s.action=='turnin' then table.insert(steps,make(d,'turnin',s,d.start)) end
   end
   if d.afterReward and s.questID==d.afterReward and s.action=='turnin' then table.insert(steps,make(d,'accept',s,d.start)) end
   if d.delivery and s.questID==d.delivery and s.action=='turnin' then table.insert(steps,make(d,'turnin',s,d.finish)) end
  end
 end
 guide.steps=steps;guide.extrasInstalled=true
 end
end
end
G.InstallExtras()
local baseSatisfied=G.Satisfied
function G.Satisfied(s)
 if s.optionalExtra then
  if G.db.extraQuests==false or (s.minlevel and UnitLevel('player')<s.minlevel) then return true end
  if s.extraPrerequisite and not G.db.completedQuests[s.extraPrerequisite] then
   local verified=false
   if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then local ok,v=pcall(C_QuestLog.IsQuestFlaggedCompleted,s.extraPrerequisite);verified=ok and v==true end
   if not verified then return true end
  end
  -- A missing optional quest is not a reason to block the main route at turn-in.
  if s.action=='turnin' and not G.QuestIndex(s.questID) and not G.db.completedQuests[s.questID] then return true end
 end
 return baseSatisfied(s)
end
