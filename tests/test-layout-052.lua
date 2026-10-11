dofile('tests/test-update-051.lua')
local G=OctoGuide
UIParent:SetHeight(900)
G.db.view='minimal';G.db.heights={minimal=1200};G.db.controlsCollapsed=false;G.db.secondaryArrow=false;G.Render()
local expanded=G.frame:GetHeight()
G.frame.controlsToggle.scripts.OnClick()
local collapsed=G.frame:GetHeight()
assert(collapsed<expanded and collapsed==G.frame.contentHeight,'Collapse must remove footer space and saved surplus height')
assert(G.frame.controlsToggle.point[4]==(G.frame:GetWidth()-44)/2,'Toggle centered')
assert(G.frame.close.width==34 and G.frame.controlsToggle.width==44,'Accessible controls')
assert(not G.frame.routeMode:IsShown(),'Mode only in Settings')
G.SecondaryTarget=function() return nil end
G.db.secondaryArrow=true;G.Render();local empty=G.frame:GetHeight()
G.db.secondaryArrow=false;G.Render();assert(G.frame:GetHeight()==empty,'Absent secondary target reserves no height')
G.ShowReport();assert(not G.options.bugButton.icon:IsShown(),'Bug button avoids decorative icon overlap')
G.SourceNotes=function() return {'Use the Blackjack on sleeping Lazy Peons'} end
local t=G.Present({action='use',text='Perform use 16114.',itemID=16114})
assert(not string.find(t,'Perform use',1,true),'Readable item action')
local current=G.Current();G.Concurrent=function() return {{questID=777,text='Complete shared quest'}} end
local _,body=G.Present(current,true);assert(not string.find(body,'Do alongside',1,true),'Preview omits concurrent repetition')
for _,w in ipairs({49,56,65,150}) do
 local b=G.MakeButton(G.frame,'Readable',w,function() end)
 assert(b.parts[1].width<=b:GetWidth()*.18 and b.parts[2].width>=b:GetWidth()*.64,'Compact button keeps a clear text surface')
end
G.db.view='full';G.db.heights={};UIParent:SetHeight(768)
G.db.progress={};G.db.completedQuests={}
G.RegisterGuide({id='layout052',faction='Horde',startLevel=1,endLevel=6,routeFamily='rxp'}, {
 {id='current',action='complete',text='Work on Vile Familiars at cave.',questID=703,sourceBlock=1},
 {id='alongside',action='complete',text='Work on Lazy Peons at trees.',questID=704,sourceBlock=1},
 {id='use',action='use',text='Perform use 16114.',itemID=16114,sourceBlock=1},
 {id='turnin',action='turnin',text='Turn in Vile Familiars to Zureetha.',questID=703},
 {id='next',action='note',text='Next distinct task',manual=true}})
assert(not G.Allowed(G.guides.layout052.steps[3]),'Redundant use folded into tracked objective')
G.Concurrent=function() return {{questID=704,text='Lazy Peons'}} end
G.Select('layout052');G.Render()
assert(G.frame.nextRows[1].title.value=='Turn in Vile Familiars','Concurrent objective not repeated as next task')
assert(G.frame:GetHeight()<=768,'Full layout fits available viewport')
G.db.heights.full=1500;G.Render();assert(G.frame:GetHeight()<=768,'Oversized saved height is clamped')
print('PASS 0.5.2 collapsing height, absent secondary target, centered accessible controls, clear buttons and readable previews')
