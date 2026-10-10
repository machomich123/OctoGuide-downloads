-- Quest progress and server-confirmed turn-in handling for Lua 5.0 / 1.12.
local G=OctoGuide

local function validQuestID(id)
  return type(id)=='number' and id>0 and id==math.floor(id)
end

function G.ConfirmQuestTurnedIn(id)
  if not validQuestID(id) or not G.db then return false end
  G.db.completedQuests=G.db.completedQuests or {}
  G.db.completedQuests[id]=true
  return true
end

local function currentTurnIn()
  if not G.ready then return nil end
  local step=G.Current()
  if step and step.action=='turnin' and validQuestID(step.questID) then return step.questID end
end

local function questCompleteInLog(id)
  local index=G.QuestIndex(id)
  if not index or type(GetQuestLogTitle)~='function' then return false end
  local ok,title,level,tag,header,collapsed,complete=pcall(GetQuestLogTitle,index)
  return ok and (complete==1 or complete==true)
end

local function fallbackHasServerHistory(id)
  if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function' then
    local ok,done=pcall(C_QuestLog.IsQuestFlaggedCompleted,id)
    if ok and done==true then return true end
  end
  return G.db and G.db.completedQuests and G.db.completedQuests[id]==true
end

local function finishFallbackIfVerified(id)
  if not validQuestID(id) or not G.rewardRequestedID or G.rewardRequestedID~=id then return false end
  if G.QuestIndex(id) then return false end
  -- A reward click followed by removal is not enough to distinguish a rejected
  -- reward request and a later abandon. Require the server's completion history
  -- on clients without the native QUEST_TURNED_IN event.
  if fallbackHasServerHistory(id) then
    G.ConfirmQuestTurnedIn(id)
    G.rewardRequestedID=nil;G.rewardDialogQuestID=nil;G.rewardHistoryPendingID=nil
    if G.Sync then G.Sync() end
    if G.Render then G.Render() end
    return true
  end
  G.rewardHistoryPendingID=id
  if type(QueryQuestsCompleted)=='function' and type(GetQuestsCompleted)=='function' and not G.rewardHistoryQueryPending then
    G.rewardHistoryQueryPending=true
    if G.events then pcall(function() G.events:RegisterEvent('QUEST_QUERY_COMPLETE') end) end
    pcall(QueryQuestsCompleted)
  end
  return false
end

local function captureRewardDialog()
  if G.Sync then G.Sync() end
  local id=currentTurnIn()
  if id and questCompleteInLog(id) then
    G.rewardDialogQuestID=id
    G.rewardRequestedID=nil
    G.rewardHistoryPendingID=nil
  else
    G.rewardDialogQuestID=nil
  end
end

local function hookRewardCall()
  if G.rewardHooked or type(GetQuestReward)~='function' then return false end
  local original=GetQuestReward
  GetQuestReward=function(choice)
    local id=G.rewardDialogQuestID
    local result=original(choice)
    if id then G.rewardRequestedID=id end
    return result
  end
  G.rewardHooked=true
  return true
end

local function startFallback()
  if not hookRewardCall() then return false end
  local frame=CreateFrame('Frame');G.rewardFallbackFrame=frame
  local registered=0
  for _,name in ipairs({'QUEST_COMPLETE','QUEST_FINISHED','QUEST_REMOVED','QUEST_LOG_UPDATE','QUEST_QUERY_COMPLETE'}) do
    local ok=pcall(function() frame:RegisterEvent(name) end)
    if ok then registered=registered+1 end
  end
  if registered==0 then return false end
  frame:SetScript('OnEvent',function()
    if event=='QUEST_COMPLETE' then
      captureRewardDialog()
    elseif event=='QUEST_REMOVED' then
      if type(arg1)=='number' and arg1==G.rewardRequestedID then finishFallbackIfVerified(arg1) end
    elseif event=='QUEST_LOG_UPDATE' then
      if G.rewardRequestedID and not G.QuestIndex(G.rewardRequestedID) then finishFallbackIfVerified(G.rewardRequestedID) end
    elseif event=='QUEST_QUERY_COMPLETE' then
      G.rewardHistoryQueryPending=false
      if G.RefreshHistory then G.RefreshHistory(true) end
      if G.rewardHistoryPendingID and G.db and G.db.completedQuests[G.rewardHistoryPendingID] then finishFallbackIfVerified(G.rewardHistoryPendingID) end
    elseif event=='QUEST_FINISHED' then
      -- Window closure alone is deliberately not evidence of a turn-in.
      if not G.rewardRequestedID then G.rewardDialogQuestID=nil end
    end
  end)
  return true
end

function G.InitProgress()
  if G.progressInitialized then return end
  G.progressInitialized=true
  -- RegisterEvent itself is the compatibility probe. ClassicAPI documents and
  -- implements QUEST_TURNED_IN as a server-confirmed event with the questID.
  local target=G.events or CreateFrame('Frame')
  local ok=pcall(function() target:RegisterEvent('QUEST_TURNED_IN') end)
  if ok then G.turnInEventAvailable=true;return end
  G.turnInEventAvailable=false
  G.fallbackProgressAvailable=startFallback()
end
