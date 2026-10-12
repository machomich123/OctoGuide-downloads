-- Bounded visible rows: the whole guide remains accessible without creating thousands of frames.
local G=OctoGuide
function G.GuideSteps(id)
 local guide=G.guides[id];local steps={}
 if not guide or not G.Playable(guide) then return steps end
 for _,s in ipairs(guide.steps) do if G.Allowed(s) then table.insert(steps,s) end end
 return steps
end
function G.JumpToStep(id,number)
 local steps=G.GuideSteps(id)
 if type(number)~='number' or number~=math.floor(number) or number<1 or number>table.getn(steps) then return false,'Enter a step number from 1 to '..tostring(table.getn(steps))..'.' end
 if G.CancelFindStep then G.CancelFindStep() end
 G.db.placements=G.db.placements or {};G.db.placements[id]={stepID=steps[number].id,reason='manual step selection'}
 G.db.reviewGuide=id;G.db.reviewStep=steps[number].id;G.db.reviewReason='jump'
 local ok,why=G.Select(id,'restore');if not ok then return false,why end
 G.db.hidden=false;G.frame:Show();G.Render();return true
end
function G.RefreshStepBrowser()
 local p=G.stepBrowser;if not p then return end
 local steps=G.GuideSteps(p.guideID);p.steps=steps
 p.offset=math.max(0,math.min(p.offset or 0,math.max(0,table.getn(steps)-12)))
 p.title:SetText((G.guides[p.guideID] and G.guides[p.guideID].title or 'Guide')..' — '..tostring(table.getn(steps))..' steps')
 for i,row in ipairs(p.rows) do
  local number=p.offset+i;local s=steps[number];row.stepNumber=number;row.stepText=s and s.text
  if s then
   local flag=G.db.completedQuests[s.questID] and '[Done] ' or ''
   row:SetText(tostring(number)..'. '..flag..s.text);row:Show()
  else row:Hide() end
 end
 p.range:SetText(tostring(p.offset+1)..'-'..tostring(math.min(p.offset+12,table.getn(steps)))..' / '..tostring(table.getn(steps)))
end
function G.OpenStepBrowser(id)
 if table.getn(G.GuideSteps(id))==0 then G.Chat('No steps for this character and mode.');return false end
 local menu=G.menu
 if not G.stepBrowser then
  local p=CreateFrame('Frame',nil,menu);G.stepBrowser=p;p:SetWidth(420);p:SetHeight(375);G.Place(p,menu,20,76)
  if p.SetFrameLevel and menu.GetFrameLevel then p:SetFrameLevel(menu:GetFrameLevel()+10) end
  p:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'});p:SetBackdropColor(.05,.05,.07,1)
  p.title=p:CreateFontString(nil,'OVERLAY','GameFontNormal');p.title:SetWidth(410);p.title:SetHeight(30);p.title:SetJustifyH('LEFT');G.Place(p.title,p,4,0)
  local label=p:CreateFontString(nil,'OVERLAY','GameFontHighlight');label:SetText('Skip to step:');G.Place(label,p,4,39)
  p.input=CreateFrame('EditBox',nil,p,'InputBoxTemplate');p.input:SetWidth(65);p.input:SetHeight(24);G.Place(p.input,p,104,33);p.input:SetAutoFocus(false);p.input:SetNumeric(true)
  local function jump(number)
   local ok,why=G.JumpToStep(p.guideID,number)
   if ok then p.input:ClearFocus();menu:Hide() else p.error:SetText(why) end
  end
  p.input:SetScript('OnEnterPressed',function() jump(tonumber(p.input:GetText())) end)
  p.input:SetScript('OnEscapePressed',function() p.input:ClearFocus() end)
  p.go=G.MakeButton(p,'Go',45,function() jump(tonumber(p.input:GetText())) end);G.Place(p.go,p,183,32)
  local back=G.MakeButton(p,'Guides',75,function() p:Hide();G.RenderMenu() end);G.Place(back,p,337,32)
  p.error=p:CreateFontString(nil,'OVERLAY','GameFontHighlight');p.error:SetWidth(410);p.error:SetHeight(22);G.Place(p.error,p,4,61)
  p.rows={}
  for i=1,12 do
   local row=G.MakeButton(p,'',410,function() jump(this.stepNumber) end);row:SetHeight(21);G.Place(row,p,4,86+(i-1)*22);p.rows[i]=row
   if row.GetScript then
    local enter,leave=row:GetScript('OnEnter'),row:GetScript('OnLeave')
    row:SetScript('OnEnter',function() if enter then enter() end;if GameTooltip and row.stepText then GameTooltip:SetOwner(row,'ANCHOR_RIGHT');GameTooltip:SetText(row.stepText,1,1,1,1,true);GameTooltip:Show() end end)
    row:SetScript('OnLeave',function() if leave then leave() end;if GameTooltip then GameTooltip:Hide() end end)
   end
  end
  p:EnableMouseWheel(true);p:SetScript('OnMouseWheel',function() p.offset=(p.offset or 0)-(arg1 or 0)*3;G.RefreshStepBrowser() end)
  p.previous=G.MakeButton(p,'Previous steps',125,function() p.offset=(p.offset or 0)-12;G.RefreshStepBrowser() end);G.Place(p.previous,p,4,352)
  p.next=G.MakeButton(p,'Next steps',125,function() p.offset=(p.offset or 0)+12;G.RefreshStepBrowser() end);G.Place(p.next,p,285,352)
  p.range=p:CreateFontString(nil,'OVERLAY','GameFontHighlight');p.range:SetWidth(140);G.Place(p.range,p,143,361)
 end
 local p=G.stepBrowser;p.guideID=id;p.offset=0;p.error:SetText('Click a step to review it. Earlier steps stay available.');p.input:SetText('')
 for _,row in ipairs(menu.rows) do row:Hide() end
 G.RefreshStepBrowser();p:Show();return true
end
