local G=OctoGuide
local P=G.Professions
local D=G.ProfessionData
local art='Interface\\AddOns\\OctoGuide-downloads\\Assets\\'
local function text(parent,value,x,y,w,h,size,gold)
 local t=G.MakeLabel(parent,size or 11,w,gold);G.Place(t,parent,x,y);t:SetHeight(h);t:SetText(value);return t
end
local function button(parent,value,x,y,w,fn)
 local b=G.MakeButton(parent,value,w,fn);b:SetWidth(w);b.width=w;b.label:SetWidth(w-8);if b.restyled then b.restyled('ButtonNormal') end;G.Place(b,parent,x,y);return b
end
local function report(ok,why) if not ok then G.Chat(why or 'Unavailable') end end
function P.OpenRecipes()
 local name=P.State().selected
 if type(CastSpellByName)=='function' then CastSpellByName(name) else G.Chat('Open '..name..' from your spellbook.') end
end
function P.MarkerLifetime()
 local n=P.State().markerSeconds;return type(n)=='number' and n>=15 and n<=1800 and n or 120
end
function P.ClearMarker()
 if P.marker and P.marker.title and pfMap and pfMap.DeleteNode then pfMap:DeleteNode('OctoGuideProfessions',P.marker.title) end
 P.marker=nil;P.waypoint=nil
 if G.gatherTarget and G.gatherTarget.profession then G.gatherTarget=nil;if G.ready then G.Render() end end
end
function P.ShowLocation(row)
 if not row or type(row.zone)~='number' or type(row.x)~='number' or type(row.y)~='number' or row.x<0 or row.x>100 or row.y<0 or row.y>100 then return false,'No verified coordinates available.' end
 P.ClearMarker();P.waypoint={zone=row.zone,x=row.x/100,y=row.y/100,text=row.name}
 if pfMap and pfMap.AddNode and pfMap.ShowMapID then
  local title='Profession: '..row.name..' ['..row.zone..' / '..row.x..','..row.y..']'
  pfMap:AddNode({addon='OctoGuideProfessions',title=title,spawn=row.name,spawnid=row.id,spawntype='Profession',zone=row.zone,x=row.x,y=row.y,texture=art..'ProfessionMark',vertex={1,1,1}})
  P.marker={title=title,expires=(GetTime and GetTime() or 0)+P.MarkerLifetime()}
  pfMap:ShowMapID(row.zone)
  -- AddNode also queues updates in some pfQuest forks; normalize only the bad boolean.
  if pfMap and type(pfMap.queue_update)=='boolean' then pfMap.queue_update=GetTime and GetTime() or 0 end
 else G.Chat('Coordinates selected. Enable pfQuest for the map flag.') end
 if not P.marker then P.marker={expires=(GetTime and GetTime() or 0)+P.MarkerLifetime()} end
 return true
end
function P.ShowRows(title,rows)
 local p=G.professionPanel;local list=p.locations
 list.title:SetText(title);list.items=rows;list.page=1
 function list:Refresh()
  local start=(self.page-1)*6
  for i,b in ipairs(self.rows) do local row=self.items[start+i];b.row=row;if row then
   b:SetText(row.name..' - '..(row.location or tostring(row.zone))..' '..string.format('%.1f, %.1f',row.x or 0,row.y or 0));b:Show()
  else b:Hide() end end
  self.note:SetText('Database locations, not live stock or trainer-service proof. Page '..self.page..' / '..math.max(1,math.ceil(table.getn(self.items)/6)))
 end
 list:Refresh();list:Show()
end
function P.Vendors(material)
 if not OctoBoard or type(OctoBoard.VendorRows)~='function' then G.Chat('Enable the updated OctoBoard for item vendors.');return end
 local faction=UnitFactionGroup('player');local rows,why=OctoBoard.VendorRows(material.id,faction)
 local valid={};for _,r in ipairs(rows or {}) do if r.zone and r.x and r.y then table.insert(valid,r) end end
 if table.getn(valid)==0 then G.Chat(why or 'No faction-compatible vendors with coordinates recorded. Gather, loot or use permitted trade.');return end
 P.ShowRows('Vendors: '..material.name,valid)
