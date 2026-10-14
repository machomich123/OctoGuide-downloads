-- Read-only, character-specific profession advice. Never craft, gather or buy.
local G=OctoGuide
local P={};G.Professions=P
local D=G.ProfessionData
local function finite(n) return type(n)=='number' and n==n and n>=0 and n<1000000000 end
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b,c,d,e,f,g=pcall(fn,unpack(arg));if ok then return a,b,c,d,e,f,g end
end
local function id(link) if type(link)~='string' then return nil end;local _,_,n=string.find(link,'item:(%d+)');return tonumber(n) end
function P.State()
 G.db=G.db or {};G.db.professions=G.db.professions or {}
 local s=G.db.professions;s.mode=s.mode=='cheap' and 'cheap' or 'fast';s.selected=D.professions[s.selected] and s.selected or 'Mining'
 s.goal=finite(s.goal) and math.max(1,math.min(300,math.floor(s.goal))) or 300
 s.tolerance=finite(s.tolerance) and math.min(100,s.tolerance) or 20
 s.recipes=s.recipes or {};s.inputs=s.inputs or {};s.craftTimes=s.craftTimes or {};s.vendorPrices=s.vendorPrices or {}
 return s
end
function P.Skills()
 local result={}
 for i=1,call(GetNumSkillLines) or 0 do
  local name,header,_,rank,temporary,modifier,maxRank=call(GetSkillLineInfo,i)
  if not header and D.professions[name] and finite(rank) then result[name]={rank=rank,cap=finite(maxRank) and maxRank or nil} end
 end
 return result
end
function P.Bags()
 local result={}
 for bag=0,4 do for slot=1,call(GetContainerNumSlots,bag) or 0 do
  local item=id(call(GetContainerItemLink,bag,slot));local _,n=call(GetContainerItemInfo,bag,slot)
  if item and finite(n) then result[item]=(result[item] or 0)+n end
 end end
 return result
end
function P.Money(copper)
 if not finite(copper) then return 'unknown' end
 copper=math.ceil(copper);return math.floor(copper/10000)..'g '..math.mod(math.floor(copper/100),100)..'s '..math.mod(copper,100)..'c'
end
function P.SetInput(item,price,seconds)
 if not finite(item) or item<1 or (price~=nil and not finite(price)) or (seconds~=nil and not finite(seconds)) then return false,'Enter non-negative copper and seconds, or leave blank for unknown.' end
 P.State().inputs[item]={price=price,seconds=seconds,source='manual',updated=call(time)};return true
end
function P.CaptureVendor()
 local state=P.State()
 for i=1,call(GetMerchantNumItems) or 0 do
  local name,texture,price,quantity,stock,usable,extended=call(GetMerchantItemInfo,i)
  local item=id(call(GetMerchantItemLink,i))
  if item and finite(price) and finite(quantity) and quantity>0 and not (extended==true or extended==1) then
   state.vendorPrices[item]={price=price/quantity,stock=stock,seen=call(time),source='observed NPC price'}
  end
 end
