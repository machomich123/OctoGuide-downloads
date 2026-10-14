-- Placement changes a resumable cursor, never pretends earlier quests are done.
local G=OctoGuide
local function validID(id) return type(id)=='number' and id>0 and id==math.floor(id) end
local function activeIndex(id)
  if G.placementIndexes then
    local found=G.placementIndexes[id]
    if found~=nil then return found or nil end
    if G.placementIndexesComplete then return nil end
    found=G.QuestIndex(id);G.placementIndexes[id]=found or false;return found
  end
  return G.QuestIndex(id)
end
function G.RefreshHistory(serverResponse)
  G.historyHints={}
  if serverResponse and G.ReadCompletedHistory then G.ReadCompletedHistory();return end
  -- pfQuest permits manual completion marks. Its cache is a placement hint only.
  -- External addon caches have no verified character ownership. Never use them to skip route steps.
  if serverResponse and type(GetQuestsCompleted)=='function' then
    local result={};local ok,data=pcall(GetQuestsCompleted,result)
    if ok then
      data=type(data)=='table' and data or result
      if type(data)=='table' then for id,done in pairs(data) do if validID(id) and (done==true or done==1) then G.db.completedQuests[id]=true end end;G.db.historySource='server' end
    end
  end
end
function G.RequestHistory()
  if G.historyRequested or type(QueryQuestsCompleted)~='function' or type(GetQuestsCompleted)~='function' then return end
  G.historyRequested=true
  if G.events then G.events:RegisterEvent('QUEST_QUERY_COMPLETE') end
  pcall(QueryQuestsCompleted)
end
local function questDone(id)
  if G.db.completedQuests[id] then return true end
  if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function' then local ok,done=pcall(C_QuestLog.IsQuestFlaggedCompleted,id);if ok and done==true then G.db.completedQuests[id]=true;return true end end
  return false
end
local function atLevel()
  local level=UnitLevel('player') or 1
  if UnitXP and UnitXPMax then local ok,xp,max=pcall(function() return UnitXP('player'),UnitXPMax('player') end);if ok and type(xp)=='number' and type(max)=='number' and max>0 then level=level+xp/max end end
  return level
end
local function recordedDone(id)
  -- Recorded history is sufficient for a suggested cursor, never for Sync's
  -- server-confirmed completion facts. Manual pfQuest marks remain reversible.
  return questDone(id)
end
local function positionPenalty(s)
  if not s.zone or not s.x or not s.y or not OctoGuideNavigation then return 0 end
  local r=OctoGuideNavigation.ReadWaypoint(s)
  if r and r.yards then return math.min(r.yards/400,8) end
  return 10
end
local function filtered(g)
  local steps={};for _,s in ipairs(g.steps) do if G.Allowed(s) then table.insert(steps,s) end end;return steps
end
local function unfinished(s)
  if s.sourceGuide and G.db.progress then
    local key=s.sourceGuide..':'..tostring(s.id)
    if s.mode or s.branch or s.requiresDeath or s.action=='death' or s.modes and not (s.modes.normal and s.modes.hardcore) then key=key..':mode:'..G.Mode() end
    local marked=G.db.progress[key]
    if marked=='manual' or marked=='skipped' then return false end
  end
  if s.questID and recordedDone(s.questID) then return false end
  return true
end
local function findQuestStart(qid,active)
  for _,id in ipairs(G.order) do local g=G.guides[id];if G.Playable(g) then
    local steps=filtered(g)
    for i,s in ipairs(steps) do
      if s.questID==qid and ((not active and s.action=='accept') or (active and (s.action=='objective' or s.action=='complete' or s.action=='turnin'))) then
        return {guide=g,steps=steps,index=i,reason='prerequisite catch-up'}
      end
    end
  end end
