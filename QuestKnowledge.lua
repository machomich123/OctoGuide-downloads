-- Character facts, pfQuest predictions and observed NPC offers are distinct.
local G=OctoGuide
local K={revision=0,offers={},positions={}};G.knowledge=K
local function valid(id) return type(id)=='number' and id>0 and id==math.floor(id) end
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b,c,d,e=pcall(fn,unpack(arg));if ok then return a,b,c,d,e end
end
local function now() return GetTime and GetTime() or 0 end
local function data(id) return pfDB and pfDB.quests and pfDB.quests.data and pfDB.quests.data[id] end
local function done(id) return G.db and G.db.completedQuests and G.db.completedQuests[id]==true end
function G.KnowledgeInvalidate() K.revision=K.revision+1;K.positions={} end

-- Capture only explicit server IDs during a pfQuest query. pfQuest's final
-- history also adds every database pre/close relation; those are NOT proof.
function G.InstallPFHistoryHook()
 if not pfDatabase or type(pfDatabase.QueryServer)~='function' then return false end
 if K.queryWrapper==pfDatabase.QueryServer then return true end
 local query=pfDatabase.QueryServer
 K.queryWrapper=function(self,...)
  if K.history then return end
  K.history={ids={},packets=0,elapsed=0,previous=pfQuest_history}
  local ok,why=pcall(query,self,unpack(arg))
  if not ok then K.history=nil;G.historyFailure='pfQuest request failed';error(why) end
 end
 pfDatabase.QueryServer=K.queryWrapper;return true
end
function G.ReceivePFHistory(prefix,payload)
 local p=K.history
 if not p or prefix~='TWQUEST' or type(payload)~='string' then return end
 if string.len(payload)>64000 or string.find(payload,'[^%d%s]') then p.invalid=true;return end
 p.packets=p.packets+1
 for value in string.gfind(payload,'%d+') do local id=tonumber(value);if valid(id) then p.ids[id]=true else p.invalid=true end end
end
function G.PollPFHistory(elapsed)
 local p=K.history;if not p then return end;p.elapsed=p.elapsed+(elapsed or 0)
 local received=p.packets>0 and not p.invalid and p.elapsed>=3.5 and pfQuest_history~=p.previous
 if not received and p.elapsed<8 then return end
 K.history=nil
 if received then
  local count=0;for id in pairs(p.ids) do G.db.completedQuests[id]=true;count=count+1 end
  G.db.pfServerHistory={ids=p.ids,count=count,source='Direct TWQUEST response; pfQuest-inferred prerequisites excluded',receivedAt=time and time() or 0}
  G.db.historySource='pfQuest server response';G.historyReady=true;G.historyFailure=nil
  G.ReadPFQuestHistory();G.KnowledgeInvalidate()
 else G.historyFailure='pfQuest server response unavailable or invalid; previous confirmed history retained' end
 local pending=G.pendingFind
 if pending and pending.pfQuest then
  G.pendingFind=nil;G.ReconcileCharacter();G.AutoPlace(pending.automatic)
  if not received then G.Chat(G.historyFailure) end
 elseif received and G.ready then G.Sync();G.Render() end
end
local find=G.FindStep
function G.FindStep(automatic)
 if type(QueryQuestsCompleted)=='function' and type(GetQuestsCompleted)=='function' then return find(automatic) end
 if not G.ready or not G.db or G.player and G.player.faction~='Horde' then return find(automatic) end
 if G.pendingFind or K.history then return false,'Quest history request already running.' end
 if not G.InstallPFHistoryHook() then return find(automatic) end
 G.pendingFind={pfQuest=true,automatic=automatic==true}
 local ok=pcall(pfDatabase.QueryServer,pfDatabase)
 if not ok or not K.history then G.pendingFind=nil;return false,'pfQuest history request failed; existing history retained.' end
 G.Chat('Checking character history through pfQuest...');return true
end
local updateFind=G.UpdateFindStep
function G.UpdateFindStep(elapsed)
 G.PollPFHistory(elapsed)
 if not G.pendingFind or not G.pendingFind.pfQuest then updateFind(elapsed) end
 K.offerElapsed=(K.offerElapsed or 0)+(elapsed or 0)
 if K.offerElapsed>=.5 then
  K.offerElapsed=0;local changed=false
  for npc,offer in pairs(K.offers) do
   if offer.revision~=K.revision or now()-offer.time>=60 then K.offers[npc]=nil;changed=true end
  end
  if changed and G.ready then G.Render() end
 end
end

