-- Original Lua 5.0 implementation. See QUEST-AUTOMATION-RESEARCH.md.
local G=OctoGuide
local A={cache={},sent={},pending=nil};G.automation=A
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b,c,d,e,f,g,h,i,j,k,l=pcall(fn,unpack(arg))
 if ok then return a,b,c,d,e,f,g,h,i,j,k,l end
end
local function enabled(key) return G.db and G.db[key]==true end
local function paused()
 return not G.ready or not G.state or (G.pauseAuto and G.state.reviewReason~='jump') or (IsShiftKeyDown and IsShiftKeyDown()) or (UnitAffectingCombat and UnitAffectingCombat('player'))
end
local function title(s)
 local locale=GetLocale and GetLocale() or 'enUS'
 local quests=pfDB and pfDB.quests and pfDB.quests[locale]
 local q=quests and quests[s.questID]
 if q and q.T then return q.T end
 local _,_,name=string.find(s.text or '',s.action=='accept' and '^Accept (.-) from ' or '^Turn in (.-) to ')
 return name
end
function A.Step(id,action)
 if not G.state or type(id)~='number' then return nil end
 for _,s in ipairs(G.state.steps) do
  if s.questID==id and s.action==action and G.Allowed(s) and (not G.SourceEligible or G.SourceEligible(s)) and not (s.minlevel and UnitLevel('player')<s.minlevel) then
   local mark=G.db.progress[G.Key(s)]
   if mark~='manual' and mark~='skipped' and not G.db.completedQuests[id] then
    if action=='accept' and not mark and not G.QuestIndex(id) then return s end
    if action=='turnin' and G.QuestIndex(id) then return s end
   end
  end
 end
end
local function resolve(name,action)
 local found
 for _,s in ipairs(G.state.steps) do
  if s.action==action and title(s)==name and A.Step(s.questID,action) then
   if found and found~=s.questID then return nil end;found=s.questID
  end
 end
 -- Same-title chains require an ID from the gossip API or the dialog.
 local quests=pfDB and pfDB.quests and pfDB.quests[GetLocale and GetLocale() or 'enUS']
 if found and quests then for id,q in pairs(quests) do if q.T==name and id~=found then return nil end end end
 return found
end
function A.DialogID(action)
 local id=call(GetQuestID)
 if type(id)=='number' and id>0 then return A.Step(id,action) and id end
 local name=call(GetTitleText)
 if A.selected and A.selected.action==action then
  local s=A.Step(A.selected.id,action)
  if s and title(s)==name then return s.questID end
 end
 return name and resolve(name,action)
end
local function complete(id)
 local index=G.QuestIndex(id);if not index then return false end
 local _,_,_,header,_,done=call(GetQuestLogTitle,index)
 return not header and (done==true or done==1)
end
local function send(key,fn,...)
 if A.sent[key] or type(fn)~='function' then return false end
 A.sent[key]=true
 local ok=pcall(fn,unpack(arg));if not ok then A.sent[key]=nil end
 return ok
