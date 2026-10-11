dofile('tests/test-update-051.lua')
local G=OctoGuide
assert(G.frame.secondaryArrow.parent==G.frame.currentCard)
assert(G.frame.secondaryText.parent==G.frame.currentCard)
assert(G.frame.targetEvidence.parent==G.frame.currentCard)
for _,alpha in ipairs({.1,.55,1}) do
 G.db.backgroundOpacity=alpha;G.ApplyOpacity()
 assert(G.frame.secondaryArrow.alpha==1 and G.frame.secondaryText.alpha==1)
end
assert(not G.options.reportHint:IsShown())
assert(G.frame.close.controlType=='Close' and not G.frame.close.label:IsShown())
assert(G.frame.controlsToggle.controlType=='Toggle' and not G.frame.controlsToggle.label:IsShown())
function UnitStandState() return 0 end
C_UnitAuras={GetAuraDataByIndex=function(token,i,filter) if i==1 and filter=='HELPFUL' then return {spellId=17743} end end}
assert(G.UnitEligibleForStep({questID=5441},'target'),'Sleep aura accepts standing animation')
C_UnitAuras.GetAuraDataByIndex=function() return nil end
function UnitStandState() return 3 end
assert(not G.UnitEligibleForStep({questID=5441},'target'),'Known absent sleep rejects awake peons')
C_UnitAuras.GetAuraDataByIndex=function(token,i) if i==1 then return {spellId=12345} end end
assert(G.UnitEligibleForStep({targetAura=12345},'target'))
C_UnitAuras=nil
assert(G.UnitEligibleForStep({questID=5441},'target'))
print('PASS 0.5.4 foreground layers, independent opacity, hidden notice, framed controls and reusable aura targeting')

local a={id='stable-a',action='objective',questID=701};local b={id='stable-b',action='objective',questID=702}
local da,db,now=10,11,0
G.db.secondaryArrow=true;G.secondaryChoice=nil
G.Concurrent=function() return {a,b} end
G.SecondaryRead=function(s) return {yards=s==a and da or db,label='Observed quest object'} end
G.QuestIndex=function() return 1 end
G.Satisfied=function() return false end
GetTime=function() return now end
assert(G.SecondaryTarget(a)==a)
now=1;da=11;db=10;assert(G.SecondaryTarget(a)==a,'Near tie retains previous valid target')
now=2;da=20;db=5;assert(G.SecondaryTarget(a)==b,'Meaningfully closer target switches')
now=3;G.Concurrent=function() return {a} end;assert(G.SecondaryTarget(a)==a,'Removed target cannot remain sticky')
print('PASS stable secondary choice at near ties, closer target switching and invalid target removal')