end
-- Scan only the currently open recipe window. Do not change the user's filters.
function P.Capture(kind)
 local craft=kind=='craft';local name,rank=call(craft and GetCraftDisplaySkillLine or GetTradeSkillLine)
 if not D.professions[name] then return false,'Open the profession recipe window first.' end
 local skills=P.Skills();local live=skills[name]
 -- Vanilla Craft display can expose only the name (unlike TradeSkill).
 if craft and live and not finite(rank) then rank=live.rank end
 if not live or not finite(rank) or rank~=live.rank then return false,'Recipe window and character skill do not match.' end
 local count=call(craft and GetNumCrafts or GetNumTradeSkills);if not finite(count) then return false,'Recipe information unavailable.' end
 local snapshot={rank=rank,recipes={},captured=call(time),partial=true}
 local complete=true
 for index=1,count do
  local rn,color,available,expanded
  if craft then local sub;rn,sub,color,available=call(GetCraftInfo,index) else rn,color,available,expanded=call(GetTradeSkillInfo,index) end
  if rn and color and color~='header' and color~='subheader' then
   local r={name=rn,color=color,kind=craft and 'enchant' or 'craft',index=index,reagents={},tools={},cooldown=call(craft and GetCraftCooldown or GetTradeSkillCooldown,index) or 0}
   r.item=id(call(craft and GetCraftItemLink or GetTradeSkillItemLink,index))
   local minimum=not craft and call(GetTradeSkillNumMade,index);r.yield=finite(minimum) and minimum>0 and minimum or 1
   local recipeLink=call(craft and GetCraftRecipeLink or GetTradeSkillRecipeLink,index);local _,_,spell=string.find(recipeLink or '','enchant:(%d+)');r.spell=tonumber(spell)
   local n=call(craft and GetCraftNumReagents or GetTradeSkillNumReagents,index)
   if not finite(n) or n<1 then complete=false else
    for j=1,n do
     local reagent,texture,quantity=call(craft and GetCraftReagentInfo or GetTradeSkillReagentInfo,index,j)
     local item=id(call(craft and GetCraftReagentItemLink or GetTradeSkillReagentItemLink,index,j))
     if not item or not finite(quantity) or quantity<1 or type(reagent)~='string' then complete=false;r.incomplete=true
     else table.insert(r.reagents,{id=item,name=reagent,quantity=quantity}) end
    end
   end
   if not craft and type(GetTradeSkillTools)=='function' then
    local tools={GetTradeSkillTools(index)}
    for j=1,table.getn(tools),2 do if type(tools[j])=='string' then table.insert(r.tools,{name=tools[j],present=tools[j+1]==true or tools[j+1]==1}) end end
   elseif craft and type(GetCraftSpellFocus)=='function' then
    local focus,present=call(GetCraftSpellFocus,index);if type(focus)=='string' and focus~='' then table.insert(r.tools,{name=focus,present=present==true or present==1}) end
   end
   local signature=r.spell and 'spell:'..r.spell or (r.item and 'item:'..r.item or 'name:'..rn)
   -- Include reagent identity/quantity to distinguish same-name recipe variants.
   for _,m in ipairs(r.reagents) do signature=signature..':'..m.id..'x'..m.quantity end
   r.key=signature
   if not r.incomplete then table.insert(snapshot.recipes,r) end
  end
 end
 snapshot.incomplete=not complete
 -- Empty/uncached reads cannot erase a previous useful snapshot.
 if table.getn(snapshot.recipes)==0 then return false,'No complete recipes visible. Expand headers and clear recipe filters.' end
 P.State().recipes[name]=snapshot;return true
end
local chances={optimal=1,medium=.5,easy=.25}
function P.Evaluate(recipe,bags,state)
 local chance=chances[recipe.color];if not chance or recipe.incomplete or not finite(recipe.cooldown) or recipe.cooldown>0 then return nil end
 local r={recipe=recipe,chance=chance,materials={},ready=true,cash=0,cashKnown=true,timeKnown=true,seconds=0,toolsReady=true,value=0,valueKnown=true}
 local craftSeconds=state.craftTimes[recipe.key];r.craftMeasured=finite(craftSeconds) and craftSeconds>0
 r.seconds=r.craftMeasured and craftSeconds or 3
 local quantities={};local names={}
 for _,m in ipairs(recipe.reagents) do quantities[m.id]=(quantities[m.id] or 0)+m.quantity;names[m.id]=m.name end
 for item,quantity in pairs(quantities) do
  local have=bags[item] or 0;local missing=math.max(0,quantity-have);local input=state.inputs[item] or {}
  local vendor=state.vendorPrices and state.vendorPrices[item];local price=finite(input.price) and input.price or vendor and vendor.price
  local m={id=item,name=names[item],quantity=quantity,have=have,missing=missing,price=price,seconds=input.seconds,priceSource=finite(input.price) and 'manual' or vendor and vendor.source};table.insert(r.materials,m)
  local value=P.UnitValue and P.UnitValue(item,state,state.valueRecipes or {},{}) or price
  if finite(value) then r.value=r.value+quantity*value else r.valueKnown=false end
  if missing>0 then
   r.ready=false
   if finite(price) then r.cash=r.cash+missing*price else r.cashKnown=false end
   if finite(input.seconds) then r.seconds=r.seconds+missing*input.seconds else r.timeKnown=false end
  end
 end
 table.sort(r.materials,function(a,b) return a.id<b.id end)
 for _,tool in ipairs(recipe.tools or {}) do if not tool.present then r.toolsReady=false;r.ready=false;r.timeKnown=false end end
 r.perPointSeconds=r.seconds/chance;r.perPointCash=r.cash/chance;r.perPointValue=r.value/chance
 return r
