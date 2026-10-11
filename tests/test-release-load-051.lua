-- Load the actual release manifest, not a manually selected module subset.
local file=assert(io.open('tests/test-runtime.lua','r'));local source=file:read('*a');file:close()
local first=assert(string.find(source,"dofile('Core.lua')",1,true));assert(loadstring(string.sub(source,1,first-1)))()
local manifest=assert(io.open('OctoGuide-downloads.toc','r'))
for line in manifest:lines() do if string.find(line,'%.lua$') then dofile(line) end end;manifest:close()
local G=OctoGuide
G.Init();assert(G.ready and G.frame.controlsToggle and G.options.scripts.OnDragStop)
G.db.view='minimal';G.db.controlsCollapsed=nil;G.Render();assert(not G.frame.title:IsShown() and not G.frame.done:IsShown())
G.db.view='full';G.Render();assert(G.frame.title:IsShown())
G.ShowReport();assert(G.reportWindow:IsShown())
print('PASS actual 0.5.1 release TOC load, initial route, both views and report form')
