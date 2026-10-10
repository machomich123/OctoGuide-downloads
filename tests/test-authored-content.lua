-- Real authored content, actual Lua 5.0 parser and real Core mode filtering.
local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS CONTENT '..name) end
function UnitLevel() return 60 end
function UnitClass() return 'Hunter','HUNTER' end
function UnitRace() return 'Orc','Orc' end
function UnitFactionGroup() return 'Horde' end
dofile('Core.lua');dofile('Guides.lua')
local G=OctoGuide
G.player={faction='Horde',race='Orc',class='HUNTER'}
G.db={mode='hardcore',progress={},completedQuests={}}
check('complete authored route loads through real parser and schema',function()
 assert(table.getn(G.order)>=35)
 local count=0;for _,g in pairs(G.guides) do count=count+table.getn(g.steps) end
 assert(count>3500)
end)
check('every declared chapter link resolves to registered content',function()
 for _,g in pairs(G.guides) do if g.nextGuide then assert(G.guides[g.nextGuide],g.id..' missing next chapter '..g.nextGuide) end end
end)
check('normal shortcut branches have live-travel hardcore alternatives',function()
 local count=0
 for _,g in pairs(G.guides) do
  local branches={}
  for _,s in ipairs(g.steps) do if s.branch then branches[s.branch]=branches[s.branch] or {};table.insert(branches[s.branch],s) end end
  for id,list in pairs(branches) do
   local n,h=0,0
   for _,s in ipairs(list) do if s.mode=='normal' then n=n+1 end;if s.mode=='hardcore' and not s.requiresDeath and s.action~='death' then h=h+1 end end
   local ghostQuest=false
   for _,s in ipairs(list) do if string.find(string.lower(s.text),'videre') or string.find(string.lower(s.text),'resurrect') and not string.find(string.lower(s.text),'continue to') then ghostQuest=true end end
   if not ghostQuest then assert(n==1 and h==1,g.id..':'..id..' missing death branch pair');count=count+1 end
  end
 end
 assert(count>=10)
end)
check('hardcore excludes ghost-dependent Videre and downstream Linken quest chain',function()
 local blocked={[3909]=true,[3912]=true,[3913]=true,[3914]=true,[3941]=true,[3942]=true,[3961]=true,[3962]=true,[4005]=true,[4084]=true}
 for _,race in ipairs({'Orc','Troll','Tauren','Scourge'}) do
  G.player.race=race;G.db.mode='hardcore'
  for _,id in ipairs(G.order) do if G.Playable(G.guides[id]) then assert(G.Select(id));for _,s in ipairs(G.state.steps) do assert(not s.requiresDeath and s.action~='death');assert(not blocked[s.questID]) end end end
 end
end)
check('normal death shortcut completion cannot complete hardcore alternative',function()
 G.player.race='Orc';G.db.mode='normal'
 local id,normal,hc
 for _,gid in ipairs(G.order) do if G.Playable(G.guides[gid]) then for _,s in ipairs(G.guides[gid].steps) do if s.branch and s.action=='death' then id=gid;normal=s;for _,a in ipairs(G.guides[gid].steps) do if a.branch==s.branch and a.mode=='hardcore' then hc=a end end;break end end end;if id then break end end
 assert(id and normal and hc);assert(G.Select(id));local key=G.Key(normal);G.db.progress[key]='manual';G.db.mode='hardcore';assert(G.Select(id));assert(not G.db.progress[G.Key(hc)] and G.Key(hc)~=key)
end)
check('level 58-60 chapter contains authored quest work and travel',function()
 local g=G.guides['vq-shared-22'];assert(g and g.startLevel==58)
 local quests,travel={},0
 for _,s in ipairs(g.steps) do if s.questID then quests[s.questID]=true end;if s.action=='fly' or s.action=='hearth' or s.action=='travel' then travel=travel+1 end end
 local n=0;for _ in pairs(quests) do n=n+1 end;assert(n>=60 and travel>=5)
end)
check('partial source objective waypoints never auto-complete from active quest alone',function()
 local seen=0
 C_QuestLog={GetLogIndexForQuestID=function() return 1 end}
 function GetQuestLogTitle() return 'Active quest',30,nil,false,false,nil end
 for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if s.action=='objective' and s.manual then assert(not G.Satisfied(s));seen=seen+1 end end end
 assert(seen>700);C_QuestLog=nil
end)
check('all race introductions lead to their own authored start',function()
 for _,data in ipairs({{'trorc','Orc'},{'trorc','Troll'},{'tauren','Tauren'},{'undead','Scourge'}}) do
  G.player.race=data[2];local g=G.guides['vq-'..data[1]..'-intro'];assert(g and G.Playable(g) and g.nextGuide=='vq-'..data[1]..'-01');assert(G.Playable(G.guides[g.nextGuide]))
 end
end)
check('source random-drop markers are not mistaken for repeatable quests',function()
 local found=0
 for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if s.randomDropStarter then assert(not s.repeatable);found=found+1 end end end
 assert(found>=8)
end)
check('Hunter pet training follows exact taming chains with real required rods',function()
 for _,chain in ipairs({{6062,6083,6082,6081},{6061,6087,6088,6089}}) do
  local have={}
  for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if s.classes and s.questID then
   for index,qid in ipairs(chain) do if s.questID==qid and s.id and string.find(s.id,'hunter%-') then
    assert(s.minlevel==10);have[qid]=have[qid] or {};have[qid][s.action]=s
   end end
  end end end
  for i,qid in ipairs(chain) do assert(have[qid] and have[qid].accept and have[qid].turnin);if i<4 then assert(have[qid].use and have[qid].use.manual and have[qid].use.itemID and have[qid].use.creatureID) end end
 end
end)
check('OctoWoW brazier permits Dark Iron Legacy without death in hardcore',function()
 G.player={class='HUNTER',race='Orc',faction='Horde'};G.db.mode='hardcore'
 local found={}
 for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if (s.questID==3801 or s.questID==3802) and s.action=='accept' and G.Allowed(s) then
  assert(not s.requiresDeath and s.zone==46 and math.abs(s.x-.2913)<.0001 and math.abs(s.y-.2883)<.0001)
  assert(string.find(s.text,'Brazier') or string.find(s.text,'brazier'));found[s.questID]=true
 end end end
 assert(found[3801] and found[3802])
end)
check('verified source errata retain corrected quest IDs and giver actions',function()
 local wanted={
  ['shared-p240']={['accept:597']=true},['shared-p447']={['accept:5848']=true},
  ['shared-p276']={['accept:2967']=true},['shared-p287']={['turnin:2967']=true},
  ['shared-p217']={['turnin:1276']=true},['shared-p198']={['turnin:521']=true},
  ['shared-p370']={['accept:3762']=true,['turnin:3762']=true},
  ['shared-p130']={['accept:1111']=true},['shared-p024']={['accept:6382']=true},
  ['shared-p424']={['turnin:5405']=true},['shared-p373']={['accept:7492']=true},
  ['undead-p017']={['accept:445']=true}
 }
 for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if s.questID and wanted[s.page] then wanted[s.page][s.action..':'..s.questID]=nil end end end
 for page,left in pairs(wanted) do for key in pairs(left) do error('Missing source correction '..page..' '..key) end end
end)
print('ALL '..passed..' AUTHORED CONTENT CHECKS PASSED')