end
local slots={INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_BODY={4},INVTYPE_CHEST={5},INVTYPE_ROBE={5},INVTYPE_WAIST={6},INVTYPE_LEGS={7},INVTYPE_FEET={8},INVTYPE_WRIST={9},INVTYPE_HAND={10},INVTYPE_FINGER={11,12},INVTYPE_TRINKET={13,14},INVTYPE_CLOAK={15},INVTYPE_WEAPON={16,17},INVTYPE_WEAPONMAINHAND={16},INVTYPE_WEAPONOFFHAND={17},INVTYPE_SHIELD={17},INVTYPE_HOLDABLE={17},INVTYPE_2HWEAPON={16,17},INVTYPE_RANGED={18},INVTYPE_RANGEDRIGHT={18},INVTYPE_THROWN={18},INVTYPE_RELIC={18},INVTYPE_TABARD={19}}
local function itemID(link) local _,_,id=string.find(link or '','item:(%d+)');return tonumber(id) end
local function tooltip(link)
 if not A.tooltip then A.tooltip=CreateFrame('GameTooltip','OctoGuideRewardScan',UIParent,'GameTooltipTemplate') end
 local t=A.tooltip
 if not t.SetHyperlink or not t.NumLines then return nil end
 t:SetOwner(UIParent,'ANCHOR_NONE');t:ClearLines();t:SetHyperlink(link)
 if t:NumLines()==0 then t:Hide();return nil end
 local usable=true;local lines={}
 for i=1,t:NumLines() do
  for _,side in ipairs({'Left','Right'}) do
   local text=getglobal('OctoGuideRewardScanText'..side..i)
   if text then
    local r,g,b=text:GetTextColor();if r and r>.8 and g<.25 and b<.25 then usable=false end
    table.insert(lines,text:GetText() or '')
   end
  end
 end
 t:Hide();return usable,lines
end
local function fallbackStats(lines)
 if GetLocale and GetLocale()~='enUS' and GetLocale()~='enGB' then return nil end
 local stats={};local attributes={Strength='ITEM_MOD_STRENGTH_SHORT',Agility='ITEM_MOD_AGILITY_SHORT',Stamina='ITEM_MOD_STAMINA_SHORT',Intellect='ITEM_MOD_INTELLECT_SHORT',Spirit='ITEM_MOD_SPIRIT_SHORT'}
 for _,line in ipairs(lines) do
  local _,_,n,stat=string.find(line,'^%+(%d+) (.+)$');if n and attributes[stat] then stats[attributes[stat]]=tonumber(n) end
  local _,_,armor=string.find(line,'^(%d+) Armor$');if armor then stats.RESISTANCE0_NAME=tonumber(armor) end
  local _,_,dps=string.find(line,'([%d%.]+) damage per second');if dps then stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT=tonumber(dps) end
  -- Unsupported bonuses must stay manual rather than silently score as zero.
  if string.find(line,'^Equip:') or string.find(line,'^Use:') or string.find(line,'^Chance on hit:') or string.find(line,'Set: ',1,true) then return nil end
 end
 return stats
end
function A.Item(link)
 if not link then return nil end
 if A.cache[link] then return A.cache[link] end
 local id=itemID(link);if not id then return nil end
 local name,_,quality,level,minlevel,kind,subkind,stack,loc,texture,price,classID,subID
 if C_Item and type(C_Item.GetItemInfo)=='function' then
  name,_,quality,level,minlevel,kind,subkind,stack,loc,texture,price,classID=call(C_Item.GetItemInfo,link)
 else
  -- Stock Vanilla has no min-level field and equipLoc is return eight.
  name,_,quality,level,kind,subkind,stack,loc,texture=call(GetItemInfo,link)
 end
 if not name or not loc then return nil end
 if price==nil and C_Item then price=call(C_Item.GetItemSellPriceByID,id) end
 local stats=call(C_Item and C_Item.GetItemStats or GetItemStats,link)
 local usable,lines=tooltip(link)
 if slots[loc] and usable==nil then return nil end
 if slots[loc] and type(stats)~='table' and lines then stats=fallbackStats(lines) end
 local uncertain=false
 for _,line in ipairs(lines or {}) do if string.find(line,'^Use:') or string.find(line,'^Chance on hit:') or string.find(line,'Set: ',1,true) then uncertain=true end end
 local item={id=id,link=link,loc=loc,price=price,stats=stats,usable=usable~=false,level=minlevel,uncertain=uncertain}
 -- Cache only fully loaded data; retry missing data on a client event.
 if (not slots[loc] or type(stats)=='table') and type(price)=='number' then A.cache[link]=item end
 return item
