dofile('tests/test-runtime.lua')
local G=OctoGuide;local slider=G.options.zoomSlider
local writes=0
function slider:SetValue(n)
 writes=writes+1;self.sliderValue=n
 self.scripts.OnValueChanged()
end
-- Model repeated native drag callbacks. Applying zoom must not move the settings
-- or write a second value into the slider while the user is dragging it.
for _,n in ipairs({100,95,75,60,45,30,35,55,80,120,150,100}) do
 slider.sliderValue=n;local before=writes
 this=G.frame;slider.scripts.OnValueChanged()
 assert(G.db.zoom==n and G.options.zoomField.value==tostring(n))
 assert(G.frame.scale==n/100 and G.menu.scale==n/100 and G.options.scale==1)
 assert(writes==before,'Dragging must not feed values back into the native slider')
end
G.options.zoomField:SetText('40');this=G.options.zoomField;this.scripts.OnEnterPressed()
assert(G.db.zoom==40 and slider.sliderValue==40 and writes==1)
assert(G.SetZoom(5) and G.db.zoom==30)
assert(G.SetZoom(200) and G.db.zoom==150)
assert(not G.SetZoom('invalid'))
G.db.zoom=35;G.ApplyZoom();assert(G.frame.scale==.35 and G.options.scale==1)
assert(string.find(G.options.zoomHint.value,'30%',1,true))
print('PASS stable slider callbacks, no feedback writes, 30-150 limits, input and saved zoom')
