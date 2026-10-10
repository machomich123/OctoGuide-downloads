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
function G.Slash(msg)
  local cmd=string.lower(msg or '')
  if not G.ready then G.Chat('Wait for character login.');return end
  if cmd=='normal' or cmd=='hardcore' then G.SetMode(cmd);G.Chat('Route mode: '..(G.Mode()=='hardcore' and 'Hardcore' or 'Normal')..'.')
  elseif cmd=='full' or cmd=='minimal' then G.db.view=cmd;G.Render()
  elseif cmd=='guides' then G.ToggleMenu()
  elseif cmd=='done' then G.Advance()
  elseif cmd=='next' then G.NextStage()
  elseif cmd=='skip' then G.Mark('skipped');G.Sync();G.Render()
  elseif cmd=='back' then G.Back()
  elseif cmd=='sync' then G.AutoPlace(false)
  elseif cmd=='route' then G.gatherTarget=nil;G.Render()
  elseif cmd=='mining' or cmd=='herbalism' then local ok,why=G.Gather(cmd=='mining' and 'ore' or 'herb');if not ok then G.Chat(why) end
  elseif cmd=='help' then G.Chat('/octoguide [normal | hardcore | sync | guides | minimal | full | done | next | skip | back | mining | herbalism | route]. Sync finds a starting point from your character state. The title button changes route mode. Drag the window to move it.')
  else G.db.hidden=false;G.frame:Show();G.Render() end
end
SLASH_OCTOGUIDE1='/octoguide';SLASH_OCTOGUIDE2='/oguide';SlashCmdList['OCTOGUIDE']=G.Slash
local events=CreateFrame('Frame');G.events=events
for _,ev in ipairs({'PLAYER_ENTERING_WORLD','QUEST_LOG_UPDATE','QUEST_ACCEPTED','QUEST_TURNED_IN','PLAYER_LEVEL_UP','BAG_UPDATE'}) do pcall(function() events:RegisterEvent(ev) end) end
if G.InitProgress then G.InitProgress() end
events:SetScript('OnEvent',function() G.Event(event,arg1,arg2) end)
events:SetScript('OnUpdate',function()
  if not G.ready then return end
  G.UpdateArrow(arg1 or .016)
  if G.refreshRemaining and G.refreshRemaining>0 then
    G.refreshRemaining=G.refreshRemaining-(arg1 or 0);G.refreshDelay=(G.refreshDelay or 0)-(arg1 or 0)
    if G.refreshDelay<=0 and not G.resizing then G.refreshDelay=.2;G.Sync();G.Render() end
  end
  G.elapsed=G.elapsed+(arg1 or 0);if G.elapsed<.25 then return end;G.elapsed=0
  if G.gatherTarget and OctoGather then local n=OctoGather.byKey[G.gatherTarget.key];if not n or not OctoGather.MapVisible(n) then G.gatherTarget=nil;G.Render() end end
end)
