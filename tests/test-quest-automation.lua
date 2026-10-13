local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua');dofile('QuestAutomation.lua')
local G=OctoGuide;local A=G.automation
G.player={class='HUNTER',race='Orc',faction='Horde'};G.db={progress={},completedQuests={},mode='hardcore'};G.ready=true
G.Render=function()end;G.Sync=function()end
G.RegisterGuide({id='auto-test',title='Test',faction='Horde'}, {
 {id='a',action='accept',text='Accept Guide Quest from NPC.',questID=10},
 {id='b',action='turnin',text='Turn in Guide Quest to NPC.',questID=10},
 {id='c',action='accept',text='Accept Later Quest from NPC.',questID=11,minlevel=4},
 {id='d',action='turnin',text='Turn in Later Quest to NPC.',questID=11}})
G.Select('auto-test')
local dialog=10;function GetQuestID()return dialog end
function GetTitleText()return 'Guide Quest'end
local accept,finish,rewards=0,0,{}
function AcceptQuest()accept=accept+1 end
function CompleteQuest()finish=finish+1 end
function IsQuestCompletable()return true end
function GetQuestReward(n)table.insert(rewards,n)end
local count=0;function GetNumQuestChoices()return count end
local shift=false;function IsShiftKeyDown()return shift end
function UnitAffectingCombat()return false end
local function event(ev)_G.event=ev;A.frame.scripts.OnEvent()end
event('QUEST_DETAIL');assert(accept==0,'Default off')
G.db.autoAccept=true;event('QUEST_DETAIL');event('QUEST_DETAIL');assert(accept==1,'Immediate and only once')
event('QUEST_FINISHED');dialog=999;event('QUEST_DETAIL');assert(accept==1,'Unrelated quest excluded')
dialog=11;event('QUEST_DETAIL');assert(accept==1,'Minimum level respected')
dialog=10;shift=true;event('QUEST_DETAIL');assert(accept==1,'Shift override');shift=false
G.pauseAuto=true;event('QUEST_DETAIL');assert(accept==1,'Back review blocks automation');G.pauseAuto=false
testQuestLog[10]={complete=1};G.db.autoTurnIn=true
event('QUEST_PROGRESS');assert(finish==1,'Immediate completion')
event('QUEST_COMPLETE');assert(table.getn(rewards)==1 and rewards[1]==0)
event('QUEST_COMPLETE');assert(table.getn(rewards)==1,'Duplicate completion ignored')
assert(not G.db.completedQuests[10],'Reward request is not server confirmation')
event('QUEST_FINISHED');count=2;event('QUEST_COMPLETE');assert(table.getn(rewards)==1,'Multiple rewards manual without autoReward')
local inventory={};local bags={};local choices={};local items={}
function GetInventoryItemLink(_,slot)return inventory[slot]end
function GetContainerNumSlots(bag)return bag==0 and table.getn(bags) or 0 end
function GetContainerItemLink(bag,slot)return bag==0 and bags[slot]end
function GetQuestItemLink(_,i)return choices[i]end
function GetQuestItemInfo(_,i)return 'Reward','icon',1 end
local function link(id)return 'item:'..id..':0:0:0'end
local function item(id,loc,agi,price,usable)
 items[link(id)]={name='Item '..id,loc=loc,stats={ITEM_MOD_AGILITY_SHORT=agi},price=price,usable=usable~=false}
 return link(id)
end
C_Item={GetItemInfo=function(l)local a=items[l];if a then return a.name,l,1,1,1,'Armor','Leather',1,a.loc,'texture',a.price end end,GetItemStats=function(l)return items[l] and items[l].stats end}
-- Model a real tooltip's red unusable requirements, separate from item stats.
local methods=getmetatable(UIParent).__index
function getglobal(name) return _G[name] end
function methods:SetOwner()end;function methods:ClearLines()end
function methods:SetHyperlink(l)
 assert(string.find(l,'^item:'),'Unknown link type')
 self.link=l
