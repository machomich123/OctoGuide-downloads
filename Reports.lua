-- Bounded, allowlisted diagnostics. No chat, account names or credentials.
local G=OctoGuide
G.reportEvents={}
function G.ReportEvent(name)
 table.insert(G.reportEvents,{event=name,time=GetTime and GetTime() or 0})
 if table.getn(G.reportEvents)>100 then table.remove(G.reportEvents,1) end
end
local function snapshot(frame)
 if not frame then return nil end
 local r={shown=frame:IsShown(),width=frame:GetWidth(),height=frame:GetHeight(),texts={}}
 if frame.GetScale then r.scale=frame:GetScale() end
 for _,key in ipairs({'title','version','route','step','details','distance','info','note','status'}) do
  local label=frame[key];if label and label.GetText then r.texts[key]=label:GetText() end
 end
 for _,key in ipairs({'rows','objectives','nextRows'}) do
  r[key]={}
  for _,row in ipairs(frame[key] or {}) do
   local item={shown=row:IsShown()}
   if row.label then item.text=row.label:GetText() end
   if row.name then item.text=row.name:GetText();item.count=row.count:GetText() end
   if row.title then item.title=row.title:GetText();item.details=row.details:GetText() end
   table.insert(r[key],item)
  end
 end
 return r
end
function G.MakeReport(description)
 if type(description)~='string' or not string.find(description,'%S') then return nil,'Describe the problem first.' end
 local s=G.Current();local apis={}
 for _,key in ipairs({'UnitPosition','GetPlayerFacing','GetQuestLogLeaderBoardID','ClosestGameObjectPosition','ClosestUnitPosition','UnitCreatureID','UnitIsDeadOrGhost'}) do apis[key]=type(getglobal and getglobal(key) or _G[key])=='function' end
 local r={version=G.version,description=string.sub(description,1,2000),time=time and time() or 0,profile={race=G.player.race,class=G.player.class,level=UnitLevel('player')},apis=apis,
  route=G.state and G.state.guide.id,step=s and s.id,quest=s and s.questID,objectives=s and G.Objectives(s),navigation=G.navigationEvidence,autoAccept=G.db.lastAutoAccept,questAvailability=G.PickupAvailability and G.PickupAvailability(s),serverHistory=G.db.pfServerHistory and {count=G.db.pfServerHistory.count,source=G.db.pfServerHistory.source,receivedAt=G.db.pfServerHistory.receivedAt},
  settings={zoom=G.db.zoom,view=G.db.view,mode=G.Mode(),party=G.PartyMode(),secondaryArrow=G.db.secondaryArrow,transparent=G.db.transparent,opacity=G.db.opacity,width=G.frame:GetWidth(),height=G.frame:GetHeight()},
  ui={guide=snapshot(G.frame),guides=snapshot(G.menu),settings=snapshot(G.options)},events={},errors={},status='saved locally',images='UI state snapshots; pixel screenshots unavailable',upload='unavailable in this client'}
 r.performance=G.PerformanceSnapshot and G.PerformanceSnapshot()
 r.addons={};r.questLog={};r.completedQuestIDs={}
 if GetBuildInfo then local ok,version,build,date=pcall(GetBuildInfo);if ok then r.client={version=version,build=build,date=date} end end
 if OctoGuideBridgeVersion then local ok,version=pcall(OctoGuideBridgeVersion);if ok then r.bridgeVersion=version end end
 if GetNumAddOns and GetAddOnInfo then
  for i=1,math.min(GetNumAddOns(),200) do
   local name,title,notes,enabled,loadable,reason=GetAddOnInfo(i)
   local version;if name and GetAddOnMetadata then local ok,v=pcall(GetAddOnMetadata,name,'Version');if ok then version=v end end
   local loaded;if name and IsAddOnLoaded then loaded=IsAddOnLoaded(name) end
   table.insert(r.addons,{name=name,version=version,enabled=enabled==true or enabled==1,loaded=loaded==true or loaded==1,loadable=loadable==true or loadable==1,reason=reason})
  end
 end
 if GetNumQuestLogEntries and GetQuestLogTitle then
  for i=1,math.min(GetNumQuestLogEntries(),100) do
   local title,level,tag,header,collapsed,complete=GetQuestLogTitle(i)
   if not header then
    local id;if C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then local ok,v=pcall(C_QuestLog.GetQuestIDForLogIndex,i);if ok then id=v end
    elseif GetQuestIDFromLogIndex then local ok,v=pcall(GetQuestIDFromLogIndex,i);if ok then id=v end end
    table.insert(r.questLog,{id=id,title=title,level=level,complete=complete})
   end
  end
 end
 for id,done in pairs(G.db.completedQuests or {}) do if done and table.getn(r.completedQuestIDs)<2000 then table.insert(r.completedQuestIDs,id) end end
 r.stepIndex=G.state and G.state.index;r.characterTracking=G.db.characterOwner~=nil
 for _,e in ipairs(G.reportEvents) do table.insert(r.events,{event=e.event,time=e.time}) end
 for _,e in ipairs(G.reportErrors or {}) do table.insert(r.errors,e) end
 G.db.reports=G.db.reports or {};G.db.reportCounter=(G.db.reportCounter or 0)+1;r.id=tostring(r.time)..'-'..G.db.reportCounter
 table.insert(G.db.reports,r);if table.getn(G.db.reports)>10 then table.remove(G.db.reports,1) end
 return r
end
function G.InstallReportErrors()
 if not geterrorhandler or not seterrorhandler or G.reportHandler then return end
 local previous=geterrorhandler();G.reportErrors={}
 G.reportHandler=function(message)
  if type(message)=='string' and string.find(string.lower(message),'octoguide',1,true) then
   table.insert(G.reportErrors,string.sub(message,1,1600));if table.getn(G.reportErrors)>20 then table.remove(G.reportErrors,1) end
  end
  if previous then return previous(message) end
 end
 seterrorhandler(G.reportHandler)
end
