local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
local first=assert(string.find(source,"dofile('Core.lua')",1,true));assert(loadstring(string.sub(source,1,first-1)))()
local methods=getmetatable(UIParent).__index
for _,name in ipairs({'SetNumeric','SetAutoFocus','SetJustifyV'}) do methods[name]=function() end end
local toc=assert(io.open('OctoGuide-downloads.toc'))
for line in toc:lines() do if string.find(line,'%.lua$') then dofile(line) end end;toc:close()
local G=OctoGuide
G.Init();assert(G.ready and G.version=='0.5.7')
G.ToggleMenu();local row=G.menu.rows[1];assert(row.guideID)
this=row;row.scripts.OnClick();assert(G.stepBrowser and G.stepBrowser:IsShown())
local p=G.stepBrowser;assert(table.getn(p.steps)>1);p.input:SetText('2');p.go.scripts.OnClick()
assert(G.Current().id==p.steps[2].id);G.Back();assert(G.Current().id==p.steps[1].id)
print('PASS complete release TOC, new modules, actual guide row / Go / Back callbacks')
