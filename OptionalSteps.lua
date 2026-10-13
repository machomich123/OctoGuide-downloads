-- XP recommendations do not block the next quest. No progress is invented.
local G=OctoGuide
function G.IsOptionalGrind(s)
 return s and not s.requiredXP and (s.action=='grind' or (s.action=='level' and string.find(string.lower(s.text or ''),'^grind '))) and not s.xpReverse
end
function G.OptionalGrinds(s)
 local result={};if not s or not G.state then return result end
 local steps=G.state.steps;local current
 for i,a in ipairs(steps) do if a==s then current=i;break end end
 if not current then return result end
 for i=G.state.startIndex or 1,current do
  local a=steps[i]
  if G.IsOptionalGrind(a) and not G.db.progress[G.Key(a)] and not G.Satisfied(a) and (not G.SourceEligible or G.SourceEligible(a)) then
   local nextQuest
   for j=i+1,table.getn(steps) do
    local b=steps[j]
    if b.questID and not b.background and not b.informational and not G.IsOptionalGrind(b) then nextQuest=j;break end
   end
   if nextQuest and current<=nextQuest then table.insert(result,a) end
  end
 end
 return result
end