end
local function weights()
 local class=G.player.class
 if class=='HUNTER' then return {str=.2,agi=2,sta=1,int=.4,spi=.2,ap=1,rap=1,spell=0,heal=0,dps=1,rdps=8,crit=8,hit=8} end
 if class=='ROGUE' then return {str=1,agi=2,sta=1,int=0,spi=.1,ap=1,rap=0,spell=0,heal=0,dps=8,rdps=.2,crit=8,hit=8} end
 if class=='WARRIOR' then return {str=2,agi=1,sta=1.2,int=0,spi=.2,ap=1,rap=0,spell=0,heal=0,dps=8,rdps=.2,crit=8,hit=8} end
 if class=='MAGE' or class=='WARLOCK' or class=='PRIEST' then return {str=0,agi=0,sta=1,int=2,spi=1,ap=0,rap=0,spell=2,heal=class=='PRIEST' and 1 or 0,dps=.1,rdps=4,crit=0,hit=0} end
 local spec,points=0,-1
 for i=1,3 do local _,_,spent=call(GetTalentTabInfo,i);if type(spent)=='number' and spent>points then spec,points=i,spent end end
 if class=='DRUID' and (points<=0 or spec==2) then return {str=2,agi=2,sta=1.2,int=.3,spi=.3,ap=1,rap=0,spell=0,heal=0,dps=0,rdps=0,crit=8,hit=8} end
 if class=='SHAMAN' and (points<=0 or spec==2) or class=='PALADIN' and (points<=0 or spec==3 or spec==2) then return {str=2,agi=1,sta=1.2,int=.6,spi=.4,ap=1,rap=0,spell=.3,heal=.2,dps=8,rdps=0,crit=8,hit=8} end
 if class=='DRUID' or class=='SHAMAN' or class=='PALADIN' then return {str=0,agi=0,sta=1,int=2,spi=1,ap=0,rap=0,spell=2,heal=(spec==3 or class=='PALADIN') and 2 or .3,dps=.1,rdps=0,crit=0,hit=0} end
 return nil
end
function A.Score(item)
 if not item or not item.usable or not slots[item.loc] or item.uncertain then return nil end
 if item.level and item.level>UnitLevel('player') then return nil end
 local w=weights();if not w or type(item.stats)~='table' then return nil end
 local hunter=G.player.class=='HUNTER'
 local map={ITEM_MOD_STRENGTH_SHORT=w.str,ITEM_MOD_AGILITY_SHORT=w.agi,ITEM_MOD_STAMINA_SHORT=w.sta,ITEM_MOD_INTELLECT_SHORT=w.int,ITEM_MOD_SPIRIT_SHORT=w.spi,ITEM_MOD_ATTACK_POWER_SHORT=w.ap,ITEM_MOD_RANGED_ATTACK_POWER_SHORT=w.rap,ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=w.spell,ITEM_MOD_SPELL_HEALING_DONE_SHORT=w.heal,ITEM_MOD_DAMAGE_PER_SECOND_SHORT=(item.loc=='INVTYPE_RANGED' or item.loc=='INVTYPE_RANGEDRIGHT') and w.rdps or w.dps,RESISTANCE0_NAME=.02,ITEM_MOD_HEALTH_SHORT=.1,ITEM_MOD_MANA_SHORT=.02,ITEM_MOD_CRIT_MELEE_RATING=hunter and 0 or w.crit,ITEM_MOD_CRIT_RANGED_RATING=hunter and w.crit or 0,ITEM_MOD_HIT_MELEE_RATING=hunter and 0 or w.hit,ITEM_MOD_HIT_RANGED_RATING=hunter and w.hit or 0,ITEM_MOD_CRIT_SPELL_RATING=w.spell>0 and 8 or 0,ITEM_MOD_HIT_SPELL_RATING=w.spell>0 and 8 or 0,ITEM_MOD_MANA_REGENERATION=w.int>0 and 2 or 0}
 local score=0
 for key,value in pairs(item.stats) do
  if type(value)=='number' and value~=0 then
   -- Resistances, procs and specialist gear should be reviewed manually.
   if map[key]==nil then return nil end
   score=score+value*map[key]
  end
 end
 return score
