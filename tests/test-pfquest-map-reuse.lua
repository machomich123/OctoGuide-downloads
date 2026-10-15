local current={action='accept',questID=894}
OctoGuide={db={},ready=true,Current=function()return current end}
local G=OctoGuide;local created=0
function CreateFrame()created=created+1;return {SetScript=function()end}end
local f={defsize=14,node={Sam={questid=894,QTYPE='NPC_START'}},texture='native',position='native',hidden=true}
function f:SetWidth(n)self.width=n end
function f:SetHeight(n)self.height=n end
pfMap={pins={f},mpins={},UpdateNode=function(self,frame,node)frame.defsize=14;frame.node=node end}
dofile('Map.lua');G.BuildMaps();G.UpdateMaps();assert(created==1 and f.width==17.5)
for i=1,5 do pfMap:UpdateNode(f,{Sam={questid=894,QTYPE='NPC_START'}}) end
assert(f.defsize==17.5 and f.texture=='native' and f.position=='native' and f.hidden,'No duplicate frames, compounding, texture, visibility or movement changes')
pfMap.highlight='Sam';pfMap.highlightdb={[f]={Sam=true}};f.width=30;G.UpdateMaps();assert(f.width==30,'Native hover animation retained')
pfMap.highlight=nil;current={action='accept',questID=999};G.UpdateMaps();assert(f.defsize==14)
current={action='accept',questID=894};G.UpdateMaps();assert(f.defsize==17.5)
pfMap:UpdateNode(f,{Other={questid=999,QTYPE='NPC_START'}});assert(f.defsize==14,'Recycled pin restored')
pfMap:UpdateNode(f,{Sam={questid=894,QTYPE='NPC_START'}});G.SetMapOption('targets',false);assert(f.defsize==14)
print('PASS native pfQuest frame reuse, size restoration, recycling, hover, movement, visibility and no duplicate icons')
