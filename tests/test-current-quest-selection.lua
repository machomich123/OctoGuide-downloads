dofile('tests/test-quest-automation.lua')
local G=OctoGuide;local A=G.automation
local pickup={id='sam',action='accept',questID=894,text='Accept Samophlange from Sputtervalve.'}
local other={id='other',action='accept',questID=900,text='Accept Samophlange from Other.'}
local trader={id='trader',action='accept',questID=70052,text="Accept Trader's Misfortune from Wharfmaster."}
local turnin={id='wharf',action='turnin',questID=1111,text='Turn in Wharfmaster Dizzywig to Wharfmaster.'}
G.state.steps={pickup,other,trader,turnin};G.state.reviewReason='back';G.state.reviewIndex=1
G.pauseAuto=true;G.db.progress={};G.db.completedQuests={};G.db.autoAccept=true;G.db.autoTurnIn=true
local current=pickup;G.Current=function() return current end
local npc=3442;function UnitCreatureID()return npc end
pfDB={quests={enUS={[894]={T='Samophlange'},[900]={T='Samophlange'},[70052]={T="Trader's Misfortune"},[1111]={T='Wharfmaster Dizzywig'}},data={[894]={start={U={3442}}},[900]={start={O={123}}}}}}
local selected,accepted=0,0
function GetQuestID()return 894 end
function GetTitleText()return 'Samophlange' end
function AcceptQuest()accepted=accepted+1 end
function UnitAffectingCombat()return false end
function IsShiftKeyDown()return false end
function GetNumQuestLogEntries()return 1,1 end
testQuestLog[894]=nil
C_GossipInfo=nil
function GetGossipAvailableQuests()return 'Samophlange',14 end
function GetGossipActiveQuests()end
function SelectGossipAvailableQuest(i)selected=i end
A.Event('GOSSIP_SHOW');assert(selected==1,'Back-selected Samophlange resolves by actual giver despite duplicate chain names')
A.Event('QUEST_DETAIL');assert(accepted==1,'Selected gossip continues through actual accept request')
npc=999;selected=0;A.Event('GOSSIP_SHOW');assert(selected==0,'Wrong giver cannot resolve title fallback')
npc=3453;current=trader;G.state.reviewIndex=3;testQuestLog[1111]={complete=1}
C_GossipInfo={GetActiveQuests=function()return {{questID=1111}} end,GetAvailableQuests=function()return {{questID=70052}} end,SelectAvailableQuest=function(id)selected=id end,SelectActiveQuest=function()error('Unrelated turn-in selected')end}
A.Event('GOSSIP_SHOW');assert(selected==70052,'Current Trader pickup wins over unrelated Wharfmaster turn-in')
G.state.reviewIndex=1;selected=0;A.Event('GOSSIP_SHOW');assert(selected==0,'Back cannot automate a different selected step')
print('PASS exact current pickup, Back, duplicate Samophlange, NPC identity, gossip-to-accept and Trader/Wharfmaster priority')
