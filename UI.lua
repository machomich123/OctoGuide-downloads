local G=OctoGuide
-- Background asset set. '' = shipped V1 (GuideFull/GuideMinimal). Set to 'V3'
-- after GuideFullV3.tga / GuideMinimalV3.tga are added to Assets/.
local OG_BG='V3'
local function label(parent,size,width,gold)
 local t=parent:CreateFontString(nil,'OVERLAY');t:SetFont('Fonts\\FRIZQT__.TTF',size,'');t:SetWidth(width);t:SetJustifyH('LEFT');t:SetTextColor(gold and 1 or .91,gold and .78 or .92,gold and .35 or .94);return t
end
local function point(o,p,x,y) o:ClearAllPoints();o:SetPoint('TOPLEFT',p,'TOPLEFT',x,-y) end
local function height(t,v,w,size)
 t:SetWidth(w);t:SetText(v);t:SetHeight(600)
 local lines=0
 for line in string.gfind(v..'\n','(.-)\n') do lines=lines+math.max(1,math.ceil(string.len(line)/math.max(8,w/(size*.65)))) end
 local h=lines*(size+4)+4
 h=math.max(size+4,h+4);t:SetHeight(h);return h
end
local function card(p)
 local c=CreateFrame('Frame',nil,p);c:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=8,insets={left=4,right=4,top=4,bottom=4}});c:SetBackdropColor(.025,.045,.075,.95);if c.SetBackdropBorderColor then c:SetBackdropBorderColor(.48,.36,.16,.8) end;return c
end
local function button(p,v,w,fn)
 local b=CreateFrame('Button',nil,p);b:SetWidth(w);b:SetHeight(26);b.width=w
 b:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=8,insets={left=3,right=3,top=3,bottom=3}});b:SetBackdropColor(.04,.055,.075,.98)
 b.surface=b:CreateTexture(nil,'ARTWORK');b.surface:SetAllPoints(b)
 local asset='Interface\\AddOns\\OctoGuide-downloads\\Assets\\'
 b.surface:SetTexture(asset..'ButtonNormal')
 b:SetScript('OnMouseDown',function() b.surface:SetTexture(asset..'ButtonPressed') end)
 b:SetScript('OnMouseUp',function() b.surface:SetTexture(asset..'ButtonNormal') end)
 if b.SetBackdropBorderColor then b:SetBackdropBorderColor(.4,.3,.12,.8) end
 b.label=label(b,11,w-8,true);b.label:SetPoint('CENTER',b,'CENTER',0,0);b.label:SetHeight(18);b.label:SetJustifyH('CENTER');if b.label.SetJustifyV then b.label:SetJustifyV('MIDDLE') end
 function b:SetText(value) self.value=value;self.label:SetText(value) end
 b:SetText(v);b:SetScript('OnClick',fn)
 b:SetScript('OnEnter',function() b.surface:SetTexture(asset..'ButtonHover') end)
 b:SetScript('OnLeave',function() b.surface:SetTexture(asset..'ButtonNormal') end)
 if G.StyleButton then G.StyleButton(b) end
 return b
