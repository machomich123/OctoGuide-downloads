-- Advance training only from learned-spell/skill evidence, never a window opening.
local G=OctoGuide
local T={};G.training=T
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b,c,d,e=pcall(fn,unpack(arg));if ok then return a,b,c,d,e end
end
local function yes(value) return value==true or value==1 end
local function rank(value)
 if not value or value=='' then return 0 end
 local _,_,n=string.find(value,'(%d+)');return tonumber(n)
end
local function atLeast(actual,wanted)
 if actual==wanted then return true end
 local a,b=rank(actual),rank(wanted)
 return a~=nil and b~=nil and a>=b
end
function T.BookKnows(name,wanted,pet)
 if type(name)~='string' or name=='' or type(GetSpellName)~='function' then return false end
 local book=pet and (BOOKTYPE_PET or 'pet') or (BOOKTYPE_SPELL or 'spell')
 local count=0
 if pet then count=call(HasPetSpells) or 0
 elseif GetNumSpellTabs and GetSpellTabInfo then
  for i=1,call(GetNumSpellTabs) or 0 do local _,_,offset,n=call(GetSpellTabInfo,i);if type(offset)=='number' and type(n)=='number' then count=math.max(count,offset+n) end end
 else return false end
 if type(count)~='number' then return false end
 for i=1,count do local known,knownRank=call(GetSpellName,i,book);if known==name and atLeast(knownRank,wanted) then return true end end
 return false
end
local professions={skinning=8613,herbalism=2366,mining=2575,cooking=2550,['first aid']=3273,fishing=7620,alchemy=2259,blacksmithing=2018,enchanting=7411,engineering=4036,leatherworking=2108,tailoring=3908}
local function profession(s)
 local _,_,name=string.find(string.lower(s.text or ''),'^learn the (.-) profession%.?$')
 return name and professions[name]
end
local function skillKnown(s,id)
 local name=s.skillName
 if not name and id then name=call(GetSpellInfo,id) end
 if not name then return false end
 for i=1,call(GetNumSkillLines) or 0 do
  local found,header,_,value=call(GetSkillLineInfo,i)
  if not header and found==name and type(value)=='number' and value>=(s.skillRank or 1) then return true end
 end
 return false
end
function G.TrainingSatisfied(s)
 if not s or s.action~='train' or s.minlevel and (UnitLevel('player') or 0)<s.minlevel then return false end
 local id=s.spellID or profession(s)
 if id then
  -- IsPlayerSpell also sees learned recipes/passives absent from the spellbook.
  if not s.petSpell and (yes(call(IsPlayerSpell,id)) or yes(call(IsSpellKnown,id))) then return true end
  if s.petSpell and yes(call(IsSpellKnown,id,true)) then return true end
  local name,wanted=call(GetSpellInfo,id)
  if T.BookKnows(name,wanted,s.petSpell==true) then return true end
  if (s.skillName or profession(s)) and skillKnown(s,id) then return true end
  return false
 end
 if s.skillName then return skillKnown(s) end
 -- A generic class-training visit covers all services available at arrival.
 -- A partial purchase, changed filter, rejected purchase or open trainer is not done.
 local visit=T.visit
 if visit and visit.step==s and visit.key==G.Key(s) and table.getn(visit.targets)>0 then
  for _,service in ipairs(visit.targets) do if not T.BookKnows(service.name,service.rank,false) then return false end end
  return true
 end
 return false
end
function T.CaptureTrainer()
 T.visit=nil
 local s=G.Current();if not s or s.action~='train' or s.spellID or profession(s) or s.skillName then return end
 if not s.personalClass or s.personalClass~=G.player.class then return end
 if G.pauseAuto and G.state.reviewReason~='jump' then return end
 local filter=call(GetTrainerServiceTypeFilter,'available')
 if filter~=nil and not yes(filter) then return end
 local targets={};local count=call(GetNumTrainerServices)
 if type(count)~='number' then return end
 for i=1,count do
  local name,wanted,category=call(GetTrainerServiceInfo,i)
  if category=='available' and type(name)=='string' and not T.BookKnows(name,wanted,false) then table.insert(targets,{name=name,rank=wanted}) end
 end
 if table.getn(targets)>0 then T.visit={step=s,key=G.Key(s),targets=targets} end
end
local events={SPELLS_CHANGED=true,LEARNED_SPELL_IN_TAB=true,SKILL_LINES_CHANGED=true,TRAINER_SHOW=true,TRAINER_UPDATE=true,TRAINER_CLOSED=true,CRAFT_UPDATE=true,PET_BAR_UPDATE=true,UNIT_PET=true}
function G.TrainingEvent(ev,unit)
 if not events[ev] then return false end
 if ev=='UNIT_PET' and unit and unit~='player' then return false end
 if ev=='TRAINER_SHOW' then T.CaptureTrainer() elseif ev=='TRAINER_CLOSED' then T.visit=nil end
 return true
end
