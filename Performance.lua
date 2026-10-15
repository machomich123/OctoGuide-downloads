-- Constant-size local measurements, no network or external tracing.
-- A slow frame alone is NOT evidence that this addon caused it.
local G=OctoGuide
local p={version=G.version,timerAvailable=type(debugprofilestop)=='function',phases={},phaseCount=0,recent={},next=1,slowFrames=0,slowOwn=0,limit=32}
G.performance=p
function G.PerformanceClock()
 if type(debugprofilestop)~='function' then return nil end
 local ok,value=pcall(debugprofilestop)
 if ok and type(value)=='number' and value==value then return value end
end
local function record(kind,ms,phase)
 local state=G.state;local step=state and state.steps and state.index and state.steps[state.index]
 local now=GetTime and GetTime() or 0
 p.recent[p.next]={kind=kind,ms=ms,phase=phase,time=now,step=step and step.id,previousRefreshMs=p.lastRefreshMs,recentEventMs=p.lastEventAt and now-p.lastEventAt<=1 and p.lastEventMs or nil}
 p.next=math.mod(p.next,32)+1
end
function G.PerformanceRecord(phase,start,frameDT)
 if G.db and G.db.performance~=p then if G.db.performance then G.db.previousPerformance=G.db.performance end;G.db.performance=p end
 phase=phase or 'callback'
 local ended=start and G.PerformanceClock();local own=ended and ended>=start and ended-start
 p.timerAvailable=own~=nil and own~=false
 local s=p.phases[phase]
 if not s then
  if p.phaseCount>=31 then phase='other';s=p.phases.other end
  if not s then s={calls=0,measuredCalls=0,totalMs=0,maxMs=0};p.phases[phase]=s;p.phaseCount=p.phaseCount+1 end
 end
 s.calls=s.calls+1
 if own then s.measuredCalls=s.measuredCalls+1;s.totalMs=s.totalMs+own;if own>s.maxMs then s.maxMs=own end
  if own>=2 then p.slowOwn=p.slowOwn+1;record('addon',own,phase) end
 end
 if phase=='refresh' then
  if type(frameDT)=='number' and frameDT>=.05 then p.slowFrames=p.slowFrames+1;record('frame',frameDT*1000,phase) end
  p.lastRefreshMs=own
 elseif string.find(phase,'^event ') then p.lastEventMs=own;p.lastEventAt=GetTime and GetTime() or 0 end
end
function G.PerformanceSnapshot()
 -- Copy only when the user explicitly creates a report, not every frame.
 local function copy(value)
  if type(value)~='table' then return value end
  local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
 end
 local result=copy(p);result.previous=G.db and copy(G.db.previousPerformance);result.meaning='Local addon callback time versus UI frame interval; frame spikes alone do not identify a culprit.';return result
end
function G.PerformanceText()
 local r=p.phases.refresh;local average=r and r.measuredCalls>0 and r.totalMs/r.measuredCalls or 0
 if not p.timerAvailable then return 'High-resolution addon timing unavailable. Recorded frame spikes: '..p.slowFrames..'. Report bug includes the local log.' end
 return string.format('OctoGuide callbacks: average refresh %.2f ms, max %.2f ms; slow own callbacks %d, frame intervals over 50 ms %d. Frame spikes alone do not identify a culprit. Report bug includes the bounded local log.',average,r and r.maxMs or 0,p.slowOwn,p.slowFrames)
end
local observe=G.ReadObservedTarget
function G.ReadObservedTarget(step)
 local started=G.PerformanceClock();local result=observe(step)
 G.PerformanceRecord('stage target observation',started);return result
end
local render=G.Render
function G.Render(layoutOnly)
 local started=G.PerformanceClock();local result=render(layoutOnly)
 G.PerformanceRecord('stage layout',started);return result
end