end
G.MakeLabel=label;G.Place=point;G.MakeCard=card;G.MakeButton=button
function G.BuildUI()
 local f=CreateFrame('Frame','OctoGuideFrame',UIParent);G.frame=f;f:SetWidth(460);f:SetHeight(600);f:SetPoint('CENTER',UIParent,'CENTER',0,80);f:SetFrameStrata('MEDIUM');f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
 f:SetScript('OnDragStart',function() this:StartMoving() end)
 f:SetScript('OnDragStop',function() this:StopMovingOrSizing();G.SavePosition(this) end)
 G.RestorePosition(f)
 G.BuildResizeHandles(f)
 f.bg=f:CreateTexture(nil,'BACKGROUND');f.bg:SetAllPoints(f);f.bg:SetTexture('Interface\\AddOns\\OctoGuide-downloads\\Assets\\GuideFullV3');if f.bg.SetTexCoord then f.bg:SetTexCoord(.24,.76,.25,.45) end
 f.skin=G.CreatePanelSkin(f)
 f.header={}
 for i=1,3 do local t=f:CreateTexture(nil,'ARTWORK');t:SetTexture('Interface\\AddOns\\OctoGuide-downloads\\Assets\\GuideFullV3');f.header[i]=t end
 f.title=label(f,21,240,true);point(f.title,f,105,16);f.title:SetHeight(25);f.title:SetText('OctoGuide')
 f.version=label(f,10,50);f.version:SetHeight(14);f.version:SetText('v'..G.version)
 f.route=label(f,10,400);point(f.route,f,22,54);f.route:SetHeight(18)
 f.routeMode=button(f,'Hardcore',78,function() G.SetMode(G.Mode()=='hardcore' and 'normal' or 'hardcore') end)
 f.currentCard=card(f);point(f.currentCard,f,15,78)
 f.section=label(f.currentCard,11,290,true);point(f.section,f,28,87);f.section:SetHeight(18)
 f.icon=f.currentCard:CreateTexture(nil,'ARTWORK');f.icon:SetWidth(29);f.icon:SetHeight(29)
 f.step=label(f.currentCard,17,300,true)
 f.detailsScroll=CreateFrame('ScrollFrame',nil,f.currentCard);f.detailsHost=CreateFrame('Frame',nil,f.detailsScroll);f.detailsScroll:SetScrollChild(f.detailsHost);f.details=label(f.detailsHost,12,300);point(f.details,f.detailsHost,0,0)
 if f.detailsScroll.EnableMouseWheel then f.detailsScroll:EnableMouseWheel(true);f.detailsScroll:SetScript('OnMouseWheel',function() local offset=this.GetVerticalScroll and this:GetVerticalScroll() or 0;this:SetVerticalScroll(math.max(0,math.min(this.maxScroll or 0,offset-(arg1 or 0)*36))) end) end
 f.arrow=f.currentCard:CreateTexture(nil,'ARTWORK');f.arrow:SetTexture('Interface\\AddOns\\OctoGuide-downloads\\Assets\\Arrow');f.arrow:SetWidth(44);f.arrow:SetHeight(44)
 f.distance=label(f.currentCard,12,88,true);f.distance:SetJustifyH('CENTER');f.distance:SetHeight(20)
 f.objectives={}
 for i=1,24 do local row=card(f);row.check=row:CreateTexture(nil,'ARTWORK');row.check:SetWidth(18);row.check:SetHeight(18);point(row.check,row,9,8);row.name=label(row,12,320);row.count=label(row,13,68,true);row.count:SetJustifyH('RIGHT');row.count:SetHeight(20);f.objectives[i]=row end
 f.note=label(f.currentCard,10,400);f.note:SetHeight(28)
 f.nextCard=card(f);f.nextTitle=label(f.nextCard,11,300,true);f.nextTitle:SetHeight(18);f.nextTitle:SetText('NEXT STEPS')
 f.nextRows={};for i=1,3 do local r=card(f);r.number=label(r,15,26,true);r.number:SetHeight(22);point(r.number,r,10,12);r.title=label(r,12,350,true);point(r.title,r,45,10);r.details=label(r,11,330);r.details:SetTextColor(.78,.83,.87);f.nextRows[i]=r end
 f.next=label(f,10,300);f.next:Hide();f.footer=label(f,10,300);f.footer:Hide()
 f.back=button(f,'Back',49,function() G.Back() end)
 f.skip=button(f,'Skip',49,function() G.Mark('skipped');G.Sync();G.Render() end)
 f.done=button(f,'Done',56,function() if G.StepButton and G.StepButton(G.Current())=='Skip' then G.Mark('skipped');G.Sync();G.Render() else G.Advance() end end)
 f.menu=button(f,'Guides',60,function() G.ToggleMenu() end)
 f.mode=button(f,'Expand',66,function() G.db.view=G.db.view=='full' and 'minimal' or 'full';G.Render() end)
 f.settingsButton=button(f,'Settings',65,function() G.ToggleSettings() end)
 f.close=button(f,'X',26,function() G.db.hidden=true;G.frame:Hide() end)
 local menu=card(UIParent);G.menu=menu;menu:SetWidth(460);menu:SetHeight(520);menu:SetPoint('CENTER',UIParent,'CENTER',0,0);menu:SetFrameStrata('DIALOG');if menu.SetFrameLevel and f.GetFrameLevel then menu:SetFrameLevel(f:GetFrameLevel()+30) end;menu:EnableMouse(true)
 menu.title=label(menu,19,400,true);point(menu.title,menu,20,16);menu.title:SetHeight(26);menu.title:SetText('Horde routes')
 menu.info=label(menu,11,420);point(menu.info,menu,180,48);menu.info:SetWidth(260);menu.info:SetHeight(25)
 menu.rows={};for i=1,14 do local row=button(menu,'',420,function() if this.guideID then if G.OpenStepBrowser then G.OpenStepBrowser(this.guideID) else local ok,why=G.Select(this.guideID);if ok then G.frame:Show();G.db.hidden=false;G.menu:Hide() else G.Chat(why) end end end end);point(row,menu,20,78+(i-1)*28);menu.rows[i]=row end
 menu.page=1
 local x=20;menu.pageButtons={}
 for _,spec in ipairs({{'Previous',85,function() menu.page=math.max(1,menu.page-1);G.RenderMenu() end},{'Next',70,function() menu.page=menu.page+1;G.RenderMenu() end},{'Find step',87,function()
   local ok,why
   local find=G.FindStep or G.AutoPlace
   if OctoAddonHealth then ok,why=OctoAddonHealth.Call('OctoGuide',find,false) else ok,why=find(false) end
   if ok then menu:Hide() else G.Chat(why or 'Find step could not select a route. Check /octocheck.');if menu.info then menu.info:SetText(why or 'Find step unavailable. See /octocheck.') end end
 end},{'Close',85,function() menu:Hide() end}}) do local b=button(menu,spec[1],spec[2],spec[3]);point(b,menu,x,478);b.pageX=x;table.insert(menu.pageButtons,b);if spec[1]=='Find step' then menu.findStep=b end;x=x+spec[2]+12 end
 menu.levelButton=button(menu,'Show current level',150,function() if menu.level then menu.level=nil else menu.level=UnitLevel('player') end;menu.page=1;G.RenderMenu() end);point(menu.levelButton,menu,20,48)
 menu:Hide()
 if G.BuildMenus then G.BuildMenus() end
 local options=card(UIParent);G.options=options;options:SetWidth(350);options:SetHeight(450);options:SetPoint('CENTER',UIParent,'CENTER',0,0);options:SetFrameStrata('DIALOG');if options.SetFrameLevel and f.GetFrameLevel then options:SetFrameLevel(f:GetFrameLevel()+30) end;options:EnableMouse(true)
 options.title=label(options,18,310,true);point(options.title,options,20,18);options.title:SetHeight(24);options.title:SetText('OctoGuide settings')
 options.rows={}
 for i,spec in ipairs({{'targets','Quest targets on maps'},{'routes','Waypoint route lines'},{'checkpoints','Numbered checkpoints'},{'minimap','Minimap guidance'}}) do
  local b=button(options,spec[2],310,function() local o=G.MapOptions and G.MapOptions() or G.db.mapOptions;if not o then return end;o[this.optionKey]=not o[this.optionKey];G.RenderSettings();if G.UpdateMaps then G.UpdateMaps(true) end end);b.optionKey=spec[1];b.optionLabel=spec[2];point(b,options,20,65+(i-1)*40);options.rows[i]=b
 end
 options.partyButton=button(options,'',310,function() local setting=G.db.partyMode or 'auto';G.SetPartyMode(setting=='auto' and 'solo' or setting=='solo' and 'group' or 'auto');G.RenderSettings() end);point(options.partyButton,options,20,225)
 options.info=label(options,11,300);point(options.info,options,23,262);options.info:SetHeight(58);options.info:SetText('Lines connect route checkpoints. Follow the written instructions for roads, obstacles and transport.')
 G.BuildZoomControls(options,label,point)
 local smaller=button(options,'Narrower',95,function() G.ResizeWidth(-40) end);point(smaller,options,20,394)
 local wider=button(options,'Wider',95,function() G.ResizeWidth(40) end);point(wider,options,125,394)
 local b=button(options,'Close',80,function() options:Hide() end);point(b,options,245,394);options.close=b;options.smaller=smaller;options.wider=wider;options:Hide()
 if G.UpgradeSettings then G.UpgradeSettings() end
