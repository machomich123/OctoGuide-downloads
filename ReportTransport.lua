local G=OctoGuide
local function quote(s)
 return '"'..string.gsub(s,'[%z\1-\31\\"]',function(c)
  if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
  return string.format('\\u%04x',string.byte(c))
 end)..'"'
end
function G.ReportJSON(value,depth)
 depth=depth or 0;if depth>12 then return 'null' end
 local kind=type(value)
 if kind=='string' then return quote(value) elseif kind=='boolean' then return value and 'true' or 'false'
 elseif kind=='number' then return value==value and math.abs(value)<1e100 and tostring(value) or 'null'
 elseif kind~='table' then return 'null' end
 local count,max=0,0;local array=true
 for key in pairs(value) do count=count+1;if type(key)~='number' or key<1 or key~=math.floor(key) then array=false else max=math.max(max,key) end end
 array=array and count==max and count>0;local items={}
 if array then for _,v in ipairs(value) do table.insert(items,G.ReportJSON(v,depth+1)) end
 else for k,v in pairs(value) do if type(k)=='string' then table.insert(items,quote(k)..':'..G.ReportJSON(v,depth+1)) end end end
 return (array and '[' or '{')..table.concat(items,',')..(array and ']' or '}')
end
function G.ReportBridgeReady()
 return type(OctoGuideBridgeVersion)=='function' and type(OctoGuideSendReport)=='function' and type(OctoGuideReportStatus)=='function'
end
function G.CaptureReportUI()
 G.captureCount=0;G.captureTime=GetTime and GetTime() or 0
 if not G.ReportBridgeReady() or not OctoGuideCaptureUI or not OctoGuideCaptureBegin then return end
 OctoGuideCaptureBegin()
 local pixelFactor=1
 if OctoGuideCaptureViewport or GetPhysicalScreenSize then
  local pw,ph=(OctoGuideCaptureViewport or GetPhysicalScreenSize)()
  -- Vanilla region coordinates use the 768-unit reference height, including glue.
  if type(ph)=='number' and ph>0 then pixelFactor=ph/768 end
 end
 for _,item in ipairs({{name='guide',frame=G.frame},{name='guides',frame=G.menu},{name='settings',frame=G.options}}) do
  local f=item.frame
  if f and f:IsShown() then
   local scale=f:GetEffectiveScale()*pixelFactor;local left,bottom=f:GetLeft(),f:GetBottom()
   if left and bottom then local ok,result=pcall(OctoGuideCaptureUI,item.name,math.floor(left*scale),math.floor(bottom*scale),math.floor(f:GetWidth()*scale),math.floor(f:GetHeight()*scale));if ok and result then G.captureCount=G.captureCount+1 end end
  end
 end
end
function G.SendReport(description)
 if G.pendingReport then return nil,'A report is already sending.' end
 local r,why=G.MakeReport(description);if not r then return nil,why end
 if not G.ReportBridgeReady() then return r,'Saved locally. Update existing ClassicAPI once for online reports and UI images.' end
 r.images=G.captureCount>0 and 'Visible UI crops captured before opening report form; closed menus have state snapshots only' or 'UI state snapshots only; pixel capture unavailable'
 r.captureCount=G.captureCount;r.captureTime=G.captureTime;r.status='sending';r.upload='pending'
 local ok,accepted=pcall(OctoGuideSendReport,G.ReportJSON(r))
 if not ok or not accepted then r.status='saved locally';r.upload='failed';return r,'Upload could not start. The local report is retained.' end
 G.pendingReport=r
 return r,'Sending in background...'
end
function G.PollReport()
 if not G.pendingReport then return end
 local ok,status,receipt=pcall(OctoGuideReportStatus);if not ok then return end
 if status=='sent' or status=='failed' then
  local r=G.pendingReport;r.status=status=='sent' and 'received online' or 'saved locally';r.upload=status;r.receipt=receipt;G.pendingReport=nil
  if G.reportWindow then
   local message=status=='sent' and 'Report received online. Thank you!' or 'Upload failed. Report retained locally; press Send again to retry.'
   if status=='sent' and receipt and string.find(receipt,'"images":0',1,true) then message='Report received online. UI images were unavailable; diagnostics are included.' end
   G.reportWindow.status:SetText(message)
   if status=='sent' then G.reportWindow.field:SetText('') end
  end
 end
end
local build=G.BuildUI
function G.BuildUI()
 build();local poll=CreateFrame('Frame',nil,UIParent);local elapsed=0
 poll:SetScript('OnUpdate',function() elapsed=elapsed+(arg1 or .01);if elapsed>=.5 then elapsed=0;G.PollReport() end end);G.reportPollFrame=poll
 if G.options.reportHint then G.options.reportHint:SetText(G.ReportBridgeReady() and 'Online reports ready. Captures visible OctoGuide UI only.' or 'Local reports ready. ClassicAPI update enables online reports and images.') end
end