end
-- Economic ingredient value includes owned materials and traces learned
-- intermediates back to their reagents. No price is invented for missing data.
function P.UnitValue(item,state,recipes,seen)
 local input=state.inputs[item];if input and finite(input.price) then return input.price end
 if seen[item] then return nil end
 local vendor=state.vendorPrices and state.vendorPrices[item];local best=vendor and finite(vendor.price) and vendor.price or nil
 seen[item]=true
 for _,r in ipairs(recipes) do if r.item==item and not r.incomplete and r.kind~='enchant' then
  local total=0;local known=true
  for _,m in ipairs(r.reagents) do local v=P.UnitValue(m.id,state,recipes,seen);if not finite(v) then known=false;break end;total=total+v*m.quantity end
  if known then local value=total/(r.yield or 1);if not best or value<best then best=value end end
 end end
 seen[item]=nil;return best
end
function P.Choose(recipes,bags,state)
 state.valueRecipes=recipes
 local all={};local fastest
 for _,recipe in ipairs(recipes) do local r=P.Evaluate(recipe,bags,state);if r then
  table.insert(all,r)
  if r.toolsReady and r.timeKnown and (not fastest or r.perPointSeconds<fastest.perPointSeconds or r.perPointSeconds==fastest.perPointSeconds and r.recipe.key<fastest.recipe.key) then fastest=r end
 end end
 if state.mode=='cheap' and fastest then
  local chosen
  for _,r in ipairs(all) do if r.toolsReady and r.timeKnown and r.valueKnown and r.perPointSeconds<=fastest.perPointSeconds*(1+state.tolerance/100) then
   if not chosen or r.perPointValue<chosen.perPointValue or r.perPointValue==chosen.perPointValue and r.perPointSeconds<chosen.perPointSeconds then chosen=r end
  end end
  if chosen then chosen.compared=true;state.valueRecipes=nil;return chosen,all end
 end
 if fastest then fastest.compared=state.mode=='fast';state.valueRecipes=nil;return fastest,all end
 -- Incomplete acquisition estimates: display a feasible next candidate, no optimum claim.
 table.sort(all,function(a,b)
  if a.toolsReady~=b.toolsReady then return a.toolsReady end
  if a.chance~=b.chance then return a.chance>b.chance end
  return a.recipe.key<b.recipe.key
 end)
 state.valueRecipes=nil;return all[1],all
end
function P.EngineeringPlan(rank,recipes,bags,state)
 local stage
 for _,s in ipairs(D.engineeringStages) do if rank<s.untilRank then stage=s;break end end
 if stage and stage.item==6219 and (bags[6219] or 0)>0 then stage=D.engineeringStages[4] end
 if not stage then return nil end
 local eligible={};local preferred
 for _,r in ipairs(recipes) do
  local reserved=false
  for _,m in ipairs(r.reagents) do if stage.reserve[m.id] and (bags[m.id] or 0)-m.quantity<stage.reserve[m.id] then reserved=true end end
  if r.item==stage.item and chances[r.color] then preferred=r end
  if not reserved or r.item==stage.item then table.insert(eligible,r) end
 end
 if not preferred then return {stage=stage,missingRecipe=true} end
 -- With incomplete inputs, use the sourced stage instead of a one-craft greedy
 -- tie. Do not discard the intended component merely because a consumer is ready.
 local choice,all=P.Choose(eligible,bags,state)
 state.valueRecipes=recipes;local planned=P.Evaluate(preferred,bags,state);state.valueRecipes=nil
 if not choice or not choice.compared or not choice.valueKnown or not planned or not planned.timeKnown or not planned.valueKnown then choice=planned end
 if choice then choice.stage=stage end
 return {choice=choice,alternatives=all,stage=stage}