end
function G.ResizeWidth(delta)
 G.db.widths=G.db.widths or {};local view=G.db.view or 'full';G.db.widths[view]=math.max(380,math.min(800,(G.db.widths[view] or G.frame:GetWidth())+delta));G.Render()
end
function G.RenderSettings()
 if G.options.modeButton then G.options.modeButton:SetText('Mode: '..(G.Mode()=='hardcore' and 'Hardcore' or 'Survival')) end
 G.options.partyButton:SetText('Party: '..(G.db.partyMode or 'auto')..' ('..G.PartyMode()..')')
 if G.UpdateAppearanceSettings then G.UpdateAppearanceSettings() end
 local o=G.MapOptions and G.MapOptions() or G.db.mapOptions or {}
 for _,b in ipairs(G.options.rows) do b:SetText((o[b.optionKey]~=false and '[ON] ' or '[OFF] ')..b.optionLabel) end
end
function G.ToggleSettings() if G.options:IsShown() then G.options:Hide() else G.RenderSettings();G.options:Show() end end
function G.RenderMenu()
 if G.stepBrowser and G.stepBrowser:IsShown() then G.RefreshStepBrowser();return end
 G.menu.levelButton:SetText(G.menu.level and 'Show all levels' or 'Show current level')
 local list=G.LevelGuides(G.menu.level)
 local pages=math.max(1,math.ceil(table.getn(list)/14));G.menu.page=math.min(G.menu.page,pages)
 G.menu.info:SetText((G.Mode()=='hardcore' and 'Hardcore' or 'Normal')..' | '..(G.menu.level and ('Level '..G.menu.level) or 'All levels')..' | Page '..G.menu.page..' / '..pages)
 for i,row in ipairs(G.menu.rows) do local id=list[(G.menu.page-1)*14+i];row.guideID=id;if id then row:SetText(G.RouteLabel(G.guides[id]));row:Show() else row:Hide() end end
