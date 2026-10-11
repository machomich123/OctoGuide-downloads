dofile('tests/test-runtime.lua')
local G=OctoGuide
local originalCreate=CreateFrame
function CreateFrame(...)
 local f=originalCreate(unpack(arg));local original=f.SetPoint
 function f:SetPoint(point,relative,relativePoint,x,y)
  assert(type(point)=='string' and type(relativePoint)=='string' and type(x)=='number' and type(y)=='number','native SetPoint usage')
  original(self,point,relative,relativePoint,x,y)
 end
 return f
end
for _,bad in ipairs({{},{'CENTER',5,10},{'CENTER','CENTER','bad',10},{'BAD','CENTER',5,10},true}) do
 G.db.position=bad;G.ready=false;G.Init()
 assert(G.ready and G.frame.arrow and G.frame.version)
 for i=1,4 do this=G.frame.mode;this.scripts.OnClick();G.UpdateArrow() end
end
G.db.position={'TOPLEFT','TOPLEFT',50,-80};G.ready=false;G.Init()
assert(G.frame.point[1]=='TOPLEFT' and G.frame.point[4]==50)
function G.frame:GetPoint() return 'BOTTOMLEFT','BOTTOMLEFT',25,40 end
assert(G.SavePosition(G.frame) and G.db.position[2]=='BOTTOMLEFT' and G.db.position[3]==25 and G.db.position[4]==40)
function G.frame:GetPoint() return 'CENTER',UIParent,'CENTER',15,20 end
assert(G.SavePosition(G.frame) and G.db.position[3]==15 and G.db.position[4]==20)
local frame=G.frame;G.frame={IsShown=function() return true end};G.UpdateArrow();G.Render();G.frame=frame
print('PASS malformed saved position recovery, native SetPoint validation, both GetPoint shapes and repeated view switching')
