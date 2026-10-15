-- Route concurrency, personal class tasks and level-based navigation, Lua 5.0.
local G=OctoGuide
local baseRegister=G.RegisterGuide
function G.RegisterGuide(meta,steps)
  meta.routeFamily=meta.routeFamily or 'baseline'
  local block=0;local page
  for _,s in ipairs(steps) do
    s.sourceGuide=meta.id
    if s.page~=page or block==0 then block=block+1;page=s.page end
    s.sourceBlock=s.sourceBlock or block
  end
  baseRegister(meta,steps)
  if meta.routeFamily=='rxp' then G.hasFamilyRoutes=true end
end
function G.RouteSource()
  return G.hasFamilyRoutes and 'rxp' or 'baseline'
end
function G.PartyMode()
  local setting=G.db and G.db.partyMode or 'auto'
  if setting=='solo' or setting=='group' then return setting end
  local n=GetNumPartyMembers and GetNumPartyMembers() or 0
  local raid=GetNumRaidMembers and GetNumRaidMembers() or 0
  return (n>0 or raid>0) and 'group' or 'solo'
end
function G.SetPartyMode(mode)
  if mode~='auto' and mode~='solo' and mode~='group' then return false end
  G.db.partyMode=mode
  if G.state then G.Select(G.state.guide.id,'restore') end
  return true
end
function G.PathTarget(s)
  if not s or not s.path or not OctoGuideNavigation then return nil end
  G.pathCursors=G.pathCursors or {};local key=s.page or s.id
  local cursor=G.pathCursors[key] or 1
  while cursor<=table.getn(s.path) do
    local p=s.path[cursor]
    if G.Allowed(p) then
      local result=OctoGuideNavigation.ReadWaypoint(p)
      if not result or not result.yards or result.yards>math.max(10,p.radius or 25) then G.pathCursors[key]=cursor;return p end
    end
    cursor=cursor+1
  end
  G.pathCursors[key]=cursor;return nil
end
local baseAllowed=G.Allowed
function G.Allowed(s)
  if not baseAllowed(s) then return false end
  if s.profiles then
    local wanted=G.player.race..':'..G.player.class;local found=false
    for _,p in ipairs(s.profiles) do if p==wanted then found=true;break end end
    if not found then return false end
  end
  if s.locations then
    local p=s.locations[G.player.race..':'..G.player.class]
    if p then s.zone=p.zone;s.x=p.x;s.y=p.y else s.zone=nil;s.x=nil;s.y=nil end
  end
  if s.soloOnly and G.PartyMode()~='solo' then return false end
  if s.groupOnly and G.PartyMode()~='group' then return false end
  return true
end
local basePlayable=G.Playable
function G.Playable(g)
  if g and g.routeFamily and g.routeFamily~=G.RouteSource() then return false end
  return basePlayable(g)
end
function G.SetRouteSource(source)
  if source~='baseline' and source~='rxp' then return false end
  if source=='rxp' and not G.hasFamilyRoutes then G.Chat('Install the private family route pack first.');return false end
  G.db.routeSource=source;local id=G.DefaultGuide()
  if id then G.Select(id,'restore') end
  if G.menu then G.RenderMenu() end
  return true
end
-- A saved cursor is not proof that independent earlier quests were accepted.
-- Reconcile the whole preceding pickup sequence, including abandoned quests.
function G.MissingPickup(index)
  if not G.state or G.state.guide.routeFamily~='rxp' or G.pauseAuto then return nil end
  local lookup=C_QuestLog and (type(C_QuestLog.GetLogIndexForQuestID)=='function' or type(C_QuestLog.GetQuestIDForLogIndex)=='function')
  if not lookup and type(GetQuestIDFromLogIndex)~='function' then return nil end
  for i=G.state.manualStart and (G.state.startIndex or 1) or 1,index-1 do
    local a=G.state.steps[i]
    if a.action=='accept' and a.questID and not G.QuestIndex(a.questID) and not G.db.completedQuests[a.questID] then
      local marked=G.db.progress[G.Key(a)]
      local completed=false
      if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function' then
        local ok,done=pcall(C_QuestLog.IsQuestFlaggedCompleted,a.questID);completed=ok and done==true
      end
      -- Explicit Done/Skip remains a user decision; observed acceptance alone
      -- never proves a quest is still in the log or was turned in.
      if not completed and marked~='manual' and marked~='skipped' and G.SourceEligible(a) then return i end
    end
  end