end
function P.Advice(name)
 local state=P.State();local meta=D.professions[name or state.selected];if not meta then return {title='Select a profession.',text=''} end
 local skill=P.Skills()[meta.name];local rank=skill and skill.rank or 0
 local result={meta=meta,rank=rank,skill=skill,title=meta.name..' '..rank..' / '..state.goal,text=meta.tool}
 if not skill then result.action='learn';result.text='Learn '..meta.name..' from a trainer first.\n'..result.text;return result end
 if rank>=state.goal then result.action='done';result.text='Selected skill goal reached.\n'..result.text;return result end
 if skill.cap and rank>=skill.cap then
  result.action='train';result.title='Train the next '..meta.name..' rank';result.text='Current skill cap: '..skill.cap..'. Visit the appropriate trainer, book or unlock quest.\n'..(meta.artisan and skill.cap>=225 and meta.artisan or meta.tool);return result
 end
 local band
 for _,b in ipairs(meta.bands) do if rank<b[1] then band=b;break end end
 result.baseline=band and band[2] or 'Check your trainer for the next suitable recipe.'
 if meta.kind=='gather' or meta.kind=='skin' or meta.kind=='fish' then result.action=meta.kind;result.text=result.baseline..'\n'..meta.tool;return result end
 local snapshot=state.recipes[meta.name]
 if not snapshot or snapshot.rank~=rank then result.action='scan';result.text='Open '..meta.name..' to refresh learned recipes and current colors.\n'..result.baseline..'\n'..meta.tool;return result end
 local bags=P.Bags();local plan=meta.name=='Engineering' and P.EngineeringPlan(rank,snapshot.recipes,bags,state)
 if plan and plan.missingRecipe then result.action='learn';result.title='Learn / show: '..plan.stage.name;result.text=plan.stage.note..'\nOpen the recipe window, expand headers and visit a trainer if this recipe is not learned.';return result end
 local choice,all
 if plan then choice,all=plan.choice,plan.alternatives else choice,all=P.Choose(snapshot.recipes,bags,state) end
 result.choice=choice;result.alternatives=all
 if not choice then result.action='learn';result.text='No usable skill-up recipe is visible: expand headers, clear filters, and learn an appropriate recipe.\n'..result.baseline;return result end
 result.action=choice.ready and 'make' or 'materials';result.title=(choice.ready and 'Make one: ' or 'Prepare: ')..choice.recipe.name
 local lines={result.baseline,'Read from your recipe window; compare visible learned recipes only.'}
 if choice.stage then table.insert(lines,choice.stage.note);table.insert(lines,'Stage target: '..math.min(choice.stage.untilRank,state.goal)..'. Reserved components are not spent on unrelated recipes.') end
 table.insert(lines,'Material value per skill point (including owned ingredients): '..P.Money(choice.valueKnown and choice.perPointValue or nil)..'. Owned materials are not automatically free.')
 table.insert(lines,choice.compared and ('Estimate per skill point: '..math.ceil(choice.perPointSeconds)..' seconds; missing-material spend '..P.Money(choice.cashKnown and choice.perPointCash or nil)..'.') or 'Cost/time comparison incomplete. Add missing prices and acquisition times; this is a candidate, not a proven fastest route.')
 table.insert(lines,'Orange/yellow/green estimates use 100%/50%/25%; Octo rates are not measured. Make one and recheck actual skill.')
 if not choice.craftMeasured then table.insert(lines,'Craft time uses a 3-second estimate; actual observed cast time replaces it.') end
 if meta.name=='Survival' and state.mode=='cheap' and not choice.ready and rank>=5 then table.insert(lines,'Low cash alternative: use Leveling node for woodcutting instead of buying crafting materials. Woodcutting speed / skill-up rate is not measured, so it is not included in the timed comparison.') end
 for _,m in ipairs(choice.materials) do table.insert(lines,m.name..': have '..m.have..', need '..m.quantity..', missing '..m.missing..(m.priceSource and ' | '..m.priceSource..' '..P.Money(m.price)..' each' or '')) end
 for _,tool in ipairs(choice.recipe.tools or {}) do table.insert(lines,tool.name..': '..(tool.present and 'ready' or 'missing / go to the required station')) end
 table.insert(lines,'Keep intermediates and quest materials. No automatic crafting or purchasing.')
 result.text=table.concat(lines,'\n');return result
end
local function contains(name,parts)
 for _,part in ipairs(parts or {}) do if string.find(string.lower(name or ''),string.lower(part),1,true) then return true end end
 return false
end
function P.MaterialResource(material)
 local info=D.resourceMaterials[material.id];if info then return info end
 -- Custom wood IDs come from the actual item link; match only the exact material family.
 for _,tier in ipairs(D.woodTiers) do if string.lower(material.name or '')==string.lower(tier[2]..' Wood') then return {cat='wood',names={tier[2]},note='Gather '..tier[2]..' wood; tool and skill requirements apply.'} end end
 return nil
end
function P.NodeEligible(node,skill,leveling,names)
 if not finite(node.skill) or node.skill>skill or names and not contains(node.name,names) then return false end
 if not leveling then return true end
 if node.cat=='ore' then
  for kind,gray in pairs(D.oreGray) do if contains(node.name,{kind}) then return skill<gray end end
  return false -- Unknown skill-up thresholds must not be presented as verified leveling nodes.
 elseif node.cat=='herb' then return skill<node.skill+100 -- Classic baseline, explicitly labeled.
 elseif node.cat=='wood' then
  local tier
  for _,row in ipairs(D.woodTiers) do if skill>=row[1] then tier=row[2] end end
  return tier and contains(node.name,{tier}) or false
 end
 return false
