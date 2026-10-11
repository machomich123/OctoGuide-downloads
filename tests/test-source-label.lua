dofile('tests/test-runtime.lua')
local G=OctoGuide
G.hasFamilyRoutes=nil;G.db.routeSource='baseline';G.Render();assert(string.find(G.frame.route.value,'Baseline |',1,true))
G.hasFamilyRoutes=true;G.db.routeSource='rxp';G.Render();assert(string.find(G.frame.route.value,'RestedXP |',1,true))
G.db.routeSource='baseline';G.Render();assert(string.find(G.frame.route.value,'RestedXP installed; baseline',1,true))
print('PASS route header distinguishes RestedXP installed and selected from baseline')
G.preferRXPInstall=true;G.db.rxpInstallerSelected=nil;G.db.routeSource='baseline';G.ready=false;G.Init();assert(G.db.routeSource=='rxp' and G.db.rxpInstallerSelected)
G.db.routeSource='baseline';G.ready=false;G.Init();assert(G.db.routeSource=='baseline')
print('PASS installer selects RestedXP once and preserves later manual source choice')
