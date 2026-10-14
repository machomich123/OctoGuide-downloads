dofile('tests/test-runtime.lua');dofile('TravelNotes.lua')
local G=OctoGuide;G.db.progress={};G.db.completedQuests={};G.db.placements={};G.pauseAuto=false;G.Render=function()end
local travel={id='swim',action='travel',text='Swim to the main island',zone=1,x=.1,y=.1}
local quest={id='work',action='complete',text='Work on Zalazane at the island.',questID=826,zone=1,x=.3,y=.3}
G.RegisterGuide({id='swim-test',faction='Horde'},{travel,quest,{id='boat',action='boat',text='Take the boat',manual=true}})
testQuestLog[826]={complete=false};G.db.placements['swim-test']={stepID='swim',reason='restore'};G.Select('swim-test','restore')
assert(G.Current()==quest,'Saved swim cursor must expose quest without Done')
local title,body=G.Present(G.Current());assert(title=='Zalazane' and string.find(body,'Swim to the main island',1,true))
assert(not G.PreviewStep(travel),'Travel advice must not also appear as a separate upcoming task')
local yards=457
OctoGuideNavigation={ReadWaypoint=function(p)assert(p==travel);return {yards=yards}end}
assert(G.RawNavTarget()==travel and not G.db.progress[G.Key(quest)],'Approach waypoint preserved without completing quest')
yards=10;assert(G.RawNavTarget()==quest and G.db.progress[G.Key(travel)]=='observed','Arrow moves to quest after reaching approach')
assert(G.Current()==quest and not G.db.progress[G.Key(quest)])
testQuestLog[826].complete=1;G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='boat','Actual boat transport is not folded')
local checkpoint={id='road',action='travel',text='Walk to the cave',zone=1,x=.1,y=.1,path={{zone=1,x=.2,y=.2}}}
G.RegisterGuide({id='path-kept',faction='Horde'},{checkpoint,{id='q',action='complete',text='Quest',questID=900,zone=1,x=.3,y=.3}})
assert(not G.FoldedTravel(checkpoint),'Explicit route checkpoints remain independent')
local cross={id='cross',action='travel',text='Travel to another zone',zone=1,x=.1,y=.1}
G.RegisterGuide({id='cross-kept',faction='Horde'},{cross,{id='q',action='accept',text='Quest',questID=901,zone=2,x=.3,y=.3}})
assert(not G.FoldedTravel(cross),'Cross-zone transport must not be guessed away')
local privateFile=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE')
if privateFile then
 G.testAllProfiles=true;dofile(privateFile)
 local n=0
 for _,g in pairs(G.guides)do for _,s in ipairs(g.steps)do if g.routeFamily=='rxp' and s.text=='Swim to the main island'then
  n=n+1;assert(s.travelFor and s.travelFor.questID and table.getn(s.travelFor.travelLeadins)>0,'Actual family swim attached to quest')
 end end end
 assert(n==4,'All four race/mode variants covered')
end
print('PASS swim under quest, existing cursor, approach arrow, real transport/checkpoint preservation and all four family variants')
