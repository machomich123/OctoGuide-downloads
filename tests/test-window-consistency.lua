dofile('tests/test-free-arrow.lua')
local G=OctoGuide;G.failed=false;G.ready=true
local methods=getmetatable(UIParent).__index
function methods:SetAlpha(a)self.alpha=a end
function methods:SetBackdropColor(r,g,b,a)self.backdropAlpha=a end
assert(G.options.automationPanel.windowReady,'Automation dialog has common controls')
local p=G.arrowSettings
assert(p.windowReady and p.closeIcon.controlType=='Close' and p.windowGrip)
p.scripts.OnDragStart();assert(p.moving);p.scripts.OnDragStop();assert(not p.moving and G.db.windowPositions.arrow)
G.db.transparent=true;G.db.opacity=30;G.ApplyOpacity()
assert(math.abs(p.backdropAlpha-.285)<.0001 and p.panelSkin[1].alpha==.3)
assert(p.closeIcon.controlArt.alpha==nil,'Background opacity must not fade controls')
local x,y=100,100;GetCursorPosition=function()return x,y end
p.windowGrip.scripts.OnMouseDown();x=250;y=0;p.windowGrip.scripts.OnUpdate();assert(p:GetScale()>1 and G.db.windowScales.arrow==p:GetScale())
p.windowGrip.scripts.OnMouseUp();assert(not p.windowDrag)
p:Show();p.closeIcon.scripts.OnClick();assert(not p:IsShown())
G.ShowReport();assert(G.reportWindow.windowReady and G.reportWindow.closeIcon and G.reportWindow.windowGrip)
local future=G.MakeCard(UIParent);assert(future.windowReady and future.closeIcon and future.windowGrip,'Future menus inherit common window controls')
G.Present=function()return 'Accept Kolkar Leaders.','Talk to Regthar\nDo alongside this step: Complete Raptor Thieves.' end
assert(G.ShortArrowTask({action='accept'})=='Talk to Regthar','Accept step describes its actual NPC interaction, not unrelated concurrent kills')
local f=G.floatingArrow;G.ArrowOptions().font=12;G.ApplyArrowSettings();assert(f.distance.fontSize==10 and f.task.fontSize==12)
for _,w in ipairs(G.windows) do assert(w.closeIcon and w.windowGrip and w.scripts.OnDragStart) end
print('PASS shared menu opacity, drag persistence, resize persistence, close icons, future menus, NPC task and smaller distance font')
