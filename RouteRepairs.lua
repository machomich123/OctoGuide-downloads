-- Server-verified route corrections; private guide content is not redistributed.
local G=OctoGuide
local register=G.RegisterGuide
function G.RegisterGuide(meta,steps)
 for i,s in ipairs(steps) do
  local nextStep=steps[i+1]
  if s.action=='vendor' and string.find(s.text or '','Hornwood Recurve Bow',1,true) and nextStep and nextStep.action=='collect' and nextStep.itemID==2506 then
   s.goalItemID=2506;s.goalItemCount=1
  end
 end
 local wild,hasLost
 for _,s in ipairs(steps) do
  if s.action=='accept' and s.questID==429 then wild=s end
  if s.action=='accept' and s.questID==428 then hasLost=true end
 end
 if meta.routeFamily=='rxp' and wild and not hasLost then
  local pickup={id='octo-required-428-accept',action='accept',questID=428,text='Accept Lost Deathstalkers from High Executor Hadrec at the Sepulcher.',name='High Executor Hadrec',entity=1952,zone=130,x=.434,y=.409,minlevel=10,requires={},requiredForQuest=429,page='octo-required-428-pickup',sourceBlock=0,expectedLevel=meta.startLevel}
  local turn={id='octo-required-428-turnin',action='turnin',questID=428,text='Turn in Lost Deathstalkers to Rane Yorick before accepting Wild Hearts.',name='Rane Yorick',entity=1950,zone=130,x=.535,y=.134,minlevel=10,requiredForQuest=429,page='octo-required-428-return',sourceBlock=0,expectedLevel=wild.expectedLevel}
  table.insert(steps,1,pickup)
  for i,s in ipairs(steps) do if s==wild then table.insert(steps,i,turn);break end end
  wild.requires=wild.requires or {};local found=false
  for _,id in ipairs(wild.requires) do if id==428 then found=true end end
  if not found then table.insert(wild.requires,428) end
 end
 register(meta,steps)
end
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,a,b=pcall(fn,unpack(arg));if ok then return a,b end
end
local function matches(link,id)
 if type(link)~='string' then return false end
 local _,_,n=string.find(link,'item:(%d+)');return tonumber(n)==id
end
function G.GoalItemCarried(s)
 if not s then return false end
 local id=s.goalItemID or ((s.action=='collect' or s.action=='buy') and s.itemID)
 local wanted=s.goalItemCount or s.itemCount
 if not id or not wanted then return false end
 local count=call(GetItemCount,id) or 0;local slots=0
 for bag=0,4 do for index=1,call(GetContainerNumSlots,bag) or 0 do
  if matches(call(GetContainerItemLink,bag,index),id) then local _,n=call(GetContainerItemInfo,bag,index);slots=slots+(tonumber(n) or 1) end
 end end
 for index=1,19 do if matches(call(GetInventoryItemLink,'player',index),id) then slots=slots+1 end end
 return math.max(type(count)=='number' and count or 0,slots)>=wanted
end