end
function methods:NumLines()return items[self.link] and 1 or 0 end
OctoGuideRewardScanTextLeft1={GetText=function()return 'Item'end,GetTextColor=function()local a=items[A.tooltip.link];if a.usable then return 1,1,1 else return 1,0,0 end end}
choices={item(100,'INVTYPE_CHEST',4,10),item(101,'INVTYPE_CHEST',2,100)}
inventory[5]=item(90,'INVTYPE_CHEST',1,5)
G.db.autoReward=true;event('QUEST_COMPLETE');assert(rewards[2]==1,'Upgrade before money')
event('QUEST_FINISHED');bags={item(91,'INVTYPE_CHEST',5,5)};A.cache={}
event('QUEST_COMPLETE');assert(rewards[3]==2,'Owned better item in bags -> money')
event('QUEST_FINISHED');choices={item(102,'INVTYPE_CHEST',100,200,false),item(103,'INVTYPE_CHEST',2,300)};A.cache={}
event('QUEST_COMPLETE');assert(rewards[4]==2,'Unusable item cannot be upgrade')
event('QUEST_FINISHED');choices={link(104),link(103)};A.cache={}
event('QUEST_COMPLETE');assert(table.getn(rewards)==4 and A.pending==10,'Uncached data stays manual/pending')
item(104,'INVTYPE_CHEST',8,1);event('GET_ITEM_INFO_RECEIVED');assert(rewards[5]==1,'Retry only after actual item-data event')
event('QUEST_FINISHED');A.pending=10;event('QUEST_FINISHED');event('GET_ITEM_INFO_RECEIVED');assert(table.getn(rewards)==5,'Closed dialog cancels pending')
-- Jewelry compares against both occupied slots and actual bag copies.
count=2;choices={item(110,'INVTYPE_FINGER',5,1),item(111,'INVTYPE_FINGER',1,10)}
inventory={};bags={item(112,'INVTYPE_FINGER',6,1),item(113,'INVTYPE_FINGER',7,1)};A.cache={}
assert(A.ChooseReward()==2,'Two better bag rings -> vendor')
bags={link(112)};A.cache={};assert(A.ChooseReward()==1,'Second ring slot upgrade')
-- Flat Vanilla item tuple fallback uses equipLoc eight, not nine.
local modern=C_Item;C_Item=nil
function GetItemInfo(l)return 'Item',l,1,1,'Armor','Leather',1,'INVTYPE_CHEST','texture'end
function GetItemStats(l)return {ITEM_MOD_AGILITY_SHORT=3}end
A.cache={};assert(A.Item(link(110)).loc=='INVTYPE_CHEST');C_Item=modern
-- Duplicate names are refused without an exact selected ID.
GetQuestID=nil;pfDB={quests={enUS={[10]={T='Guide Quest'},[99]={T='Guide Quest'}}}}
assert(A.DialogID('turnin')==nil)
C_GossipInfo={GetActiveQuests=function()return {{questID=10,title='Guide Quest',isComplete=true}}end,GetAvailableQuests=function()return {}end,SelectActiveQuest=function(id)assert(id==10)end}
event('GOSSIP_SHOW');event('GOSSIP_CLOSED');assert(A.DialogID('turnin')==10,'Gossip selection retains exact ID into dialog')
event('QUEST_GREETING');assert(A.DialogID('turnin')==10,'ClassicAPI greeting retains exact ID too')
C_GossipInfo=nil;pfDB=nil
function GetGossipActiveQuests()return 'Unrelated',1,'Guide Quest',1 end
local activeIndex;function SelectGossipActiveQuest(i)activeIndex=i end
event('GOSSIP_SHOW');assert(activeIndex==2,'Stock Vanilla active gossip uses pairs')
-- Total reward vendor value includes stack quantity.
choices={item(140,'',0,10),item(141,'',0,50)};count=2;A.cache={};inventory={};bags={}
function GetQuestItemInfo(_,i)return 'Reward','icon',i==1 and 20 or 1 end
assert(A.ChooseReward()==1,'Stack total beats higher unit price')
function GetQuestItemInfo(_,i)return 'Reward','icon',1 end
-- One/two-hand weapons are compared as loadouts, including bag alternatives.
inventory={};bags={};G.player.class='WARRIOR';count=2
choices={item(120,'INVTYPE_2HWEAPON',5,1),item(121,'INVTYPE_CHEST',0,100)}
inventory[16]=item(122,'INVTYPE_WEAPONMAINHAND',3,1);inventory[17]=item(123,'INVTYPE_SHIELD',3,1);A.cache={}
assert(A.ChooseReward()==2,'Two-hand reward worse than one-hand plus shield')
choices[1]=item(124,'INVTYPE_2HWEAPON',8,1);A.cache={};assert(A.ChooseReward()==1,'Better two-hand loadout is upgrade')
-- Talent tuple uses return THREE for Vanilla points spent.
G.player.class='DRUID';function GetTalentTabInfo(i)return 'Tree','icon',i==1 and 10 or 0,'background'end
local caster={usable=true,loc='INVTYPE_CHEST',stats={ITEM_MOD_INTELLECT_SHORT=5}}
assert(A.Score(caster)==10,'Balance talent profile selected')
-- Auto pick without auto turn-in must only click the reward choice.
GetQuestID=function()return 10 end;G.player.class='HUNTER';G.db.autoTurnIn=false
inventory={};bags={};choices={item(130,'INVTYPE_CHEST',5,1),item(131,'INVTYPE_CHEST',1,100)};A.cache={}
local selected
function methods:GetScript(k)return self.scripts[k]end
QuestRewardItem1=CreateFrame('Button');QuestRewardItem1:SetScript('OnClick',function()selected=1 end)
event('QUEST_FINISHED');event('QUEST_COMPLETE');assert(selected==1 and table.getn(rewards)==5,'Selection alone cannot turn in')
G.db.autoTurnIn=true;event('QUEST_FINISHED');items[choices[1]].stats.UNKNOWN_STAT=10;A.cache={}
event('QUEST_COMPLETE');assert(table.getn(rewards)==5,'Unknown scoring stat stays manual')
-- Runtime path has no artificial wait: handler returns only after dispatch.
G.db.autoAccept=true;testQuestLog[10]=nil;GetQuestID=function()return 10 end;event('QUEST_FINISHED')
local before=accept;local t=os.clock();event('QUEST_DETAIL');assert(accept==before+1)
print('Measured mock direct-accept handler CPU time (seconds): '..(os.clock()-t))
print('PASS quest gating, defaults, instant events, rewards, bags, two rings, missing data, duplicate titles and Vanilla tuple')
