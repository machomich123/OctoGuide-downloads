local G=OctoGuide
local art='Interface\\AddOns\\OctoGuide-downloads\\Assets\\'
local function point(o,p,x,y) G.Place(o,p,x,y) end
local function heading(p,text,x,y,w)
 local t=G.MakeLabel(p,11,w or 310,true);point(t,p,x,y);t:SetHeight(20);t:SetText(text);return t
end
local function skin(p)
 p.panelSkin=G.CreatePanelSkin(p)
 G.LayoutPanelSkin(p.panelSkin,p:GetWidth(),p:GetHeight(),p)
end
local function sliderStyle(slider,width)
 slider:SetBackdrop(nil)
 local track=slider:CreateTexture(nil,'BACKGROUND');track:SetTexture('Interface\\Buttons\\WHITE8X8');track:SetWidth(width);track:SetHeight(4);track:SetPoint('CENTER',slider,'CENTER',0,0)
 if track.SetVertexColor then track:SetVertexColor(.28,.32,.38,1) end
 if slider.GetThumbTexture then local thumb=slider:GetThumbTexture();if thumb then thumb:SetWidth(24);thumb:SetHeight(24);thumb:SetTexture(art..'Control054Grip') end end
end
function G.BuildMenus()
 local p=G.menu;skin(p)
 p.title:SetText('Leveling guides');point(p.title,p,25,24)
 p.info:SetWidth(230);point(p.info,p,195,57)
 point(p.levelButton,p,25,54)
 for i,row in ipairs(p.rows) do row:SetWidth(410);row:SetHeight(25);point(row,p,25,87+(i-1)*27) end
end
function G.ApplyOpacity()
 local alpha=G.db.transparent and math.max(.1,math.min(1,(G.db.opacity or 55)/100)) or 1
 local function texture(t) if t and t.SetAlpha then t:SetAlpha(alpha) end end
 if G.frame then
  texture(G.frame.bg)
  for _,t in ipairs({G.frame.secondaryArrow,G.frame.secondaryText,G.frame.targetEvidence}) do if t.SetAlpha then t:SetAlpha(1) end end
  for _,t in ipairs(G.frame.skin or {}) do texture(t) end
  for _,t in ipairs(G.frame.header or {}) do texture(t) end
  for _,c in ipairs({G.frame.currentCard,G.frame.nextCard}) do c:SetBackdropColor(.025,.045,.075,.95*alpha) end
  for _,list in ipairs({G.frame.objectives,G.frame.nextRows}) do for _,c in ipairs(list) do c:SetBackdropColor(.025,.045,.075,.95*alpha) end end
 end
 for _,p in ipairs({G.menu,G.options}) do
  if p then p:SetBackdropColor(.025,.045,.075,.95*alpha);for _,t in ipairs(p.panelSkin or {}) do texture(t) end end
 end
end
function G.SetOpacity(value)
 local n=tonumber(value);if not n then return false end
 G.db.opacity=math.floor(math.max(10,math.min(100,n))+.5);G.ApplyOpacity()
 if G.options.opacityLabel then G.options.opacityLabel:SetText('Background opacity: '..G.db.opacity..'%') end
 return true
end
function G.UpgradeSettings()
 local p=G.options;p:SetWidth(410);p:SetHeight(650);skin(p)
 p.solidBackground:Hide();p.title:SetText('OctoGuide settings');p.title:SetWidth(360);point(p.title,p,25,25)
 heading(p,'MAP AND PARTY',25,65)
 for i,b in ipairs(p.rows) do b:SetWidth(360);b.label:SetWidth(344);point(b,p,25,90+(i-1)*33) end
 p.partyButton:SetWidth(360);p.partyButton.label:SetWidth(344);point(p.partyButton,p,25,222)
 p.info:Hide();heading(p,'APPEARANCE AND NAVIGATION',25,265,360)
 p.secondaryButton=G.MakeButton(p,'',360,function() G.db.secondaryArrow=not G.db.secondaryArrow;if G.db.heights then G.db.heights[G.db.view]=nil end;G.RenderSettings();G.Render() end);point(p.secondaryButton,p,25,291)
 p.transparentButton=G.MakeButton(p,'',360,function() G.db.transparent=not G.db.transparent;G.ApplyOpacity();G.RenderSettings() end);point(p.transparentButton,p,25,324)
 p.opacityLabel=heading(p,'',25,362,360)
 local slider=CreateFrame('Slider',nil,p);p.opacitySlider=slider;slider:SetWidth(355);slider:SetHeight(18);point(slider,p,27,389);slider:EnableMouse(true)
 if slider.SetOrientation then slider:SetOrientation('HORIZONTAL') end
 if slider.SetMinMaxValues then slider:SetMinMaxValues(10,100);slider:SetValueStep(1);slider:SetThumbTexture(art..'ButtonNormal');slider:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});slider:SetBackdropColor(.18,.23,.29,1);slider:SetValue(G.db.opacity or 55) end
 slider:SetScript('OnValueChanged',function() G.SetOpacity(slider:GetValue()) end)
 sliderStyle(slider,355)
 point(p.zoomLabel,p,25,424);point(p.zoomField,p,315,421);point(p.zoomSlider,p,27,462);p.zoomSlider:SetWidth(355);point(p.zoomHint,p,25,488);p.zoomHint:SetWidth(360)
 sliderStyle(p.zoomSlider,355)
 point(p.smaller,p,25,522);point(p.wider,p,135,522);point(p.close,p,305,594)
 p.bugButton=G.MakeButton(p,'Report bug',150,function() G.ShowReport() end);point(p.bugButton,p,25,565)
 p.bugButton.icon=p.bugButton:CreateTexture(nil,'OVERLAY');p.bugButton.icon:SetTexture(art..'BugIcon');p.bugButton.icon:SetWidth(18);p.bugButton.icon:SetHeight(18);p.bugButton.icon:Hide();point(p.bugButton.icon,p.bugButton,8,4)
 p.bugButton.label:SetWidth(142);p.bugButton.label:ClearAllPoints();p.bugButton.label:SetPoint('CENTER',p.bugButton,'CENTER',0,0)
 p.reportHint=heading(p,'Diagnostics saved locally; online upload unavailable.',25,602,265);p.reportHint:SetHeight(30);p.reportHint:Hide()
 local f=G.frame
 f.secondaryArrow=f.currentCard:CreateTexture(nil,'OVERLAY');f.secondaryArrow:SetTexture(art..'Arrow');f.secondaryArrow:SetWidth(20);f.secondaryArrow:SetHeight(20);f.secondaryArrow:Hide()
 f.secondaryText=G.MakeLabel(f.currentCard,10,95);f.secondaryText:SetHeight(24);f.secondaryText:Hide()
 f.targetEvidence=G.MakeLabel(f.currentCard,9,95);f.targetEvidence:SetHeight(25)
 G.UpdateAppearanceSettings();G.ApplyOpacity()
