dofile('tests/test-runtime.lua')
local G=OctoGuide
assert(G.frame.version.value=='v'..G.version)
for _,view in ipairs({'minimal','full'}) do
 G.db.view=view
 for _,width in ipairs({380,490,800}) do
  G.db.widths=G.db.widths or {};G.db.widths[view]=width;G.Render()
  assert(G.frame.version.value=='v'..G.version and G.frame.version.width==60)
  assert(G.frame.version.point[4]==108 and 108+60<width-102)
 end
end
print('PASS visible loaded version in both views at all supported widths')

