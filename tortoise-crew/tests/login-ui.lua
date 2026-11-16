local frame, update
local visible, blocked, sent, taken = false, false, 0, 0
local methods = {}
function methods:SetScript(event, fn) update = fn end
function CreateFrame() frame = setmetatable({}, {__index=methods}); return frame end
AccountLogin = {IsVisible=function() return visible end}
GlueDialog = {IsVisible=function() return blocked end}
AccountLoginAccountEdit = {SetText=function(self,text) self.text=text end}
AccountLoginPasswordEdit = {SetText=function(self,text) self.text=text end}
local exact = "a+^%~(){}[] !?\"Z"
function CrewLoginTakeCredentials() taken=taken+1; return "AUGUST", exact end
function DefaultServerLogin(account,password)
    assert(account=="AUGUST" and password==exact)
    sent=sent+1
end
function AccountLogin_OnShow() end
assert(loadfile(arg[1]))()
AccountLogin_OnShow()
update(); assert(taken==0 and sent==0)
visible=true; blocked=true
update(); assert(taken==0 and sent==0)
blocked=false
update(); assert(taken==1 and sent==1 and update==nil)
assert(AccountLoginAccountEdit.text=="AUGUST" and AccountLoginPasswordEdit.text=="")
AccountLogin_OnShow(); assert(update==nil and sent==1)
print("PASS: waits for visible unblocked UI, preserves symbols, clears password field and submits once")
