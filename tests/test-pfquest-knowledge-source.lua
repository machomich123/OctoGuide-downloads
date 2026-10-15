dofile('tests/test-runtime.lua');dofile('Placement.lua');dofile('CharacterScan.lua');dofile('QuestAutomation.lua');dofile('LiveTargets.lua');dofile('QuestKnowledge.lua')
local G=OctoGuide
local base=os.getenv('OCTOGUIDE_PFQUEST_TEST_DIR') or 'W:/Games/Octowow/Interface/AddOns/pfQuest'
pfDB={quests={},units={},objects={}}
for _,name in ipairs({'quests','units','objects'}) do dofile(base..'/db/'..name..'.lua') end
dofile(base..'/db/enUS/quests.lua');dofile(base..'/db/enUS/units.lua');pfDB.quests.loc=pfDB.quests.enUS
-- Run the installed pfQuest filter itself, including its cosmetic visibility rules.
pfDatabase={GetBitByRace=function()return 2 end,GetBitByClass=function()return 4 end,GetPlayerSkill=function()return nil end}
bit={band=function(a,b)local out,p=0,1;while a>0 and b>0 do if math.mod(a,2)==1 and math.mod(b,2)==1 then out=out+p end;a=math.floor(a/2);b=math.floor(b/2);p=p*2 end;return out end}
pfQuest={questlog={}};pfQuest_history={};pfQuest_config={showlowlevel='0',showhighlevel='0',showfestival='0'}
quests=pfDB.quests.data
local f=assert(io.open(base..'/database.lua'));local text=f:read('*a');f:close()
local first=assert(string.find(text,'function pfDatabase:QuestFilter(',1,true))
local last=assert(string.find(text,'-- SearchQuests',first,true));assert(loadstring(string.sub(text,first,last-1)))()
function UnitLevel()return 15 end
function UnitRace()return 'Orc','Orc' end
function UnitClass()return 'Hunter','HUNTER' end
function UnitFactionGroup()return 'Horde' end
G.db.completedQuests={};G.db.progress={}
assert(pfDB.quests.data[870].start.U[1]==3448)
local status=G.QuestAvailability(870)
assert(status.state=='needs_check','Actual pfQuest record lists breadcrumb 886; absence is uncertainty, not proof of unavailability')
G.db.completedQuests[886]=true;pfQuest_history[886]={0,0}
status=G.QuestAvailability(870)
assert(status.state=='expected' and status.mapMarker==true,'Actual Forgotten Pools agrees with pfQuest marker filter')
-- Hiding a quest by display preference does not turn that preference into a lock.
pfDB.quests.data[870].lvl=1
status=G.QuestAvailability(870);assert(status.state=='expected' and status.mapMarker==false)
local rows=G.AreaQuestList(17);local found=false;local available=0
for _,row in ipairs(rows) do
 if row.id==870 then found=true;assert(row.state=='expected' and row.points[1].entry==3448) end
 if row.state=='expected' then available=available+1 end
end
assert(found and table.getn(rows)>30 and available>0,'Area records must include the actual Barrens catalogue')
testQuestLog[870]={complete=false};assert(G.QuestAvailability(870).state=='active')
testQuestLog[870]=nil;G.db.completedQuests[870]=true;assert(G.QuestAvailability(870).state=='completed')
print('PASS actual pfQuest QuestFilter and '..table.getn(rows)..' Barrens quest records; direct ID/giver mapping, expected/hidden/active/completed distinctions')
-- Apply the installed extension's exact replacement/deletion merge convention.
local turtle='W:/Games/Octowow/Interface/AddOns/pfQuest-turtle'
for _,name in ipairs({'quests','units','objects'}) do
 if not pfDB[name].enUS then dofile(base..'/db/enUS/'..name..'.lua') end
 dofile(turtle..'/db/'..name..'-turtle.lua')
 for id,value in pairs(pfDB[name]['data-turtle'] or {}) do if value=='_' then pfDB[name].data[id]=nil else pfDB[name].data[id]=value end end
 dofile(turtle..'/db/enUS/'..name..'-turtle.lua')
 for id,value in pairs(pfDB[name]['enUS-turtle'] or {}) do if value=='_' then pfDB[name].enUS[id]=nil else pfDB[name].enUS[id]=value end end
end
quests=pfDB.quests.data;G.db.completedQuests[870]=nil
local merged=G.AreaQuestList(17);assert(table.getn(merged)>30)
local current=G.QuestAvailability(870)
assert(current.state=='expected' or current.state=='needs_check')
print('PASS installed pfQuest-turtle merge: '..table.getn(merged)..' Barrens records; 870 pre='..table.concat(pfDB.quests.data[870].pre or {},',')..'; status='..current.state)
