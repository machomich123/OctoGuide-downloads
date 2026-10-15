local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
local first=assert(string.find(source,"dofile('Core.lua')",1,true));assert(loadstring(string.sub(source,1,first-1)))()
local methods=getmetatable(UIParent).__index
for _,key in ipairs({'SetNumeric','SetAutoFocus','SetJustifyV'}) do methods[key]=function()end end
function methods:SetFont(path,size)self.fontSize=size end
function methods:EnableMouse(on)self.mouseEnabled=on end
function methods:StartMoving()self.moving=true end
function methods:StopMovingOrSizing()self.moving=false end
function methods:SetVertexColor(r,g,b)self.color={r,g,b}end
local toc=assert(io.open('OctoGuide-downloads.toc'));for line in toc:lines() do if string.find(line,'%.lua$') then dofile(line) end end;toc:close()
local G=OctoGuide;G.Init();assert(G.ready and G.floatingArrow and G.arrowSettings and G.options.arrowButton)
assert(G.ArrowOptions().mode=='panel' and not G.floatingArrow:IsShown(),'Existing users retain panel arrow')
local a={id='a',action='travel',text='Walk to the tower.',zone=1,x=.1,y=0,manual=true}
local b={id='b',action='travel',text='Speak to the guard.',zone=1,x=.2,y=0,manual=true}
G.RegisterGuide({id='free-arrow-test',title='Free arrow',faction='Horde'},{a,b});G.Select('free-arrow-test')
local reads=0;local result={angle=0,yards=100,heightDelta=0}
G.NavigationRead=function()reads=reads+1;return result end
local o=G.ArrowOptions();o.mode='both';G.ApplyArrowSettings();reads=0;G.UpdateArrow(.016)
local f=G.floatingArrow
assert(G.frame:IsShown() and G.frame.arrow:IsShown() and f:IsShown(),'Guide and free arrow coexist')
assert(reads==1 and G.frame.distance:GetText()=='100 yd' and f.distance:GetText()=='100 yd','Both views share one navigation result')
assert(f.task:GetText()=='Walk to the tower.' and f.task:IsShown())
assert(G.ArrowCell(0)==0 and G.ArrowCell(math.pi/2)==81 and G.ArrowCell(math.pi)==54 and G.ArrowCell(3*math.pi/2)==27)
for i=0,107 do assert(G.ArrowCell(-i*2*math.pi/108)==i,'Every sprite cell must be reachable') end
assert(G.ArrowCell(2*math.pi-.0001)==0 and G.ArrowCell(.0001)==0,'Angle wrap is stable')
assert(f.mouseEnabled==false);f.scripts.OnDragStart();assert(not f.moving,'Locked arrow does not capture dragging')
o.locked=false;G.ApplyArrowSettings();assert(f.mouseEnabled);f.scripts.OnDragStart();assert(f.moving)
local guidePosition=G.db.position;f.scripts.OnDragStop();assert(not f.moving and o.position[3]==5 and G.db.position==guidePosition,'Arrow drag never moves/saves the guide frame')
o.scale=1.5;o.font=14;G.ApplyArrowSettings();assert(f:GetScale()==1.5 and f.task.fontSize==14)
o.task=false;G.UpdateArrow(.016);assert(not f.task:IsShown() and f.distance:IsShown())
o.task=true;o.mode='floating';G.UpdateArrow(.016);assert(G.frame:IsShown() and not G.frame.arrow:IsShown() and f:IsShown(),'Detach primary arrow without closing guide')
G.frame:Hide();o.withHidden=true;reads=0;G.UpdateArrow(.016);assert(f:IsShown() and reads==1,'Standalone navigation continues with hidden guide')
o.withHidden=false;G.UpdateArrow(.016);assert(not f:IsShown())
G.frame:Show();o.mode='off';reads=0;G.UpdateArrow(.016);assert(reads==0 and not f:IsShown() and not G.frame.arrow:IsShown(),'Disabled arrow adds no navigation polling')
o.mode='both';G.UpdateArrow(.016);assert(G.frame.arrow:IsShown() and f:IsShown(),'Changing mode restores both views')
result={angle=0,yards=2,heightDelta=12};G.UpdateArrow(.016);assert(not string.find(f.distance:GetText(),'At waypoint',1,true),'Different floor cannot mean arrival')
result.heightDelta=0;G.UpdateArrow(.016);assert(string.find(f.distance:GetText(),'At waypoint',1,true))
assert(G.Current()==a and not G.db.progress[G.Key(a)],'Arrival never completes a manual step')
testQuestLog[987]={objectives={{'Boars slain: 2/8',nil}}};assert(G.ShortArrowTask({action='objective',questID=987})=='Boars slain: 2/8')
testQuestLog[987].objectives[1][1]='Peons awakened: 0/5';assert(G.ShortArrowTask({action='objective',questID=987})=='Peons awakened: 0/5','Do not turn interactions into kill instructions')
local progress=G.db.progress;local index=G.state.index
assert(G.PinArrowStep(b));G.SecondaryRead=function(s)assert(s==b);return {angle=0,yards=200}end
G.UpdateArrow(.25);assert(string.find(f.title:GetText(),'[Selected]',1,true) and G.Current()==a and G.db.progress==progress and G.state.index==index,'Pinning changes only navigation')
G.ClearArrowPin();G.UpdateArrow(.25);assert(not string.find(f.title:GetText(),'[Selected]',1,true))
o.position={'BAD','CENTER',0,0};G.ApplyArrowSettings();assert(o.position==nil,'Invalid saved positions recover safely')
G.options.arrowButton.scripts.OnClick();assert(G.arrowSettings:IsShown())
G.arrowSettings.rows.task.scripts.OnClick();assert(o.task==false)
G.arrowSettings.rows.reset.scripts.OnClick();assert(o.position==nil)
G.HidePanels();assert(not f:IsShown() and not G.arrowSettings:IsShown())
G.failed=true;G.ready=false;G.UpdateArrow(.016);assert(not f:IsShown(),'Failure containment hides free arrow')
print('PASS full manifest, shared navigation, all sprite angles, independent settings/position, short text, hidden guide, pins, arrival and failure containment')