end
local baseCurrent=G.Current
-- A saved cursor or old observed flag cannot discard an active unfinished quest.
-- Re-evaluate earlier authored work using live quest evidence before moving on.
function G.PendingQuestStep(index)
 if not G.state or G.pauseAuto or type(GetQuestLogTitle)~='function' then return nil end
 local first=G.state.manualStart and (G.state.startIndex or 1) or 1
 local live={}
 for i=first,index-1 do
  local s=G.state.steps[i]
  local mark=G.db.progress[G.Key(s)]
  if s.questID and (s.action=='objective' or s.action=='complete' or s.action=='turnin') and not s.background and not s.informational and mark~='manual' and mark~='skipped' and not G.db.completedQuests[s.questID] then
   if live[s.questID]==nil then
    local qi=G.QuestIndex(s.questID);live[s.questID]=false
    if qi then local _,_,_,_,_,done=GetQuestLogTitle(qi);live[s.questID]={ready=done==true or done==1} end
   end
   local q=live[s.questID]
   if q and G.SourceEligible(s) and ((q.ready or s.requiredForQuest) and s.action=='turnin' or not q.ready and (s.action=='objective' or s.action=='complete')) and not G.Satisfied(s) then return i end
  end
 end
end
function G.Current()
  if not G.state then return nil end
  if G.state.reviewIndex then G.state.index=G.state.reviewIndex;return G.state.steps[G.state.reviewIndex] end
  for i=G.state.startIndex or 1,table.getn(G.state.steps) do
    local s=G.state.steps[i]
    if not s.background and not s.informational and not (G.FoldedTravel and G.FoldedTravel(s)) and not (G.IsOptionalGrind and G.IsOptionalGrind(s)) and not G.db.progress[G.Key(s)] then
      local pickup=G.MissingPickup and G.MissingPickup(i)
      local pending=G.PendingQuestStep(i)
      if pending and (not pickup or pending<pickup) then pickup=pending end
      if pickup then
        G.state.startIndex=math.min(G.state.startIndex or 1,pickup)
        G.state.index=pickup
        G.db.placements=G.db.placements or {}
        G.db.placements[G.state.guide.id]={stepID=G.state.steps[pickup].id,reason=pending==pickup and 'unfinished active quest' or 'missing quest pickup'}
        G.db.progress[G.Key(G.state.steps[pickup])]=nil
        return G.state.steps[pickup]
      end
      -- Finish pickups explicitly grouped with this work before starting it.
      -- Never pull in later blocks or cross a turn-in in the same block.
      if (s.action=='complete' or s.action=='objective') and G.SourceEligible(s) then
       for j=i+1,table.getn(G.state.steps) do
        local a=G.state.steps[j]
        if a.sourceBlock~=s.sourceBlock or a.action=='turnin' then break end
        local lookup=(C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID)=='function') or type(GetQuestIDFromLogIndex)=='function'
        if lookup and a.action=='accept' and a.questID and not G.db.progress[G.Key(a)] and not G.Satisfied(a) and G.SourceEligible(a) and (not a.minlevel or UnitLevel('player')>=a.minlevel) then
         G.state.index=j;return a
        end
       end
      end
      G.state.index=i;return s
    end
  end
  local pending=G.PendingQuestStep(table.getn(G.state.steps)+1)
  if pending then
    G.state.startIndex=math.min(G.state.startIndex or 1,pending);G.state.index=pending
    G.db.progress[G.Key(G.state.steps[pending])]=nil
    G.db.placements=G.db.placements or {};G.db.placements[G.state.guide.id]={stepID=G.state.steps[pending].id,reason='unfinished active quest'}
    return G.state.steps[pending]
  end
  G.state.index=nil;return nil
