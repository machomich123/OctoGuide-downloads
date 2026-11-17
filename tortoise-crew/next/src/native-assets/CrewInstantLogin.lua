-- Tortoise Crew instant login experiment for WoW 1.12.1 / Turtle 1.18.1.
-- ClassicAPI authenticates through Windows Credential Manager. No password
-- is written in this script, a CVar, or the WoW folder.

local CrewInstantAttempted = false;
local CrewInstantSplash = nil;

local function CrewHideSplash()
    if CrewInstantSplash then CrewInstantSplash:Hide(); end
end

local function CrewGetSplash()
    if CrewInstantSplash then return CrewInstantSplash; end
    if not AccountLoginUI then return nil; end
    local overlay = CreateFrame("Frame", nil, AccountLoginUI);
    overlay:SetAllPoints(AccountLoginUI);
    overlay:SetFrameStrata("FULLSCREEN_DIALOG");
    overlay:SetFrameLevel(200);
    overlay:EnableMouse(true);
    local backdrop = overlay:CreateTexture(nil, "BACKGROUND");
    backdrop:SetAllPoints(overlay);
    backdrop:SetTexture(0.025, 0.045, 0.075);
    local title = overlay:CreateFontString(nil, "OVERLAY", "GlueFontNormalLarge");
    title:SetPoint("CENTER", overlay, "CENTER", 0, 35);
    title:SetText("TORTOISE CREW");
    local sub = overlay:CreateFontString(nil, "OVERLAY", "GlueFontNormal");
    sub:SetPoint("TOP", title, "BOTTOM", 0, -16);
    sub:SetText("Authenticating securely...");
    overlay:EnableKeyboard(true);
    overlay:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then CrewHideSplash(); end
    end);
    overlay:Hide();
    CrewInstantSplash = overlay;
    return overlay;
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
    if account == "" or not CrewHasSavedCredential(account) then return; end
    local splash = CrewGetSplash();
    if splash then splash:Show(); end
    local ok, started = pcall(LoginWithSavedAccount, account);
    if not ok or not started then
        CrewHideSplash();
        return;
    end
    -- If authentication fails, reveal the ordinary login after a timeout.
    local remaining = 16;
    local timer = CreateFrame("Frame");
    timer:SetScript("OnUpdate", function()
        remaining = remaining - arg1;
        if remaining <= 0 then
            timer:SetScript("OnUpdate", nil);
            CrewHideSplash();
        end
    end);
end

local CrewOriginalOnShow = AccountLogin_OnShow;
AccountLogin_OnShow = function()
    if CrewOriginalOnShow then CrewOriginalOnShow(); end
    CrewTryInstantLogin();
end

local CrewOriginalCharacterShow = CharacterSelect_OnShow;
CharacterSelect_OnShow = function()
    CrewHideSplash();
    if CrewOriginalCharacterShow then CrewOriginalCharacterShow(); end
end

local CrewOriginalLogin = AccountLogin_Login;
AccountLogin_Login = function()
    -- Provision the secure Windows vault during the FIRST manual login.
    -- Native authentication is available on subsequent starts.
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
