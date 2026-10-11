dofile('tests/test-update-051.lua')
local G=OctoGuide
OctoGuideClosestLivingUnit=nil
local step={id='cactus',action='objective',questID=902,objective=1,zone=1,x=.5,y=.5}
G.TargetEntries=function() return {{id=18001,kind='object'}} end
local west,north,facing,now=1000,-4000,0,0
function UnitPosition(token) if token=='player' then return west,north,0,1 end;return 1000,-3993,0,1 end
function GetPlayerFacing() return facing end
function GetTime() return now end
function ClosestGameObjectPosition(id) assert(id==18001);return -3996,1000,4 end
local r=G.ReadObservedTarget(step)
assert(r and math.abs(r.yards-4)<.001,'Object raw x/y must be normalized against UnitPosition y/x')
G.secondaryPoll={};r=G.SecondaryRead(step);facing=1;west=1001
local changed=G.SecondaryRead(step)
assert(changed and math.abs(changed.angle-r.angle)>.5 and changed.yards>4,'Cached targets must still follow current facing and position')
function ClosestGameObjectPosition() return 1000,-3996,4 end
assert(not G.ReadObservedTarget(step),'Inconsistent API distance must not create 5500-yard observed target')
G.TargetEntries=function() return {{id=3098,kind='monster'}} end
C_NamePlate={GetNamePlates=function() return {{},{}} end}
function UnitCreatureID(token) if token=='nameplate1' or token=='nameplate2' then return 3098 end end
function UnitHealth(token) return token=='nameplate1' and 0 or 20 end
function UnitIsDeadOrGhost(token) return token=='nameplate1' end
local mob=G.ReadObservedTarget(step)
assert(mob and mob.token=='nameplate2' and mob.label=='Live quest target','Nearest eligible observed mob excludes dead nameplate')
function UnitStandState() return 0 end
step.questID=5441;testQuestLog[5441]={objectives={{'Peons: 0 / 5',false}}}
assert(not G.ReadObservedTarget(step),'Awake peons excluded')
function UnitStandState() return 3 end
assert(G.ReadObservedTarget(step),'Sleeping peon included')
for _,action in ipairs({'level','vendor','auction','note'}) do assert(not G.PreviewStep({action=action}),'Utility action must not be a route preview') end
assert(G.PreviewStep({action='turnin',questID=99}) and G.PreviewStep({action='fly'}))
print('PASS 0.5.3 object axes, distance validation, frame-current secondary bearing, living nameplates, sleeping peons and purposeful previews')