-- Returns the reason to stop, without marking an unavailable quest complete.
function G.QuestAvailability(id,step)
 if not valid(id) then return {state='unknown',reason='Quest identity unavailable.'} end
 if G.QuestIndex(id) then return {state='active',reason='Already in your live quest log.'} end
 if done(id) then return {state='completed',reason='Recorded server-confirmed completion.'} end
 for npc,offer in pairs(K.offers) do
  if offer.revision==K.revision and now()-offer.time<60 and offer.available[id] then return {state='offered',reason='Offered by the NPC in the observed quest dialog.',npc=npc} end
 end
 local q=data(id)
 if not q then return {state='unknown',reason='No quest record in the installed pfQuest database.'} end
 local givers,unavailable=0,0
 for _,npc in pairs(q.start and q.start.U or {}) do
  givers=givers+1
  local offer=K.offers[npc]
  if offer and offer.revision==K.revision and now()-offer.time<60 then
   if offer.available[id] then return {state='offered',reason='Offered by the NPC in the observed quest dialog.',npc=npc} end
   if offer.complete then unavailable=unavailable+1 end
  end
 end
 if givers>0 and unavailable==givers then return {state='blocked',reason='The observed NPC quest list did not offer this quest. Check the NPC manually or refresh Find step.'} end
 local level=UnitLevel and UnitLevel('player') or 0
 local minimum=math.max(q.min or 0,step and step.minlevel or 0)
 if level<minimum then return {state='blocked',reason='Requires level '..minimum..'; your level is '..level..'.'} end
 local _,race=call(UnitRace,'player');local _,class=call(UnitClass,'player')
 for _,spec in ipairs({{field='race',value=race,method='GetBitByRace'},{field='class',value=class,method='GetBitByClass'}}) do
  if q[spec.field] then
   local mask=pfDatabase and call(pfDatabase[spec.method],pfDatabase,spec.value)
   if type(mask)~='number' or not bit or not bit.band then return {state='unknown',reason='Cannot verify the pfQuest '..spec.field..' requirement with the loaded APIs.'} end
   if bit.band(q[spec.field],mask)~=mask then return {state='blocked',reason='pfQuest lists a different '..spec.field..' requirement.'} end
  end
 end
 if q.skill and (not pfDatabase or type(pfDatabase.GetPlayerSkill)~='function') then return {state='unknown',reason='Profession requirement could not be checked.'} end
 if q.skill and pfDatabase and type(pfDatabase.GetPlayerSkill)=='function' then
  local ok,skill=pcall(pfDatabase.GetPlayerSkill,pfDatabase,q.skill)
  if ok and not skill then return {state='blocked',reason='Required profession is not known.'} end
 end
 local faction=call(UnitFactionGroup,'player');local wanted=faction=='Horde' and 'H' or faction=='Alliance' and 'A'
 if wanted then
  local hasStarter,matching=false,false
  for _,kind in ipairs({'U','O'}) do
   local entries=pfDB[kind=='U' and 'units' or 'objects']
   for _,entry in pairs(q.start and q.start[kind] or {}) do
    local record=entries and entries.data and entries.data[entry]
    if record then hasStarter=true;if not record.fac or string.find(record.fac,wanted,1,true) then matching=true end end
   end
  end
  if hasStarter and not matching then return {state='blocked',reason='The recorded quest starters belong to the other faction.'} end
 end
 if q.event then return {state='needs_check',reason='Event quest: the current event and NPC offer have not been observed.'} end
 for _,pre in ipairs(step and step.requires or {}) do
  if not done(pre) then return {state='needs_check',reason='An authored prerequisite is not confirmed completed. Use Find step before travelling.'} end
 end
 if q.pre and table.getn(q.pre)>0 then
  local confirmed=false
  for _,pre in pairs(q.pre) do if done(pre) then confirmed=true end end
  if not confirmed then return {state='needs_check',reason='pfQuest lists an unconfirmed predecessor; it may be a breadcrumb rather than a hard requirement. Refresh Find step or check the actual NPC before travelling.'} end
 end
 local marker
 if pfDatabase and type(pfDatabase.QuestFilter)=='function' and type(pfDatabase.GetBitByRace)=='function' and type(pfDatabase.GetBitByClass)=='function' then
  local rm=call(pfDatabase.GetBitByRace,pfDatabase,race);local cm=call(pfDatabase.GetBitByClass,pfDatabase,class)
  if rm and cm then local ok,result=pcall(pfDatabase.QuestFilter,pfDatabase,id,level,cm,rm);if ok then marker=result==true end end
 end
 return {state='expected',reason='Expected from pfQuest data; the remote NPC offer has not been observed.',mapMarker=marker}
end
function G.PickupAvailability(s)
 if not s or not (s.action=='accept' or s.startsQuestID) then return nil end
 return G.QuestAvailability(s.questID or s.startsQuestID,s)
end
function G.ObserveQuestGiver()
 local npc=call(UnitCreatureID,'npc')
 if not valid(npc) or not C_GossipInfo then return end
 local available=call(C_GossipInfo.GetAvailableQuests);local active=call(C_GossipInfo.GetActiveQuests)
 if type(available)~='table' or type(active)~='table' then return end
 local offer={time=now(),revision=K.revision,available={},complete=true}
 for _,entry in ipairs(available) do if type(entry)=='table' and valid(entry.questID) then offer.available[entry.questID]=true else offer.complete=false end end
 -- Active entries need valid identities too before absence can mean anything.
 for _,entry in ipairs(active) do if type(entry)~='table' or not valid(entry.questID) then offer.complete=false end end
 K.offers[npc]=offer
