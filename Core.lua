-- OctoGuide original runtime, Lua 5.0 / WoW 1.12 + installed ClassicAPI.
OctoGuide={version='0.4.5',guides={},order={},ready=false,elapsed=0}
local G=OctoGuide
local actions={accept=true,complete=true,objective=true,turnin=true,travel=true,level=true,train=true,buy=true,note=true,death=true,hearth=true,fly=true,flight=true,boat=true,grind=true,collect=true,use=true,bind=true,flightpath=true,vendor=true,repair=true}
local deathActions={death=true}
function G.Mode() return G.db and G.db.mode=='normal' and 'normal' or 'hardcore' end
local function validateModes(item)
  if item.mode then assert(item.mode=='normal' or item.mode=='hardcore','Unknown route mode') end
  if item.modes then
    assert(type(item.modes)=='table','Modes must be a table')
    local count=0
    for k,v in pairs(item.modes) do assert((k=='normal' or k=='hardcore') and type(v)=='boolean','Unknown route mode');if v then count=count+1 end end
    assert(count>0,'No supported route mode')
  end
  if item.requiresDeath~=nil then assert(type(item.requiresDeath)=='boolean','requiresDeath must be a boolean') end
  if item.branch then assert(type(item.branch)=='string' and string.len(item.branch)>0 and (item.mode or item.modes),'Branch requires explicit mode') end
end
function G.ModeAllowed(item,mode)
  mode=mode or G.Mode()
  if mode=='hardcore' and (item.requiresDeath or deathActions[item.action]) then return false end
  if item.mode and item.mode~=mode then return false end
  if item.modes and not item.modes[mode] then return false end
  return true
