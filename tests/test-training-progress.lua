local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua');dofile('Training.lua')
local G=OctoGuide
G.player={class='HUNTER',race='Orc',faction='Horde'};G.db={progress={},completedQuests={},mode='hardcore'};G.ready=true
local renders=0;G.Render=function()renders=renders+1 end
local known={};local playerSpells={};local petKnown={};local book={};local skills={}
local metadata={[5116]={'Concussive Shot',''},[13549]={'Serpent Sting','Rank 2'},[3273]={'First Aid','Apprentice'},[3278]={'Heavy Wool Bandage',''},[8613]={'Skinning','Apprentice'},[24547]={'Natural Armor','Rank 1'}}
function IsSpellKnown(id,pet)return pet and petKnown[id] or known[id] or false end
function IsPlayerSpell(id)return playerSpells[id] or false end
function GetSpellInfo(id)local s=metadata[id];if s then return s[1],s[2]end end
function GetNumSpellTabs()return 1 end
function GetSpellTabInfo()return 'Hunter','icon',0,table.getn(book)end
function GetSpellName(slot,kind)local s=book[slot];if s then return s[1],s[2]end end
function GetNumSkillLines()return table.getn(skills)end
function GetSkillLineInfo(i)return skills[i][1],false,false,skills[i][2]end
local function select(id,step)
 G.db.progress={};G.db.placements={};G.pauseAuto=false
 G.RegisterGuide({id=id,faction='Horde'},{step,{id='next',action='note',text='Next quest waypoint',manual=true,zone=1,x=.2,y=.3}})
 assert(G.Select(id));return G.Current()
end
local function expectNext()assert(G.Current().id=='next' and G.Current().x==.2 and G.db.progress[G.Key(G.state.steps[1])]=='observed')end
local step={id='learn',action='train',text='Train Concussive Shot',spellID=5116,manual=true}
select('learn-exact',step);G.Event('TRAINER_SHOW');G.Event('TRAINER_UPDATE');assert(G.Current()==step,'Trainer opening/update is not learning')
known[999]=true;G.Event('SPELLS_CHANGED');assert(G.Current()==step,'Unrelated learned skill cannot finish')
known[5116]=true;G.Event('SPELLS_CHANGED');expectNext()
known[5116]=nil;select('learn-event',step);known[5116]=true;G.Event('LEARNED_SPELL_IN_TAB',5116);expectNext()
known[5116]=nil;select('buy-failed',step);G.Event('TRAINER_UPDATE');assert(G.Current()==step,'Rejected purchase cannot finish')
-- Professions/recipes can be known without a spellbook button.
local recipe={id='bandage',action='train',text='Train Heavy Wool Bandage',spellID=3278,manual=true}
select('learn-recipe',recipe);playerSpells[3278]=true;G.Event('CRAFT_UPDATE');expectNext()
local skin={id='skin',action='train',text='Learn the skinning profession.',manual=true}
select('learn-skinning',skin);skills={{'Skinning',1}};G.Event('SKILL_LINES_CHANGED');expectNext();skills={}
-- Same name with a lower rank is insufficient; a higher trained rank is sufficient.
local rank2={id='rank2',action='train',text='Train Serpent Sting Rank 2',spellID=13549,manual=true}
book={{'Serpent Sting','Rank 1'}};select('learn-rank',rank2);G.Event('SPELLS_CHANGED');assert(G.Current()==rank2)
book={{'Serpent Sting','Rank 3'}};G.Event('SPELLS_CHANGED');expectNext();book={}
-- Back remains fixed, while a direct jump resumes from real skill evidence.
known[5116]=nil;select('learn-back',step);G.state.reviewIndex=1;G.state.reviewReason='back';G.pauseAuto=true
known[5116]=true;G.Event('SPELLS_CHANGED');assert(G.Current()==step and G.pauseAuto and not G.db.progress[G.Key(step)])
G.state.reviewReason='jump';G.Event('SPELLS_CHANGED');expectNext()
-- Generic class visits wait for all initially trainable skills, not merely one.
local services={{'Arcane Shot','Rank 1','available'},{'Hunter Mark','Rank 1','available'}}
function GetNumTrainerServices()return table.getn(services)end
function GetTrainerServiceInfo(i)return unpack(services[i])end
function GetTrainerServiceTypeFilter()return 1 end
local generic={id='visit',action='train',text='Train your class spells',personalClass='HUNTER',manual=true}
select('generic-visit',generic);G.Event('TRAINER_SHOW');assert(G.Current()==generic)
book={{'Arcane Shot','Rank 1'}};G.Event('SPELLS_CHANGED');assert(G.Current()==generic,'Partial class training stays active')
book[2]={'Hunter Mark','Rank 1'};G.Event('SPELLS_CHANGED');expectNext();book={}
select('generic-filter',generic);G.Event('TRAINER_SHOW');services={};G.Event('TRAINER_UPDATE');assert(G.Current()==generic,'Changed trainer list is not evidence')
G.Event('TRAINER_CLOSED');G.Event('SPELLS_CHANGED');assert(G.Current()==generic,'Closing trainer cannot complete visit')
-- Already-known exact skills reconcile on selection; absent APIs remain manual.
known[5116]=true;select('already-known',step);expectNext()
IsSpellKnown=nil;IsPlayerSpell=nil;GetSpellInfo=nil;GetNumSpellTabs=nil;GetNumSkillLines=nil
select('missing-apis',step);G.Event('SPELLS_CHANGED');assert(G.Current()==step)
print('PASS exact learning events, recipes, professions, ranks, generic visits, failed purchases, already-known skills and Back/jump')
