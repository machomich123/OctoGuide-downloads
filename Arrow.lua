-- Optional presentation of the existing navigation result. No extra scanner.
local G=OctoGuide
local art='Interface\\AddOns\\OctoGuide-downloads\\Assets\\WaypointArrow'
local modes={'panel','floating','both','off'}
local names={panel='Guide window',floating='Free arrow',both='Window + free arrow',off='Hidden'}
local function text(t,value) if t:GetText()~=value then t:SetText(value) end end
function G.ArrowOptions()
 G.db.arrow=G.db.arrow or {};local o=G.db.arrow
 if not names[o.mode] then o.mode='panel' end
 o.scale=math.max(.5,math.min(2,tonumber(o.scale) or 1))
 o.font=math.max(10,math.min(16,tonumber(o.font) or 11))
 return o
end
function G.ArrowCell(angle)
 -- The shipped pfQuest sprite turns counter-clockwise; navigation is clockwise.
 local n=math.floor(-angle/(2*math.pi)*108+.5)
 return math.mod(math.mod(n,108)+108,108)
end
local anchors={CENTER=true,TOP=true,TOPLEFT=true,TOPRIGHT=true,LEFT=true,RIGHT=true,BOTTOM=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
function G.SaveArrowPosition()
 local f=G.floatingArrow;local a,relative,b,x,y=f:GetPoint()
 if type(relative)=='string' and type(b)=='number' and type(x)=='number' and y==nil then y=x;x=b;b=relative end
 if anchors[a] and anchors[b] and type(x)=='number' and type(y)=='number' and x==x and y==y and math.abs(x)<100000 and math.abs(y)<100000 then G.ArrowOptions().position={a,b,x,y};return true end
 return false
end
function G.ApplyArrowSettings()
 if not G.floatingArrow then return end
 local f,o=G.floatingArrow,G.ArrowOptions();f:SetScale(o.scale)
 f:EnableMouse(o.locked==false)
 for _,label in ipairs({f.title,f.distance,f.task,f.height}) do label:SetFont('Fonts\\FRIZQT__.TTF',o.font,'OUTLINE') end
 local p=o.position
 f:ClearAllPoints()
 if type(p)=='table' and anchors[p[1]] and anchors[p[2]] and type(p[3])=='number' and type(p[4])=='number' and p[3]==p[3] and p[4]==p[4] and math.abs(p[3])<100000 and math.abs(p[4])<100000 then
  f:SetPoint(p[1],UIParent,p[2],p[3],p[4])
 else o.position=nil;f:SetPoint('CENTER',UIParent,'CENTER',0,160) end
 f.captionElapsed=.2;f.cachedCaption=nil
end
function G.ShortArrowTask(s)
 if not s then return 'Choose a guide step.' end
 if type(s.shortText)=='string' and s.shortText~='' then return s.shortText end
 local title=G.Present(s)
 local action=s.action
 if action=='objective' or action=='complete' then
  for _,goal in ipairs(G.Objectives(s)) do
   if not goal.done and (not s.objective or s.objective==goal.index) then
    local value=goal.text or goal.name
    if value and value~='' then
     -- "monster" objectives also include talking/waking/using items.
     -- Preserve the client's actual wording rather than inventing "Kill".
     return value
    end
   end
  end
  return s.sourceObjective or ('Complete '..title)
 end
 if action=='accept' or action=='turnin' or action=='travel' or action=='fly' or action=='hearth' or action=='use' or action=='train' or action=='collect' or action=='buy' or action=='bind' or action=='flightpath' then return s.text or title end
 return title
end
local function concise(value)
 value=string.gsub(value or '','|c%x%x%x%x%x%x%x%x','');value=string.gsub(value,'|r','');value=string.gsub(value,'[\r\n]+',' ')
 if string.len(value)>110 then local start=string.sub(value,1,107);start=string.gsub(start,'%s+%S*$','');value=start..'...' end
 return value
end
function G.PinArrowStep(s)
 if not s or not G.state or not s.zone or not s.x or not s.y then return false end
 G.ArrowOptions().pin={guide=s.sourceGuide or G.state.guide.id,id=s.id,hadQuest=s.questID and G.QuestIndex(s.questID)~=nil};G.arrowPinnedStep=s
 if G.ArrowOptions().mode=='panel' or G.ArrowOptions().mode=='off' then G.ArrowOptions().mode='floating' end
 G.ApplyArrowSettings();return true
end
function G.ClearArrowPin() G.ArrowOptions().pin=nil;G.arrowPinnedStep=nil;G.ApplyArrowSettings() end
local function pinned()
 local o=G.ArrowOptions();local p=o.pin;if not p then return nil end
 local guide=G.guides[p.guide]
 if not guide or not G.Allowed(guide) or guide.routeFamily and guide.routeFamily~=G.RouteSource() then G.ClearArrowPin();return nil end
 local step=G.arrowPinnedStep
 if not step or step.id~=p.id or step.sourceGuide~=p.guide then
  step=nil;for _,s in ipairs(guide.steps) do if s.id==p.id then step=s;break end end;G.arrowPinnedStep=step
 end
 if not step or not G.Allowed(step) or step.questID and G.db.completedQuests[step.questID] then G.ClearArrowPin();return nil end
 if step.questID then
  local index=G.QuestIndex(step.questID)
  if index then
   p.hadQuest=true
   local _,_,_,_,_,complete=GetQuestLogTitle(index)
   if complete==true or complete==1 then
    for _,s in ipairs(guide.steps) do if s.questID==step.questID and s.action=='turnin' and G.Allowed(s) then step=s;break end end
   end
  elseif p.hadQuest then G.ClearArrowPin();return nil end
 end
 return step
end
local function build()
 local f=CreateFrame('Frame','OctoGuideFloatingArrow',UIParent);G.floatingArrow=f
 f:SetWidth(250);f:SetHeight(165);f:SetMovable(true);if f.SetClampedToScreen then f:SetClampedToScreen(true) end
 f:SetFrameStrata('MEDIUM');f:RegisterForDrag('LeftButton');f:Hide()
 f:SetScript('OnDragStart',function()if G.ArrowOptions().locked==false then f:StartMoving() end end)
 f:SetScript('OnDragStop',function()f:StopMovingOrSizing();G.SaveArrowPosition() end)
 f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetWidth(84);f.icon:SetHeight(63);f.icon:SetPoint('TOP',f,'TOP',0,0);f.icon:SetTexture(art)
 local function label(y,height)
  local t=f:CreateFontString(nil,'OVERLAY');t:SetWidth(250);t:SetHeight(height);t:SetPoint('TOP',f,'TOP',0,-y);t:SetJustifyH('CENTER');return t
 end
 f.title=label(65,18);f.distance=label(84,18);f.task=label(104,38);f.height=label(147,18)
 G.ApplyArrowSettings()
end
local function show(label,on)if label:IsShown()~=on then if on then label:Show() else label:Hide() end end end
function G.DrawFloatingArrow(elapsed)
 local f=G.floatingArrow;if not f or not G.db then return end
 local o=G.ArrowOptions();local enabled=o.mode=='floating' or o.mode=='both'
 if not G.ready or not enabled or o.withHidden==false and (not G.frame or not G.frame:IsShown()) then f:Hide();return end
 local selected=pinned();local r,why,target
 if selected then target=selected;r=G.SecondaryRead and G.SecondaryRead(selected) or OctoGuideNavigation.ReadWaypoint(selected)
 else r,why,target=G.ReadArrowNavigation() end
 local s=selected or G.Current()
 if not target then f:Hide();return end
 if not f:IsShown() then f:Show() end
 if r and r.angle then
  local angle=r.angle
  if f.angle and elapsed then local delta=math.mod(angle-f.angle+3*math.pi,2*math.pi)-math.pi;angle=f.angle+delta*(1-math.exp(-18*math.min(elapsed,.1))) end
  f.angle=angle;local cell=G.ArrowCell(angle)
  if cell~=f.cell then local col=math.mod(cell,9);local row=math.floor(cell/9);f.icon:SetTexCoord(col*56/512,(col+1)*56/512,row*42/512,(row+1)*42/512);f.cell=cell end
  if f.icon.SetVertexColor then local alignment=(math.cos(angle)+1)/2;local red=math.min(1,2*(1-alignment));local green=math.min(1,2*alignment);if red~=f.red or green~=f.green then f.icon:SetVertexColor(red,green,0);f.red=red;f.green=green end end
  f.icon:Show()
  local near=r.yards<=8 and (type(r.heightDelta)~='number' or math.abs(r.heightDelta)<3)
  text(f.distance,(near and 'At waypoint | ' or '')..math.floor(r.yards+.5)..' yd')
 else
  f.angle=nil;f.icon:Hide();text(f.distance,target.blockedReason and 'Check pickup' or why=='transport required' and 'Transport required' or 'Position unavailable')
 end
 f.captionElapsed=(f.captionElapsed or .2)+(elapsed or .016)
 if f.captionElapsed>=.2 or f.captionStep~=s then
  f.captionElapsed=0;f.captionStep=s
  local title=G.Present(s);text(f.title,(selected and '[Selected] ' or '')..concise(title))
  text(f.task,concise(G.ShortArrowTask(s)))
 end
 text(f.height,r and (G.HeightText and G.HeightText(r.heightDelta) or '') or '')
 show(f.title,o.title~=false);show(f.distance,o.distance~=false);show(f.task,o.task~=false);show(f.height,o.height~=false)
end
local function settings()
 local p=G.MakeCard(UIParent);G.arrowSettings=p;p:SetWidth(410);p:SetHeight(530);p:SetPoint('CENTER',UIParent,'CENTER',0,0);p:SetFrameStrata('DIALOG');p:EnableMouse(true);p:Hide()
 p.title=G.MakeLabel(p,16,360,true);p.title:SetHeight(24);G.Place(p.title,p,25,20);p.title:SetText('Navigation arrow')
 p.rows={}
 local function row(key,y,label,fn)
  local b=G.MakeButton(p,label,360,function()fn();G.ApplyArrowSettings();G.UpdateArrowSettings();G.UpdateArrow(.016)end);G.Place(b,p,25,y);p.rows[key]=b
 end
 row('mode',57,'',function()local o=G.ArrowOptions();for i,m in ipairs(modes) do if o.mode==m then o.mode=modes[math.mod(i,4)+1];break end end end)
 for i,spec in ipairs({{'locked','Lock position'},{'task','Short task text'},{'title','Target name'},{'distance','Distance'},{'height','Height text'},{'withHidden','Keep arrow when guide is hidden'}}) do
  local key,label=spec[1],spec[2];row(key,57+i*32,label,function()local o=G.ArrowOptions();o[key]=not (o[key]~=false) end)
 end
 row('smaller',289,'Smaller arrow',function()local o=G.ArrowOptions();o.scale=o.scale-.1 end)
 row('larger',321,'Larger arrow',function()local o=G.ArrowOptions();o.scale=o.scale+.1 end)
 row('font',353,'',function()local o=G.ArrowOptions();o.font=o.font>=16 and 10 or o.font+1 end)
 row('reset',385,'Reset position',function()G.ArrowOptions().position=nil end)
 row('follow',417,'Follow guide (clear selected target)',G.ClearArrowPin)
 p.close=G.MakeButton(p,'Close',100,function()p:Hide()end);G.Place(p.close,p,285,465)
 local hint=G.MakeLabel(p,10,250);hint:SetHeight(34);hint:SetText('Ctrl-click a guide step to point at it without changing progress.');G.Place(hint,p,25,462)
 G.options.arrowButton=G.MakeButton(G.options,'Arrow settings',185,function()G.UpdateArrowSettings();p:Show()end);G.Place(G.options.arrowButton,G.options,195,565)
end
function G.UpdateArrowSettings()
 local p=G.arrowSettings;if not p then return end;local o=G.ArrowOptions()
 p.rows.mode:SetText('Arrow: '..names[o.mode]);p.rows.font:SetText('Text size: '..o.font..' (click to change)')
 for _,spec in ipairs({{'locked','Lock position'},{'task','Short task text'},{'title','Target name'},{'distance','Distance'},{'height','Height text'},{'withHidden','Keep arrow when guide is hidden'}}) do local key,label=spec[1],spec[2];p.rows[key]:SetText((o[key]~=false and '[ON] ' or '[OFF] ')..label) end
 p.rows.smaller:SetText('Smaller arrow ('..math.floor(o.scale*100+.5)..'%)')
end
local buildUI=G.BuildUI
function G.BuildUI()buildUI();build();settings()end
local update=G.UpdateArrow
function G.UpdateArrow(elapsed)
 if not G.db then return update(elapsed) end
 local o=G.ArrowOptions()
 if o.mode=='panel' then
  update(elapsed);if G.floatingArrow then G.floatingArrow:Hide() end
  if G.frame and G.previousArrowMode~='panel' then for _,label in ipairs({G.frame.distance,G.frame.heightLabel,G.frame.targetEvidence}) do if label then label:Show() end end end
  G.previousArrowMode='panel'
  return
 end
 if o.mode=='off' then
  if G.previousArrowMode~='off' then
   if G.floatingArrow then G.floatingArrow:Hide() end
   if G.frame then for _,element in ipairs({G.frame.arrow,G.frame.distance,G.frame.heightLabel,G.frame.targetEvidence,G.frame.secondaryArrow,G.frame.secondaryText}) do if element then element:Hide() end end end
  end
  G.previousArrowMode='off'
  return
 end
 G.shareArrowRead=true;G.sharedArrowRead=nil
 update(elapsed)
 G.DrawFloatingArrow(elapsed)
 G.shareArrowRead=nil;G.sharedArrowRead=nil
 G.previousArrowMode=o.mode
 local f=G.frame
 if f and f.arrow then
  local embedded=o.mode=='panel' or o.mode=='both'
  if not embedded then f.arrow:Hide() end
  for _,label in ipairs({f.distance,f.heightLabel,f.targetEvidence}) do if label then show(label,embedded) end end
 end
end
local hide=G.HidePanels
function G.HidePanels()hide();if G.floatingArrow then G.floatingArrow:Hide() end;if G.arrowSettings then G.arrowSettings:Hide() end end
