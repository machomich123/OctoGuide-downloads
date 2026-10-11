local G=OctoGuide
local art='Interface\\AddOns\\OctoGuide-downloads\\Assets\\GuideFullV3'
function G.CreatePanelSkin(parent)
 local pieces={}
 for i=1,9 do local t=parent:CreateTexture(nil,'BORDER');t:SetTexture(art);pieces[i]=t end
 return pieces
end
function G.LayoutPanelSkin(pieces,w,h)
 -- Slice the existing high resolution art in texture coordinates. Fixed
 -- corners are never stretched, and the logo is not part of this panel.
 local u={0,.047,.953,1};local v={.14,.171,.54,.571};local x={0,18,w-18,w};local y={0,18,h-18,h}
 local k=0
 for row=1,3 do for col=1,3 do
  k=k+1;local t=pieces[k];t:ClearAllPoints();t:SetPoint('TOPLEFT',G.frame,'TOPLEFT',x[col],-y[row]);t:SetWidth(x[col+1]-x[col]);t:SetHeight(y[row+1]-y[row]);if t.SetTexCoord then if col==1 then t:SetTexCoord(u[4],v[row],u[4],v[row+1],u[3],v[row],u[3],v[row+1]) else t:SetTexCoord(u[col],u[col+1],v[row],v[row+1]) end end
 end end
end
function G.LayoutHeader(f,w)
 local left,center,right=f.header[1],f.header[2],f.header[3]
 local function part(t,x,width,u1,u2)
  t:ClearAllPoints();t:SetPoint('TOPLEFT',f,'TOPLEFT',x,0);t:SetWidth(width);t:SetHeight(92);if t.SetTexCoord then t:SetTexCoord(u1,u2,0,.136) end
 end
 part(left,0,96,0,.212);part(center,96,w-130,.212,.925);part(right,w-34,34,.925,1)
 f.title:ClearAllPoints();f.title:SetPoint('TOPLEFT',f,'TOPLEFT',108,-22);f.title:SetWidth(110)
 f.version:ClearAllPoints();f.version:SetPoint('TOPLEFT',f,'TOPLEFT',222,-30);f.version:SetWidth(50)
 f.route:ClearAllPoints();f.route:SetPoint('TOPLEFT',f,'TOPLEFT',108,-55);f.route:SetWidth(w-134)
end
function G.ApplyZoom()
 local scale=math.max(60,math.min(150,G.db.zoom or 100))/100
 for _,f in ipairs({G.frame,G.menu,G.options}) do if f and f.SetScale then f:SetScale(scale) end end
end
function G.SetZoom(value)
 local n=tonumber(value);if not n then return false end
 G.db.zoom=math.floor(math.max(60,math.min(150,n))+.5);G.ApplyZoom()
 if G.options and G.options.zoomField then
  G.zoomUpdating=true;G.options.zoomField:SetText(tostring(G.db.zoom));if G.options.zoomSlider then G.options.zoomSlider:SetValue(G.db.zoom) end;G.zoomUpdating=false
 end
 return true
