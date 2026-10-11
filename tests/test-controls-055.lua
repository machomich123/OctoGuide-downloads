dofile('tests/test-controls-054.lua')
local G=OctoGuide
local methods=getmetatable(G.frame).__index
function methods:SetBackdrop(value) self.backdrop=value;self.backdropCleared=value==nil end
G.frame.close.backdrop={};G.frame.controlsToggle.backdrop={}
G.StyleControl(G.frame.close,'Close');G.StyleControl(G.frame.controlsToggle,'Toggle')
assert(G.frame.close.backdropCleared and G.frame.controlsToggle.backdropCleared)
assert(G.frame.close.width==34 and G.frame.controlsToggle.width==44)
assert(G.frame.close.controlArt.texture and G.frame.controlsToggle.controlArt.texture)
print('PASS 0.5.5 outer backdrops removed, custom artwork and click sizes preserved')
