-- Free, local character reconciliation. Unknown observations never prove completion.
local G=OctoGuide
local function id(v) return type(v)=='number' and v>0 and v==math.floor(v) end
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b,c,d,e,f,g,h=pcall(fn,unpack(arg));if ok then return a,b,c,d,e,f,g,h end
end
function G.ReadCompletedHistory()
 if type(GetQuestsCompleted)~='function' then return false end
 local ok,data=pcall(GetQuestsCompleted)
 if not ok or type(data)~='table' then
  local out={};ok,data=pcall(GetQuestsCompleted,out)
  if ok and data==nil then data=out end
 end
 if not ok or type(data)~='table' then return false end
 local list=true;local count=0;local nonFlag=false
 for k,v in pairs(data) do count=count+1;if not id(k) or not id(v) then list=false end;if id(v) and v>1 then nonFlag=true end end
 if table.getn(data)~=count or not nonFlag then list=false end
 for k,v in pairs(data) do
  local q=list and v or tonumber(k)
  if id(q) and (list or v~=false and v~=0) then G.db.completedQuests[q]=true end
 end
 G.db.historySource='server';G.historyReady=true;return true
end
function G.ReadPFQuestHistory()
 if type(pfQuest_history)~='table' or not G.db then return 0 end
 local rows={};local count=0
 for key,value in pairs(pfQuest_history) do
  local q=tonumber(key)
  if id(q) and type(value)=='table' then
   rows[q]={timestamp=tonumber(value[1]) or 0,level=tonumber(value[2]) or 0,source='pfQuest (may include manual marks)'};count=count+1
  end
 end
 G.db.pfQuestHistory=rows
 return count
end
function G.ScanCharacter(reason)
 if G.InvalidateRuntimeReads then G.InvalidateRuntimeReads() end
 -- Do not recopy an unchanged completion-history table for every bag event.
 -- Inventory AND quest objectives remain live (collect goals may regress).
 local previous=reason=='BAG_UPDATE' and G.characterScan
 local pfCount=previous and previous.pfQuestCount or G.ReadPFQuestHistory()
 local scan={pfQuestCount=pfCount,quests={},items={},equipped={},flight={},questCount=0,itemSlots=0,history=G.historyReady and 'server response' or G.historyFailure or 'not available',flightStatus='previously observed only',bankStatus='closed; not scanned'}
 local count=call(GetNumQuestLogEntries)
 if type(count)=='number' then
  for i=1,count do
   local q=C_QuestLog and call(C_QuestLog.GetQuestIDForLogIndex,i) or call(GetQuestIDFromLogIndex,i)
   if id(q) then
    local title,level,tag,header,collapsed,done=call(GetQuestLogTitle,i)
    local quest={index=i,title=title,complete=done==true or done==1,objectives={}}
    local n=call(GetNumQuestLeaderBoards,i) or 0
    for j=1,n do local text,kind,finished=call(GetQuestLogLeaderBoard,j,i);quest.objectives[j]={text=text,kind=kind,done=finished==true or finished==1} end
    scan.quests[q]=quest;scan.questCount=scan.questCount+1
   end
  end
  scan.questLog='scanned'
 else scan.questLog='unavailable' end
 local function add(link,n)
  if type(link)~='string' then return end
  local _,_,value=string.find(link,'item:(%d+)');value=tonumber(value)
  if value then scan.items[value]=(scan.items[value] or 0)+(tonumber(n) or 1);scan.itemSlots=scan.itemSlots+1 end
 end
 local function bag(b)
  for slot=1,call(GetContainerNumSlots,b) or 0 do
   local link=call(GetContainerItemLink,b,slot)
   local texture,n=call(GetContainerItemInfo,b,slot);add(link,n)
  end
 end
 for b=0,4 do bag(b) end
 for slot=0,23 do local link=call(GetInventoryItemLink,'player',slot);scan.equipped[slot]=link;add(link,call(GetInventoryItemCount,'player',slot)) end
 if BankFrame and BankFrame.IsShown and BankFrame:IsShown() then
  scan.bankStatus='open; scanned';bag(-1);for b=5,10 do bag(b) end
 end
 scan.inventory=type(GetContainerItemLink)=='function' and 'scanned' or 'unavailable'
 scan.hearth=call(GetBindLocation)
 local taxiOpen=TaxiFrame and TaxiFrame.IsShown and TaxiFrame:IsShown()
 -- The native taxi APIs read live flight-master state. Do not call them at world load.
 if taxiOpen and G.Travel and G.Travel.ObserveTaxi then pcall(G.Travel.ObserveTaxi) end
 local saved=G.db.travel and G.db.travel.known or {}
 for node,known in pairs(saved) do if known then scan.flight[node]=true end end
 local taxi=taxiOpen and C_TaxiMap and call(C_TaxiMap.GetAllTaxiNodes)
 if type(taxi)=='table' and table.getn(taxi)>0 then scan.flightStatus='current flight master and previous observations' end
 scan.level=call(UnitLevel,'player');scan.xp=call(UnitXP,'player');scan.xpMax=call(UnitXPMax,'player')
 scan.zone=call(GetZoneText);scan.time=call(GetTime) or 0
 G.characterScan=scan;return scan