end
function G.Chat(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffdfbd72OctoGuide:|r '..s) end end
function G.RegisterGuide(meta,steps)
  assert(type(meta)=='table' and type(meta.id)=='string' and meta.faction=='Horde','Invalid Horde guide')
  assert(type(steps)=='table' and table.getn(steps)>0,'Empty guide')
  assert(not G.guides[meta.id],'Duplicate guide')
  validateModes(meta)
  local identities={}
  for i,s in ipairs(steps) do
    s.id=s.id or tostring(i)
    assert(not identities[s.id],'Duplicate step ID');identities[s.id]=true
    assert(type(s.text)=='string' and type(s.action)=='string' and actions[s.action],'Unknown or invalid action')
    validateModes(s)
    if s.manual~=nil then assert(type(s.manual)=='boolean','manual must be a boolean') end
    if s.xpFraction~=nil then assert(s.action=='level' and type(s.xpFraction)=='number' and s.xpFraction>=0 and s.xpFraction<1,'Invalid experience fraction') end
    if s.requiresDeath or deathActions[s.action] then assert(s.id and string.len(tostring(s.id))>0,'Death step requires a stable ID') end
    if s.questID then assert(type(s.questID)=='number' and s.questID>0 and s.questID==math.floor(s.questID),'Invalid quest ID') end
    if s.objective then assert(type(s.objective)=='number' and s.objective>=1 and s.objective==math.floor(s.objective),'Invalid objective') end
    if s.x or s.y then assert(type(s.x)=='number' and type(s.y)=='number' and s.x>=0 and s.x<=1 and s.y>=0 and s.y<=1 and type(s.zone)=='number','Invalid waypoint') end
  end
  meta.steps=steps;G.guides[meta.id]=meta;table.insert(G.order,meta.id)
end
function G.Allowed(step)
  local function allowed(values,value)
    if not values then return true end
    if type(values)=='string' then return values==value end
    if values[value] then return true end
    for _,v in ipairs(values) do if v==value then return true end end
    return false
  end
  return G.ModeAllowed(step) and allowed(step.classes,G.player.class) and allowed(step.races,G.player.race)
end
function G.Key(step)
  local key=G.state.guide.id..':'..tostring(step.id)
  if step.mode or step.branch or step.requiresDeath or deathActions[step.action] or (step.modes and not (step.modes.normal and step.modes.hardcore)) then key=key..':mode:'..G.Mode() end
  return key
end
function G.Playable(guide)
  if not guide or not G.Allowed(guide) then return false end
  for _,s in ipairs(guide.steps) do if G.Allowed(s) then return true end end
  return false
end
function G.Current()
  if not G.state then return nil end
  for i=G.state.startIndex or 1,table.getn(G.state.steps) do local s=G.state.steps[i];if not G.db.progress[G.Key(s)] then G.state.index=i;return s end end
  G.state.index=nil;return nil
end
function G.Select(id,reason)
  local guide=G.guides[id];if not guide then return false,'Unknown guide' end
  if G.player.faction~='Horde' then return false,'Only Horde guides are included' end
  if not G.Playable(guide) then return false,'Guide unavailable for this character and mode' end
  local steps={}
  for i,s in ipairs(guide.steps) do
    if G.Allowed(s) then
      s.id=s.id or tostring(i)
      assert(type(s.text)=='string' and type(s.action)=='string','Invalid step')
      if s.questID then assert(s.questID>0 and s.questID==math.floor(s.questID),'Invalid quest ID') end
      table.insert(steps,s)
    end
  end
  if table.getn(steps)==0 then return false,'No steps for this character' end
  local startIndex=1
  local placement=G.db.placements and G.db.placements[id]
  if placement then
    local matched=false
    for i,s in ipairs(steps) do if s.id==placement.stepID then startIndex=i;matched=true;break end end
    if not matched then
      local original,rawIndex
      for i,s in ipairs(guide.steps) do if s.id==placement.stepID then original,rawIndex=s,i;break end end
      if original and original.branch then for i,s in ipairs(steps) do if s.branch==original.branch then startIndex=i;matched=true;break end end end
      if original and not matched then
        local later={};for i=rawIndex,table.getn(guide.steps) do later[guide.steps[i].id]=true end
        for i,s in ipairs(steps) do if later[s.id] then startIndex=i;matched=true;break end end
        if not matched then startIndex=table.getn(steps)+1 end
      end
    end
  end
  G.state={guide=guide,steps=steps,startIndex=startIndex};G.db.guide=id;G.gatherTarget=nil
  G.pauseAuto=reason=='restore' and G.db.reviewGuide==id or false
  if reason~='restore' then G.db.reviewGuide=nil end
  if reason~='automatic' and reason~='restore' then G.autoplacePending=false;G.placementMessage=nil end
  G.Current();G.Sync();if G.Render then G.Render() end;return true
end
function G.SetMode(mode)
  if mode~='normal' and mode~='hardcore' then return false,'Choose normal or hardcore' end
  if not G.db then return false,'Wait for character login' end
  local old=G.Mode();G.db.mode=mode
  if old~=mode then
    G.gatherTarget=nil;G.pauseAuto=false;G.db.reviewGuide=nil
    local id=G.state and G.state.guide.id
    if not id or not G.Playable(G.guides[id]) then id=G.DefaultGuide() end
    if id then G.Select(id,'restore') else G.state=nil;G.db.guide=nil;if G.Render then G.Render() end end
  end
  if G.RenderMenu and G.menu then G.RenderMenu() end
  if G.Render then G.Render() end
  return true
end
function G.Mark(reason)
  local s=G.Current();if not s then return end
  G.autoplacePending=false;G.placementMessage=nil
  G.db.progress[G.Key(s)]=reason or 'manual';G.pauseAuto=false;G.db.reviewGuide=nil;G.Current()
  if G.Render then G.Render() end
end
function G.NextStage()
  if not G.state then return false end
  local nextID=G.state.guide.nextGuide
  if type(nextID)=='table' then nextID=nextID[G.Mode()] end
  if nextID and not G.Playable(G.guides[nextID]) then nextID=nil end
  if not nextID then
    local level=G.state.guide.endLevel or 60;local bestScore
    for _,id in ipairs(G.order) do
      local g=G.guides[id]
      if id~=G.state.guide.id and G.Playable(g) and (g.startLevel or 1)>=level then
        local score=g.startLevel or 1;if not bestScore or score<bestScore then nextID,bestScore=id,score end
      end
    end
  end
  if nextID then return G.Select(nextID) end
  G.Chat('No next level range. Choose a route from Guides.');return false
end
function G.Advance()
  if G.Current() then G.Mark('manual');G.Sync();G.Render() else G.NextStage() end
end
function G.Back()
  if not G.state then return end
  local i=(G.state.index or table.getn(G.state.steps)+1)-1
  if i<1 then return end
  G.autoplacePending=false;G.placementMessage=nil
  if i<(G.state.startIndex or 1) then G.state.startIndex=i;G.db.placements=G.db.placements or {};G.db.placements[G.state.guide.id]={stepID=G.state.steps[i].id,reason='manual review'} end
  G.db.progress[G.Key(G.state.steps[i])]=nil;G.pauseAuto=true;G.db.reviewGuide=G.state.guide.id;G.Current();G.Render()
end
function G.QuestIndex(id)
  if type(id)~='number' or id<=0 then return nil end
  if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID)=='function' then
    local ok,index=pcall(C_QuestLog.GetLogIndexForQuestID,id)
    if ok and type(index)=='number' and index>0 then return index end
  end
  -- Older ClassicAPI versions expose only the index-to-ID direction.
  -- Never guess by title: separate quests in a chain can share a name.
  local readID=C_QuestLog and C_QuestLog.GetQuestIDForLogIndex
  if type(readID)~='function' then readID=GetQuestIDFromLogIndex end
  if type(readID)~='function' or type(GetNumQuestLogEntries)~='function' then return nil end
  local ok,count=pcall(GetNumQuestLogEntries)
  if not ok or type(count)~='number' then return nil end
  for index=1,count do
    local valid,questID=pcall(readID,index)
    if valid and questID==id then return index end
  end