end
function G.ToggleMenu() if G.menu:IsShown() then G.menu:Hide() else G.RenderMenu();G.menu:Show() end end
function G.Render(layoutOnly)
 if not G.frame or not G.frame.arrow or not G.frame.distance then return end
 local f=G.frame;local full=G.db.view=='full';local width=math.max(380,math.min(800,(G.db.widths or {})[G.db.view] or (full and 460 or 490)));f:SetWidth(width)
 -- Legacy background selection is replaced by independent skins.
 -- f.bg:SetTexture('Interface\\AddOns\\OctoGuide-downloads\\Assets\\'..((full and 'GuideFull' or 'GuideMinimal')..OG_BG))
 G.LayoutHeader(f,width)
 for _,t in ipairs(f.header) do if full then t:Show() else t:Hide() end end
 for _,t in ipairs({f.title,f.version,f.route}) do if full then t:Show() else t:Hide() end end
 f.routeMode:Hide();f.routeMode:SetText(G.Mode()=='hardcore' and 'Hardcore' or 'Normal');point(f.routeMode,f,width-102,24);f.mode:SetText(full and 'Minimal' or 'Expand')
 local cached=layoutOnly and f.layoutData
 local s=cached and cached.step or G.Current();local guide=G.state and G.state.guide
 local title,body,action=G.Present(s)
 local journey=not layoutOnly and G.Travel and G.Travel.Plan(G.RawNavTarget())
 if journey then body=journey.hint..(body~='' and ('\n'..body) or '') end
 local objectives=cached and cached.objectives or (s and G.DisplayObjectives(s) or {})
 if not layoutOnly then f.layoutData={step=s,objectives=objectives} end
 if s and table.getn(objectives)==0 and s.sourceObjective and (action=='objective' or action=='complete' or action=='use') then body=body..'\n'..s.sourceObjective end
 if G.gatherTarget then title='GATHER: '..G.gatherTarget.text;body='Possible resource spawn. Use /octoguide route to resume quests.';action='collect' end
 local index=G.state and (G.state.index or table.getn(G.state.steps)) or 0
 local source=G.hasFamilyRoutes and (G.RouteSource()=='rxp' and 'RestedXP' or 'RestedXP installed; baseline') or 'Baseline'
 f.route:SetText(source..' | '..G.RouteLabel(guide)..'  |  Step '..index..' / '..(G.state and table.getn(G.state.steps) or 0))
 local names={accept='ACCEPT QUEST',turnin='TURN IN QUEST',objective='CURRENT OBJECTIVES',complete='CURRENT OBJECTIVES',travel='TRAVEL',collect='GATHER',death='NORMAL SHORTCUT'}
 f.section:SetText(names[action] or string.upper(action or 'CURRENT STEP'));if full then f.section:Show() else f.section:Hide() end
 local cardTop=full and 96 or 54;local titleTop=full and 130 or 66;point(f.currentCard,f,15,cardTop);point(f.section,f,28,106)
 f.icon:SetTexture(action=='turnin' and 'Interface\\GossipFrame\\ActiveQuestIcon' or 'Interface\\GossipFrame\\AvailableQuestIcon');point(f.icon,f,27,titleTop)
 point(f.step,f,65,titleTop);local y=titleTop+height(f.step,title,width-188,17)+8
 point(f.arrow,f,width-86,titleTop-2);point(f.distance,f,width-109,titleTop+54)
 if body~='' then
  point(f.detailsScroll,f,28,y);f.detailsScroll:SetWidth(width-150);f.detailsHost:SetWidth(width-150)
  local h=height(f.details,body,width-150,12);local visible=math.min(h,220);f.detailsHost:SetHeight(h);f.detailsScroll:SetHeight(visible);f.detailsScroll.maxScroll=math.max(0,h-visible)
  if f.detailsScroll.lastBody~=body then f.detailsScroll:SetVerticalScroll(0);f.detailsScroll.lastBody=body end
  y=y+visible+9;f.details:Show();f.detailsScroll:Show()
 else f.details:SetText('');f.details:Hide();f.detailsScroll:Hide() end
 local secondary=G.db.secondaryArrow and G.SecondaryTarget and G.SecondaryTarget(s)
 y=math.max(y,titleTop+100,secondary and titleTop+195 or 0)
 for i,row in ipairs(f.objectives) do local o=objectives[i]
  if o then
   point(row,f,25,y);row:SetWidth(width-50)
   local name=o.name or o.text or '';local current,required=o.current,o.required
   if not current then local _,_,a,b=string.find(name,'(%d+)%s*/%s*(%d+)');current=tonumber(a);required=tonumber(b);name=string.gsub(name,'%s*:?%s*%d+%s*/%s*%d+','') end
   row.count:SetText(required and tostring(current or 0)..' / '..required or (o.done and 'Done' or ''));point(row.count,row,width-130,10)
   row.check:SetTexture(o.done and 'Interface\\Buttons\\UI-CheckBox-Check' or 'Interface\\Buttons\\UI-CheckBox-Up');point(row.name,row,33,8)
   row.name:SetTextColor(o.done and .48 or .91,o.done and .78 or .92,o.done and .54 or .94)
   local h=math.max(34,height(row.name,name,width-174,12)+16);row:SetHeight(h);row:Show();y=y+h+5
  else row:Hide() end
 end
 local note=''
 if s and s.minlevel and UnitLevel('player')<s.minlevel then note='Requires level '..s.minlevel..'.'
 elseif s and s.optionalSupply then note='Optional supplies: buy only what you need. Use Skip to continue.'
 elseif s and s.action=='turnin' then note='Advances after the quest reward is confirmed.'
 elseif s and s.manual and table.getn(objectives)==0 then note='Use Done after completing this local action.' end
 if note~='' then point(f.note,f,28,y+3);y=y+height(f.note,note,width-56,10)+9;f.note:Show() else f.note:Hide() end
 f.currentCard:SetWidth(width-30);f.currentCard:SetHeight(y-cardTop+10);y=y+24
 if full then
  local top=y;point(f.nextCard,f,15,y);f.nextCard:SetWidth(width-30);point(f.nextTitle,f,28,y+10);f.nextTitle:Show();f.nextCard:Show();y=y+36
  local upcoming=cached and cached.upcoming or {}
  if not cached and G.state and G.state.index then
   local seen={};if s and s.questID then seen[s.questID]=true end
   for _,n in ipairs(G.Concurrent and G.Concurrent(s) or {}) do if n.questID then seen[n.questID]=true end end
   for i=G.state.index+1,table.getn(G.state.steps) do
    local n=G.state.steps[i]
    if (not G.PreviewStep or G.PreviewStep(n)) and not G.db.progress[G.Key(n)] and not G.Satisfied(n) and G.Allowed(n) and not (n.questID and seen[n.questID] and (n.action=='complete' or n.action=='objective' or n.action=='use')) then
     table.insert(upcoming,n);if n.questID then seen[n.questID]=true end;if table.getn(upcoming)==3 then break end
    end
   end
  end
  if f.layoutData then f.layoutData.upcoming=upcoming end
  for i,row in ipairs(f.nextRows) do local n=upcoming[i]
   if n then
    local t,b=G.Present(n,true);point(row,f,25,y);row:SetWidth(width-50);row.number:SetText(i)
    local titleHeight=height(row.title,t,width-109,12);local h=titleHeight+20
    if b~='' then
     point(row.details,row,63,10+titleHeight+6)
     local detailHeight=height(row.details,b,width-127,11);detailHeight=math.min(detailHeight,60);row.details:SetHeight(detailHeight);h=h+6+detailHeight;row.details:Show()
    else row.details:SetText('');row.details:Hide() end
    h=math.max(43,h);local viewport=UIParent:GetHeight()*UIParent:GetEffectiveScale()/f:GetEffectiveScale();if y+h+95<=viewport then row:SetHeight(h);row:Show();y=y+h+6 else row:Hide() end
   else row:Hide() end
  end
  f.nextCard:SetHeight(y-top+8);y=y+20
 else f.nextCard:Hide();f.nextTitle:Hide();for _,row in ipairs(f.nextRows) do row:Hide() end end
 local primary=G.StepButton and G.StepButton(s) or (s and 'Done' or 'Next')
 local collapsed=G.ControlsCollapsed and G.ControlsCollapsed()
 local buttons={f.back,f.done,f.menu,f.mode,f.settingsButton}
 f.skip:Hide()
 local x=24;local buttonY=y
 for _,b in ipairs(buttons) do
  if collapsed then b:Hide() else
   b.width=math.max(104,b.width);if x+b.width>width-24 then x=24;buttonY=buttonY+32 end
   b.width=math.max(104,b.width);b:SetWidth(b.width);b.label:SetWidth(b.width-8);b.layoutX=x;b.layoutY=buttonY;point(b,f,x,buttonY);b:Show();if b.restyled then b.restyled('ButtonNormal') end;x=x+b.width+6
  end
 end
 f.done:SetText(primary)
 local toggleY=collapsed and y or buttonY+34
 if f.controlsToggle then point(f.controlsToggle,f,(width-44)/2,toggleY);f.controlsToggle:SetText(collapsed and 'v' or '^');if f.controlsToggle.restyled then f.controlsToggle.restyled('ButtonNormal') end;f.controlsToggle:Show() end
 point(f.close,f,width-58,full and 22 or 14);f.close:Show()
 if f.close.SetFrameLevel and f.GetFrameLevel then f.close:SetFrameLevel(f:GetFrameLevel()+25);f.controlsToggle:SetFrameLevel(f:GetFrameLevel()+25) end
 local contentHeight=toggleY+38;f.contentHeight=contentHeight
 local viewport=UIParent:GetHeight()*UIParent:GetEffectiveScale()/f:GetEffectiveScale()
 local saved=(G.db.heights or {})[G.db.view] or 0
 local finalHeight=math.max(contentHeight,math.min(saved,viewport-12));f:SetHeight(finalHeight)
 if finalHeight>contentHeight then
  for _,b in ipairs(buttons) do point(b,f,b.layoutX or 24,(b.layoutY or y)+finalHeight-contentHeight) end
  if f.controlsToggle then point(f.controlsToggle,f,(width-44)/2,toggleY+finalHeight-contentHeight) end
 end
 G.LayoutPanelSkin(f.skin,width,f:GetHeight());G.ApplyZoom();if G.ApplyOpacity then G.ApplyOpacity() end
 G.tooltipText=nil
 if not layoutOnly then G.navigationTarget=G.NavTarget();G.UpdateArrow() end
 if not layoutOnly and G.UpdateMaps then G.UpdateMaps(true) end