end
function G.BuildZoomControls(p,label,point)
 p.solidBackground=p:CreateTexture(nil,'BACKGROUND');p.solidBackground:SetAllPoints(p);p.solidBackground:SetTexture('Interface\\Buttons\\WHITE8X8');if p.solidBackground.SetVertexColor then p.solidBackground:SetVertexColor(.015,.025,.045,1) end
 p.zoomLabel=label(p,12,180,true);point(p.zoomLabel,p,23,300);p.zoomLabel:SetHeight(20);p.zoomLabel:SetText('UI zoom (%)')
 local field=CreateFrame('EditBox',nil,p);p.zoomField=field;field:SetWidth(58);field:SetHeight(25);field:SetPoint('TOPLEFT',p,'TOPLEFT',260,-297)
 if field.SetFont then field:SetFont('Fonts\\FRIZQT__.TTF',12,'') end
 if field.SetAutoFocus then field:SetAutoFocus(false) end
 if field.SetNumeric then field:SetNumeric(true) end
 if field.SetMaxLetters then field:SetMaxLetters(3) end
 field:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=8});field:SetBackdropColor(.02,.03,.05,1)
 if field.SetTextInsets then field:SetTextInsets(8,5,0,0) end
 field:SetText(tostring(G.db.zoom or 100))
 field:SetScript('OnEnterPressed',function() local ok=G.SetZoom(this:GetText());if not ok then this:SetText(tostring(G.db.zoom or 100)) end;this:ClearFocus() end)
 field:SetScript('OnEscapePressed',function() this:SetText(tostring(G.db.zoom or 100));this:ClearFocus() end)
 local slider=CreateFrame('Slider',nil,p);p.zoomSlider=slider;slider:EnableMouse(true);slider:SetWidth(286);slider:SetHeight(18);slider:SetPoint('TOPLEFT',p,'TOPLEFT',25,-340)
 if slider.SetOrientation then slider:SetOrientation('HORIZONTAL') end
 if slider.SetMinMaxValues then slider:SetMinMaxValues(60,150);slider:SetValueStep(1);slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal');slider:SetBackdrop({bgFile='Interface\\Buttons\\UI-SliderBar-Background',edgeFile='Interface\\Buttons\\UI-SliderBar-Border',tile=true,tileSize=8,edgeSize=8});slider:SetValue(G.db.zoom or 100) end
 slider:SetScript('OnValueChanged',function() if not G.zoomUpdating then G.SetZoom(this:GetValue()) end end)
 p.zoomHint=label(p,10,285);point(p.zoomHint,p,25,366);p.zoomHint:SetHeight(18);p.zoomHint:SetText('60% - 150%. Enter a value and press Enter.')
end
function G.BuildResizeHandles(f)
 f.resizeHandles={}
 for _,corner in ipairs({'TOPLEFT','TOPRIGHT','BOTTOMLEFT','BOTTOMRIGHT'}) do
  local h=CreateFrame('Frame',nil,f);h:SetWidth(16);h:SetHeight(16);h:SetPoint(corner,f,corner,0,0);h:EnableMouse(true);h.corner=corner;f.resizeHandles[corner]=h
  if h.SetFrameLevel and f.GetFrameLevel then h:SetFrameLevel(f:GetFrameLevel()+20) end
  h:SetScript('OnMouseDown',function()
   if arg1 and arg1~='LeftButton' then return end
   if not GetCursorPosition then return end
   local cx,cy=GetCursorPosition();local scale=f:GetEffectiveScale()
   G.resizeDrag={handle=this,corner=this.corner,x=cx/scale,y=cy/scale,width=f:GetWidth(),height=f:GetHeight(),left=f:GetLeft(),bottom=f:GetBottom(),scale=scale}
   G.resizing=true
  end)
  h:SetScript('OnUpdate',function() if G.resizeDrag and G.resizeDrag.handle==this then G.UpdateResize() end end)
  h:SetScript('OnMouseUp',function() if G.resizeDrag and G.resizeDrag.handle==this then G.UpdateResize();G.resizeDrag=nil;G.resizing=false;local p,r,rp,x,y=f:GetPoint();G.db.position={p,rp,x,y} end end)
 end
end
function G.UpdateResize()
 local d=G.resizeDrag;if not d or not GetCursorPosition then return end
 local f=G.frame;local cx,cy=GetCursorPosition();local dx,dy=cx/d.scale-d.x,cy/d.scale-d.y
 local left=string.find(d.corner,'LEFT',1,true);local bottom=string.find(d.corner,'BOTTOM',1,true)
 local width=math.max(380,math.min(800,d.width+(left and -dx or dx)))
 local requestedHeight=math.max(160,math.min(1600,d.height+(bottom and -dy or dy)))
 G.db.widths=G.db.widths or {};G.db.heights=G.db.heights or {};G.db.widths[G.db.view]=width;G.db.heights[G.db.view]=requestedHeight
 G.Render(true)
 -- Keep the diagonally opposite corner fixed after text reflow determines
 -- the minimum content height. Coordinates are converted to parent units.
 local x=d.left+(left and d.width-width or 0);local y=d.bottom+(bottom and d.height-f:GetHeight() or 0)
 local ratio=f:GetEffectiveScale()/UIParent:GetEffectiveScale();f:ClearAllPoints();f:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',x*ratio,y*ratio)
end
