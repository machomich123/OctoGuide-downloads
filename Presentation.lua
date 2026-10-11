local G=OctoGuide
function G.Present(s)
  if not s then return 'Level range complete','Choose Next to continue to the next level range.','note' end
  local value=s.text or ''
  value=string.gsub(value,'^Group quest %(use a suitable party%): ','')
  value=string.gsub(value,'^Escort quest: ','')
  value=string.gsub(value,' Complete this local part, then press Done; the whole quest may continue at later waypoints%.','')
  local title,body
  if s.action=='objective' or s.action=='complete' then
    local _,_,quest,place=string.find(value,'^Work on (.-) at (.-)%.?$')
    if quest then title=quest;body='Complete the objectives at '..string.gsub(place,'%.$','')..'.' end
  elseif s.action=='accept' then
    local _,_,quest,place=string.find(value,'^Accept (.-) from (.+)')
    if quest then title='Accept '..quest;body='Speak to '..place end
  elseif s.action=='turnin' then
    local _,_,quest,place=string.find(value,'^Turn in (.-) to (.+)')
    if quest then title='Turn in '..quest;body='Speak to '..place end
  end
  title=title or value;body=body or ''
  if title==value and (s.action=='objective' or s.action=='complete') and s.questID and G.QuestIndex and GetQuestLogTitle then
    local qi=G.QuestIndex(s.questID)
    if qi then local questTitle=GetQuestLogTitle(qi);if type(questTitle)=='string' and questTitle~='' then title=questTitle;body=value end end
  end
  if s.requiresGroup then body=body..' A suitable group is required.' end
  if s.optionalExtra then body=(s.extraHint or '')..'\nOptional OctoWoW addition. Use Skip to keep the main route.' end
  if G.SourceNotes and not s.optionalExtra then
    local seen={}
    for _,note in ipairs(G.SourceNotes(s)) do if note~='' and not seen[note] then body=body..'\n'..note;seen[note]=true end end
  end
  if s.personalClass then body='Personal '..s.personalClass..' task: each player of this class must complete their own unlock.\n'..body end
  if s.optionalSupply then title='Optional: food and drinks';body=body..'\nBuy only what you need. Skip this visit if you already have supplies.' end
  if G.PartyMode and G.PartyMode()=='group' and s.questID and (s.action=='complete' or s.action=='objective' or s.action=='collect') then body=body..'\nGroup: check each player\'s own quest progress. Item drops and class unlocks may be individual.' end
  if G.Concurrent then
    local list=G.Concurrent(s);local seen={}
    for _,a in ipairs(list) do if a.questID and not seen[a.questID] then body=body..'\nDo alongside this step: '..a.text;seen[a.questID]=true end end
  end
  if s.action=='accept' and s.minlevel and UnitLevel('player')<s.minlevel then
    title='Reach level '..s.minlevel..' before accepting this quest'
    body='This quest is not available at your current level. Finish earlier available quests or gain experience, then return.\n'..body
  end
  return title,body,s.action
end
function G.RawNavTarget()
  local s=G.gatherTarget or G.Current()
  if s and not G.gatherTarget and G.PathTarget then local p=G.PathTarget(s);if p then return p end end
  if s and s.targets and not G.gatherTarget then
    local objectives=G.Objectives(s)
    for _,p in ipairs(s.targets) do
      local complete=false
      for _,o in ipairs(objectives) do
        if (p.objective and p.objective==o.index) or (p.match and string.find(string.lower(o.text),string.lower(p.match),1,true)) then complete=o.done;break end
      end
      if not complete then return p end
    end
  end
  return s
end
function G.NavTarget()
  local s=G.RawNavTarget()
  local plan=G.Travel and G.Travel.Plan(s)
  return plan and plan.target or s
end