end
-- Find a necessary chain start without assuming an unknown prerequisite is done.
local function catchup(candidate,seen,depth)
  local step=candidate.steps[candidate.index]
  if step and not step.questID and step.page then
    for i=candidate.index+1,table.getn(candidate.steps) do
      local nextStep=candidate.steps[i];if nextStep.page~=step.page then break end
      if nextStep.questID then step=nextStep;break end
    end
  end
  if not step or not step.questID or activeIndex(step.questID) then return candidate end
  if depth>24 then return candidate end
  if step.action~='accept' and not recordedDone(step.questID) and not seen[step.questID] then
    seen[step.questID]=true
    local start=findQuestStart(step.questID,false)
    if start then return catchup(start,seen,depth+1) end
    candidate.reason='quest acceptance unknown';return candidate
  end
  for _,qid in ipairs(step.requires or {}) do
    if not recordedDone(qid) and not seen[qid] then
      seen[qid]=true
      local found=findQuestStart(qid,activeIndex(qid))
      if found then return catchup(found,seen,depth+1) end
      candidate.reason='prerequisite history unknown';return candidate
    end
  end
  return candidate
end
-- A good later waypoint is not permission to discard independent unfinished work.
local function requiredRemaining(s,guide)
  if not G.Allowed(s) or not G.SourceEligible(s) then return false end
  if s.minlevel and (UnitLevel('player') or 1)<s.minlevel then return false end
  local starter=(guide.startLevel or 1)<6
  local required=s.action=='train' or starter and s.questID and (s.action=='accept' or s.action=='objective' or s.action=='complete' or s.action=='turnin')
  if not required then return false end
  local key=guide.id..':'..tostring(s.id)
  if s.mode or s.branch or s.requiresDeath or s.modes and not (s.modes.normal and s.modes.hardcore) then key=key..':mode:'..G.Mode() end
  local marked=G.db.progress[key]
  if marked=='manual' or marked=='skipped' then return false end
  return not G.Satisfied(s)
end
local function preserveRequired(candidate,level)
  -- Starter chapters can be split into several short guides. Check the whole
  -- applicable starter sequence before a later chapter wins on level or XP.
  if level<6 then
    local earlier
    for _,guideID in ipairs(G.order) do local guide=G.guides[guideID]
      if G.Playable(guide) and (guide.startLevel or 1)<6 and (guide.startLevel or 1)<=level then
        local steps=filtered(guide)
        for i,s in ipairs(steps) do if requiredRemaining(s,guide) then
          if not earlier or (guide.startLevel or 1)<(earlier.guide.startLevel or 1) then earlier={guide=guide,steps=steps,index=i,reason='unfinished starter quest or training'} end
          break
        end end
      end
    end
    if earlier then candidate=earlier end
  end
  for i=1,candidate.index-1 do
    if requiredRemaining(candidate.steps[i],candidate.guide) then
      candidate.index=i;candidate.reason='earlier unfinished quest or training';break
    end
  end
  return candidate