end
function P.Trainers()
 local meta=D.professions[P.State().selected];local names=meta.trainers
 if not names then G.Chat('Consult '..meta.name..' trainers in your faction towns; rank books/quests may be required. '..(meta.artisan or ''));return end
 local faction=UnitFactionGroup('player');local wanted={};for _,n in ipairs(names[faction] or {}) do wanted[n]=true end;for _,n in ipairs(names.neutral or {}) do wanted[n]=true end
 local rows={};local db=pfDB;local loc=db and db.units and (db.units.loc or db.units.enUS) or {};local zones=db and db.zones and (db.zones.loc or db.zones.enUS) or {}
 for unit,name in pairs(loc) do if wanted[name] then
  local data=db.units.data and db.units.data[unit]
  for _,c in pairs(data and data.coords or {}) do if type(c[1])=='number' and type(c[2])=='number' and type(c[3])=='number' then table.insert(rows,{id=unit,name=name,zone=c[3],x=c[1],y=c[2],location=zones[c[3]]}) end end
 end end
 table.sort(rows,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.zone<b.zone end)
 if table.getn(rows)==0 then G.Chat('Trainer coordinates not recorded. '..(meta.artisan or meta.tool));return end
 P.ShowRows('Trainer candidates: check services for your rank',rows)
end
function P.EditMaterial(m)
 local p=G.professionPanel.editor;local input=P.State().inputs[m.id] or {};p.material=m
 p.title:SetText(m.name..' - manual estimates per item')
 p.price:SetText(input.price and tostring(input.price) or '');p.seconds:SetText(input.seconds and tostring(input.seconds) or '')
 p.error:SetText('');p:Show()
end
function P.MaterialSources(m)
 local panel=G.professionPanel.sources;panel.material=m;panel.title:SetText(m.name)
 panel.find:SetText(P.MaterialResource(m) and 'Find gathering node' or 'No gathering mapping');panel:Show()
end
function P.RefreshUI()
 local p=G.professionPanel;if not p then return end
 local s=P.State();local skills=P.Skills();local advice=P.Advice();p.advice=advice
 for i,b in ipairs(p.professions) do local name=D.order[i];local skill=skills[name];b:SetText((s.selected==name and '> ' or '')..name..(skill and ' '..skill.rank or ' (not learned)')) end
 p.goal:SetText('Goal '..s.goal..' | '..advice.rank..(advice.skill and advice.skill.cap and ' / '..advice.skill.cap or ''))
 p.fast:SetText((s.mode=='fast' and '[X] ' or '')..'Fastest');p.cheap:SetText((s.mode=='cheap' and '[X] ' or '')..'Fast + cheap')
 p.tolerance:SetText('Extra time: '..s.tolerance..'%');p.lifetime:SetText('Flag: '..math.floor(P.MarkerLifetime()/60*10)/10 ..' min')
 p.heading:SetText(advice.title)
 local body=advice.text..'\n\nSource: '..advice.meta.confidence
 body=body..'\nPrices: manual estimates or observed NPC buy prices. Stock, discounts and availability can change.'
 if G.Mode()=='hardcore' then body=body..'\nHardcore: no AH; only permitted trade.' end
 p.body:SetText(body);local h=math.max(180,math.ceil(string.len(body)/62)*17+120);p.body:SetHeight(h);p.host:SetHeight(h);p.scroll.maxScroll=math.max(0,h-180)
 local offset=p.scroll.GetVerticalScroll and p.scroll:GetVerticalScroll() or 0;p.scroll:SetVerticalScroll(math.min(offset,p.scroll.maxScroll))
 local materials=advice.choice and advice.choice.materials or {}
 for i,row in ipairs(p.materials) do local m=materials[i];row.material=m
  if m then row.label:SetText(m.name..' '..m.have..' / '..m.quantity);row.price:SetText('Price / time');row.source:SetText('Sources');row.label:Show();row.price:Show();row.source:Show()
  else row.label:Hide();row.price:Hide();row.source:Hide() end
 end
 p.materialNote:SetText(table.getn(materials)>6 and 'More reagents listed above; first six have source controls.' or 'Have / required for one craft. Bank materials are not counted.')
 local meta=advice.meta;p.node:SetText(meta.category=='fish' and 'Nearest pool' or 'Leveling node')
 p.source:SetText('Guide source');p.status:SetText(P.notice or 'Choose a profession. Open its recipe window to read learned recipes. Advice only; no automatic actions.')
end
function P.Toggle()
 if not G.ready then G.Chat('Wait for character login.');return end
 local p=G.professionPanel
 if p:IsShown() then p:Hide() else P.RefreshUI();p:Show() end
