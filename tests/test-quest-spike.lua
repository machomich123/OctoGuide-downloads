dofile('tests/test-runtime.lua')
local G=OctoGuide
local direct,entries=0,0;local present=false
C_QuestLog.GetLogIndexForQuestID=function()direct=direct+1;return present and 1 or 0 end
C_QuestLog.GetQuestIDForLogIndex=function()entries=entries+1;return 777 end
function GetNumQuestLogEntries()return 25 end
for i=1,1000 do assert(G.QuestIndex(100000+i)==nil) end
assert(direct==1000 and entries==0,'An authoritative negative native result must not scan the whole log')
direct=0
assert(G.RunProtected(function()for i=1,1000 do assert(not G.QuestIndex(777)) end end,'lookup'))
assert(direct==1,'Reuse lookups within one protected event/update')
present=true;assert(G.QuestIndex(777)==1,'No cached result escapes the update boundary')
present=false;direct=0
assert(G.RunProtected(function()
 assert(not G.QuestIndex(777));present=true;G.InvalidateQuestLookup();assert(G.QuestIndex(777)==1)
end,'invalidation'));assert(direct==2,'Quest changes invalidate cached misses')
C_QuestLog.GetLogIndexForQuestID=nil;entries=0
assert(G.QuestIndex(777)==1 and entries==1,'Legacy inverse-only clients still work')
C_QuestLog.GetLogIndexForQuestID=function()error('unsupported')end;assert(G.QuestIndex(777)==1,'Broken native API still falls back')
assert(G.questLookupCache==nil)
print('PASS native misses, operation-local lookup reuse, event invalidation, cache isolation and legacy API fallback')