end
function G.StepEvidence(s,scan)
 scan=scan or G.characterScan;if not scan then return nil end
 local q=s.questID and scan.quests[s.questID]
 if s.questID and G.db.completedQuests[s.questID] and (s.action=='accept' or s.action=='objective' or s.action=='complete' or s.action=='turnin') then return 'quest turned in' end
 if q then
  if s.action=='accept' then return 'quest already accepted' end
  if s.action=='complete' or s.action=='objective' then
   if s.objective and q.objectives[s.objective] and q.objectives[s.objective].done then return 'objective complete' end
   if not s.objective and q.complete then return 'quest ready for turn-in' end
  end
 end
 -- Never use inventory to manufacture an actual quest turn-in or manual action.
 if (s.action=='collect' or s.action=='buy') and s.itemID and s.itemCount and (scan.items[s.itemID] or 0)>=s.itemCount then return 'items already carried' end
 if s.goalItemID and (scan.items[s.goalItemID] or 0)>=(s.goalItemCount or 1) then return 'required item already carried or equipped' end
 local inn=s.inn or s.bindName
 if not inn and s.action=='bind' then local _,_,name=string.find(s.text or '','^Set your Hearthstone to (.+)$');inn=name and string.gsub(name,'%.$','') end
 if s.action=='bind' and inn and scan.hearth==inn then return 'hearthstone already bound here' end
 if s.action=='flightpath' then
  if s.taxiNodeID and scan.flight[s.taxiNodeID] then return 'flight path already known' end
  local _,_,wanted=string.find(s.text or '','^Get the (.+) flight path%.?$')
  wanted=wanted and string.gsub(wanted,'%.$','')
  if wanted then for node in pairs(scan.flight) do
   local name=G.db.travel.knownNames and G.db.travel.knownNames[node] or G.Travel and G.Travel.nodes and G.Travel.nodes[node] and G.Travel.nodes[node].name
   if name==wanted or name and string.sub(name,1,string.len(wanted)+1)==wanted..',' then return 'flight path already known' end
  end end
 end
 return nil
end
function G.ReconcileCharacter()
 local scan=G.ScanCharacter();scan.completedSteps=0;scan.completedQuestCount=0
 if not G.historyReady and C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function' then
  local seen={}
  for _,guideID in ipairs(G.order) do local guide=G.guides[guideID];if G.Playable(guide) then for _,s in ipairs(guide.steps) do
   if s.questID and not seen[s.questID] and G.Allowed(s) then seen[s.questID]=true;if call(C_QuestLog.IsQuestFlaggedCompleted,s.questID)==true then G.db.completedQuests[s.questID]=true end end
  end end end
  scan.history='available route quests checked individually'
 end
 for q,done in pairs(G.db.completedQuests) do if done then scan.completedQuestCount=scan.completedQuestCount+1 end end
 G.db.observedSteps=G.db.observedSteps or {}
 for _,guideID in ipairs(G.order) do
  local guide=G.guides[guideID]
  if G.Playable(guide) then for _,s in ipairs(guide.steps) do if G.Allowed(s) then
   local key=guide.id..':'..tostring(s.id)
   if s.mode or s.branch or s.requiresDeath or s.action=='death' or s.modes and not (s.modes.normal and s.modes.hardcore) then key=key..':mode:'..G.Mode() end
   -- Separate current evidence from explicit Done/Skip and old observed acceptance.
   local why=G.StepEvidence(s,scan);G.db.observedSteps[key]=why
   if why then scan.completedSteps=scan.completedSteps+1 end
  end end end
 end
 return scan
