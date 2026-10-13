-- Regression fixture reproduces the reported Vanilla tooltip failure on 0.5.12.
local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua')
local module=os.getenv('OCTOGUIDE_AUTOMATION_UNDER_TEST') or 'QuestAutomation.lua'
dofile(module)
local G=OctoGuide;local A=G.automation
G.player={class='HUNTER',race='Orc',faction='Horde'};G.db={progress={},completedQuests={},autoReward=true,autoTurnIn=true,mode='hardcore'};G.ready=true
G.Render=function()end;G.Sync=function()end
G.RegisterGuide({id='reward-link-test',faction='Horde'},{{id='turn',text='Turn in Guide Quest to NPC.',action='turnin',questID=10}});G.Select('reward-link-test')
testQuestLog[10]={complete=1};function GetQuestID()return 10 end
local items={}
local function full(id,loc,agi,price,suffix)
 local raw='item:'..id..':0:'..(suffix or 0)..':123'
 local link='|cff1eff00|H'..raw..'|h[Item '..id..']|h|r'
 items[link]={raw=raw,loc=loc,stats={ITEM_MOD_AGILITY_SHORT=agi},price=price};items[raw]=items[link]
 return link
end
local choices={full(100,'INVTYPE_CHEST',4,10,-769),full(101,'INVTYPE_CHEST',2,100)}
local worn=full(90,'INVTYPE_CHEST',1,5)
function GetNumQuestChoices()return 2 end
function GetQuestItemLink(_,i)return choices[i]end
function GetQuestItemInfo(_,i)return 'Item','icon',1 end
function GetInventoryItemLink(_,slot)return slot==5 and worn end
function GetContainerNumSlots()return 0 end;function GetContainerItemLink()end
C_Item={GetItemInfo=function(l)local a=items[l];return 'Item',l,1,1,1,'Armor','Leather',1,a.loc,'texture',a.price end,GetItemStats=function(l)return items[l].stats end}
local methods=getmetatable(UIParent).__index
function methods:SetOwner()end;function methods:ClearLines()end
local seen={};local reject=false
function methods:SetHyperlink(l)
 if not string.find(l,'^item:') or reject then error('Unknown link type')end
 assert(items[l],'Enchant/random suffix/unique payload changed');self.link=l;seen[l]=true
end
function methods:NumLines()return 1 end
function getglobal(name)return _G[name]end
OctoGuideRewardScanTextLeft1={GetText=function()return 'Item'end,GetTextColor=function()return 1,1,1 end}
local requested
function GetQuestReward(choice)requested=choice end
local ok,why=pcall(A.Event,'QUEST_COMPLETE')
if os.getenv('OCTOGUIDE_EXPECT_OLD_LINK_FAILURE') then
 assert(not ok and string.find(why,'Unknown link type',1,true));print('REPRODUCED 0.5.12 Unknown link type on colored quest/inventory links');return
end
assert(ok,why);assert(requested==1 and seen['item:100:0:-769:123'],'Full quest link must select upgrade and preserve suffix')
A.Event('QUEST_FINISHED');A.cache={};requested=nil;reject=true
ok,why=pcall(A.Event,'QUEST_COMPLETE');assert(ok,why);assert(requested==nil,'Rejected tooltip stays manual without breaking addon')
reject=false;A.Event('GET_ITEM_INFO_RECEIVED');assert(requested==1,'Valid data can retry after rejection')
print('PASS full colored quest and equipped links, preserved suffix, handled rejection, reward dispatch and retry')