end
function G.FindPlacement()
  local level=atLevel();local best,bestScore
  -- Character level chooses the chapter first. An old active quest or nearby
  -- zone may choose within that level bracket, never pull us into an old one.
  local bestGap
  for _,id in ipairs(G.order) do local g=G.guides[id];if G.Playable(g) then
    local lo,hi=g.startLevel or 1,g.endLevel or 60
    local gap=level<lo and lo-level or (level>=hi and level-hi+.01 or 0)
    if not bestGap or gap<bestGap then bestGap=gap end
  end end
  G.placementIndexes={};G.placementIndexesComplete=false
  if GetNumQuestLogEntries and C_QuestLog and type(C_QuestLog.GetQuestIDForLogIndex)=='function' then
    local ok=pcall(function()
      local count=GetNumQuestLogEntries() or 0
      for i=1,count do local qid=C_QuestLog.GetQuestIDForLogIndex(i);if validID(qid) then G.placementIndexes[qid]=i end end
    end)
    G.placementIndexesComplete=ok
  end
  for _,id in ipairs(G.order) do
    local g=G.guides[id]
    if G.Playable(g) then
      local steps=filtered(g);local lo,hi=g.startLevel or 1,g.endLevel or 60
      local gap=level<lo and lo-level or (level>=hi and level-hi+.01 or 0)
      if gap==bestGap then
      local base=gap*30+math.abs(level-lo)
      local candidate={guide=g,steps=steps,index=1,reason='level and route prerequisites'}
      -- Position may choose a source page, but preserves all actions on that page.
      local pageIndex=1;local pageScore
      for i,s in ipairs(steps) do
        if not s.page or i==1 or s.page~=steps[i-1].page then pageIndex=i end
        if g.routeFamily~='rxp' and level>=5 and s.expectedLevel and s.expectedLevel<=level and math.abs(s.expectedLevel-level)<1.5 and s.zone and s.x and s.y then
          local score=math.abs(s.expectedLevel-level)*12+positionPenalty(s)
          if not pageScore or score<pageScore then pageScore=score;candidate.index=pageIndex;candidate.reason='level, location and route prerequisites' end
        end
      end
      if not bestScore or base<bestScore then best,bestScore=candidate,base end
      for i,s in ipairs(steps) do
        local expected=s.expectedLevel or lo;local diff=math.abs(expected-level)
        local index=s.questID and activeIndex(s.questID)
        local score,reason
        if index and diff<6 then
          local title,qlevel,tag,header,collapsed,complete=GetQuestLogTitle(index)
          local done=complete==1 or complete==true
          if (done and s.action=='turnin') or (not done and (s.action=='complete' or s.action=='objective') and not G.Satisfied(s)) then
            score=-120+diff*10+positionPenalty(s);reason='active quest log'
          end
        elseif s.questID and diff<3 and (questDone(s.questID) or (G.historyHints and G.historyHints[s.questID])) and s.action=='turnin' and i<table.getn(steps) then
          score=(questDone(s.questID) and -75 or -35)+diff*10+positionPenalty(steps[i+1]);reason=questDone(s.questID) and 'confirmed quest history' or 'recorded quest history; check prerequisites'
          i=i+1
        end
        if score and (not bestScore or score<bestScore) then best,bestScore={guide=g,steps=steps,index=i,reason=reason},score end
      end
      end
    end
  end
  if best then
    best=preserveRequired(best,level)
    best=catchup(best,{},0)
    while best.index<table.getn(best.steps) and (not unfinished(best.steps[best.index]) or G.StepEvidence and G.StepEvidence(best.steps[best.index])) do best.index=best.index+1 end
  end
  G.placementIndexes=nil;G.placementIndexesComplete=nil
  return best
end
function G.AutoPlace(automatic)
  if G.player and G.player.faction=='Alliance' then return false,'Find step has no Alliance route. This guide currently includes Horde routes only.' end
  if OctoAddonHealth and not OctoAddonHealth.Check('OctoGuide',false) then return false,'Find step is unavailable: required addon components did not load. See /octocheck.' end
  if not G.ready then return false,'The guide is not initialized. Check /octocheck before finding a step.' end
  if G.player.faction~='Horde' then return false,'Find step has no route for this faction. Only Horde routes are included.' end
  G.RefreshHistory(false)
  -- Full scanning belongs to an explicit Find step request, never startup placement.
  local p=G.FindPlacement();if not p then return false,'No supported route matches this character and mode. Open Guides and check the route pack; no progress has been marked complete.' end
  G.db.placements=G.db.placements or {}
  G.db.placements[p.guide.id]={stepID=p.steps[p.index].id,reason=p.reason}
  G.db.reviewGuide=nil;G.db.reviewStep=nil;G.db.reviewPositions={}
  local ok,why=G.Select(p.guide.id,'automatic');if not ok then G.Chat(why);return false end
  G.autoplacePending=automatic==true and G.db.historySource~='server'
  G.placementMessage=G.PlacementSummary and G.PlacementSummary(p.reason) or 'Starting step: '..p.reason..'. Earlier steps remain available with Back.'
  G.Render();if not automatic then G.Chat(G.placementMessage) end
  return true
end
