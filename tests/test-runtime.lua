-- Actual addon file load and script callbacks under Lua 5.0, mock client API.
local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS '..name) end
local frames={}
local methods={}
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:RegisterEvent(ev) self.events[ev]=true end
function methods:CreateTexture() local t=setmetatable({scripts={},events={}}, {__index=methods});return t end
function methods:CreateFontString() return self:CreateTexture() end
function methods:SetText(v) self.value=v end
function methods:SetTexture(v) self.texture=v end
function methods:SetRotation(v) self.rotation=v end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown~=false end
function methods:GetPoint() return 'CENTER',UIParent,'CENTER',5,10 end
for _,key in ipairs({'SetFont','SetPoint','SetWidth','SetHeight','SetJustifyH','SetTextColor','SetFrameStrata','EnableMouse','SetMovable','RegisterForDrag','SetAllPoints','SetBackdrop','SetBackdropColor','ClearAllPoints','StartMoving','StopMovingOrSizing'}) do methods[key]=function() end end
function methods:SetWidth(n) self.width=n end
function methods:SetHeight(n) self.height=n end
function methods:GetWidth() return self.width or 460 end
function methods:GetHeight() return self.height or 600 end
function methods:SetScale(n) self.scale=n end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:GetLeft() return 100 end
function methods:GetBottom() return 100 end
function methods:SetTexCoord(...) self.uv=arg end
function methods:SetPoint(...) self.point=arg end
function methods:SetJustifyH(n) self.justify=n end
function methods:GetText() return self.value end
function methods:ClearFocus() self.focused=false end
function methods:SetValue(n) self.sliderValue=n end
function methods:GetValue() return self.sliderValue end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:EnableMouseWheel(value) self.mouseWheel=value end
function methods:SetVerticalScroll(value) self.scrollOffset=value end
function methods:GetVerticalScroll() return self.scrollOffset or 0 end
function CreateFrame(kind,name,parent,template) local f=setmetatable({name=name,parent=parent,scripts={},events={}}, {__index=methods});table.insert(frames,f);return f end
UIParent=CreateFrame('Frame');SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
local playerLevel=1;local class='HUNTER';local faction='Horde'
function UnitClass() return 'Hunter',class end
function UnitRace() return 'Orc','Orc' end
function UnitFactionGroup() return faction end
function UnitLevel() return playerLevel end
local qlog={};testQuestLog=qlog;C_QuestLog={GetLogIndexForQuestID=function(id) return qlog[id] and id or 0 end}
function GetQuestLogTitle(i) return 'Quest',1,nil,false,false,qlog[i] and qlog[i].complete end
function GetNumQuestLeaderBoards(i) return qlog[i] and table.getn(qlog[i].objectives or {}) or 0 end
function GetQuestLogLeaderBoard(i,qi) local o=qlog[qi].objectives[i];return o[1],'monster',o[2] end
function GetQuestLogLeaderBoardID(i,qi) return 4000+i,'monster' end
local px,py,map,facing=0,0,1,0
function UnitPosition() return py,px,0,map end
function GetPlayerFacing() return facing end
C_Map={GetWorldPosFromMapPos=function(zone,p) return zone,{x=p.x*1000,y=p.y*1000} end}
function GetNumSkillLines() return 1 end
function GetSkillLineInfo() return 'Mining',false,false,50 end
dofile('Core.lua');dofile('Route.lua');dofile('Progress.lua');dofile('Navigation.lua');dofile('Presentation.lua');dofile('Layout.lua');dofile('UI.lua');dofile('Integration.lua')
local G=OctoGuide
local route={
 {id='a',action='accept',text='Take quest',questID=10,zone=1,x=.1,y=0},
 {id='b',action='objective',text='Kill',questID=10,objective=2},
 {id='c',action='complete',text='Finish quest',questID=10},
 {id='d',action='turnin',text='Turn in',questID=10},
 {id='e',action='train',text='Hunter trainer',classes={HUNTER=true}},
 {id='f',action='train',text='Mage trainer',classes={MAGE=true}},
 {id='g',action='level',text='Reach level 3',level=3},
 {id='h',action='travel',text='Go north',zone=1,x=.2,y=0}}