end

function G.AreaQuestList(zone)
 local rows={};local quests=pfDB and pfDB.quests and pfDB.quests.data or {}
 for id,q in pairs(quests) do
  local points={}
  for _,kind in ipairs({'U','O'}) do
   local db=pfDB[kind=='U' and 'units' or 'objects']
   for _,entry in pairs(q.start and q.start[kind] or {}) do
    for _,p in ipairs(db and db.data and db.data[entry] and db.data[entry].coords or {}) do
     if p[3]==zone then table.insert(points,{zone=zone,x=p[1]/100,y=p[2]/100,entry=entry,kind=kind}) end
    end
   end
  end
  if table.getn(points)>0 then
   local state=G.QuestAvailability(id)
   local loc=pfDB.quests.loc or pfDB.quests.enUS or {};local name=loc[id] and loc[id].T
   table.insert(rows,{id=id,title=name or tostring(id),state=state.state,reason=state.reason,mapMarker=state.mapMarker,points=points})
  end
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
 G.areaQuestSnapshot={zone=zone,quests=rows,source='pfQuest quest/start records, character requirements and observed NPC dialogs',revision=K.revision}
 return rows
end
function G.ShowAreaQuests(zone)
 zone=zone or C_Map and call(C_Map.GetBestMapForUnit,'player')
 if not zone then G.Chat('Current area unavailable. Use /octoguide quests AREA_ID.');return end
 local rows=G.AreaQuestList(zone);local counts={offered=0,expected=0,active=0,completed=0,blocked=0,needs_check=0,unknown=0}
 local names={}
 for _,q in ipairs(rows) do
  counts[q.state]=(counts[q.state] or 0)+1
  if (q.state=='offered' or q.state=='expected') and table.getn(names)<8 then table.insert(names,q.title..' ['..q.state..']') end
 end
 G.Chat('Area '..zone..': '..counts.offered..' observed offers, '..counts.expected..' expected from pfQuest, '..counts.active..' active, '..counts.completed..' completed; '..(counts.needs_check+counts.unknown)..' need verification. Map visibility filters are separate from availability.')
 if table.getn(names)>0 then G.Chat(table.concat(names,'; ')) end
end

local scan=G.ScanCharacter
function G.ScanCharacter(reason)
 local result=scan(reason)
 if G.db.pfServerHistory then result.history='Saved direct pfQuest server snapshot ('..G.db.pfServerHistory.count..' explicit IDs); refresh with Find step' end
 return result
end

local raw=G.RawNavTarget
function G.RawNavTarget()
 if not G.gatherTarget then
  local s=G.Current();local state=G.PickupAvailability(s)
  if state and (state.state=='blocked' or state.state=='needs_check' or state.state=='unknown') then return {blockedReason=state.reason,blockedQuestID=s.questID or s.startsQuestID} end
 end
 return raw()
end
local present=G.Present
function G.Present(s,preview)
 local title,body,action=present(s,preview);local state=G.PickupAvailability(s)
 if state and state.state~='completed' and state.state~='active' then
  body=body..'\nAvailability: '..state.reason
  if state.state=='blocked' or state.state=='needs_check' or state.state=='unknown' then title='Check pickup: '..title end
 end
 return title,body,action
end
local step=G.automation.Step
function G.automation.Step(id,action)
 local s=step(id,action)
 if s and action=='accept' then local state=G.PickupAvailability(s);if state and (state.state=='blocked' or state.state=='needs_check' or state.state=='unknown') then return nil end end
 return s
end
local automationEvent=G.automation.Event
function G.automation.Event(ev)
 -- Read lists before automation selects a quest and closes the gossip session.
 if ev=='GOSSIP_SHOW' or ev=='QUEST_GREETING' then G.ObserveQuestGiver() end
 automationEvent(ev)
end

local baseEvent=G.Event
function G.Event(ev,a,b)
 if ev=='QUEST_LOG_UPDATE' or ev=='QUEST_ACCEPTED' or ev=='QUEST_TURNED_IN' or ev=='PLAYER_LEVEL_UP' or ev=='SKILL_LINES_CHANGED' then G.KnowledgeInvalidate() end
 baseEvent(ev,a,b)
 if ev=='PLAYER_ENTERING_WORLD' and G.ready then G.InstallPFHistoryHook() end
end
local frame=CreateFrame('Frame');K.frame=frame
for _,name in ipairs({'GOSSIP_SHOW','QUEST_GREETING','CHAT_MSG_ADDON'}) do frame:RegisterEvent(name) end
frame:SetScript('OnEvent',function()
 if event=='CHAT_MSG_ADDON' then G.ReceivePFHistory(arg1,arg2)
 else
  if G.ready then G.Render() end
 end
end)