end
local function owned()
 if type(GetInventoryItemLink)~='function' or type(GetContainerNumSlots)~='function' or type(GetContainerItemLink)~='function' then return nil end
 local result={}
 local function add(link,slot)
  local item=A.Item(link);if not item then return false end
  local copy={};for k,v in pairs(item) do copy[k]=v end;copy.equippedSlot=slot;table.insert(result,copy);return true
 end
 for slot=1,19 do local link=GetInventoryItemLink('player',slot);if link and not add(link,slot) then return nil end end
 for bag=0,4 do for slot=1,GetContainerNumSlots(bag) do local link=GetContainerItemLink(bag,slot);if link and not add(link) then return nil end end end
 return result
end
local function baseline(item,inventory)
 local weapons={INVTYPE_WEAPON=true,INVTYPE_2HWEAPON=true,INVTYPE_WEAPONMAINHAND=true,INVTYPE_WEAPONOFFHAND=true,INVTYPE_SHIELD=true,INVTYPE_HOLDABLE=true}
 if weapons[item.loc] then
  local pool={};local dual=call(IsSpellKnown,674)==true or G.player.class=='ROGUE'
  for _,a in ipairs(inventory) do if a.usable and weapons[a.loc] then if A.Score(a)==nil then return nil end;table.insert(pool,a) end end
  local function best(include)
   local total=0
   local candidates={};for _,a in ipairs(pool) do table.insert(candidates,a) end
   if include then table.insert(candidates,item) end
   for _,main in ipairs(candidates) do
    if main.loc=='INVTYPE_2HWEAPON' or main.loc=='INVTYPE_WEAPON' or main.loc=='INVTYPE_WEAPONMAINHAND' then
     local score=A.Score(main)
     if not include or main==item then total=math.max(total,score) end
     if main.loc~='INVTYPE_2HWEAPON' then
      for _,off in ipairs(candidates) do
       local offAllowed=off.loc=='INVTYPE_SHIELD' or off.loc=='INVTYPE_HOLDABLE' or (dual and (off.loc=='INVTYPE_WEAPON' or off.loc=='INVTYPE_WEAPONOFFHAND'))
       if off~=main and offAllowed and (not include or main==item or off==item) then total=math.max(total,score+A.Score(off)) end
      end
     end
    end
   end
   -- A shield/held item can also improve an otherwise empty main-hand slot.
   if include and (item.loc=='INVTYPE_SHIELD' or item.loc=='INVTYPE_HOLDABLE' or dual and item.loc=='INVTYPE_WEAPONOFFHAND') then total=math.max(total,A.Score(item)) end
   return total
  end
  return best(false)-best(true)+A.Score(item)
 end
 local target=slots[item.loc];local values={};for _,slot in ipairs(target) do values[slot]={} end
 for _,a in ipairs(inventory) do
  if a.usable and slots[a.loc] then
   local score=A.Score(a)
   for _,slot in ipairs(slots[a.loc]) do
    if values[slot] then
     if score==nil then return nil end
     table.insert(values[slot],{score=score,link=a.link,slot=a.equippedSlot})
    end
   end
  end
 end
 local best=0
 if item.loc=='INVTYPE_FINGER' or item.loc=='INVTYPE_TRINKET' then
  local a,b=0,0
  for _,v in ipairs(values[target[1]]) do
   if v.score>a then b=a;a=v.score elseif v.score>b then b=v.score end
  end
  return b
 end
 for _,slot in ipairs(target) do for _,v in ipairs(values[slot]) do best=math.max(best,v.score) end end
 return best