end
function G.Concurrent(s)
  local result={};if not s or not G.state or not s.sourceBlock then return result end
  local seen={};if s.questID then seen[s.questID]=true end
  for _,a in ipairs(G.state.steps) do
    local nearby=true
    if a.optionalExtra then nearby=a.zone and a.zone==s.zone and a.x and a.y and s.x and s.y and ((a.x-s.x)^2+(a.y-s.y)^2<=.075*.075) end
    if nearby and a.background and a.sourceBlock<s.sourceBlock and a.parallelUntil and s.sourceBlock<=a.parallelUntil and G.Allowed(a) and not G.Satisfied(a) and not G.db.progress[G.Key(a)] then
      -- Missing prerequisites are not replaced by an assumption that work is done.
      if not a.questID or (G.QuestIndex(a.questID) and not seen[a.questID]) then table.insert(result,a);if a.questID then seen[a.questID]=true end end
    end
  end
  -- The quest log can differ from the authored sequence. Surface nearby active
  -- work without moving acceptance, turn-ins or prerequisites in the route.
  if s.action=='complete' or s.action=='objective' then
    for _,a in ipairs(G.state.steps) do
      if a.questID and not seen[a.questID] and (a.action=='complete' or a.action=='objective') and G.Allowed(a) and G.QuestIndex(a.questID) and not G.Satisfied(a) and a.zone and a.zone==s.zone and a.x and a.y and s.x and s.y then
        local dx,dy=a.x-s.x,a.y-s.y
        if dx*dx+dy*dy<=.075*.075 then table.insert(result,a);seen[a.questID]=true end
      end
    end
  end
  return result
end
local function history(id)
  if G.db and G.db.completedQuests[id] then return true end
  if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function' then
    local ok,done=pcall(C_QuestLog.IsQuestFlaggedCompleted,id);if ok and done==true then return true end
  end
  return false
end
function G.SourceChecks(s)
  local guide=s.sourceGuide and G.guides[s.sourceGuide]
  return guide and guide.blockChecks and guide.blockChecks[s.sourceBlock] or {}
end
function G.SourceNotes(s)
  local guide=s.sourceGuide and G.guides[s.sourceGuide];local result={}
  for _,n in ipairs(guide and guide.blockNotes and guide.blockNotes[s.sourceBlock] or {}) do
    if G.Allowed(n) then table.insert(result,n.text) end
  end
  return result
end
local function questComplete(id)
  if history(id) then return true end
  local qi=G.QuestIndex(id)
  if qi and GetQuestLogTitle then local _,_,_,_,_,done=GetQuestLogTitle(qi);return done==true or done==1 end
  return false
end
local function reachedXP(level,amount)
  local actual=UnitLevel('player') or 0;local target=level
  if amount<0 then target=level-1 end
  if actual~=target then return actual>target end
  if amount==0 then return true end
  if not UnitXP or not UnitXPMax then return nil end
  local xp,max=UnitXP('player'),UnitXPMax('player')
  if not xp or not max or max<=0 then return nil end
  local required=amount<0 and max+amount or amount<1 and amount*max or amount
  return xp>=required
end
-- False means a source conditional explicitly excludes this action now.
-- Unknown comparison checks stay visible as instructions; they never manufacture
-- completion of an actual quest.
function G.SourceEligible(s)
  if s.requiredForQuest and (G.QuestIndex(s.requiredForQuest) or history(s.requiredForQuest)) then return false end
  for _,c in ipairs(G.SourceChecks(s)) do
    if not c.profiles or G.Allowed(c) then
      local any=false
      if c.ids then
        for _,id in ipairs(c.ids) do
          if c.kind=='isOnQuest' or c.kind=='isNotOnQuest' then any=any or G.QuestIndex(id)~=nil
          elseif c.kind=='isQuestComplete' or c.kind=='isQuestNotComplete' then any=any or questComplete(id)
          elseif c.kind=='isQuestAvailable' then any=any or not history(id)
          else any=any or history(id) end
        end
        if c.kind=='isNotOnQuest' or c.kind=='isQuestNotComplete' then any=not any end
        if not any then return false end
      elseif c.kind=='money' and GetMoney and c.value and not string.find(c.value,',1') then
        local _,_,op,amount=string.find(c.value,'^([<>])([%d%.]+)')
        amount=tonumber(amount)
        if amount then local money=GetMoney();if (op=='>' and money>=amount*10000) or (op=='<' and money<amount*10000) then return false end end
      elseif c.kind=='itemcount' and GetItemCount and c.value then
        local _,_,id,op,eq,n=string.find(c.value,'^(%d+),([<>]?)(=?)(%d+)')
        id=tonumber(id);n=tonumber(n)
        if id and n then
          local count=GetItemCount(id) or 0
          local eligible=(op=='<' and (count<n or eq=='=' and count==n)) or (op=='>' and (count>n or eq=='=' and count==n)) or (op=='' and count>=n)
          if not eligible then return false end
        end
      elseif c.kind=='xp' and c.value then
        local _,_,reverse,level,amount=string.find(c.value,'^(<?)(%d+)([%+%.%-]?[%d%.]*)')
        level=tonumber(level);amount=tonumber(amount) or 0
        if level then local reached=reachedXP(level,amount);if reached~=nil and ((reverse=='<' and not reached) or (reverse~='<' and reached)) then return false end end
      end
    end
  end
  return true
