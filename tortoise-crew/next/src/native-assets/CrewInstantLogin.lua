-- The launcher prepares the real SRP/world session before Play. This code
-- connects to its loopback frontend without drawing the account-login scene.
-- The actual WoW window stays visible, at its normal position, with no cover.
local CrewAttempted = false;
local CrewConnecting = false;
local CrewReady = false;
local CrewElapsed = 0;

local function CrewSignal(text)
    if type(AppendToFile) == "function" then
        pcall(AppendToFile, "WTF\\CrewInstantTrace.log", text .. "\n");
    end
end

local function CrewRestoreLogin(reason)
    if not CrewConnecting then return; end
    CrewConnecting = false;
    if AccountLogin and not CrewReady then AccountLogin:Show(); end
    if AccountLoginUI and not CrewReady then AccountLoginUI:Show(); end
    CrewSignal("manual-login: " .. reason);
end

local function CrewHasCredential(account)
    if type(GetSavedAccounts) ~= "function" or
       type(LoginWithSavedAccount) ~= "function" then return false; end
    local ok, entries = pcall(GetSavedAccounts);
    if not ok or type(entries) ~= "table" then return false; end
    for i = 1, table.getn(entries) do
        if entries[i] and entries[i].name and
           string.upper(entries[i].name) == account then return true; end
    end
    return false;
end

local CrewOriginalOnShow = AccountLogin_OnShow;
AccountLogin_OnShow = function()
    if CrewOriginalOnShow then CrewOriginalOnShow(); end
    if CrewAttempted then return; end
    CrewAttempted = true;
    if GetCVar("realmList") ~= "127.0.0.1" then return; end
    local account = string.upper(GetCVar("accountName") or "");
    if account == "" or not CrewHasCredential(account) then
        CrewSignal("credential-unavailable"); return;
    end
    CrewConnecting = true;
    CrewSignal("native-login-requested");
    local ok, started = pcall(LoginWithSavedAccount, account);
    if not ok or not started then CrewRestoreLogin("credential-rejected"); return; end
    -- Hide the unused scene, never the operating-system window.
    if AccountLoginUI then AccountLoginUI:Hide(); end
    if AccountLogin then AccountLogin:Hide(); end
    if type(StopGlueMusic) == "function" then pcall(StopGlueMusic); end
end

local CrewOriginalDialog = GlueDialog_Show;
if CrewOriginalDialog then
    GlueDialog_Show = function(which, text, arg1, arg2)
        CrewOriginalDialog(which, text, arg1, arg2);
        if CrewConnecting and (which == "STATUS" or which == "CANCEL") then
            if GlueDialog then GlueDialog:Hide(); end
        elseif CrewConnecting then CrewRestoreLogin("server-dialog"); end
    end
end

local CrewOriginalCharacterEvent = CharacterSelect_OnEvent;
CharacterSelect_OnEvent = function(evt, a1, a2, a3, a4)
    if CrewOriginalCharacterEvent then CrewOriginalCharacterEvent(evt, a1, a2, a3, a4); end
    local name = evt or event;
    if name == "CHARACTER_LIST_UPDATE" and not CrewReady then
        if not IsConnectedToServer() then return; end
        CrewReady = true; CrewConnecting = false;
        CrewSignal("character-list-ready");
        if type(AppendToFile) == "function" then
            pcall(AppendToFile, "WTF\\CrewCharacterReady.flag", "CREW_CHARACTER_LIST_READY\n");
        end
    end
end

local CrewWatch = CreateFrame("Frame");
CrewWatch:SetScript("OnUpdate", function()
    if not CrewConnecting then return; end
    CrewElapsed = CrewElapsed + arg1;
    -- Recovery on failure; no delay on the successful path.
    if CrewElapsed > 8 then CrewRestoreLogin("connection-timeout"); end
end);

local CrewOriginalLogin = AccountLogin_Login;
AccountLogin_Login = function()
    CrewRestoreLogin("manual-attempt");
    if type(SaveAccount) == "function" and AccountLoginAccountEdit and AccountLoginPasswordEdit then
        local account = string.upper(AccountLoginAccountEdit:GetText() or "");
        local password = AccountLoginPasswordEdit:GetText() or "";
        if account ~= "" and password ~= "" then pcall(SaveAccount, account, password); end
    end
    if CrewOriginalLogin then CrewOriginalLogin(); end
end