end
function G.UpdateAppearanceSettings()
 local p=G.options;if not p.secondaryButton then return end
 p.secondaryButton:SetText((G.db.secondaryArrow and '[ON] ' or '[OFF] ')..'Small secondary arrow')
 p.transparentButton:SetText((G.db.transparent and '[ON] ' or '[OFF] ')..'Transparent background')
 p.opacityLabel:SetText('Background opacity: '..(G.db.opacity or 55)..'%')
end
function G.UpdateSecondaryArrow(elapsed)
 local f=G.frame;if not f.secondaryArrow then return end
 f.targetEvidence:ClearAllPoints();f.targetEvidence:SetPoint('TOPLEFT',f.distance,'BOTTOMLEFT',0,-2)
 local target=G.SecondaryTarget and G.SecondaryTarget(G.Current());local r=target and (G.SecondaryRead and G.SecondaryRead(target) or OctoGuideNavigation.ReadWaypoint(target))
 if r and r.angle and f.secondaryArrow.SetRotation then
  local angle=r.angle
  if elapsed and f.secondaryAngle then local delta=math.mod(angle-f.secondaryAngle+3*math.pi,2*math.pi)-math.pi;angle=f.secondaryAngle+delta*(1-math.exp(-18*math.min(elapsed,.1))) end
  f.secondaryAngle=angle;f.secondaryArrow:SetRotation(-angle);point(f.secondaryArrow,f,f:GetWidth()-80,(G.db.view=='full' and 130 or 66)+108);point(f.secondaryText,f,f:GetWidth()-113,(G.db.view=='full' and 130 or 66)+135)
  local title=G.Present(target);f.secondaryText:SetText('Also: '..title..'\n'..math.floor(r.yards+.5)..' yd | '..(r.label or 'Quest area'));f.secondaryText:SetHeight(55);f.secondaryText:Show();f.secondaryArrow:Show()
 else f.secondaryAngle=nil;f.secondaryArrow:Hide();f.secondaryText:Hide() end
end
function G.ShowReport()
 if G.CaptureReportUI and (not G.reportWindow or not G.reportWindow:IsShown()) then G.CaptureReportUI() end
 if not G.reportWindow then
  local p=G.MakeCard(UIParent);G.reportWindow=p;p:SetWidth(440);p:SetHeight(300);p:SetPoint('CENTER',UIParent,'CENTER',0,0);p:SetFrameStrata('DIALOG');p:EnableMouse(true);skin(p)
  if p.SetFrameLevel and G.options.GetFrameLevel then p:SetFrameLevel(G.options:GetFrameLevel()+10) end
  p.title=heading(p,'Report an OctoGuide problem',25,23,390)
  p.info=heading(p,'Describe what happened and what you expected.',25,53,390)
  local scroll=CreateFrame('ScrollFrame',nil,p);scroll:SetWidth(390);scroll:SetHeight(110);point(scroll,p,25,82)
  scroll:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});scroll:SetBackdropColor(.02,.035,.055,.95)
  local field=CreateFrame('EditBox',nil,scroll);p.field=field;field:SetWidth(374);field:SetHeight(110);point(field,scroll,8,8);scroll:SetScrollChild(field)
  field:SetFont('Fonts\\FRIZQT__.TTF',12,'');if field.SetMultiLine then field:SetMultiLine(true) end;if field.SetAutoFocus then field:SetAutoFocus(false) end;if field.SetMaxLetters then field:SetMaxLetters(2000) end
  scroll:EnableMouse(true);scroll:SetScript('OnMouseDown',function() if field.SetFocus then field:SetFocus() end end)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function() local maximum=math.max(0,field:GetHeight()-94);scroll:SetVerticalScroll(math.max(0,math.min(maximum,(scroll:GetVerticalScroll() or 0)-(arg1 or 0)*24))) end) end
  p.status=G.MakeLabel(p,10,390);point(p.status,p,25,204);p.status:SetHeight(40)
  local send=G.MakeButton(p,'Send',110,function()
   local r,why
   if G.SendReport then r,why=G.SendReport(field:GetText()) else r,why=G.MakeReport(field:GetText()) end
   p.status:SetText(why or (r and ('Saved locally: '..r.id) or 'Unable to save report.'))
   if r then field:ClearFocus() end
  end);point(send,p,25,255)
  local close=G.MakeButton(p,'Close',85,function() p:Hide() end);point(close,p,330,255)
 end
 G.reportWindow:Show();G.ApplyOpacity()
end