end
function G.Objectives(step)
  local index=step.questID and G.QuestIndex(step.questID);local list={}
  if not index then return list end
  local count=GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0
  for i=1,count do
    local text,kind,finished=GetQuestLogLeaderBoard(i,index);text=text or ''
    local name,current,required=text,nil,nil
    local parseText=string.gsub(text,'\239\188\154',':')
    local _,_,label,have,need=string.find(parseText,'^(.*):%s*(%d[%d,]*)%s*/%s*(%d[%d,]*)%s*$')
    if have and need then
      name=string.gsub(label,'^%s*(.-)%s*$','%1')
      local haveNumber=string.gsub(have,',','');local needNumber=string.gsub(need,',','')
      current=tonumber(haveNumber);required=tonumber(needNumber)
    end
    local done=finished==1 or finished==true or (current and required and current>=required) or false
    local objectiveID,objectiveKind
    if type(GetQuestLogLeaderBoardID)=='function' then
      local ok,id,kindID=pcall(GetQuestLogLeaderBoardID,i,index)
      if ok then objectiveID=id;objectiveKind=kindID end
    end
    table.insert(list,{text=text,name=name,current=current,required=required,done=done and true or false,index=i,id=objectiveID,kind=kind or objectiveKind})
  end
  return list
end
function G.LocalGoalsDone(s)
  if not s.localGoals or table.getn(s.localGoals)==0 then return false end
  local objectives=G.Objectives(s)
  for _,goal in ipairs(s.localGoals) do
    local found=false
    for _,o in ipairs(objectives) do if o.id==goal.id and o.kind==goal.kind then found=o.done;break end end
    if not found then return false end
  end
  return true
end
function G.Satisfied(s)
  if s.minlevel and (UnitLevel('player') or 0)<s.minlevel and s.action~='level' then return false end
  if s.questID and G.db.completedQuests[s.questID] and (s.action=='accept' or s.action=='complete' or s.action=='objective' or s.action=='turnin') then return true end
  if s.manual then
    if s.questID and (s.action=='objective' or s.action=='complete') then
      if G.LocalGoalsDone(s) then return true end
      if s.objective then for _,o in ipairs(G.Objectives(s)) do if o.index==s.objective and o.done then return true end end end
      local qi=G.QuestIndex(s.questID)
      if qi then local title,level,tag,header,collapsed,complete=GetQuestLogTitle(qi);if complete==1 or complete==true then return true end end
      return false
    end
    if s.questID and s.action=='complete' then
      local qi=G.QuestIndex(s.questID)
      if qi then local title,level,tag,header,collapsed,complete=GetQuestLogTitle(qi);if complete==1 or complete==true then return true end end
    end
    return false
  end
  if s.action=='level' then
    local actual,target=UnitLevel('player') or 0,s.level or s.minlevel or 60
    if actual>target then return true end
    if actual<target then return false end
    if not s.xpFraction or s.xpFraction==0 then return true end
    if not UnitXP or not UnitXPMax then return false end
    local ok,xp,max=pcall(function() return UnitXP('player'),UnitXPMax('player') end)
    return ok and type(xp)=='number' and type(max)=='number' and max>0 and xp/max>=s.xpFraction
  end
  local index=s.questID and G.QuestIndex(s.questID)
  if s.action=='accept' then return index~=nil end
  if (s.action=='complete' or s.action=='objective') and index then
    if s.objective then for _,o in ipairs(G.Objectives(s)) do if o.index==s.objective then return o.done end end;return false end
    local title,level,tag,header,collapsed,complete=GetQuestLogTitle(index)
    return complete==1 or complete==true
  end
  return false
end
function G.Sync()
  if not G.state or G.pauseAuto then return end
  local count=0
  while count<100 do local s=G.Current();if not s or not G.Satisfied(s) then break end;G.db.progress[G.Key(s)]='observed';count=count+1 end
  G.Current()
