local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
local first=assert(string.find(source,"dofile('Core.lua')",1,true));assert(loadstring(string.sub(source,1,first-1)))()
local methods=getmetatable(UIParent).__index
for _,name in ipairs({'SetNumeric','SetAutoFocus','SetJustifyV'}) do methods[name]=function() end end
local toc=assert(io.open('OctoGuide-downloads.toc'))
for line in toc:lines() do if string.find(line,'%.lua$') then dofile(line) end end;toc:close()
local G=OctoGuide
local scan=G.ScanCharacter;local scans=0
G.ScanCharacter=function() scans=scans+1;return scan() end
G.Init();assert(G.ready and G.version=='0.6.7')
local settings=G.options;local automation=settings.automationPanel
assert(automation and not automation:IsShown() and settings.height==650)
settings.automationButton.scripts.OnClick();assert(automation:IsShown())
for _,b in ipairs(automation.automationRows) do
 assert(string.find(b.value,'[OFF]',1,true));this=b;b.scripts.OnClick();assert(G.db[b.optionKey]==true and string.find(b.value,'[ON]',1,true));b.scripts.OnClick();assert(G.db[b.optionKey]==false)
 assert(b.point[4]+b.width<automation.width and -b.point[5]+b.height<automation.height)
end
G.Event('BAG_UPDATE');G.Event('QUEST_LOG_UPDATE');assert(scans==0,'Full scan must not run during startup events')
G.ToggleMenu();local row=G.menu.rows[1];assert(row.guideID)
this=row;row.scripts.OnClick();assert(G.stepBrowser and G.stepBrowser:IsShown())
local p=G.stepBrowser;assert(table.getn(p.steps)>1);p.input:SetText('2');p.go.scripts.OnClick()
assert(G.Current().id==p.steps[2].id);G.Back();assert(G.Current().id==p.steps[1].id)
for _,ev in ipairs({'SPELLS_CHANGED','SKILL_LINES_CHANGED','LEARNED_SPELL_IN_TAB','TRAINER_SHOW','TRAINER_UPDATE'}) do assert(G.events.events[ev],'Actual integration must subscribe to '..ev) end
local trained=false
function IsSpellKnown(id) return trained and id==5116 end
G.RegisterGuide({id='manifest-training',title='Training events',faction='Horde'},{{id='learn',action='train',text='Train Concussive Shot',spellID=5116,manual=true},{id='after',action='note',text='Continue',manual=true}})
G.Select('manifest-training');assert(G.Current().id=='learn');trained=true
event='SPELLS_CHANGED';G.events.scripts.OnEvent();assert(G.Current().id=='after','Actual release callback must continue after learning')
print('PASS complete release TOC, new modules, actual guide row / Go / Back callbacks')
