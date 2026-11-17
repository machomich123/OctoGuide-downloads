-- Tortoise Crew: native saved-account login with NO visual cover or password
-- simulation. WoW is launched hidden by Windows and only shown after
-- CHARACTER_LIST_UPDATE confirms that character selection data has arrived.
-- ClassicAPI retrieves the secret from Windows Credential Manager.

local CrewInstantAttempted = false;
local CrewCharacterReady = false;
local CrewReadyFile = "WTF\\CrewCharacterReady.flag";

local function CrewSignal(text)
    if type(AppendToFile) == "function" then
        pcall(AppendToFile, "WTF\\CrewInstantTrace.log", text .. "\n");
    end
end

local function CrewHasSavedCredential(account)
    if type(GetSavedAccounts) ~= "function" or
       type(LoginWithSavedAccount) ~= "function" then return false; end
    local ok, entries = pcall(GetSavedAccounts);
    if not ok or type(entries) ~= "table" then return false; end
    for i = 1, table.getn(entries) do
        local entry = entries[i];
        if entry and entry.name and
           string.upper(entry.name) == account then return true; end
    end
    return false;
end

local function CrewTryInstantLogin()
    if CrewInstantAttempted then return; end
    CrewInstantAttempted = true;
    local account = string.upper(GetCVar("accountName") or "");
    if account == "" and AccountLoginAccountEdit then
        account = string.upper(AccountLoginAccountEdit:GetText() or "");
    end
    if account == "" or not CrewHasSavedCredential(account) then
        CrewSignal("credential-unavailable");
        return;
    end
    CrewSignal("native-login-requested");
    local ok, started = pcall(LoginWithSavedAccount, account);
    if not ok or not started then CrewSignal("native-login-rejected"); end
end

local CrewOriginalOnShow = AccountLogin_OnShow;
AccountLogin_OnShow = function()
    if CrewOriginalOnShow then CrewOriginalOnShow(); end
    CrewTryInstantLogin();
end

local CrewOriginalCharacterEvent = CharacterSelect_OnEvent;
CharacterSelect_OnEvent = function()
    if CrewOriginalCharacterEvent then CrewOriginalCharacterEvent(); end
    if event == "CHARACTER_LIST_UPDATE" and not CrewCharacterReady then
        CrewCharacterReady = true;
        -- Let the existing character list and previews finish one frame.
        local elapsed = 0;
        local frame = CreateFrame("Frame");
        frame:SetScript("OnUpdate", function()
            elapsed = elapsed + arg1;
            if elapsed < 0.15 then return; end
            frame:SetScript("OnUpdate", nil);
            if not IsConnectedToServer() then return; end
            CrewSignal("character-list-ready");
            if type(AppendToFile) == "function" then
                pcall(AppendToFile, CrewReadyFile, "CREW_CHARACTER_LIST_READY\n");
            end
        end);
    end
end

local CrewOriginalLogin = AccountLogin_Login;
AccountLogin_Login = function()
    if type(SaveAccount) == "function" and
       AccountLoginAccountEdit and AccountLoginPasswordEdit then
        local account = string.upper(AccountLoginAccountEdit:GetText() or "");
        local password = AccountLoginPasswordEdit:GetText() or "";
        if account ~= "" and password ~= "" then
            pcall(SaveAccount, account, password);
        end
    end
    if CrewOriginalLogin then CrewOriginalLogin(); end
end