end
function G.ScanSummary()
 local s=G.characterScan;if not s then return '' end
 return tostring(s.questCount)..' active quests; '..tostring(s.completedQuestCount or 0)..' recorded turn-ins; '..tostring(s.pfQuestCount or 0)..' pfQuest history entries (separate source); '..tostring(s.completedSteps or 0)..' satisfied guide actions (not separate completed quests). Inventory: '..s.inventory..'. Bank: '..s.bankStatus..'. Hearthstone: '..(s.hearth or 'unavailable')..'. Flight paths: '..s.flightStatus..'. Earlier quest history: '..s.history..'.'
end
function G.PlacementSummary(reason)
 local s=G.characterScan
 if not s then return 'Starting step: '..reason..'. Earlier steps remain available with Back.' end
 local history=G.historyReady and 'Earlier quest history checked.' or 'Full earlier quest history unavailable; using current quests and recorded turn-ins.'
 if s.history=='available route quests checked individually' then history='Available quest completion flags checked.' end
 return 'Found step: '..reason..'. '..history..' /octoguide scan shows details.'
end
function G.CancelFindStep()
 G.pendingFind=nil;G.autoplacePending=false
end
function G.FindStep(automatic)
 if G.player and G.player.faction~='Horde' then return G.AutoPlace(automatic) end
 if not G.ready then return false,'The guide is not initialized. Check /octocheck.' end
 if OctoAddonHealth and not OctoAddonHealth.Check('OctoGuide',false) then return false,'Required addon components are unavailable. See /octocheck.' end
 if G.pendingFind then return false,'Scanning quest history. Please wait.' end
 G.ScanCharacter()
 if type(QueryQuestsCompleted)=='function' and type(GetQuestsCompleted)=='function' then
  G.pendingFind={automatic=automatic==true,remaining=8};G.historyReady=false;G.historyFailure=nil
  if G.events then pcall(function() G.events:RegisterEvent('QUEST_QUERY_COMPLETE') end) end
  -- Register and set pending before request: a synchronous response is also safe.
  local ok,why=pcall(QueryQuestsCompleted)
  if ok then
   if G.pendingFind then G.Chat('Scanning quest history...');if G.menu and G.menu.info then G.menu.info:SetText('Scanning quest history...') end end
   return true
  end
  G.pendingFind=nil
 end
 G.historyReady=false
 if type(QueryQuestsCompleted)~='function' or type(GetQuestsCompleted)~='function' then
  G.historyFailure='not supported by this client; using locally recorded turn-ins'
 else G.historyFailure='history request failed; using locally recorded turn-ins' end
 G.ReconcileCharacter();return G.AutoPlace(automatic)
end
function G.FinishFindStep(received)
 local pending=G.pendingFind;if not pending then return end
 G.pendingFind=nil
 G.historyReady=received and G.ReadCompletedHistory() or false
 G.historyFailure=not G.historyReady and (received and 'server response could not be read' or 'server unavailable or timed out') or nil
 G.ReconcileCharacter()
 local ok,why=G.AutoPlace(pending.automatic);if not ok then G.Chat(why or 'No matching route.') end
end
function G.UpdateFindStep(elapsed)
 if not G.pendingFind then return end
 G.pendingFind.remaining=G.pendingFind.remaining-elapsed
 if G.pendingFind.remaining<=0 then G.FinishFindStep(false) end
end
-- Keep later out-of-order completion dynamically visible without overwriting manual choices.
local satisfied=G.Satisfied
function G.Satisfied(s)
 if G.StepEvidence(s) then return true end
 return satisfied(s)
end