end
local baseSatisfied=G.Satisfied
function G.Satisfied(s)
  if s.startsQuestID and (G.QuestIndex(s.startsQuestID) or history(s.startsQuestID)) then return true end
  if G.GoalItemCarried and (s.goalItemID or (s.action=='collect' or s.action=='buy') and s.itemID and s.itemCount) and G.GoalItemCarried(s) then return true end
  if s.sourceBlock and not G.SourceEligible(s) then return true end
  if s.goalQuestID and questComplete(s.goalQuestID) then return true end
  if s.action=='level' and s.levelXP then
    local reached=reachedXP(s.level,s.levelXP)
    return reached~=nil and ((s.xpReverse and not reached) or (not s.xpReverse and reached))
  end
  if s.action=='collect' and s.itemID and s.itemCount and GetItemCount then
    local ok,count=pcall(GetItemCount,s.itemID);if ok and type(count)=='number' and count>=s.itemCount then return true end
  end
  if s.action=='train' then
    if G.TrainingSatisfied then return G.TrainingSatisfied(s) end
    if s.spellID and IsSpellKnown then local ok,known=pcall(IsSpellKnown,s.spellID);if ok and (known==true or known==1) then return true end end
  end
  return baseSatisfied(s)
end
function G.DisplayObjectives(s)
  local list=G.Objectives(s);local seen={}
  if s and s.questID then seen[s.questID]=true end
  for _,a in ipairs(G.Concurrent(s)) do
    if a.questID and not seen[a.questID] then
      seen[a.questID]=true
      local title=a.text
      local qi=G.QuestIndex(a.questID);if qi and GetQuestLogTitle then title=GetQuestLogTitle(qi) or title end
      local goals=G.Objectives(a)
      for _,o in ipairs(goals) do
        local copy={};for k,v in pairs(o) do copy[k]=v end
        copy.name='Also: '..title..' - '..(o.name or o.text or '')
        table.insert(list,copy)
      end
    end
  end
  return list
end
function G.RouteLabel(g)
  if not g then return 'Horde guide' end
  if string.find(g.title or '','^Level ') then return g.title end
  return 'Level '..(g.title or tostring(g.startLevel or 1)..'-'..tostring(g.endLevel or 60))
end
function G.LevelGuides(level)
  local result={}
  for _,id in ipairs(G.order) do
    local g=G.guides[id]
    if G.Playable(g) and (not level or (level>=(g.startLevel or 1) and level<=math.max(g.startLevel or 1,g.endLevel or 60))) then table.insert(result,id) end
  end
  table.sort(result,function(a,b)
    local x,y=G.guides[a],G.guides[b]
    if x.startLevel==y.startLevel then return x.title<y.title end
    return (x.startLevel or 1)<(y.startLevel or 1)
  end)
  return result
end
local baseNext=G.NextStage
function G.NextStage()
  local authored
  if G.state then
    for _,id in ipairs(G.state.guide.nextGuides or {}) do if G.Playable(G.guides[id]) then authored=G.guides[id];break end end
    local id=G.state.guide.nextGuide;if type(id)=='table' then id=id[G.Mode()] end
    authored=authored or id and G.Playable(G.guides[id]) and G.guides[id]
  end
  local level=UnitLevel('player') or 1
  if authored and authored.endLevel and level>=authored.endLevel then
    local best
    for _,id in ipairs(G.order) do local guide=G.guides[id]
      if G.Playable(guide) and id~=G.state.guide.id and (guide.startLevel or 1)<=level and level<(guide.endLevel or 60) and (guide.startLevel or 1)>=(G.state.guide.startLevel or 1) then
        if not best or (guide.startLevel or 1)>(best.startLevel or 1) then best=guide end
      end
    end
    if best then return G.Select(best.id) end
  end
  if G.state and G.state.guide.nextGuides then
    for _,id in ipairs(G.state.guide.nextGuides) do if G.Playable(G.guides[id]) then return G.Select(id) end end
  end
  return baseNext()
end
local baseEvent=G.Event
function G.Event(ev,a,b)
  if ev=='PARTY_MEMBERS_CHANGED' and G.ready and G.db and (G.db.partyMode or 'auto')=='auto' then
    if G.state then G.Select(G.state.guide.id,'restore') end
    if G.RenderSettings and G.options then G.RenderSettings() end
    return
  end
  baseEvent(ev,a,b)
end
