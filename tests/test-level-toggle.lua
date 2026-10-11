dofile('tests/test-runtime.lua')
local G=OctoGuide
G.menu.level=nil;G.menu.page=2;G.RenderMenu()
assert(G.menu.levelButton.value=='Show current level')
for i=1,3 do
 G.menu.levelButton.scripts.OnClick()
 assert(G.menu.level==UnitLevel('player') and G.menu.page==1 and G.menu.levelButton.value=='Show all levels')
 assert(string.find(G.menu.info.value,'Level '..UnitLevel('player'),1,true))
 G.menu.levelButton.scripts.OnClick()
 assert(G.menu.level==nil and G.menu.page==1 and G.menu.levelButton.value=='Show current level')
 assert(string.find(G.menu.info.value,'All levels',1,true))
end
print('PASS level filter toggles both ways repeatedly and resets page')
