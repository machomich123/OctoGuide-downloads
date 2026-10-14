local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
local methods=getmetatable(UIParent).__index
for _,name in ipairs({'SetNumeric','SetAutoFocus','SetJustifyV'})do methods[name]=function()end end
local toc=assert(io.open('OctoGuide-downloads.toc'));for line in toc:lines()do if string.find(line,'%.lua$')then dofile(line)end end;toc:close()
local G=OctoGuide;local messages={};DEFAULT_CHAT_FRAME.AddMessage=function(_,text)table.insert(messages,text)end
OctoGuideDB={progress={preserved='manual'},completedQuests={[786]=true},mode='hardcore'}
local build=G.BuildUI;local builds=0
G.BuildUI=function()builds=builds+1;build();error('Injected constructor failure')end
assert(pcall(G.Init));assert(G.failed and not G.ready and not G.frame:IsShown(),'Partial startup must hide rather than block screen')
assert(G.db.lastFailure.phase=='startup' and string.find(G.db.lastFailure.message,'Injected constructor failure',1,true))
assert(G.db.progress.preserved=='manual' and G.db.completedQuests[786],'Recovery must preserve saved progress')
event='PLAYER_ENTERING_WORLD';G.events.scripts.OnEvent();assert(builds==1,'No duplicate frame construction after failure')
assert(pcall(G.Slash,''));assert(string.find(messages[table.getn(messages)],'Injected constructor failure',1,true),'Slash reports exact failure even when not ready')
G.frame:Show();assert(pcall(G.Slash,'hide'));assert(not G.frame:IsShown())
local originalFrame=G.frame;local close=originalFrame.close.scripts.OnClick;local newer=CreateFrame('Frame');G.frame=newer;originalFrame:Show();newer:Show();close()
assert(not originalFrame:IsShown() and newer:IsShown(),'Close must hide its own frame, even if a newer frame reference exists')
G.frame=originalFrame;G.failed=nil;G.BuildUI=build;G.Init();assert(G.ready and not G.failed and not G.db.lastFailure,'Clean startup can recover while retaining failure history')
assert(table.getn(G.db.failureHistory)==1)
local calls=0;G.UpdateArrow=function()calls=calls+1;error('Injected refresh failure')end
arg1=.016;G.events.scripts.OnUpdate();assert(G.failed and not G.ready and not G.frame:IsShown())
G.events.scripts.OnUpdate();assert(calls==1,'Stop failing refresh loop after one captured failure')
assert(G.db.lastFailure.phase=='refresh' and table.getn(G.db.failureHistory)==2)
assert(pcall(G.Slash,''));assert(string.find(messages[table.getn(messages)],'Injected refresh failure',1,true))
print('PASS protected startup/refresh, saved errors, responsive slash/close, no duplicate frames and preserved progress')