end
local originalBuild=G.BuildUI
function G.BuildUI()
 originalBuild();P.State()
 local p=G.MakeCard(UIParent);G.professionPanel=p;p:SetWidth(760);p:SetHeight(760);p:SetPoint('CENTER',UIParent,'CENTER',0,0);p:SetFrameStrata('DIALOG');G.MakeMovable(p,'professions')
 local screen=UIParent.GetHeight and UIParent:GetHeight() or 900;if p.SetScale then p:SetScale(math.min(1,math.max(.5,(screen-50)/760))) end
 p.title=text(p,'OctoGuide - Professions',22,18,650,30,21,true)
 p.banner=p:CreateTexture(nil,'ARTWORK');G.Place(p.banner,p,20,54);p.banner:SetWidth(720);p.banner:SetHeight(76);p.banner:SetTexture(art..'ProfessionBanner');p.banner:SetTexCoord(0,1,.33,.65)
 p.professions={};for i,name in ipairs(D.order) do
  local b=button(p,name,20,145+(i-1)*28,210,function() P.State().selected=this.profession;P.notice=nil;P.ClearMarker();P.RefreshUI() end);b.profession=name;p.professions[i]=b
 end
 p.goal=text(p,'',252,145,230,24,13,true)
 button(p,'-25',490,142,50,function() P.State().goal=math.max(1,P.State().goal-25);P.RefreshUI() end)
 button(p,'+25',547,142,50,function() P.State().goal=math.min(300,P.State().goal+25);P.RefreshUI() end)
 button(p,'Recipes',604,142,130,P.OpenRecipes)
 p.fast=button(p,'Fastest',252,177,140,function() P.State().mode='fast';P.RefreshUI() end)
 p.cheap=button(p,'Fast + cheap',400,177,160,function() P.State().mode='cheap';P.RefreshUI() end)
 p.tolerance=button(p,'Extra time',568,177,166,function() local s=P.State();s.tolerance=math.mod(s.tolerance+10,60);P.RefreshUI() end)
 p.heading=text(p,'',252,213,480,33,14,true)
 p.scroll=CreateFrame('ScrollFrame','OctoGuideProfessionScroll',p);G.Place(p.scroll,p,252,249);p.scroll:SetWidth(480);p.scroll:SetHeight(180)
 p.host=CreateFrame('Frame',nil,p.scroll);p.host:SetWidth(470);p.scroll:SetScrollChild(p.host)
 p.body=text(p.host,'',0,0,466,400,11)
 if p.scroll.EnableMouseWheel then p.scroll:EnableMouseWheel(true);p.scroll:SetScript('OnMouseWheel',function() local offset=this.GetVerticalScroll and this:GetVerticalScroll() or 0;this:SetVerticalScroll(math.max(0,math.min(this.maxScroll or 0,offset-(arg1 or 0)*36))) end) end
 p.materialNote=text(p,'',252,433,480,18,10)
 p.materials={};for i=1,6 do
  local row={};local y=456+(i-1)*28;row.label=text(p,'',252,y,260,25,11)
  row.price=button(p,'Price / time',515,y,100,function() P.EditMaterial(row.material) end)
  row.source=button(p,'Sources',623,y,111,function() P.MaterialSources(row.material) end);table.insert(p.materials,row)
 end
 p.node=button(p,'Leveling node',252,635,150,function()
  local meta=D.professions[P.State().selected]
  if not meta.category then G.Chat('This profession has no static resource nodes. '..meta.tool);return end
  report(P.FindResource(meta.category,meta.category~='fish'))
 end)
 p.track=button(p,'Find skill',410,635,150,function() report(P.Track(D.professions[P.State().selected].category)) end)
 p.trainers=button(p,'Trainers',568,635,166,P.Trainers)
 p.source=button(p,'Guide source',252,669,150,function() local url=D.professions[P.State().selected].source;G.Chat(url);p.status:SetText(url) end)
 p.lifetime=button(p,'Flag: 2 min',410,669,150,function() local s=P.State();s.markerSeconds=P.MarkerLifetime()==120 and 300 or P.MarkerLifetime()==300 and 60 or 120;P.RefreshUI() end)
 button(p,'Back to quests',568,669,166,function() P.ClearMarker();P.ReturnToQuests() end)
 p.status=text(p,'',22,710,712,35,10)
 button(p,'Close',642,17,92,function() p:Hide() end)
 local e=G.MakeCard(p);p.editor=e;e:SetWidth(460);e:SetHeight(230);e:SetPoint('CENTER',p,'CENTER',0,0);e:SetFrameStrata('FULLSCREEN_DIALOG')
 e.title=text(e,'',18,18,424,30,13,true);text(e,'Buy price in copper per item (blank = unknown)',18,57,420,22,11)
 e.price=CreateFrame('EditBox','OctoGuideProfessionPrice',e,'InputBoxTemplate');e.price:SetWidth(160);e.price:SetHeight(24);e.price:SetAutoFocus(false);G.Place(e.price,e,24,80)
 text(e,'Seconds to acquire one item, including travel',18,113,420,22,11)
 e.seconds=CreateFrame('EditBox','OctoGuideProfessionSeconds',e,'InputBoxTemplate');e.seconds:SetWidth(160);e.seconds:SetHeight(24);e.seconds:SetAutoFocus(false);G.Place(e.seconds,e,24,136)
 e.error=text(e,'',192,78,245,81,11)
 e.save=button(e,'Save',18,186,130,function()
  local a,b=e.price:GetText(),e.seconds:GetText();local price=a~='' and tonumber(a) or nil;local seconds=b~='' and tonumber(b) or nil
  if a~='' and not price or b~='' and not seconds then e.error:SetText('Use numbers or leave blank.');return end
  local ok,why=P.SetInput(e.material.id,price,seconds);if ok then e:Hide();P.RefreshUI() else e.error:SetText(why) end
 end)
 button(e,'Cancel',156,186,130,function() e:Hide() end);e:Hide()
 local sources=G.MakeCard(p);p.sources=sources;sources:SetWidth(400);sources:SetHeight(180);sources:SetPoint('CENTER',p,'CENTER',0,0);sources:SetFrameStrata('FULLSCREEN_DIALOG')
 sources.title=text(sources,'',18,18,364,30,13,true)
 sources.find=button(sources,'Find gathering node',18,58,364,function()
  local r=P.MaterialResource(sources.material)
  if r then report(P.FindResource(r.cat,false,r.names));if r.note then G.Chat(r.note) end else G.Chat('No resource-node mapping for this item; it may need crafting, looting or trade.') end
  sources:Hide()
 end)
 button(sources,'Vendor locations',18,94,364,function() P.Vendors(sources.material);sources:Hide() end)
 button(sources,'Close',18,132,364,function() sources:Hide() end);sources:Hide()
 local list=G.MakeCard(p);p.locations=list;list:SetWidth(670);list:SetHeight(300);list:SetPoint('CENTER',p,'CENTER',0,0);list:SetFrameStrata('FULLSCREEN_DIALOG')
 list.title=text(list,'',18,18,620,27,13,true);list.rows={}
 for i=1,6 do list.rows[i]=button(list,'',18,55+(i-1)*28,632,function() report(P.ShowLocation(this.row));list:Hide() end) end
 list.note=text(list,'',18,225,632,26,10)
 button(list,'Previous',18,260,140,function() list.page=math.max(1,list.page-1);list:Refresh() end)
 button(list,'Next',168,260,140,function() list.page=math.min(math.max(1,math.ceil(table.getn(list.items)/6)),list.page+1);list:Refresh() end)
 button(list,'Close',510,260,140,function() list:Hide() end);list:Hide()
 p:Hide()
 G.menu.professions=button(G.menu,'Professions',190,465,245,function() G.menu:Hide();P.Toggle() end)
 p.arrow=p:CreateTexture(nil,'ARTWORK');G.Place(p.arrow,p,85,559);p.arrow:SetWidth(64);p.arrow:SetHeight(64);p.arrow:SetTexture(art..'Arrow');p.arrow:Hide()
 p.distance=text(p,'Select a node or location',22,632,208,60,11,true)
 p:SetScript('OnUpdate',function()
  P.elapsed=(P.elapsed or 0)+(arg1 or 0);if P.elapsed<.1 then return end;P.elapsed=0
  if P.marker and GetTime and GetTime()>=P.marker.expires then P.ClearMarker() end
  local waypoint=P.waypoint or G.gatherTarget and G.gatherTarget.profession and G.gatherTarget
  local result,why=OctoGuideNavigation.ReadWaypoint(waypoint)
  if not result then p.arrow:Hide();p.distance:SetText(waypoint and ('Transport / position unavailable\n'..waypoint.text) or 'Select a node or location');return end
  if result.angle and p.arrow.SetRotation then p.arrow:SetRotation(-result.angle);p.arrow:Show()
  elseif result.angle and p.arrow.SetTexCoord then
   local c,sn=math.cos(result.angle),math.sin(result.angle);local function uv(x,y) return .5+c*x+sn*y,.5-sn*x+c*y end
   local a,b=uv(-.5,-.5);local c1,d=uv(-.5,.5);local e,f=uv(.5,-.5);local h,i=uv(.5,.5);p.arrow:SetTexCoord(a,b,c1,d,e,f,h,i);p.arrow:Show()
  else p.arrow:Hide() end
  p.distance:SetText(math.floor(result.yards+.5)..' yd - '..waypoint.text..'\nDatabase point / straight-line')
 end)
 -- Marker expiry must also run while the profession panel is closed.
 if P.timer then P.timer:SetScript('OnUpdate',nil) end
 P.timer=CreateFrame('Frame',nil,UIParent);P.timer:SetScript('OnUpdate',function()
  if P.marker and GetTime and GetTime()>=P.marker.expires then P.ClearMarker();return end
  if P.marker and P.marker.resourceKey and OctoGather then local node=OctoGather.byKey and OctoGather.byKey[P.marker.resourceKey];if not node or not OctoGather.MapVisible(node) then P.ClearMarker() end end
 end)
end
local oldHide=G.HidePanels
function G.HidePanels() oldHide();if G.professionPanel then G.professionPanel:Hide() end end