end
function P.FindResource(category,leveling,names)
 local gather=OctoGather;local skillName=category=='ore' and 'Mining' or category=='herb' and 'Herbalism' or category=='wood' and 'Survival' or category=='fish' and 'Fishing'
 local skill=skillName and P.Skills()[skillName]
 if not skill then return false,(skillName or 'Resource skill')..' is not learned.' end
 if not gather or not gather.ready or type(gather.MapVisible)~='function' or not C_Map or not C_Map.GetWorldPosFromMapPos then return false,'OctoGather / map navigation unavailable.' end
 local west,north,_,map=call(UnitPosition,'player');if not finite(math.abs(west or 1000000000)) or not finite(math.abs(north or 1000000000)) then return false,'Player position unavailable.' end
 local currentZone=call(GetRealZoneText);local zoneID=currentZone and gather.zoneNames and gather.zoneNames[currentZone]
 local best,distance
 for _,node in pairs(gather.byKey or {}) do
  -- Stay in the current zone when its identity is available. No dangerous cross-zone shortcut.
  local eligible=category=='fish' and not leveling and (not names or contains(node.name,names)) or P.NodeEligible(node,skill.rank,leveling,names)
  if node.cat==category and eligible and (not zoneID or node.zone==zoneID) and gather.MapVisible(node) then
   local nmap,pos=call(C_Map.GetWorldPosFromMapPos,node.zone,{x=node.x/100,y=node.y/100})
   if nmap==map and pos and type(pos.x)=='number' and type(pos.y)=='number' then
    local d=(pos.x-north)^2+(pos.y-west)^2;if not best or d<distance or d==distance and node.key<best.key then best,distance=node,d end
   end
  end
 end
 if not best then return false,'No suitable visible known node here. Use tracking or move to a suitable safe area.' end
 if P.ShowLocation then P.ShowLocation({id=best.id,name=best.name,zone=best.zone,x=best.x,y=best.y}) end
 if P.marker then P.marker.resourceKey=best.key end
 G.gatherTarget={zone=best.zone,x=best.x/100,y=best.y/100,text=best.name,key=best.key,profession=true}
 G.db.hidden=false;G.frame:Show();G.Render()
 G.Chat('Known possible spawn: '..best.name..'. Distance is straight-line, not a safe walking route. Skill-up rules use baseline estimates.');return true
end
function P.Track(category)
 local wanted=category=='ore' and 'Find Minerals' or category=='herb' and 'Find Herbs' or category=='wood' and 'Find Trees'
 if not wanted or not OctoGather or type(OctoGather.TrackingList)~='function' or type(OctoGather.Track)~='function' then return false,'Tracking is unavailable.' end
 for _,row in ipairs(OctoGather.TrackingList()) do if row.name==wanted then OctoGather.Track(row);return true end end
 return false,wanted..' is not learned.'
end
function P.ReturnToQuests()
 if G.professionPanel then G.professionPanel:Hide() end
 if G.gatherTarget and G.gatherTarget.profession then G.gatherTarget=nil end
 G.db.hidden=false;G.frame:Show();G.Render()
end
local oldEvent=G.Event
function G.Event(ev,a,b)
 oldEvent(ev,a,b)
 if not G.ready then return end
 if ev=='TRADE_SKILL_SHOW' or ev=='TRADE_SKILL_UPDATE' then P.Capture('trade')
 elseif ev=='CRAFT_SHOW' or ev=='CRAFT_UPDATE' then P.Capture('craft')
 elseif ev=='MERCHANT_SHOW' or ev=='MERCHANT_UPDATE' then P.CaptureVendor()
 elseif ev=='SPELLCAST_START' and type(b)=='number' and b>0 then
  local state=P.State();local snapshot=state.recipes[state.selected];local matched;local count=0
  for _,r in ipairs(snapshot and snapshot.recipes or {}) do if r.name==a then matched=r;count=count+1 end end
  if count==1 then state.craftTimes[matched.key]=b/1000 end
 end
 if ev=='BAG_UPDATE' or ev=='SKILL_LINES_CHANGED' or ev=='TRADE_SKILL_SHOW' or ev=='TRADE_SKILL_UPDATE' or ev=='CRAFT_SHOW' or ev=='CRAFT_UPDATE' or ev=='SPELLS_CHANGED' or ev=='SPELLCAST_START' or ev=='MERCHANT_SHOW' or ev=='MERCHANT_UPDATE' then
  if G.professionPanel and G.professionPanel:IsShown() then P.RefreshUI() end
 end
end
