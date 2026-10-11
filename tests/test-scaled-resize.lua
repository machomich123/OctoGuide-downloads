dofile('tests/test-runtime.lua')
local G=OctoGuide;local f=G.frame;local cx,cy=500,600
function GetCursorPosition() return cx,cy end
function f:GetEffectiveScale() return self.scale*UIParent:GetEffectiveScale() end
function f:GetPoint() return unpack(self.point) end
local function cornerPosition(corner)
 local p,r,rp,x,y=f:GetPoint()
 local ax=string.find(p,'LEFT',1,true) and 0 or (string.find(p,'RIGHT',1,true) and 1 or .5)
 local ay=string.find(p,'BOTTOM',1,true) and 0 or (string.find(p,'TOP',1,true) and 1 or .5)
 local xx=string.find(corner,'LEFT',1,true) and 0 or 1
 local yy=string.find(corner,'BOTTOM',1,true) and 0 or 1
 return x*r:GetEffectiveScale()+(xx-ax)*f:GetWidth()*f:GetEffectiveScale(),y*r:GetEffectiveScale()+(yy-ay)*f:GetHeight()*f:GetEffectiveScale()
end
local opposites={TOPLEFT='BOTTOMRIGHT',TOPRIGHT='BOTTOMLEFT',BOTTOMLEFT='TOPRIGHT',BOTTOMRIGHT='TOPLEFT'}
local count=0
for _,parentScale in ipairs({.8,1,1.25}) do
 UIParent:SetScale(parentScale)
 for _,zoom in ipairs({30,60,75,100,150}) do
  G.SetZoom(zoom)
  for corner,opposite in pairs(opposites) do
   G.db.view='minimal';G.db.widths={minimal=460};G.db.heights={minimal=800};G.Render()
   f:ClearAllPoints();f:SetPoint('CENTER',UIParent,'CENTER',5,10)
   local h=f.resizeHandles[corner];assert(math.abs(h.width*zoom/100-24)<.0001)
   local beforeX,beforeY=cornerPosition(opposite);local width=f.width;local height=f.height
   cx=500;cy=600;this=h;arg1='LeftButton';h.scripts.OnMouseDown();G.UpdateResize()
   assert(f.point[4]==5 and f.point[5]==10,'Mouse-down must not jump at low zoom')
   cx=cx+(string.find(corner,'LEFT',1,true) and -30 or 30)
   cy=cy+(string.find(corner,'BOTTOM',1,true) and -20 or 20)
   G.UpdateResize();local afterX,afterY=cornerPosition(opposite)
   assert(math.abs(beforeX-afterX)<.0001 and math.abs(beforeY-afterY)<.0001,'Opposite corner must remain fixed')
   assert(math.abs(f.width-width-30/f:GetEffectiveScale())<.0001 and math.abs(f.height-height-20/f:GetEffectiveScale())<.0001,'Resize must follow cursor in physical pixels')
   this=h;h.scripts.OnMouseUp();assert(not G.resizing and not G.resizeDrag)
   count=count+1
  end
 end
end
assert(f.title.width>=140 and f.version.point[5]==-43 and f.route.height==30)
print('PASS '..count..' corner/zoom/parent-scale combinations, no initial jump, cursor tracking and full title width')
