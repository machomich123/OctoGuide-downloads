local G=OctoGuide
G.windows={}
function G.PrepareWindow(p,key)
 if p.windowReady then return end
 if p.headerClose then p.headerClose:Hide() end
 if p.title and p.title.SetWidth then p.title:SetWidth(p:GetWidth()-75) end
 if p.SetClampedToScreen then p:SetClampedToScreen(true) end
 p.windowReady=true;table.insert(G.windows,p);G.MakeMovable(p,key)
 if not p.panelSkin then p.panelSkin=G.CreatePanelSkin(p) end
 local close=G.MakeButton(p,'X',26,function()p:Hide()end);p.closeIcon=close
 close:SetHeight(26);close:SetPoint('TOPRIGHT',p,'TOPRIGHT',-10,-10);G.StyleControl(close,'Close')
 if close.SetFrameLevel and p.GetFrameLevel then close:SetFrameLevel(p:GetFrameLevel()+25) end
 local grip=CreateFrame('Frame',nil,p);p.windowGrip=grip;grip:SetWidth(20);grip:SetHeight(20);grip:SetPoint('BOTTOMRIGHT',p,'BOTTOMRIGHT',0,0);grip:EnableMouse(true)
 if grip.SetFrameLevel and p.GetFrameLevel then grip:SetFrameLevel(p:GetFrameLevel()+25) end
 local mark=grip:CreateTexture(nil,'OVERLAY');mark:SetAllPoints(grip);mark:SetTexture('Interface\\AddOns\\OctoGuide-downloads\\Assets\\Control054Grip')
 grip:SetScript('OnMouseDown',function()
  if arg1 and arg1~='LeftButton' then return end
  if not GetCursorPosition then return end
  local x,y=GetCursorPosition();p.windowDrag={x=x,y=y,scale=p:GetScale(),effective=p:GetEffectiveScale(),width=p:GetWidth(),height=p:GetHeight()}
 end)
 grip:SetScript('OnUpdate',function()
  local d=p.windowDrag;if not d then return end
  local x,y=GetCursorPosition();local factor=math.max(.6,math.min(1.6,1+((x-d.x)-(y-d.y))/(d.effective*(d.width+d.height))))
  local scale=math.max(.4,math.min(1.8,d.scale*factor));p:SetScale(scale)
  G.db.windowScales=G.db.windowScales or {};G.db.windowScales[key]=scale
 end)
 grip:SetScript('OnMouseUp',function()p.windowDrag=nil end)
 local saved=G.db.windowScales and G.db.windowScales[key];if type(saved)=='number' then p:SetScale(math.max(.4,math.min(1.8,saved))) end
 p:SetScript('OnHide',function()p.windowDrag=nil end)
 p:SetScript('OnShow',function()if p.title then p.title:SetWidth(p:GetWidth()-75) end;G.LayoutPanelSkin(p.panelSkin,p:GetWidth(),p:GetHeight(),p);G.ApplyOpacity()end)
end
local opacity=G.ApplyOpacity
function G.ApplyOpacity()
 opacity()
 local alpha=G.db.transparent and math.max(.1,math.min(1,(G.db.opacity or 55)/100)) or 1
 for _,p in ipairs(G.windows) do
  p:SetBackdropColor(.025,.045,.075,.95*alpha)
  for _,t in ipairs(p.panelSkin or {}) do if t.SetAlpha then t:SetAlpha(alpha) end end
 end
end
local build=G.BuildUI
function G.BuildUI()
 build()
 for _,entry in ipairs({{G.menu,'guides'},{G.options,'settings'},{G.options and G.options.automationPanel,'automation'},{G.arrowSettings,'arrow'},{G.professionPanel,'professions'}}) do if entry[1] then G.PrepareWindow(entry[1],entry[2]) end end
 local p=G.professionPanel
 if p then for _,key in ipairs({'editor','sources','locations'}) do if p[key] then G.PrepareWindow(p[key],'profession-'..key) end end end
 local card=G.MakeCard
 local serial=0
 G.MakeCard=function(parent)
  local panel=card(parent);serial=serial+1;G.PrepareWindow(panel,'extra-'..serial);return panel
 end
 G.ApplyOpacity()
end


local zoom=G.ApplyZoom
function G.ApplyZoom()
 zoom()
 local saved=G.db.windowScales and G.db.windowScales.guides
 if saved and G.menu then G.menu:SetScale(saved) end
end
