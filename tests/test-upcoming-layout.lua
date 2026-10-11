dofile('tests/test-runtime.lua')
local G=OctoGuide
G.db.view='full';G.db.progress={};G.db.completedQuests={};G.db.placements={}
G.RegisterGuide({id='readability',title='Level 1-6 Orc/Troll',faction='Horde',startLevel=1,endLevel=6},{
 {id='a',action='note',text='Current',manual=true},
 {id='b',action='turnin',text='Turn in Cutting Teeth to Gornek.',questID=788},
 {id='c',action='complete',text='Work on Sting of the Scorpid at Scorpid Workers.',questID=789}})
G.Select('readability')
for _,width in ipairs({380,460,800}) do
 G.db.widths={full=width};G.Render()
 local first=G.frame.nextRows[1];assert(first.title.value=='Turn in Cutting Teeth' and first.details.value=='Speak to Gornek.')
 assert(first.details.point[4]>first.title.point[4] and first.details.point[5]<first.title.point[5],'Instruction must be indented below task')
 local second=G.frame.nextRows[2];assert(second.title.value=='Sting of the Scorpid' and string.find(second.details.value,'Scorpid Workers',1,true))
 assert(G.frame.route.point[5]==-55 and G.frame.route.height==25,'Header must remain inside its border')
end
print('PASS separate upcoming task titles and indented NPC/objective instructions at three widths')
