local G=OctoGuide
-- Uses existing OctoGather records only, no world scan and no game actions.
function G.Gather(category)
  local gather=OctoGather
  if not gather or not gather.ready or not C_Map or not UnitPosition then return false,'OctoGather or navigation is unavailable' end
  local west,north,z,map=UnitPosition('player');if not west or not north then return false,'Position unavailable' end
  local skillName=category=='ore' and 'Mining' or category=='herb' and 'Herbalism' or nil
  if not skillName then return false,'Use mining or herbalism' end
  local skill
  for i=1,GetNumSkillLines() do local name,header,expanded,rank=GetSkillLineInfo(i);if name==skillName then skill=rank end end
  if not skill then return false,skillName..' is not learned' end
  local best,dist
  for _,n in pairs(gather.byKey) do
    if n.cat==category and n.skill<=skill and gather.MapVisible(n) then
      local ok,nmap,p=pcall(C_Map.GetWorldPosFromMapPos,n.zone,{x=n.x/100,y=n.y/100})
      if ok and nmap==map and p then local d=math.sqrt((p.x-north)^2+(p.y-west)^2);if not best or d<dist then best,dist=n,d end end
    end
  end
  if not best then return false,'No eligible visible resource point' end
  G.gatherTarget={zone=best.zone,x=best.x/100,y=best.y/100,text=best.name,key=best.key}
  G.Chat('Pointing to '..best.name..' (possible spawn; not guaranteed present). /octoguide route returns to quest navigation.');G.Render();return true
end
function G.HandleSlash(msg)
  local cmd=string.lower(msg or '')
  if cmd=='hide' then if G.db then G.db.hidden=true end;G.HidePanels();return end
  if G.failed then local f=G.lastFailure;G.Chat('OctoGuide '..G.version..' stopped ('..f.phase..'): '..f.message..' Update the addon and /reload.');return end
  if not G.ready then
    if OctoAddonHealth and not OctoAddonHealth.Check('OctoGuide',false) then G.Chat(OctoAddonHealth.Text and OctoAddonHealth.Text('OctoGuide') or 'Required addon components are unavailable. Use /octocheck.');return end
    G.Chat('Wait for character login.');return
  end
  if cmd=='history' then G.ReadPFQuestHistory();G.Chat('pfQuest history copied locally with source labels. Use /db journal to browse and /db query to request the server history. Manual marks are not server confirmation.')
  elseif cmd=='normal' or cmd=='hardcore' then G.SetMode(cmd);G.Chat('Route mode: '..(G.Mode()=='hardcore' and 'Hardcore' or 'Normal')..'.')
  elseif cmd=='solo' or cmd=='group' or cmd=='auto' then G.SetPartyMode(cmd);G.Chat('Party setting: '..cmd..'.')
  elseif cmd=='rxp' or cmd=='baseline' then G.SetRouteSource(cmd)
  elseif cmd=='check' then
    local lookup=(C_QuestLog and (type(C_QuestLog.GetLogIndexForQuestID)=='function' or type(C_QuestLog.GetQuestIDForLogIndex)=='function')) or type(GetQuestIDFromLogIndex)=='function'
    local history=(C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted)=='function') or (type(QueryQuestsCompleted)=='function' and type(GetQuestsCompleted)=='function')
    local navigation=type(UnitPosition)=='function' and type(GetPlayerFacing)=='function' and C_Map and type(C_Map.GetWorldPosFromMapPos)=='function'
    G.Chat('Version '..G.version..'. Quest lookup: '..(lookup and 'ready' or 'missing')..'. Completion history: '..(history and 'ready' or 'missing')..'. Position: '..(navigation and 'ready' or 'missing')..'. '..(G.hasFamilyRoutes and 'RestedXP routes loaded.' or 'RestedXP routes not installed.'))
  elseif string.find(cmd,'^level %d+$') then local _,_,n=string.find(cmd,'^level (%d+)$');G.menu.level=tonumber(n);G.menu.page=1;G.RenderMenu();G.menu:Show()
  elseif cmd=='full' or cmd=='minimal' then G.db.view=cmd;G.Render()
  elseif cmd=='guides' then G.ToggleMenu()
  elseif cmd=='professions' or cmd=='profession' then G.Professions.Toggle()
  elseif cmd=='done' then G.Advance()
  elseif cmd=='next' then G.NextStage()
  elseif cmd=='skip' then G.Mark('skipped');G.Sync();G.Render()
  elseif cmd=='back' then G.Back()
  elseif cmd=='sync' then if G.FindStep then G.FindStep(false) else G.AutoPlace(false) end
  elseif cmd=='scan' then G.Chat(G.ScanSummary and G.ScanSummary() or 'Use Find step first.')
  elseif cmd=='route' then if G.Professions then G.Professions.ClearMarker();G.Professions.ReturnToQuests() end;G.gatherTarget=nil;G.Render()
  elseif cmd=='mining' or cmd=='herbalism' then local ok,why=G.Gather(cmd=='mining' and 'ore' or 'herb');if not ok then G.Chat(why) end
  elseif cmd=='help' then G.Chat('/octoguide [professions | normal | hardcore | solo | group | auto | level N | check | sync | guides | minimal | full | done | next | skip | back | mining | herbalism | route]. Professions opens all 14 profession guides. Sync finds a starting point from your character state.')
  else G.db.hidden=false;G.frame:Show();G.Render() end
