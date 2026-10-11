local G=OctoGuide
local art='Interface\\AddOns\\OctoGuide-downloads\\Assets\\'
function G.StyleButton(b)
 if not b or not b.surface then return end
 if b.restyled then b.restyled('ButtonNormal');return end
 b.surface:Hide();b.parts={}
 for i=1,3 do b.parts[i]=b:CreateTexture(nil,'ARTWORK') end
 local function state(name)
  local w,h=b:GetWidth(),b:GetHeight();local control=w<80
  local cap=control and 4 or math.min(h*4*.15,w*.18)
  for i,t in ipairs(b.parts) do
   t:ClearAllPoints();local x=i==1 and 0 or i==2 and cap or w-cap
   t:SetPoint('LEFT',b,'LEFT',x,0);t:SetWidth(i==2 and math.max(.1,w-2*cap) or cap);t:SetHeight(h)
   local suffix=name=='ButtonHover' and 'Hover' or name=='ButtonPressed' and 'Pressed' or 'Normal'
   t:SetTexture(art..'Button053'..suffix)
   if control then
    -- Crop the fine border without squeezing the wide decorative endcaps.
    t:SetTexCoord(i==1 and .20 or i==2 and .49 or .79,i==1 and .21 or i==2 and .51 or .80,0,1)
   else t:SetTexCoord(i==1 and 0 or i==2 and .49 or .85,i==1 and .15 or i==2 and .51 or 1,0,1) end
  end
 end
 b.restyled=state
 b:SetScript('OnMouseDown',function() state('ButtonPressed') end)
 b:SetScript('OnMouseUp',function() state('ButtonNormal') end)
 b:SetScript('OnEnter',function() state('ButtonHover') end)
 b:SetScript('OnLeave',function() state('ButtonNormal') end)
 state('ButtonNormal')
end
function G.MakeMovable(p,key)
 p:EnableMouse(true);p:SetMovable(true);p:RegisterForDrag('LeftButton')
 p:SetScript('OnDragStart',function() p:StartMoving() end)
 p:SetScript('OnDragStop',function()
  p:StopMovingOrSizing()
  local left,bottom=p:GetLeft(),p:GetBottom()
  if type(left)=='number' and type(bottom)=='number' then G.db.windowPositions=G.db.windowPositions or {};G.db.windowPositions[key]={left,bottom};p:ClearAllPoints();p:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',left,bottom) end
 end)
 local saved=G.db.windowPositions and G.db.windowPositions[key]
 if saved and type(saved[1])=='number' and type(saved[2])=='number' and math.abs(saved[1])<100000 and math.abs(saved[2])<100000 then p:ClearAllPoints();p:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',saved[1],saved[2]) end
end
local build=G.BuildUI
function G.BuildUI()
 if G.db.compactLayoutVersion~=2 then G.db.heights={};G.db.compactLayoutVersion=2 end
 build()
 local f=G.frame;G.MakeMovable(G.menu,'guides');G.MakeMovable(G.options,'settings')
 f.controlsToggle=G.MakeButton(f,'v',44,function() G.db.controlsCollapsed=not G.ControlsCollapsed();if G.db.heights then G.db.heights[G.db.view]=nil end;G.Render() end)
 local skip=G.MakeButton(G.menu,'Skip current step',150,function() G.Mark('skipped');G.Sync();G.Render();G.menu:Hide() end)
 G.menu.skipCurrent=skip;G.Place(skip,G.menu,25,465);G.menu:SetHeight(555)
 -- Move pagination down to keep the separate recovery action out of the main guide.
 for _,b in ipairs(G.menu.pageButtons or {}) do G.Place(b,G.menu,b.pageX,515) end
 G.LayoutPanelSkin(G.menu.panelSkin,G.menu:GetWidth(),G.menu:GetHeight(),G.menu)
 f.close:ClearAllPoints();f.close:SetPoint('TOPRIGHT',f,'TOPRIGHT',-24,-8);f.close:SetWidth(34);f.close.width=34;f.close:SetHeight(30);f.controlsToggle:SetHeight(30)
 G.options.modeButton=G.MakeButton(G.options,'',135,function() G.SetMode(G.Mode()=='hardcore' and 'normal' or 'hardcore');G.RenderSettings() end);G.Place(G.options.modeButton,G.options,245,522)
 f.arrow:SetWidth(55);f.arrow:SetHeight(55);f.secondaryArrow:SetWidth(25);f.secondaryArrow:SetHeight(25)
 for _,p in ipairs({G.menu,G.options}) do for _,b in ipairs(p.rows or {}) do G.StyleButton(b) end end
 for _,b in ipairs({f.back,f.skip,f.done,f.menu,f.mode,f.settingsButton,f.close,f.controlsToggle,f.routeMode,G.menu.levelButton,G.options.partyButton,G.options.secondaryButton,G.options.transparentButton,G.options.bugButton,G.options.smaller,G.options.wider,G.options.close}) do G.StyleButton(b) end
 -- Buttons are styled at construction too, including page and report controls.
end
local button=G.MakeButton
function G.MakeButton(...)
 local b=button(unpack(arg));if b.width and b.width>=49 and b.width<104 then b.width=104;b:SetWidth(104);b.label:SetWidth(88) end;G.StyleButton(b);return b
end
function G.ControlsCollapsed()
 if G.db.controlsCollapsed~=nil then return G.db.controlsCollapsed end
 return G.db.view=='minimal'
end
function G.StepButton(s)
 if not s then return 'Next' end
 if s.optionalSupply or s.action=='accept' or s.action=='complete' or s.action=='objective' or s.action=='turnin' then return 'Skip' end
 return 'Done'
end
