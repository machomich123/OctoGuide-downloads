-- Executed in the login UI, never an in-world addon or simulated keyboard input.
do
    local original = AccountLogin_OnShow
    local driver
    local finished = false
    local function install()
        if driver or not AccountLogin or not CrewLoginTakeCredentials then return end
        driver = CreateFrame("Frame", nil, AccountLogin)
        driver:SetScript("OnUpdate", function()
            if finished or not AccountLogin:IsVisible() then return end
            if GlueDialog and GlueDialog:IsVisible() then return end
            if not AccountLoginAccountEdit or not AccountLoginPasswordEdit or
                not DefaultServerLogin then return end
            -- Yield until the real login UI is ready, then consume exactly once.
            finished = true
            driver:SetScript("OnUpdate", nil)
            local account, password = CrewLoginTakeCredentials()
            if not account or not password then return end
            AccountLoginAccountEdit:SetText(account)
            AccountLoginPasswordEdit:SetText("")
            DefaultServerLogin(account, password)
            password = nil
        end)
    end
    AccountLogin_OnShow = function()
        if original then original() end
        install()
    end
end