end

-- Consume only our own slash command, leaving unrelated chat drafts intact.
function G.Slash(msg)
  local boxes={}
  local function add(box) if box and type(box.GetText)=='function' and type(box.SetText)=='function' then table.insert(boxes,box) end end
  add(this);add(ChatFrameEditBox)
  if type(ChatEdit_GetActiveWindow)=='function' then add(ChatEdit_GetActiveWindow()) end
  local owned={}
  for _,box in ipairs(boxes) do
    local text=box:GetText()
    if type(text)=='string' then
      local _,_,command=string.find(string.lower(text),'^%s*(/[^%s]+)')
      if command=='/octoguide' or command=='/oguide' then table.insert(owned,box) end
    end
  end
  local ok,why=pcall(G.HandleSlash,msg)
  for _,box in ipairs(owned) do
    box:SetText('')
    if type(box.ClearFocus)=='function' then box:ClearFocus() end
    if type(box.Hide)=='function' then box:Hide() end
  end
  if not ok then error(why) end
end

SLASH_OCTOGUIDE1='/octoguide';SLASH_OCTOGUIDE2='/oguide';SlashCmdList['OCTOGUIDE']=G.Slash
local events=CreateFrame('Frame');G.events=events
for _,ev in ipairs({'PLAYER_ENTERING_WORLD','QUEST_LOG_UPDATE','QUEST_ACCEPTED','QUEST_TURNED_IN','PLAYER_LEVEL_UP','BAG_UPDATE','PARTY_MEMBERS_CHANGED','SPELLS_CHANGED','LEARNED_SPELL_IN_TAB','SKILL_LINES_CHANGED','TRAINER_SHOW','TRAINER_UPDATE','TRAINER_CLOSED','TRADE_SKILL_SHOW','TRADE_SKILL_UPDATE','CRAFT_SHOW','CRAFT_UPDATE','SPELLCAST_START','MERCHANT_SHOW','MERCHANT_UPDATE','PET_BAR_UPDATE','UNIT_PET'}) do pcall(function() events:RegisterEvent(ev) end) end
if G.InitProgress then G.InitProgress() end
events:SetScript('OnEvent',function() if G.InstallReportErrors then G.InstallReportErrors() end;if G.ReportEvent then G.ReportEvent(event) end;G.RunProtected(G.Event,'event '..tostring(event),event,arg1,arg2) end)
local function update()
  if not G.ready then return end
  if G.UpdateFindStep then G.UpdateFindStep(arg1 or .016) end
  G.UpdateArrow(arg1 or .016)
  if G.refreshRemaining and G.refreshRemaining>0 then
    G.refreshRemaining=G.refreshRemaining-(arg1 or 0);G.refreshDelay=(G.refreshDelay or 0)-(arg1 or 0)
    if G.refreshDelay<=0 and not G.resizing then G.refreshDelay=.2;G.Sync();G.Render() end
  end
  G.elapsed=G.elapsed+(arg1 or 0);if G.elapsed<.25 then return end;G.elapsed=0
  if G.gatherTarget and OctoGather then local n=OctoGather.byKey[G.gatherTarget.key];if not n or not OctoGather.MapVisible(n) then G.gatherTarget=nil;G.Render() end end
end
events:SetScript('OnUpdate',function() G.RunProtected(update,'refresh') end)