G.RegisterGuide({id='starter',title='Starter',faction='Horde',startLevel=1,endLevel=5,source='Synthetic test only',quality='Test'},route)
check('addon files initialize via live callback',function() event='PLAYER_ENTERING_WORLD';G.events.scripts.OnEvent();assert(G.ready and G.frame:IsShown() and G.Current().id=='a') end)
check('class filtering removes unrelated training',function() assert(table.getn(G.state.steps)==7) end)
check('minimal and full preserve exact current step',function() G.Slash('full');assert(G.db.view=='full' and G.frame.nextCard:IsShown());G.Slash('minimal');assert(G.Current().id=='a' and not G.frame.nextCard:IsShown()) end)
check('correct positional live arrow',function() G.UpdateArrow();assert(G.frame.distance.value=='100 yd' and G.frame.arrow.rotation==0);px=50;facing=math.pi/2;G.UpdateArrow();assert(G.frame.distance.value=='50 yd' and math.abs(G.frame.arrow.rotation+math.pi/2)<.001) end)
check('hidden frame does not poll navigation',function() G.frame:Hide();local old=G.frame.distance.value;px=75;G.UpdateArrow();assert(G.frame.distance.value==old);G.frame:Show() end)
check('quest acceptance read by exact ID',function() qlog[11]={};G.Event('QUEST_ACCEPTED',11,11);assert(G.Current().id=='a');qlog[10]={objectives={{'First',1},{'Second',nil}}};G.Event('QUEST_ACCEPTED',10,10);assert(G.Current().id=='b') end)
check('objectives preserve individual completion',function() local o=G.Objectives(G.Current());assert(o[1].done and not o[2].done);G.Sync();assert(G.Current().id=='b');qlog[10].objectives[2][2]=1;G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='c') end)
check('whole quest complete remains until reward',function() qlog[10].complete=1;G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='d') end)
check('abandon and quest dialog cannot fake turnin',function() qlog[10]=nil;G.Event('QUEST_REMOVED',10);G.Event('QUEST_FINISHED',10);G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='d' and not G.db.completedQuests[10]) end)
check('wrong reward ID does not advance current',function() G.Event('QUEST_TURNED_IN',999);assert(G.Current().id=='d') end)
check('server confirmed reward advances',function() G.Event('QUEST_TURNED_IN',10);assert(G.Current().id=='e' and G.db.completedQuests[10]) end)
check('manual steps only advance by explicit button',function() this=G.frame.done;G.frame.done.scripts.OnClick();assert(G.Current().id=='g') end)
check('level gate uses actual level',function() G.Event('PLAYER_LEVEL_UP',3);assert(G.Current().id=='g');playerLevel=3;G.Event('PLAYER_LEVEL_UP',3);assert(G.Current().id=='h') end)
check('back preserves review until explicit advance',function() G.Back();assert(G.Current().id=='g');G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='g');G.Mark();assert(G.Current().id=='h') end)
check('transport does not give invented distance',function() map=2;G.UpdateArrow();assert(not G.frame.arrow:IsShown() and G.frame.distance.value=='Transport');map=1 end)
check('missing API gives no misleading arrow',function() local old=UnitPosition;UnitPosition=nil;G.UpdateArrow();assert(not G.frame.arrow:IsShown());UnitPosition=old end)
check('guide menu exposes selectable guide and preserves progress',function() G.ToggleMenu();assert(G.menu:IsShown() and G.menu.rows[1].guideID=='starter');this=G.menu.rows[1];this.scripts.OnClick();assert(G.Current().id=='h' and not G.menu:IsShown()) end)
check('reload restores same progress',function() local db=OctoGuideDB;G.ready=false;G.Init();assert(G.Current().id=='h' and G.db==db) end)
check('gathering skips hidden and skill-ineligible nodes',function()
 OctoGather={ready=true,byKey={a={key='a',zone=1,x=20,y=0,cat='ore',skill=1,name='Copper'},b={key='b',zone=1,x=8,y=0,cat='ore',skill=100,name='Iron'},c={key='c',zone=1,x=9,y=0,cat='ore',skill=1,name='Hidden'}},MapVisible=function(n) return n.key~='c' end}
 local ok=G.Gather('ore');assert(ok and G.gatherTarget.key=='a' and string.find(G.frame.step.value,'GATHER: Copper'));G.Slash('route');assert(not G.gatherTarget and G.frame.section.value=='TRAVEL')
end)
check('expired hidden gathering goal is removed',function() G.Gather('ore');OctoGather.MapVisible=function() return false end;arg1=.25;G.events.scripts.OnUpdate();assert(not G.gatherTarget) end)
check('faction restriction is explicit',function() G.player.faction='Alliance';local ok=G.Select('starter');assert(not ok);G.player.faction='Horde' end)
check('finished route has no current step',function() G.Mark();assert(not G.Current());G.Render();assert(string.find(G.frame.step.value,'Level range complete')) end)
check('explicit next-stage transition keeps old progress',function()
  G.RegisterGuide({id='stage2',title='Next stage',faction='Horde',startLevel=5,endLevel=10},{{id='one',action='travel',text='Next region'}})
  G.Advance();assert(G.state.guide.id=='stage2' and G.Current().id=='one' and G.db.progress['starter:h']=='manual')
end)
check('fresh character saved table starts independently',function()
 local prior=OctoGuideDB;OctoGuideDB={};G.ready=false;G.Init();assert(G.Current().id=='a' and not G.db.completedQuests[10] and G.db~=prior)
 OctoGuideDB=prior;G.ready=false;G.Init();assert(G.state.guide.id=='stage2')
end)
check('long instructions remain visible in both views without a hover wall',function()
 G.Current().text=string.rep('Long instruction ',15);G.Render();assert(string.len(G.frame.step.value)>77 and not G.tooltipText and not G.frame.scripts.OnEnter)
 G.Slash('minimal');assert(string.len(G.frame.step.value)>77);G.Slash('full')
end)
check('malformed imported data rejected before selection',function()
 local ok=pcall(G.RegisterGuide,{id='bad',faction='Horde'},{{action='complete',text='Invalid decimal quest',questID=25.3}});assert(not ok and not G.guides.bad)
 ok=pcall(G.RegisterGuide,{id='badmap',faction='Horde'},{{action='travel',text='Invalid percent coordinate',zone=1,x=50,y=70}});assert(not ok and not G.guides.badmap)
end)
check('completed objective redirects arrow to unfinished target',function()
 local s=G.Current();s.action='complete';s.questID=55;s.targets={{zone=1,x=.1,y=0,objective=1},{zone=1,x=.4,y=0,objective=2}}
 qlog[55]={objectives={{'First objective',1},{'Second objective',nil}}};px=0;py=0;G.UpdateArrow();assert(G.frame.distance.value=='400 yd')
end)
check('data-name matching handles unknown objective index',function()
 local s=G.Current();s.targets={{zone=1,x=.1,y=0,match='First objective'},{zone=1,x=.6,y=0,match='Second objective'}}
 G.UpdateArrow();assert(G.frame.distance.value=='600 yd')
end)
print('ALL '..passed..' RUNTIME CHECKS PASSED')
