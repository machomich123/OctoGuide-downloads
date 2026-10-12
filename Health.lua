-- Shared dependency diagnostics; Lua 5.0 / WoW 1.12. No game actions or network requests.
if not OctoAddonHealth or OctoAddonHealth.version~=1 then
OctoAddonHealth={version=1,profiles={},active={},states={},runtime={},announced={}}
local H=OctoAddonHealth
local function append(list,text) table.insert(list,text) end
local function present(value) return type(value)=='function' end
local function module(list,object,key,label)
 if not object or not present(object[key]) then append(list,'Addon file did not load: '..label..'. Update this addon in the launcher, then /reload.') end
end
function H.Register(id,check) H.profiles[id]=check end
function H.Check(id,quiet)
 local missing,warnings={},{}
 local check=H.profiles[id]
 if check then
  local ok,why=pcall(check,missing,warnings)
  if not ok then append(missing,'Requirement check failed. Update this addon and use /octocheck. Detail: '..tostring(why)) end
 else append(missing,'Addon requirement checker did not load. Update this addon.') end
 if H.runtime[id] then append(missing,H.runtime[id]) end
 local state={ok=table.getn(missing)==0,missing=missing,warnings=warnings}
 H.states[id]=state
 if not quiet and (not state.ok or table.getn(warnings)>0) then H.Show(id) end
 return state.ok,state
end
function H.Text(id)
 local state=H.states[id] or {};local lines={id}
 for _,s in ipairs(state.missing or {}) do append(lines,'ERROR: '..s) end
 for _,s in ipairs(state.warnings or {}) do append(lines,'LIMITED FEATURE: '..s) end
 if state.ok and table.getn(state.warnings or {})==0 then append(lines,'Requirements loaded.') end
 return table.concat(lines,'\n')