end
function G.DefaultGuide()
  local level=UnitLevel('player') or 1;local best,bestScore
  for _,id in ipairs(G.order) do
    local g=G.guides[id]
    local compatible=G.Playable(g)
    if compatible then
      local lo,hi=g.startLevel or 1,g.endLevel or 60
      local score=math.abs(level-lo)+1000
      if level>=lo and level<hi then score=math.abs(level-lo) end
      if not best or score<bestScore then best,bestScore=id,score end
    end
  end
  return best
end
function G.BindCharacter()
  local name=UnitName and UnitName('player')
  local realm=GetRealmName and GetRealmName()
  if not name or name=='' or not realm or realm=='' then return end
  local owner=realm..':'..name
  if G.db.characterOwner and G.db.characterOwner~=owner then
    G.db.characterArchives=G.db.characterArchives or {}
    G.db.characterArchives[G.db.characterOwner]={progress=G.db.progress,completedQuests=G.db.completedQuests,placements=G.db.placements,guide=G.db.guide}
    local saved=G.db.characterArchives[owner] or {}
    G.db.progress=saved.progress or {};G.db.completedQuests=saved.completedQuests or {}
    G.db.placements=saved.placements;G.db.guide=saved.guide;G.db.reviewGuide=nil;G.db.historySource=nil
  end
  G.db.characterOwner=owner
  if G.db.placementVersion~=2 then
    -- Discard old automatic cursors, retain manual progress and a backup for review.
    G.db.previousPlacements=G.db.placements;G.db.placements=nil;G.db.placementVersion=2
  end
end
function G.Init()
  if G.ready then return end
  local cname,class=UnitClass('player');local rname,race=UnitRace('player')
  G.player={class=class or cname,race=race or rname,faction=UnitFactionGroup('player')}
  OctoGuideDB=OctoGuideDB or {};G.db=OctoGuideDB;G.db.progress=G.db.progress or {};G.db.completedQuests=G.db.completedQuests or {};G.db.view=G.db.view or 'minimal'
  G.BindCharacter()
  -- Older common-step keys remain unchanged. Mode-only keys are never migrated:
  -- a skip made before modes existed must not silently complete an alternative.
  if G.db.mode~='normal' and G.db.mode~='hardcore' then G.db.mode='hardcore' end
  G.BuildUI();G.ready=true
  if G.InitProgress then G.InitProgress() end
  if G.BuildMaps then G.BuildMaps() end
  local id=G.db.guide;local savedPlayable=G.Playable(G.guides[id]);if not savedPlayable then id=G.DefaultGuide() end
  if G.RefreshHistory then G.RefreshHistory(false) end
  if id then
    if not savedPlayable and G.AutoPlace then G.AutoPlace(true);G.initialQuestSyncPending=true else local ok,why=G.Select(id,'restore');if not ok then G.Chat(why) end end
  end
  if G.RequestHistory then G.RequestHistory() end
  if G.db.hidden then G.frame:Hide() else G.frame:Show() end
  G.Chat('Loaded. /octoguide opens the guide; /octoguide help lists commands.')
end
function G.Event(ev,a,b)
  if ev=='PLAYER_ENTERING_WORLD' then G.Init();return end
  if not G.ready then return end
  if ev=='QUEST_TURNED_IN' and type(a)=='number' and a>0 then
    local current=G.Current()
    if current and current.questID==a then G.pauseAuto=false;G.db.reviewGuide=nil end
    if G.ConfirmQuestTurnedIn then G.ConfirmQuestTurnedIn(a) else G.db.completedQuests[a]=true end
  end
  if ev=='QUEST_QUERY_COMPLETE' and G.RefreshHistory then G.RefreshHistory(true);if G.autoplacePending and G.AutoPlace then G.AutoPlace(true) end;G.Sync();G.Render();return end
  if ev=='QUEST_LOG_UPDATE' and G.initialQuestSyncPending then G.initialQuestSyncPending=false;if G.autoplacePending and G.AutoPlace then G.AutoPlace(true) end end
  -- QUEST_REMOVED and QUEST_FINISHED deliberately do not prove a turn-in.
  if ev=='BAG_UPDATE' or ev=='QUEST_LOG_UPDATE' then G.refreshRemaining=1.2;G.refreshDelay=.08 end
  if ev=='BAG_UPDATE' or ev=='QUEST_LOG_UPDATE' or ev=='QUEST_ACCEPTED' or ev=='QUEST_TURNED_IN' or ev=='PLAYER_LEVEL_UP' then
    G.Sync()
    if ev=='QUEST_TURNED_IN' and not G.Current() and G.state and G.state.guide.nextGuide and G.Playable(G.guides[G.state.guide.nextGuide]) then G.NextStage() end
    G.Render()
  end
end