end
function A.ChooseReward()
 local n=call(GetNumQuestChoices);if type(n)~='number' or n<1 then return nil,'No choices' end
 local inventory=owned();if not inventory then return nil,'Item data unavailable' end
 local best,bestGain,vendor,vendorValue=nil,0,nil,-1
 for i=1,n do
  local link=call(GetQuestItemLink,'choice',i);local item=A.Item(link)
  if not item or type(item.price)~='number' then return nil,'Item data unavailable' end
  local _,_,count=call(GetQuestItemInfo,'choice',i);if type(count)~='number' then return nil,'Reward quantity unavailable' end
  local value=item.price*count;if value>vendorValue then vendor,vendorValue=i,value end
  if item.usable and slots[item.loc] then
   local score=A.Score(item);if score==nil then return nil,'Compare this equipment manually' end
   local current=baseline(item,inventory)
   if current==nil then return nil,'Compare this equipment manually' end
   local gain=score-current
   if gain>bestGain then best,bestGain=i,gain end
  end
 end
 return best or vendor,best and 'Equipment upgrade' or 'Highest vendor value'
end
local function reward(id)
 local count=call(GetNumQuestChoices);if type(count)~='number' then return end
 local choice
 if count==0 then choice=0 elseif count==1 then choice=1
 elseif enabled('autoReward') then choice=A.ChooseReward() end
 if choice~=nil then
  -- Set the existing evidence hook before the request, independent of frame order.
  G.rewardDialogQuestID=id
  if enabled('autoTurnIn') then send('reward:'..id,GetQuestReward,choice)
  elseif enabled('autoReward') and count>1 and getglobal then
   local b=getglobal('QuestRewardItem'..choice)
   if b and b.GetScript then
    local click=b:GetScript('OnClick')
    if click then local previous=this;this=b;pcall(click);this=previous end
   end
  end
 else A.pending=id end
end
local function selectQuest(action,id,fn,index)
 A.selected={id=id,action=action}
 send('select:'..action..':'..id,fn,index)
end
function A.Greeting(gossip)
 A.selected=nil;A.sent={};A.pending=nil
 if C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetActiveQuests then
  local active=call(C_GossipInfo.GetActiveQuests) or {};local available=call(C_GossipInfo.GetAvailableQuests) or {}
  for _,q in ipairs(active) do
   if enabled('autoTurnIn') and A.Step(q.questID,'turnin') and complete(q.questID) then selectQuest('turnin',q.questID,C_GossipInfo.SelectActiveQuest,q.questID);return end
  end
  for _,q in ipairs(available) do
   if enabled('autoAccept') and A.Step(q.questID,'accept') then selectQuest('accept',q.questID,C_GossipInfo.SelectAvailableQuest,q.questID);return end
  end
  if table.getn(active)+table.getn(available)>0 then return end
 end
 if not gossip then
  for i=1,call(GetNumActiveQuests) or 0 do local name=call(GetActiveTitle,i);local id=name and resolve(name,'turnin');if enabled('autoTurnIn') and id and complete(id) then selectQuest('turnin',id,SelectActiveQuest,i);return end end
  for i=1,call(GetNumAvailableQuests) or 0 do local name=call(GetAvailableTitle,i);local id=name and resolve(name,'accept');if enabled('autoAccept') and id then selectQuest('accept',id,SelectAvailableQuest,i);return end end
 else
  -- Stock 1.12 gossip uses title/level pairs for both lists.
  if GetGossipActiveQuests and enabled('autoTurnIn') then
   local list={GetGossipActiveQuests()}
   for i=1,table.getn(list),2 do local id=resolve(list[i],'turnin');if id and complete(id) then selectQuest('turnin',id,SelectGossipActiveQuest,(i+1)/2);return end end
  end
  if GetGossipAvailableQuests and enabled('autoAccept') then
   local list={GetGossipAvailableQuests()}
   for i=1,table.getn(list),2 do local id=resolve(list[i],'accept');if id then selectQuest('accept',id,SelectGossipAvailableQuest,(i+1)/2);return end end
  end
 end