end
function H.Show(id)
 if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffff7755'..H.Text(id)..'|r') end
 if not UIParent or not CreateFrame then return end
 if not H.panel then
  local p=CreateFrame('Frame','OctoAddonHealthPanel',UIParent)
  p:SetWidth(550);p:SetHeight(350);p:SetPoint('CENTER',UIParent,'CENTER',0,60);p:SetFrameStrata('DIALOG')
  p:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  p:SetBackdropColor(.05,.05,.07,.98)
  p:EnableMouse(true);p:SetMovable(true);p:RegisterForDrag('LeftButton')
  p:SetScript('OnDragStart',function() p:StartMoving() end);p:SetScript('OnDragStop',function() p:StopMovingOrSizing() end)
  local title=p:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',p,'TOPLEFT',20,-18);title:SetText('Octo addon requirements')
  local scroll=CreateFrame('ScrollFrame',nil,p,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',p,'TOPLEFT',20,-48);scroll:SetWidth(480);scroll:SetHeight(235)
  local child=CreateFrame('Frame',nil,scroll);child:SetWidth(470);child:SetHeight(235);scroll:SetScrollChild(child)
  p.text=child:CreateFontString(nil,'OVERLAY','GameFontHighlight');p.text:SetPoint('TOPLEFT',child,'TOPLEFT',0,0);p.text:SetWidth(465);p.text:SetJustifyH('LEFT');p.text:SetJustifyV('TOP');p.child=child
  local again=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');again:SetWidth(140);again:SetHeight(25);again:SetPoint('BOTTOMLEFT',p,'BOTTOMLEFT',20,18);again:SetText('Check again')
  again:SetScript('OnClick',function() H.runtime={};H.CheckAll(true) end)
  local close=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');close:SetWidth(100);close:SetHeight(25);close:SetPoint('BOTTOMRIGHT',p,'BOTTOMRIGHT',-20,18);close:SetText('Close');close:SetScript('OnClick',function() p:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames,'OctoAddonHealthPanel') end
  H.panel=p
 end
 local lines={}
 for name,state in pairs(H.states) do if name==id or not state.ok or table.getn(state.warnings)>0 then append(lines,H.Text(name)) end end
 local message=table.concat(lines,'\n\n');H.panel.text:SetText(message)
 -- Vanilla lacks GetStringHeight. Reserve enough scroll space for wrapped diagnostics.
 local height=0
 for line in string.gfind(message..'\n','([^\n]*)\n') do height=height+math.max(1,math.ceil(string.len(line)/60))*17 end
 if H.panel.text.GetStringHeight then height=H.panel.text:GetStringHeight()+10 end
 H.panel.child:SetHeight(math.max(235,height))
 H.panel:Show()
end
function H.Failure(id,why)
 H.runtime[id]='A loaded addon module failed: '..tostring(why)..'. Update the addon and check its requirements before continuing.'
 H.Check(id,true);H.Show(id)
end
function H.Call(id,fn,...)
 local args=arg
 if not H.Check(id,false) then return false,'Required addon components are unavailable.' end
 local result={pcall(fn,unpack(args))}
 if not result[1] then H.Failure(id,result[2]);return false,result[2] end
 table.remove(result,1);return unpack(result)
end
function H.CheckAll(force)
 for id in pairs(H.profiles) do
  if H.active[id] then
  local ok,state=H.Check(id,true);local text=H.Text(id)
  if force or ((not ok or table.getn(state.warnings)>0) and H.announced[id]~=text) then H.announced[id]=text;H.Show(id) end
  end
 end
end
function H.InstallErrorCapture()
 if H.errorCapture or not present(geterrorhandler) or not present(seterrorhandler) then return end
 local previous=geterrorhandler();if not present(previous) then return end
 H.errorCapture=true
 seterrorhandler(function(why)
  if not H.reporting then
   local text=tostring(why)
   for id in pairs(H.active) do
    local marker=id=='OctoHunter' and 'OctoHunterProbe' or id
    if string.find(text,marker,1,true) then H.reporting=true;pcall(H.Failure,id,why);H.reporting=nil;break end
   end
  end
  return previous(why)
 end)
end
H.Register('OctoGuide',function(missing,warnings)
 local G=OctoGuide
 module(missing,G,'BuildUI','UI.lua');module(missing,G,'AutoPlace','Placement.lua');module(missing,G,'Render','UI.lua');module(missing,G,'LocalGoalsDone','Goals.lua')
 if not G or not G.guides or not next(G.guides) then append(missing,'Guide data is missing or did not load. Update OctoGuide and its installed route pack; this is not completed progress.') end
 local q=C_QuestLog
 if not ((q and (present(q.GetLogIndexForQuestID) or present(q.GetQuestIDForLogIndex))) or present(GetQuestIDFromLogIndex)) then append(missing,'ClassicAPI.dll quest-ID functions are unavailable. Enable ClassicAPI in the launcher Mods tab and restart the entire game. Find step and automatic quest progress are paused.') end
 if not present(UnitPosition) or not present(GetPlayerFacing) or not C_Map or not present(C_Map.GetWorldPosFromMapPos) then append(warnings,'ClassicAPI navigation functions are unavailable. Enable ClassicAPI and restart the game. Route text remains available; precise world navigation is limited.') end
 if G and G.db and G.db.routeSource=='rxp' and not G.hasFamilyRoutes then append(missing,'The selected route pack did not load. Enable or update RestedXP Routes (OctoGuideFamily); saved progress has been kept.') end
end)
H.Register('OctoBoard',function(missing,warnings)
 local B=OctoBoard
 module(missing,B,'BuildUI','UI.lua');module(missing,B,'Parse','Core.lua');module(missing,B,'Publish','Market.lua');module(missing,B,'ResolveItems','Items.lua')
 if type(OctoBoardItemData)~='table' or not next(OctoBoardItemData) then append(missing,'The item catalogue did not load (ItemData.lua). Update OctoBoard; empty data is not an empty market.') end
 -- Public-chat tracking uses the stock client API; no native DLL is required.
 if not present(SendChatMessage) then append(missing,'The client chat API is unavailable. Posting is disabled until the client/addon finishes loading.') end
end)
H.Register('OctoGather',function(missing,warnings)
 local G=OctoGather
 module(missing,G,'Init','Core.lua');module(missing,G,'BuildUI','UI.lua');module(missing,G,'Event','Observe.lua');module(missing,G,'NearbySupported','Nearby.lua')
 if type(OctoGatherData)~='table' or type(OctoGatherData.nodes)~='table' or type(OctoGatherData.zones)~='table' then append(missing,'Resource data did not load (Data.lua). Update OctoGather; no data does not mean no resources.') end
 if not GameTooltip or not present(GameTooltip.GetGameObject) then append(warnings,'ClassicAPI object identification is unavailable. Name matching and stored locations remain available; object IDs and nearby observations are limited. Enable ClassicAPI and restart the game.') end
end)
H.Register('OctoHunter',function(missing,warnings)
 local P=OctoHunterProbe
 module(missing,P,'Show','Journal.lua');module(missing,P,'NativeReady','Probe.lua');module(missing,P,'AutoTick','Probe.lua')
 if type(OctoHunterData)~='table' or type(OctoHunterModelViews)~='table' then append(missing,'Hunter data or model settings did not load. Update OctoHunter in the launcher.') end
 local ok,available=false,false
 if P and present(P.NativeReady) then ok,available=pcall(P.NativeReady) end
 if not ok or not available then append(warnings,'OctoHunterNative.dll is missing, rejected this client, or failed to register its API. Automatic feeding is unavailable. Restart the game after repairing the native mod; the pet guide and manual controls remain available.') end
end)
local frame=CreateFrame('Frame','OctoAddonHealthEvents',UIParent);H.frame=frame
frame:RegisterEvent('PLAYER_ENTERING_WORLD');frame:RegisterEvent('ADDON_LOADED')
frame:SetScript('OnEvent',function() if event=='PLAYER_ENTERING_WORLD' then H.remaining=1 end end)
frame:SetScript('OnUpdate',function()
 if not H.remaining then return end
 H.remaining=H.remaining-(arg1 or 0)
 if H.remaining<=0 then H.remaining=nil;H.InstallErrorCapture();H.CheckAll(false) end
end)
SLASH_OCTOADDONCHECK1='/octocheck';SlashCmdList.OCTOADDONCHECK=function() H.CheckAll(true) end
end

OctoAddonHealth.active['OctoGuide']=true