end
function G.UpdateArrow(elapsed)
 local f=G.frame;if not f or not f.arrow or not f.distance or not f:IsShown() then return end
 local s=G.NavTarget();if G.UpdateSecondaryArrow then G.UpdateSecondaryArrow(elapsed) end;if not s or not s.zone or not s.x or not s.y then f.arrow:Hide();f.distance:SetText('No waypoint');return end
 local result,why;if G.NavigationRead and not G.gatherTarget then result,why=G.NavigationRead(G.Current()) else result,why=OctoGuideNavigation.ReadWaypoint(s) end
 if not result then f.arrow:Hide();f.distance:SetText(why=='transport required' and 'Transport' or 'Position N/A');f.arrowAngle=nil;return end
 local angle=result.angle
 if angle and elapsed and f.arrowAngle then local d=math.mod(angle-f.arrowAngle+3*math.pi,2*math.pi)-math.pi;angle=f.arrowAngle+d*(1-math.exp(-18*math.min(elapsed,.1))) end
 f.arrowAngle=angle
 local rotated=false
 if angle and f.arrow.SetRotation then f.arrow:SetRotation(-angle);rotated=true
 elseif angle and f.arrow.SetTexCoord then
  local c,sn=math.cos(angle),math.sin(angle)
  local function uv(x,y) return .5+c*x+sn*y,.5-sn*x+c*y end
  local a,b=uv(-.5,-.5);local c1,d=uv(-.5,.5);local e,h=uv(.5,-.5);local j,k=uv(.5,.5);f.arrow:SetTexCoord(a,b,c1,d,e,h,j,k);rotated=true
 end
 if rotated then f.arrow:Show() else f.arrow:Hide() end
 f.distance:SetText(math.floor(result.yards+.5)..' yd')
 if f.targetEvidence then f.targetEvidence:SetText(G.navigationEvidence or 'Route waypoint') end
end