end
function A.Event(ev)
 if ev=='QUEST_FINISHED' or ev=='PLAYER_ENTERING_WORLD' then A.pending=nil;A.selected=nil;A.sent={};return end
 if ev=='GOSSIP_CLOSED' then A.pending=nil;return end
 if ev=='BAG_UPDATE' or ev=='PLAYER_EQUIPMENT_CHANGED' or ev=='PLAYER_LEVEL_UP' then A.cache={} end
 if paused() then return end
 if ev=='QUEST_GREETING' or ev=='GOSSIP_SHOW' then A.Greeting(ev=='GOSSIP_SHOW')
 elseif ev=='QUEST_DETAIL' and enabled('autoAccept') then
  local id=A.DialogID('accept');if id then send('accept:'..id,AcceptQuest) end
 elseif ev=='QUEST_PROGRESS' and enabled('autoTurnIn') then
  local id=A.DialogID('turnin');if id and call(IsQuestCompletable) then send('complete:'..id,CompleteQuest) end
 elseif ev=='QUEST_COMPLETE' and (enabled('autoTurnIn') or enabled('autoReward')) then
  local id=A.DialogID('turnin');if id and complete(id) then A.pending=nil;reward(id) end
 elseif ev=='GET_ITEM_INFO_RECEIVED' and A.pending then
  local id=A.DialogID('turnin');if id==A.pending and complete(id) then A.cache={};reward(id) end
 end
end
local f=CreateFrame('Frame');A.frame=f
for _,ev in ipairs({'QUEST_GREETING','GOSSIP_SHOW','QUEST_DETAIL','QUEST_PROGRESS','QUEST_COMPLETE','QUEST_FINISHED','GOSSIP_CLOSED','GET_ITEM_INFO_RECEIVED','BAG_UPDATE','PLAYER_EQUIPMENT_CHANGED','PLAYER_LEVEL_UP','PLAYER_ENTERING_WORLD'}) do pcall(function() f:RegisterEvent(ev) end) end
f:SetScript('OnEvent',function() A.Event(event) end)
function G.BuildAutomationSettings()
 local options=G.options
 local p=G.MakeCard(UIParent);options.automationPanel=p
 p:SetWidth(410);p:SetHeight(280);p:SetPoint('CENTER',UIParent,'CENTER',0,0);p:SetFrameStrata('DIALOG');p:EnableMouse(true)
 if p.SetFrameLevel and options.GetFrameLevel then p:SetFrameLevel(options:GetFrameLevel()+10) end
 options.automationButton=G.MakeButton(options,'Quest automation settings',260,function() G.UpdateAutomationSettings();p:Show() end);G.Place(options.automationButton,options,25,605)
 p.automationRows={}
 local h=G.MakeLabel(p,16,360,true);G.Place(h,p,25,20);h:SetHeight(24);h:SetText('Optional quest automation')
 for i,spec in ipairs({{'autoAccept','Accept guide quests'},{'autoTurnIn','Turn in guide quests'},{'autoReward','Choose reward: gear / vendor value'}}) do
  local b=G.MakeButton(p,'',360,function() G.db[this.optionKey]=not G.db[this.optionKey];G.UpdateAutomationSettings() end)
  b.optionKey=spec[1];b.optionLabel=spec[2];G.Place(b,p,25,60+(i-1)*33);p.automationRows[i]=b
 end
 local hint=G.MakeLabel(p,10,360);G.Place(hint,p,25,162);hint:SetHeight(58);hint:SetText('All OFF by default. Hold Shift for manual control.\nCompares class leveling stats with gear and bags.\nUncertain equipment or missing data stays manual.')
 local close=G.MakeButton(p,'Close',80,function() p:Hide() end);G.Place(close,p,305,232);p:Hide()
 G.UpdateAutomationSettings()
end
function G.UpdateAutomationSettings()
 local p=G.options and G.options.automationPanel;if not p then return end
 for _,b in ipairs(p.automationRows) do b:SetText((enabled(b.optionKey) and '[ON] ' or '[OFF] ')..b.optionLabel) end
end
