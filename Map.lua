-- Reuse pfQuest frames. Never create, position or move quest map icons.
local G=OctoGuide
OctoGuideMap={factor=1.25,highlighted={}}
local M=OctoGuideMap
function G.MapOptions()
 if not G.db then return {targets=true,minimap=true} end
 G.db.mapOptions=G.db.mapOptions or {};local o=G.db.mapOptions
 o.routes=nil;o.checkpoints=nil
 if o.targets==nil then o.targets=true end
 if o.minimap==nil then o.minimap=true end
 return o
end
function G.SetMapOption(key,value)
 if key~='targets' and key~='minimap' then return false end
 local o=G.MapOptions();o[key]=value==true;G.UpdateMaps(true);return true
end
function M.Matches(step,node)
 local id=step and (step.questID or step.startsQuestID)
 if not id or type(node)~='table' then return false end
 for _,meta in pairs(node) do
  if type(meta)=='table' and meta.questid==id then
   local kind=meta.QTYPE
   if step.action=='accept' or step.startsQuestID then
    if kind=='NPC_START' or kind=='OBJECT_START' then return true end
   elseif step.action=='turnin' then
    if kind=='NPC_END' or kind=='OBJECT_END' then return true end
   elseif kind and string.find(kind,'OBJECTIVE',1,true) then return true end
  end
 end
 return false
end
local function size(frame,value)
 -- Read actual dimensions so native hover/resizing remains authoritative.
 if not frame.GetWidth or frame:GetWidth()~=value then frame:SetWidth(value) end
 if not frame.GetHeight or frame:GetHeight()~=value then frame:SetHeight(value) end
end
function M.Apply(frame,originalUpdated,context)
 if not frame then return end
 -- pfQuest resets defsize inside UpdateNode, including recycled frames.
 if originalUpdated or frame.octoBaseSize==nil then frame.octoBaseSize=frame.defsize end
 local base=frame.octoBaseSize or frame.defsize
 if type(base)~='number' then return end
 local o=context and context.options or G.MapOptions()
 local current;if context then current=context.current else current=G.ready and G.Current and G.Current() end
 local enabled=o.targets and (not frame.minimap or o.minimap)
 local highlighted=enabled and M.Matches(current,frame.node)
 local hovering=pfMap and pfMap.highlight and pfMap.highlightdb and pfMap.highlightdb[frame] and pfMap.highlightdb[frame][pfMap.highlight]
 if highlighted then
  frame.defsize=base*M.factor;if not hovering then size(frame,frame.defsize) end
  M.highlighted[frame]=true
 elseif M.highlighted[frame] then
  frame.defsize=base;if not hovering then size(frame,base) end;M.highlighted[frame]=nil
 end
end
function M.Install()
 if not pfMap or type(pfMap.UpdateNode)~='function' then return false end
 if M.wrapper then return true end
 local update=pfMap.UpdateNode
 M.wrapper=function(self,frame,...)
  local result=update(self,frame,unpack(arg))
  M.Apply(frame,true)
  return result
 end
 pfMap.UpdateNode=M.wrapper;return true
end
function G.UpdateMaps(force)
 M.Install()
 local context={options=G.MapOptions(),current=G.ready and G.Current and G.Current()}
 M.epoch=(M.epoch or 0)+1
 local function apply(frame)
  if frame and frame.octoMapEpoch~=M.epoch then frame.octoMapEpoch=M.epoch;M.Apply(frame,false,context) end
 end
 -- pfQuest controls visibility, position, rotation, textures, hover and clicks.
 for frame in pairs(M.highlighted) do apply(frame) end
 if pfMap then
  for _,list in ipairs({pfMap.pins or {},pfMap.mpins or {}}) do
   for _,frame in pairs(list) do apply(frame) end
  end
 end
end
function G.BuildMaps()
 G.MapOptions();M.Install()
 if M.driver or not CreateFrame then return M.wrapper~=nil end
 M.driver=CreateFrame('Frame');local elapsed=0
 M.driver:SetScript('OnUpdate',function()
  elapsed=elapsed+(arg1 or 0)
  if elapsed>=.5 then elapsed=0;G.UpdateMaps(false) end
 end)
 return true
end
