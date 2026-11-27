-- TortoiseBots Party Inventory; classic-client Lua 5.0/5.1 compatible.
-- Server authorization and real item GUIDs are required for remote mutations.
local TB = TortoiseBots
local page = 1
local requestedScale = 1
local columns = {}
local dragged
local transferStatus
local partyTypes = {}
local pendingTrade = {}
local pendingTransfer
-- Each paid native trade can safely transfer ONE GUID/count/price at a time.
-- The checkout batch therefore holds user-approved independent purchases and
-- advances only after authoritative buyer money + item + seller GUID checks.
-- Never send concurrent purchases or retry an ambiguous transaction.
local checkoutQueue
local startQueuedCheckout
local abortCheckout
-- Purchases and ALT transfers use native server trade transactions, but the
-- Party Inventory panel is their visual owner. Hide only the redundant native
-- TradeFrame while this panel's explicit transaction is in progress. Do NOT
-- call TradeFrame:Hide(): Blizzard OnHide can cancel an active transaction.
local nativeTradeSuppressed = false
local originalTradeAlpha = 1
local function syncNativeTradeFrame(restore)
    if not TradeFrame then return end
    local suppress = not restore and TBMPartyInventoryFrame
        and TBMPartyInventoryFrame:IsShown() and pendingTransfer ~= nil
    if suppress and not nativeTradeSuppressed then
        nativeTradeSuppressed = true
        originalTradeAlpha = TradeFrame:GetAlpha() or 1
        TradeFrame:SetAlpha(0)
        TradeFrame:EnableMouse(false)
    elseif not suppress and nativeTradeSuppressed then
        nativeTradeSuppressed = false
        TradeFrame:SetAlpha(originalTradeAlpha)
        TradeFrame:EnableMouse(true)
    end
end
local deferredGuidTransfer
local guidResolveCapable = false
-- Only the visual bag grid is optimistic. The actual item ownership, money,
-- target positions and authority remain on the server. A rejected or timed-out
-- request discards the preview and restores the last confirmed inventory.
local optimisticPlacements = {}
local refreshAt
local managerWasVisible = false
local quoteCapable = false
local tradeCapable = false
local moneyCapable = false
local batchMoneyCapable = false
local pendingCoinTransfer
local openCoinDialog
local refreshCoinBars
local coinDialog
local nextCoinRequest = 0
local lastCoinNonce = 0
local render
local repaintSelf
local refreshTrade
local fillTradeAmount
local verifyActivePurchase
local refreshControl, settingsControl
local EMPTY = "Interface\\Buttons\\WHITE8X8"
-- The actual 1.12 backpack empty-slot artwork. Checked against both client
-- MPQ archives and visually decoded: the full 64x64 image contains the
-- embossed bag slot and its raised border. WHITE8X8 is for panel fills only.
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local FRAME_WIDTH = 1266
local fullscreen = false
local FULLSCREEN_MAX_SCALE = 3
local CARD_WIDTH = 242
local CARD_STEP = 250
TBMPartyInventorySettings = TBMPartyInventorySettings or {}
local BAG_COLUMNS = 7
local savedBagColumns = tonumber(TBMPartyInventorySettings.columns)
if savedBagColumns and savedBagColumns >= 4 and savedBagColumns <= 7 then
    BAG_COLUMNS = savedBagColumns
end
local BAG_CELL = 32
local BAG_GRID_TOP = -300
-- Five-party fullscreen needs 12 backpack rows for an 80-slot inventory.
-- Keep the paper doll intact but use the idle 50px between the grid and
-- footer before reducing icon size or forcing an unnecessary scrollbar.
local COMPACT_BAG_GRID_TOP = -275
local COMPACT_BAG_FOOTER = 167
-- Reserve a real, non-overlapping card footer for the equipped bags, sale
-- controls, status and native trade preview. Inventory items may scroll above
-- this region; they must never push action buttons outside the card.
local BAG_FOOTER_RESERVED = 188
-- Allow the entire authenticated 80+ slot inventory to be visible whenever
-- the actual fullscreen card has enough height. The old 56-cell hard limit
-- created eight rows and hundreds of pixels of needless empty space.
-- Normal/windowed mode still uses eight rows and scrolls.
local MAX_BAG_CELLS = 128
-- Scroll only when the current viewport genuinely cannot fit all real rows.
local visibleBagCells = MAX_BAG_CELLS
local cardLayoutWidth = CARD_WIDTH
local cardGridX = 4
local iconCache = {}
local unresolvedIconIds = {}
local nextIconRetryAt = 0
-- Keep confirmed inventory snapshots across panel close/open cycles. The
-- roster-change event invalidates access classes; opening the UI must not.
local inventoryCachedAt = {}
local inventoryRequestedAt = {}
local nextVisibleRefreshAt = 0
local selfSnapshotValid = false
local selfInventoryRevision = 0
local selfEquippableItemIds = {}
local pendingSelfEquip
-- Exact server instance GUIDs, never item names/IDs, identify queued sales.
local markedForSale = {}
local activeMarkedSale = {}
local sellMarkedCapable = false
local toggleSaleMark
local updateSellButton
local requestFreshInventory
local updateViewport
local selfServerProtocolAvailable -- nil unknown, false old server, true verified
-- A self inventory snapshot does not imply that older server builds support
-- the newer self equip/unequip commands. Enable them only by explicit advert.
local selfServerEquipmentAvailable = false
-- Server equipment commands address current slots. Keep one self gear action
-- in flight so rapid clicks cannot accidentally act on a different item that
-- moved into the same slot while an earlier command was still in the queue.
TB._partySelfGearCommand = nil
-- True charcoal/near-black surfaces, not the earlier blue-tinted slate UI.
-- Original WoW inventory/gear icons retain their unmodified native colors.
local COLORS = {
    panel = {0.015, 0.015, 0.017, 0.995},
    card = {0.032, 0.032, 0.035, 0.995},
    inset = {0.009, 0.009, 0.011, 1},
    header = {0.046, 0.046, 0.049, 1},
    outline = {0.15, 0.15, 0.16, 0.9},
    accent = {0.43, 0.43, 0.40, 1},
    text = {0.92, 0.92, 0.91, 1},
    muted = {0.64, 0.64, 0.62, 1},
    gold = {0.93, 0.80, 0.56, 1},
    slotEmpty = {0.07, 0.07, 0.075, 1},
    slotOccupied = {0.17, 0.17, 0.18, 1},
    emptyGear = {0.11, 0.11, 0.12, 1},
    emptyEdge = {0.21, 0.21, 0.22, 1},
    button = {0.065, 0.065, 0.071, 1},
    buttonOuter = {0.17, 0.17, 0.18, 1},
    buttonHover = {0.145, 0.137, 0.120, 1},
}
-- Native WoW item quality outlines, not a uniform dark border for every item.
-- Server quality takes priority if the client's WDB entry is not yet cached.
local ITEM_QUALITY_EDGES = {
    [0] = {0.62, 0.62, 0.62, 1},
    [1] = COLORS.slotOccupied,
    [2] = {0.12, 0.91, 0.10, 1},
    [3] = {0.06, 0.53, 0.96, 1},
    [4] = {0.73, 0.28, 0.91, 1},
    [5] = {0.99, 0.54, 0.05, 1},
    [6] = {0.90, 0.79, 0.48, 1},
}
local SELLER_COLORS = {
    {1.00, 0.70, 0.32, 1}, {0.53, 0.77, 1.00, 1},
    {0.91, 0.62, 0.94, 1}, {0.60, 0.90, 0.59, 1},
    {0.98, 0.54, 0.59, 1},
}

local function sellerColor(name)
    local hash = 0
    name = string.lower(name or "")
    for i = 1, string.len(name or "") do
        hash = math.mod(hash * 31 + string.byte(name, i), 997)
    end
    return SELLER_COLORS[math.mod(hash, table.getn(SELLER_COLORS)) + 1]
end

local function colorTexture(texture, rgba)
    local old = texture._tbColor
    if old and old[1] == rgba[1] and old[2] == rgba[2]
        and old[3] == rgba[3] and old[4] == (rgba[4] or 1) then return end
    texture:SetTexture(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    texture._tbColor = {rgba[1], rgba[2], rgba[3], rgba[4] or 1}
    texture._tbPath = nil
end

local function validTexturePath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = string.gsub(path, "/", "\\")
    -- Vanilla textures use file paths. Numeric modern FileIDs turn into solid
    -- color fills (often bright red) on a classic 1.12 Texture region.
    if string.sub(path, 1, 10) == "Interface\\" then return path end
    -- Some custom clients return the icon's basename instead of a full path.
    if string.find(path, "^[%a][%w_]*$") then
        if string.find(path, "^INV_") or string.find(path, "^Spell_")
            or string.find(path, "^Ability_") or string.find(path, "^Trade_") then
            return "Interface\\Icons\\" .. path
        end
    end
    return nil
end

local function setPathTexture(texture, path)
    local safe = validTexturePath(path) or UNKNOWN
    if texture._tbPath == safe then return end
    texture:SetTexture(safe)
    texture._tbPath = safe
    texture._tbColor = nil
end

local function setAlpha(texture, alpha)
    if texture._tbAlpha == alpha then return end
    texture:SetAlpha(alpha)
    texture._tbAlpha = alpha
end

local function tintText(font, rgba)
    if font and font.SetTextColor then
        font:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end
end

local function panelOutline(panel, background, outline, accentTop)
    panel:SetBackdrop({ bgFile = EMPTY })
    panel:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = panel:CreateTexture(nil, "BORDER")
        if edge == "TOP" then
            tex:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
            tex:SetHeight(accentTop and 2 or 1)
        elseif edge == "BOTTOM" then
            tex:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
            tex:SetHeight(1)
        elseif edge == "LEFT" then
            tex:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
            tex:SetWidth(1)
        else
            tex:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
            tex:SetWidth(1)
        end
        colorTexture(tex, accentTop and edge == "TOP" and COLORS.accent or outline)
    end
end

local function controlButton(parent, title, width, height, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width)
    b:SetHeight(height or 24)
    -- A raw classic-client Button has no normal text region. Give it a custom
    -- caption instead of relying on the vanilla button-template SetText path.
    b.controlLabel = title
    b:RegisterForClicks("LeftButtonUp")
    b.base = b:CreateTexture(nil, "BACKGROUND")
    b.base:SetAllPoints(b)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.edge = b:CreateTexture(nil, "OVERLAY")
    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
    b.edge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -1)
    b.edge:SetHeight(1)
    b.caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.caption:SetAllPoints(b)
    b.caption:SetText(title)
    b.hovered = false
    b.pressed = false
    b.primary = primary and true or false

    b.RefreshAppearance = function()
        local enabled = not b.IsEnabled or b:IsEnabled()
        if not enabled then
            colorTexture(b.base, {0.10, 0.10, 0.105, 1})
            colorTexture(b.fill, {0.034, 0.034, 0.038, 1})
            colorTexture(b.edge, {0.13, 0.13, 0.14, 1})
            tintText(b.caption, {0.43, 0.43, 0.42, 1})
        elseif b.pressed then
            colorTexture(b.base, COLORS.accent)
            colorTexture(b.fill, {0.16, 0.15, 0.14, 1})
            colorTexture(b.edge, COLORS.accent)
            tintText(b.caption, COLORS.text)
        elseif b.hovered then
            colorTexture(b.base, {0.29, 0.28, 0.25, 1})
            colorTexture(b.fill, COLORS.buttonHover)
            colorTexture(b.edge, COLORS.accent)
            tintText(b.caption, COLORS.text)
        else
            colorTexture(b.base, b.primary and {0.32, 0.29, 0.24, 1}
                or COLORS.buttonOuter)
            colorTexture(b.fill, b.primary and {0.13, 0.117, 0.097, 1}
                or COLORS.button)
            colorTexture(b.edge, b.primary and COLORS.accent
                or {0.23, 0.23, 0.24, 1})
            tintText(b.caption, b.primary and COLORS.text or
                {0.80, 0.80, 0.78, 1})
        end
    end
    b:SetScript("OnEnter", function()
        this.hovered = true
        this.RefreshAppearance()
    end)
    b:SetScript("OnLeave", function()
        this.hovered, this.pressed = false, false
        this.RefreshAppearance()
    end)
    b:SetScript("OnMouseDown", function()
        this.pressed = true
        this.RefreshAppearance()
    end)
    b:SetScript("OnMouseUp", function()
        this.pressed = false
        this.RefreshAppearance()
    end)
    -- WoW 1.12 buttons cannot register OnEnable/OnDisable script handlers.
    -- Every state change in this addon instead uses setControlEnabled(),
    -- which updates the custom skin explicitly after Enable()/Disable().
    b.RefreshAppearance()
    return b
end

local function setControlEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
    if button.RefreshAppearance then button.RefreshAppearance() end
end

local function norm(name)
    if not name or name == "" then return nil end
    return string.lower(TB.NormalizeName and TB.NormalizeName(name) or name)
end

local function groupMembers()
    local members, seen = {}, {}
    local ownName = norm(UnitName("player"))
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local prefix = raidCount > 0 and "raid" or "party"
    local count = raidCount > 0 and raidCount or (GetNumPartyMembers and GetNumPartyMembers() or 0)
    -- Party size is authoritative. Never invent phantom units to fill cards.
    for index = 1, count do
        local unit = prefix .. index
        local name = UnitName(unit)
        local key = norm(name)
        if name and key and key ~= ownName and not seen[key]
            and (not UnitExists or UnitExists(unit)) then
            table.insert(members, { name = name, unit = unit, key = key })
            seen[key] = true
        end
    end
    return members
end

local function isInGroup(name)
    local key = norm(name)
    if not key then return false end
    if key == norm(UnitName("player")) then return true end
    for _, member in ipairs(groupMembers()) do
        if member.key == key then return true end
    end
    return false
end

local function itemTexture(id)
    if not id then return nil end
    if iconCache[id] and iconCache[id] ~= UNKNOWN then return iconCache[id] end
    -- Unlike GetItemInfo, GetItemIcon does not wait for a cached item tooltip.
    -- Use the client's actual icon record immediately for remote bot items.
    if GetItemIcon then
        local directIcon = validTexturePath(GetItemIcon(id))
        if directIcon then
            iconCache[id] = directIcon
            unresolvedIconIds[id] = nil
            return directIcon
        end
    end
    -- Vanilla GetItemInfo returns equipLoc in position 9, texture in 10.
    -- Some custom compatibility shims omit the 10th return value.
    local _, _, _, _, _, _, _, _, location, texture = GetItemInfo(id)
    texture = validTexturePath(texture)
    if texture then
        iconCache[id] = texture
        unresolvedIconIds[id] = nil
        return texture
    end
    location = validTexturePath(location)
    if location then
        iconCache[id] = location
        unresolvedIconIds[id] = nil
        return location
    end
    -- Do not memoize the question mark: item data may finish loading later.
    unresolvedIconIds[id] = true
    return UNKNOWN
end

local function resolvedItemTexture(id, provided)
    local serverPath = validTexturePath(provided)
    -- The fallback question mark may have been saved into a prior snapshot.
    -- It is NOT an authoritative server icon and must not poison the cache.
    if serverPath and serverPath ~= UNKNOWN then
        if id then iconCache[id] = serverPath end
        if id then unresolvedIconIds[id] = nil end
        return serverPath
    end
    return itemTexture(id)
end

local function paintItemAppearance(button, item)
    if not button or not button.icon then return end
    local quality = item and tonumber(item.quality)
    local equipLocation, nativeClass
    if item and item.id and GetItemInfo then
        local _, _, nativeQuality, _, _, itemClass, _, _, location = GetItemInfo(item.id)
        if quality == nil then quality = tonumber(nativeQuality) end
        nativeClass, equipLocation = itemClass, location
    end
    -- An 'e' flag missing on a consumable does not mean unusable gear.
    -- Older servers omit the new 'w' hint; a cached native equipLoc fills it.
    local nativeWearable = type(equipLocation) == "string" and
        string.sub(equipLocation, 1, 8) == "INVTYPE_" and
        equipLocation ~= "INVTYPE_NON_EQUIP"
    local wearable = item and (item.wearable == true or nativeWearable)
    local restricted = wearable and item.equippable == false
    colorTexture(button.border, restricted and {0.91, 0.12, 0.12, 1}
        or ITEM_QUALITY_EDGES[quality] or COLORS.slotOccupied)
    if button.icon.SetVertexColor then
        if restricted then button.icon:SetVertexColor(1, 0.23, 0.23)
        else button.icon:SetVertexColor(1, 1, 1) end
    end
    local quest = item and (item.quest == true or nativeClass == "Quest")
    if quest then
        if not button.questMarker then
            local marker = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            marker:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
            marker:SetText("?")
            marker:SetTextColor(1, 0.84, 0.18)
            button.questMarker = marker
        end
        button.questMarker:Show()
    elseif button.questMarker then
        button.questMarker:Hide()
    end
end

local function itemIdFromLink(link)
    local _, _, id = string.find(link or "", "item:(%d+)")
    return id and tonumber(id) or nil
end

local function serverBag(bag)
    if bag == 0 then return 255 end
    return bag + 18
end

local function serverSlot(bag, position)
    if bag == 0 then return position + 22 end
    -- Native GetContainerItemInfo/GetContainerItemLink use 1-based positions
    -- inside each equipped bag. TortoiseBots Core's INV_ITEM and GetItemByPos
    -- use 0-based positions for bags 19..22. Returning `position` here made
    -- every SELF item inside an equipped bag miss its real GUID, causing the
    -- observed "three refreshes; no transfer sent" after item reordering.
    return position - 1
end

local function commandArgs(item)
    if not item or not item.bag or not item.slot or not item.guid or not item.count then return nil end
    return item.bag .. " " .. item.slot .. " " .. item.guid .. " " .. item.count
end

local function invalidateSelfSnapshot()
    -- WoW 1.12 does not expose a carried item's database GUID through its
    -- bag APIs. Any native move may make an older INV_SELF slot->GUID map
    -- unsafe even when another stack has the same itemID. Discard that map
    -- until a newer server snapshot has been received.
    selfSnapshotValid = false
    selfInventoryRevision = selfInventoryRevision + 1
end

local function status(text)
    if transferStatus then transferStatus:SetText(text or "") end
end

local function command(text, sendingText)
    if not text or text == "" then return false end
    -- TBM Core returns FALSE when its 350ms throttle has *queued* a valid
    -- command, not only when a command is rejected. Treating this as failure
    -- allowed a second sell order to be issued for items already in flight.
    local immediate = TB.SendBotCommand(text)
    status((sendingText or "Awaiting server confirmation...") ..
        (immediate and "" or " (queued by the safe command throttle)"))
    return true
end

TB.SubmitPartySelfGearCommand = function(text, op)
    local active = TB._partySelfGearCommand
    if active then
        if not active.recoveryRequested and
            (GetTime() - active.startedAt > 8 or
                (active.possibleErrorAt and GetTime() - active.possibleErrorAt > 1.1)) then
            active.recoveryRequested = true
            -- Transport may queue this read-only request. A snapshot that
            -- arrives before actual dispatch cannot prove the slot is safe.
            TB.SendBotCommand("inv self")
            status("Previous equipment action was not verified. Refreshing self inventory; retry after it settles.")
        else
            status(active.recoveryRequested and
                "Waiting for a current self inventory snapshot before the next equipment move." or
                "Previous equipment move is still being confirmed by the server.")
        end
        return false
    end
    TB._partySelfGearCommand = {op = op, startedAt = GetTime()}
    command(text)
    invalidateSelfSnapshot()
    return true
end

local previousCommandSent = TB.OnCommandSent
TB.OnCommandSent = function(text)
    if previousCommandSent then previousCommandSent(text) end
    local pending = TB._partySelfGearCommand
    if pending and pending.recoveryRequested and not pending.recoverySentAt
        and text == "inv self" then
        -- Called on actual chat/addon transport dispatch, not queue insert.
        pending.recoverySentAt = GetTime()
    end
    local _, _, altName = string.find(text or "", "^sellmarked%s+([^%s]+)")
    if altName and activeMarkedSale[norm(altName)] then
        local active = activeMarkedSale[norm(altName)]
        active.sentAt = GetTime()
        status("Vendor order delivered for " .. altName ..
            ". Waiting for the server to approve the route and selected stacks...")
    end
end
-- While the inventory is visible, dispatch user actions and authorization
-- requests 29% more responsively without removing TBM's anti-flood queue.
-- Restore the user's original manager throttle when the panel closes.
local originalManagerSendDelay
local function adjustInventoryQueue(active)
    if not TB.C then return end
    if active and not originalManagerSendDelay then
        local current = tonumber(TB.C.SEND_DELAY)
        if current and current >= 0.35 and current <= 0.60 then
            originalManagerSendDelay = current
            TB.C.SEND_DELAY = 0.25
        end
    elseif not active and originalManagerSendDelay then
        if TB.C.SEND_DELAY == 0.25 then
            TB.C.SEND_DELAY = originalManagerSendDelay
        end
        originalManagerSendDelay = nil
    end
end

local function moneyText(copper)
    if not copper then return "Price pending" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor(math.mod(copper, 10000) / 100)
    local bronze = math.mod(copper, 100)
    return gold .. "g " .. silver .. "s " .. bronze .. "c"
end

-- WoW 1.12's genuine backpack MoneyFrame draws ALL coin symbols from one
-- horizontally-sliced atlas. Modern standalone UI-GoldIcon/UI-SilverIcon/
-- UI-CopperIcon paths do not exist in this client and render invisible.
local COIN_TEXTURES = {
    "Interface\\MoneyFrame\\UI-MoneyIcons",
    "Interface\\MoneyFrame\\UI-MoneyIcons",
    "Interface\\MoneyFrame\\UI-MoneyIcons",
}
local function coinAmounts(copper)
    if type(copper) ~= "number" or copper < 0 then return 0, 0, 0 end
    return math.floor(copper / 10000),
        math.floor(math.mod(copper, 10000) / 100), math.mod(copper, 100)
end
local function confirmedMoney(name)
    if norm(name) == norm(UnitName("player")) then
        return GetMoney and GetMoney() or nil
    end
    local inventory = name and TB.GetInventory(name)
    return inventory and inventory.money or nil
end

local function countLocalItem(id)
    if not GetContainerNumSlots or not GetContainerItemInfo or not GetContainerItemLink then return nil end
    local total = 0
    for bag = 0, 4 do
        for position = 1, GetContainerNumSlots(bag) do
            local texture, count = GetContainerItemInfo(bag, position)
            local linkId = itemIdFromLink(GetContainerItemLink(bag, position))
            if texture and not linkId then
                -- An unknown occupied item could be the purchase item.
                -- Refuse a monetary baseline that cannot count it accurately.
                return nil
            end
            if linkId == id then
                total = total + (count or 1)
            end
        end
    end
    return total
end

local function botType(name)
    return name and partyTypes[norm(name)] or nil
end

local function authorizedBot(name)
    local kind = botType(name)
    return kind == "own" or kind == "ai"
end

local function owned(name)
    return name and (name == UnitName("player") or botType(name) == "own")
end

local function createButton(parent, x, y, w, h)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(w)
    button:SetHeight(h)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetAllPoints(button)
    colorTexture(button.border, COLORS.slotEmpty)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    setPathTexture(button.icon, EMPTY_SLOT)
    setAlpha(button.icon, 0.8)
    button.hl = button:CreateTexture(nil, "OVERLAY")
    button.hl:SetAllPoints(button)
    colorTexture(button.hl, {0.76, 0.68, 0.48, 0.16})
    button.hl:Hide()
    button:SetScript("OnEnter", function()
        if this.card and not this.card.canInspect then return end
        this.hl:Show()
        this:SetScript("OnUpdate", function()
            -- Animate only the slot currently under the pointer.
            button.hl:SetAlpha(0.65 + 0.22 * math.sin(GetTime() * 4))
        end)
        local item = this.item
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if item and item.id then
            if item.playerBag ~= nil and GameTooltip.SetBagItem then
                GameTooltip:SetBagItem(item.playerBag, item.playerSlot)
            elseif item.ownerGear and GameTooltip.SetInventoryItem then
                GameTooltip:SetInventoryItem("player", item.slot + 1)
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. item.id .. ":0:0:0")
            end
            if item.noTrade then GameTooltip:AddLine("Bound to this character", 1, 0.45, 0.35) end
            if this.saleSelected then
                GameTooltip:AddLine("Marked to sell (Alt+Click to unmark)", 1, 0.80, 0.28)
            end
            if this.card and this.card.characterType == "ai" and item.salePrice ~= nil then
                if item.salePrice > 0 then
                    GameTooltip:AddLine("Bot asks: " .. moneyText(item.salePrice), 1, 0.86, 0.4)
                else
                    GameTooltip:AddLine("This item is not for sale.", 1, 0.45, 0.35)
                end
            end
            if this.previewKind == "source" then
                GameTooltip:AddLine("TRADE PREVIEW: FROM " .. (this.card.character or "AI bot"),
                    1, 0.69, 0.28)
                GameTooltip:AddLine("Not yet transferred or paid.", 0.8, 0.82, 0.86)
            elseif this.previewKind == "destination" then
                GameTooltip:AddLine("INTENDED TRADE DESTINATION", 0.35, 0.87, 0.78)
                GameTooltip:AddLine("Final position depends on the game's trade placement.",
                    0.8, 0.82, 0.86)
            end
            GameTooltip:AddLine("Drag to move, right-click to equip or unequip.", 0.75, 0.78, 0.84)
        else
            GameTooltip:SetText(this.slotLabel or "Empty slot")
            GameTooltip:AddLine("Drop an item here.", 0.72, 0.74, 0.78)
            if this.previewKind == "destination" then
                GameTooltip:AddLine("Trade preview only; no item has moved.", 0.35, 0.87, 0.78)
            end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        this:SetScript("OnUpdate", nil)
        this.hl:Hide()
        GameTooltip:Hide()
    end)
    return button
end

local frame = CreateFrame("Frame", "TBMPartyInventoryFrame", UIParent)
frame:SetWidth(FRAME_WIDTH)
frame:SetHeight(695)
frame:SetPoint("CENTER", UIParent, "CENTER")
frame:SetFrameStrata("DIALOG")
if frame.SetMovable then frame:SetMovable(true) end
if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
panelOutline(frame, COLORS.panel, COLORS.outline, true)
frame:Hide()
local fullscreenBackdrop = CreateFrame("Frame", "TBMPartyInventoryFullBackdrop", UIParent)
fullscreenBackdrop:SetAllPoints(UIParent)
-- Backdrop must be in a LOWER strata than the panel. Raising the entire
-- panel to frame level 11 left its pre-existing child buttons/models at older
-- levels and the black backdrop visibly covered them in the REAL Wine GUI.
fullscreenBackdrop:SetFrameStrata("FULLSCREEN")
fullscreenBackdrop:SetFrameLevel(1)
fullscreenBackdrop:EnableMouse(true)
fullscreenBackdrop:SetBackdrop({bgFile = EMPTY})
fullscreenBackdrop:SetBackdropColor(0.006, 0.006, 0.008, 0.995)
fullscreenBackdrop:Hide()

local headerFill = frame:CreateTexture(nil, "BACKGROUND")
headerFill:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -3)
headerFill:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -3)
headerFill:SetHeight(39)
colorTexture(headerFill, COLORS.header)
local headerRule = frame:CreateTexture(nil, "BORDER")
headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -42)
headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -42)
headerRule:SetHeight(1)
colorTexture(headerRule, COLORS.outline)
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
title:SetText("Party Inventory")
tintText(title, COLORS.gold)
transferStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
transferStatus:SetPoint("LEFT", title, "RIGHT", 16, 0)
transferStatus:SetWidth(FRAME_WIDTH - 350)
transferStatus:SetJustifyH("LEFT")
tintText(transferStatus, COLORS.muted)
local close = controlButton(frame, "X", 27, 24)
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -9)
close:SetScript("OnClick", function() frame:Hide() end)
local fullscreenButton = controlButton(frame, "Maximize", 85, 24)
fullscreenButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
fullscreenButton:SetScript("OnClick", function()
    fullscreen = not fullscreen
    fullscreenButton.caption:SetText(fullscreen and "Restore" or "Maximize")
    if fullscreen then
        fullscreenBackdrop:Show()
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(1)
        frame:SetClampedToScreen(false)
    else
        fullscreenBackdrop:Hide()
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER")
    if updateViewport then updateViewport() end
    if render then render(false) end
end)
-- The normal panel no longer spends a bottom row on Previous / Next / Refresh.
-- The two header icons use original transparent classic-compatible TGA art.
local settingsButton = controlButton(frame, "", 29, 25)
settingsButton.controlLabel = "Settings"
settingsButton:SetPoint("RIGHT", fullscreenButton, "LEFT", -6, 0)
local settingsIcon = settingsButton:CreateTexture(nil, "OVERLAY")
settingsIcon:SetPoint("CENTER", settingsButton, "CENTER", 0, 0)
settingsIcon:SetWidth(22)
settingsIcon:SetHeight(22)
settingsIcon:SetTexture("Interface\\AddOns\\TortoiseBotsPartyInventory\\Assets\\Settings")
local refreshButton = controlButton(frame, "", 29, 25)
refreshButton.controlLabel = "Refresh"
refreshButton:SetPoint("RIGHT", settingsButton, "LEFT", -5, 0)
local refreshIcon = refreshButton:CreateTexture(nil, "OVERLAY")
refreshIcon:SetPoint("CENTER", refreshButton, "CENTER", 0, 0)
refreshIcon:SetWidth(23)
refreshIcon:SetHeight(23)
refreshIcon:SetTexture("Interface\\AddOns\\TortoiseBotsPartyInventory\\Assets\\Refresh")
refreshControl, settingsControl = refreshButton, settingsButton

local settingsPanel = CreateFrame("Frame", "TBMPartyInventorySettingsPanel", frame)
settingsPanel:SetWidth(244)
settingsPanel:SetHeight(171)
-- In the Classic client, restoring from fullscreen can briefly retain the
-- taller logical parent coordinates on 1366x768. A small inset keeps the
-- settings flyout fully within UIParent without altering header placement.
settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -33, -52)
settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 20)
panelOutline(settingsPanel, COLORS.panel, COLORS.outline, true)
settingsPanel:EnableMouse(true)
local settingsTitle = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
settingsTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -12)
settingsTitle:SetText("Inventory layout")
tintText(settingsTitle, COLORS.gold)
local settingsHelp = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
settingsHelp:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -37)
settingsHelp:SetText("Columns per character  (fewer = larger items)")
tintText(settingsHelp, COLORS.muted)
local columnButtons = {}
for i = 4, 7 do
    local n = i
    local button = controlButton(settingsPanel, tostring(n), 43, 27)
    button:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14 + (i - 4) * 55, -66)
    button:SetScript("OnClick", function()
        BAG_COLUMNS = n
        TBMPartyInventorySettings.columns = n
        for _, card in ipairs(columns) do card.offset = 0 end
        settingsPanel:Hide()
        if render then render(false) end
        status("Showing " .. n .. " inventory columns. Fewer columns give bigger item icons.")
    end)
    columnButtons[i] = button
end
-- Optional GM tool: server authorization is enforced by .bot chat itself.
-- A single compact switch is synced from the server's real chat state.
local chatEnabled
local chatToggle = controlButton(settingsPanel, "AI Chat: checking", 131, 24)
chatToggle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -123)
local chatReload = controlButton(settingsPanel, "Reload", 67, 24)
chatReload:SetPoint("LEFT", chatToggle, "RIGHT", 6, 0)
local chatLabel = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
chatLabel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -104)
chatLabel:SetText("AI chat controls (GM only)")
tintText(chatLabel, COLORS.muted)
chatToggle:SetScript("OnClick", function()
    if chatEnabled == nil then
        status("Waiting for AI chat state from server. Try Reload or reopen Settings.")
        TB.SendBotCommand("chat status")
        return
    end
    TB.SendBotCommand(chatEnabled and "chat off" or "chat on")
    status("Requested AI chat " .. (chatEnabled and "OFF" or "ON") ..
        "; awaiting authoritative server status.")
end)
chatReload:SetScript("OnClick", function()
    TB.SendBotCommand("chat reload")
    status("Requested server-side runtime.json reload; no realm restart required.")
end)
settingsPanel:Hide()
settingsButton:SetScript("OnClick", function()
    if settingsPanel:IsShown() then
        settingsPanel:Hide()
    else
        for n, button in pairs(columnButtons) do
            button.primary = n == BAG_COLUMNS
            if button.RefreshAppearance then button.RefreshAppearance() end
        end
        TB.SendBotCommand("chat status")
        settingsPanel:Show()
    end
end)
refreshButton:SetScript("OnClick", function()
    if not frame:IsShown() then return end
    local own = UnitName("player")
    if own then requestFreshInventory(own, true) end
    for _, member in ipairs(groupMembers()) do
        if member.name and authorizedBot(member.name) then
            requestFreshInventory(member.name, true)
        end
    end
    if render then render(false) end
    status("Refreshing the visible party's inventory snapshots...")
end)
if UISpecialFrames then table.insert(UISpecialFrames, "TBMPartyInventoryFrame") end

-- The draggable title strip and four scale handles work with 1.12's
-- StartMoving/StopMovingOrSizing and SetScale. They do not require modern
-- SetResizeBounds (absent on some classic clients).
local moveStrip = CreateFrame("Button", nil, frame)
moveStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -2)
moveStrip:SetWidth(FRAME_WIDTH - 110)
moveStrip:SetHeight(35)
moveStrip:RegisterForDrag("LeftButton")
moveStrip:SetScript("OnDragStart", function()
    if frame.StartMoving then frame:StartMoving() end
end)
moveStrip:SetScript("OnDragStop", function()
    if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
end)
local function fitFrameScale(target)
    local w = UIParent.GetWidth and UIParent:GetWidth() or 0
    local h = UIParent.GetHeight and UIParent:GetHeight() or 0
    if fullscreen then
        return math.min(FULLSCREEN_MAX_SCALE,
            (w - 8) / FRAME_WIDTH, (h - 8) / frame:GetHeight())
    end
    if w and w > 150 then target = math.min(target, (w - 18) / FRAME_WIDTH) end
    if h and h > 150 then target = math.min(target, (h - 22) / frame:GetHeight()) end
    return math.max(0.50, math.min(2.25, target))
end
local resizeCorners = {
    {"TOPLEFT", -1, 1}, {"TOPRIGHT", 1, 1},
    {"BOTTOMLEFT", -1, -1}, {"BOTTOMRIGHT", 1, -1},
}
for _, corner in ipairs(resizeCorners) do
    local grip = CreateFrame("Button", nil, frame)
    grip.cornerRole = corner[1]
    -- A 1.12 drag callback runs long after this generic-for iteration ends.
    -- Never dereference the loop control table inside a deferred callback.
    grip.resizeXSign = corner[2]
    grip.resizeYSign = corner[3]
    grip:SetWidth(13)
    grip:SetHeight(13)
    grip:SetPoint(corner[1], frame, corner[1], 0, 0)
    grip:RegisterForDrag("LeftButton")
    grip:EnableMouse(true)
    local fill = grip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(grip)
    colorTexture(fill, COLORS.outline)
    grip:SetScript("OnDragStart", function()
        if not GetCursorPosition then return end
        local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if scale <= 0 then scale = 1 end
        local x, y = GetCursorPosition()
        if type(x) ~= "number" or type(y) ~= "number" then return end
        -- WoW 1.12 drag handlers do not consistently populate global `this`.
        -- Capture the grip directly; all four corners must work in-game.
        grip.resizeStartX, grip.resizeStartY = x / scale, y / scale
        -- The requested scale may be 1.0 while the viewport forcibly renders
        -- this 1266px panel at 0.795. Starting a resize at the UNCLAMPED
        -- requested value created a 260px dead zone: users could drag a
        -- corner inward without any visible change at all. Start from the
        -- actual displayed scale so the first mouse movement takes effect.
        grip.resizeStartScale = frame:GetScale() or requestedScale
        grip:SetScript("OnUpdate", function()
            if type(grip.resizeStartX) ~= "number"
                or type(grip.resizeStartY) ~= "number"
                or type(grip.resizeStartScale) ~= "number" then return end
            local xNow, yNow = GetCursorPosition()
            if type(xNow) ~= "number" or type(yNow) ~= "number" then return end
            local dx = grip.resizeXSign * (xNow / scale - grip.resizeStartX) / FRAME_WIDTH
            local dy = grip.resizeYSign * (yNow / scale - grip.resizeStartY) / frame:GetHeight()
            local delta = math.abs(dx) > math.abs(dy) and dx or dy
            requestedScale = math.max(0.50, math.min(2.25, grip.resizeStartScale + delta))
            frame:SetScale(fitFrameScale(requestedScale))
        end)
    end)
    grip:SetScript("OnDragStop", function()
        grip:SetScript("OnUpdate", nil)
        grip.resizeStartX = nil
        grip.resizeStartY = nil
        grip.resizeStartScale = nil
    end)
end

-- The drag icon is a frame that follows the actual cursor in the UI's coordinate system.
local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetWidth(32)
ghost:SetHeight(32)
ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
ghost.icon:SetAllPoints(ghost)
ghost:Hide()
ghost:SetScript("OnUpdate", function()
    if not dragged then this:Hide(); return end
    if GetCursorPosition then
        local x, y = GetCursorPosition()
        local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if not scale or scale <= 0 then scale = 1 end
        this:ClearAllPoints()
        this:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale - 12)
    end
end)

local EQUIPMENT = {0, 1, 2, 14, 4, 3, 18, 8, 9, 5, 6, 7, 10, 11, 12, 13, 15, 16, 17}
local GEAR_NAMES = {
    [0] = "Head", [1] = "Neck", [2] = "Shoulder", [3] = "Shirt", [4] = "Chest",
    [5] = "Waist", [6] = "Legs", [7] = "Feet", [8] = "Wrist", [9] = "Hands",
    [10] = "Finger 1", [11] = "Finger 2", [12] = "Trinket 1", [13] = "Trinket 2",
    [14] = "Back", [15] = "Main hand", [16] = "Off hand", [17] = "Ranged", [18] = "Tabard",
}
local GEAR_EMPTY_LABELS = {
    [0]="Hd", [1]="Nk", [2]="Sh", [3]="Sr", [4]="Ch",
    [5]="Wa", [6]="Lg", [7]="Ft", [8]="Wr", [9]="Ha",
    [10]="R1", [11]="R2", [12]="T1", [13]="T2", [14]="Bk",
    [15]="MH", [16]="OH", [17]="Rg", [18]="Tb",
    [19]="B1", [20]="B2", [21]="B3", [22]="B4",
}
-- GetInventorySlotInfo is the original client API for the vanilla paper-doll
-- empty-slot image, including trinkets, rings and the 4 equipped bag slots.
-- Do not substitute generic modern icons or gray squares for empty equipment.
local PAPER_DOLL_SLOTS = {
    [0] = "HeadSlot", [1] = "NeckSlot", [2] = "ShoulderSlot",
    [3] = "ShirtSlot", [4] = "ChestSlot", [5] = "WaistSlot",
    [6] = "LegsSlot", [7] = "FeetSlot", [8] = "WristSlot",
    [9] = "HandsSlot", [10] = "Finger0Slot", [11] = "Finger1Slot",
    [12] = "Trinket0Slot", [13] = "Trinket1Slot", [14] = "BackSlot",
    [15] = "MainHandSlot", [16] = "SecondaryHandSlot", [17] = "RangedSlot",
    [18] = "TabardSlot", [19] = "Bag0Slot", [20] = "Bag1Slot",
    [21] = "Bag2Slot", [22] = "Bag3Slot",
}
local PAPER_DOLL_FALLBACK = {
    [0] = "Head", [1] = "Neck", [2] = "Shoulder",
    [3] = "Shirt", [4] = "Chest", [5] = "Waist",
    [6] = "Legs", [7] = "Feet", [8] = "Wrists",
    [9] = "Hands", [10] = "Finger", [11] = "Finger",
    [12] = "Trinket", [13] = "Trinket", [14] = "Chest",
    [15] = "MainHand", [16] = "SecondaryHand", [17] = "Ranged",
    [18] = "Tabard", [19] = "Bag", [20] = "Bag",
    [21] = "Bag", [22] = "Bag",
}
local paperDollTextures = {}
local function emptyGearTexture(id)
    if paperDollTextures[id] then return paperDollTextures[id] end
    -- Every suffix below was verified against the actual installed MPQs,
    -- including the critical "Wrists" spelling (not "Wrist"). The custom
    -- client GetInventorySlotInfo fallback sometimes returns valid-looking
    -- paths that the renderer displays as red question marks.
    local texture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
        .. (PAPER_DOLL_FALLBACK[id] or "Bag")
    paperDollTextures[id] = texture
    return texture
end

local function beginDrag(button)
    local card, item = button.card, button.item
    if not card or not card.canInspect or not item or not item.id then return end
    local key = norm(card.character)
    local preview = optimisticPlacements[key]
    if preview and GetTime() - preview.startedAt > 8 then
        optimisticPlacements[key] = nil
        requestFreshInventory(card.character, true)
        preview = nil
    end
    if preview then
        status("This ALT's previous placement is still settling; no new move was sent.")
        return
    end
    -- An explicit new drag supersedes an older deferred GUID lookup. Never
    -- let a stale drag intention block all later trades, and never replay the
    -- old intention when its delayed inventory snapshot finally arrives.
    if deferredGuidTransfer then
        deferredGuidTransfer = nil
        if render then render(false) end
    end
    if item.noTrade and button.kind ~= "gear" then
        -- Bound stacks can still be equipped by their own bot.
        if not owned(card.character) then
            status("Bound items cannot be traded between participants.")
        end
    end
    dragged = {
        owner = card.character, type = card.characterType, item = item,
        kind = button.kind, gearSlot = button.gearSlot, card = card,
    }
    setPathTexture(ghost.icon, resolvedItemTexture(item.id, item.texture))
    ghost:Show()
    GameTooltip:Hide()
end

local function stopDrag()
    ghost:Hide()
    dragged = nil
end

local function nativeMove(source, destination)
    if TB._partySelfGearCommand then
        -- The queued self equipment command still addresses its original
        -- native bag/gear slot, so avoid moving that source behind its back.
        TB.SubmitPartySelfGearCommand(nil, nil)
        return
    end
    if CursorHasItem and CursorHasItem() then
        status("Put the item currently on your cursor away first.")
        return
    end
    if (source.kind == "gear" and not PickupInventoryItem)
        or (source.kind == "bag" and not PickupContainerItem)
        or (destination.kind == "gear" and not PickupInventoryItem)
        or (destination.kind == "bag" and not PickupContainerItem) then
        status("Native equipment movement is unavailable in this client.")
        return
    end
    if destination.kind == "bag" and
        (not destination.item or destination.item.playerBag == nil) then
        status("Destination bag slot cannot be resolved.")
        return
    end
    if source.kind == "gear" then
        invalidateSelfSnapshot()
        PickupInventoryItem(source.gearSlot + 1)
    else
        invalidateSelfSnapshot()
        PickupContainerItem(source.item.playerBag, source.item.playerSlot)
    end
    if CursorHasItem and not CursorHasItem() then
        status("The source item is locked or could not be picked up.")
        return
    end
    if destination.kind == "gear" then
        PickupInventoryItem(destination.gearSlot + 1)
    else
        PickupContainerItem(destination.item.playerBag, destination.item.playerSlot)
    end
    if CursorHasItem and CursorHasItem() then
        -- A displaced item goes back to the now-vacant source slot where possible.
        if source.kind == "gear" then
            PickupInventoryItem(source.gearSlot + 1)
        else
            PickupContainerItem(source.item.playerBag, source.item.playerSlot)
        end
    end
    if CursorHasItem and CursorHasItem() then
        status("Swap needs attention: the displaced item is still on your cursor.")
    else
        status("Move sent to the game.")
        if source.kind == "bag" and destination.kind == "bag" and
            source.item.id ~= destination.item.id then
            TB._partyLocalBagMove = {
                from = source.owner, to = destination.owner,
                source = source.item, target = destination.item,
                expires = GetTime() + 0.7,
            }
        end
    end
    if repaintSelf then repaintSelf() end
    refreshAt = GetTime() + 0.04
end

local function unequipLocalGear(slot)
    if TB._partySelfGearCommand then
        TB.SubmitPartySelfGearCommand(nil, nil)
        return
    end
    if CursorHasItem and CursorHasItem() then
        status("Put the item on your cursor away before unequipping.")
        return
    end
    if (slot >= 19 and slot <= 22) or not PickupInventoryItem
        or not PickupContainerItem or not CursorHasItem then
        -- Equipped bags may require evacuating their contents atomically.
        if selfServerEquipmentAvailable then
            TB.SubmitPartySelfGearCommand("item self unequip 255 " .. slot, "unequip")
        else
            status("This client or realm cannot safely unequip the selected slot.")
        end
        return
    end
    if not GetInventoryItemTexture("player", slot + 1) then return end
    local free = {}
    for bag = 0, 4 do
        for position = 1, (GetContainerNumSlots(bag) or 0) do
            if not GetContainerItemInfo(bag, position) then
                table.insert(free, { bag = bag, slot = position })
            end
        end
    end
    if table.getn(free) == 0 then
        status("No empty bag slot is available for this equipment.")
        return
    end
    invalidateSelfSnapshot()
    PickupInventoryItem(slot + 1)
    if not CursorHasItem() then
        status("The game did not allow that item to be unequipped.")
        return
    end
    for _, dest in ipairs(free) do
        PickupContainerItem(dest.bag, dest.slot)
        if not CursorHasItem() then
            status("Unequipped to your bags.")
            if repaintSelf then repaintSelf() end
            refreshAt = GetTime() + 0.04
            return
        end
    end
    -- Put it back, not leave a displaced weapon attached to the cursor.
    PickupInventoryItem(slot + 1)
    status(CursorHasItem() and "No compatible free slot; item remains on cursor." or
        "The item could not be unequipped and was restored.")
end

local function stagePaid(source, destination)
    if checkoutQueue then
        status("Checkout is running. Wait for each item's verified settlement.")
        return
    end
    if source.type ~= "ai" or destination.owner ~= UnitName("player") or source.kind ~= "bag" then
        status("Paid bot trades currently support bot bags to your character only.")
        return
    end
    local args = commandArgs(source.item)
    if not args then
        status("A server item GUID is required before staging this trade. Refresh inventory.")
        return
    end
    if source.item.salePrice == 0 then
        status("This bot does not offer that item for sale.")
        return
    end
    local key = norm(source.owner) .. "|" .. args
    for _, entry in ipairs(pendingTrade) do
        if entry.key == key then
            status("Item is already staged. No trade was performed.")
            return
        end
    end
    table.insert(pendingTrade, {
        key = key, name = source.owner, item = source.item, bag = source.item.bag,
        slot = source.item.slot, guid = source.item.guid, count = source.item.count,
        id = source.item.id, price = source.item.salePrice,
        targetOwner = destination.owner,
        targetBag = destination.item and destination.item.bag or nil,
        targetSlot = destination.item and destination.item.slot or nil,
    })
    status(source.item.salePrice and
        ("Staged at bot's server price: " .. moneyText(source.item.salePrice)) or
        "Staged; requesting the bot price automatically.")
    refreshTrade()
    if render then render(false) end
    -- Request the real price immediately rather than requiring a second click.
    -- The shared send queue serializes requests when chat is rate-limited.
    if not source.item.salePrice and fillTradeAmount then fillTradeAmount() end
end

StaticPopupDialogs.TBM_PARTY_SWAP = {
    text = "Swap the selected stacks between %s and %s?",
    button1 = ACCEPT, button2 = CANCEL, timeout = 0, hideOnEscape = 1,
    OnAccept = function()
        if this.data and not pendingTransfer then
            pendingTransfer = {
                kind = "transfer", from = this.from, to = this.to,
                startedAt = GetTime(),
            }
            command(this.data)
        end
    end,
}

local function buyOne(entry, enteredCopper)
    if not entry or not tradeCapable or type(entry.price) ~= "number"
        or entry.price <= 0 or entry.price ~= math.floor(entry.price)
        or pendingTransfer then return false end
    if not isInGroup(entry.name) or botType(entry.name) ~= "ai" then return false end
    local staged = false
    for _, candidate in ipairs(pendingTrade) do
        if candidate == entry then staged = true; break end
    end
    if not staged then return false end
    if enteredCopper ~= entry.price then
        status("Entered amount differs from the actual bot quote; no purchase submitted.")
        return false
    end
    local beforeCount = countLocalItem(entry.id)
    local beforeMoney = GetMoney and GetMoney() or nil
    if not beforeCount or not beforeMoney then
        status("Cannot verify inventory or money baseline. Purchase cancelled.")
        return false
    end
    -- Snapshot the agreed price and source identity at submission time. The
    -- staging entry is mutable: late INV_TYPE/TRADE_CAPS/INV_ITEM can reprice
    -- or invalidate it while the native trade is still waiting for acceptance.
    -- Never use entry.price again to verify money taken by this transaction.
    pendingTransfer = {
        kind = "buy", entry = entry, beforeCount = beforeCount, beforeMoney = beforeMoney,
        price = enteredCopper, sourceGuid = entry.guid, sourceId = entry.id,
        sourceCount = entry.count, serverComplete = false,
        serverPending = false, botSeen = false, startedAt = GetTime(),
    }
    syncNativeTradeFrame()
    command("item " .. entry.name .. " buy " .. entry.bag .. " " .. entry.slot
        .. " " .. entry.guid .. " " .. entry.count .. " " .. enteredCopper)
    refreshTrade()
    return true
end

abortCheckout = function(reason)
    checkoutQueue = nil
    status("Checkout stopped: " .. (reason or "unverified trade") ..
        ". Purchased items stay purchased; remaining items remain staged. Do not retry an uncertain payment.")
    if refreshTrade then refreshTrade() end
end

startQueuedCheckout = function()
    local queue = checkoutQueue
    if not queue or pendingTransfer then return false end
    local wanted = queue.entries[queue.nextIndex]
    if not wanted then
        checkoutQueue = nil
        status("All " .. queue.total .. " purchases verified: exact items and copper, no duplicate payments.")
        if refreshTrade then refreshTrade() end
        return true
    end
    local entry = wanted.entry
    if entry.guid ~= wanted.guid or entry.id ~= wanted.id
        or entry.count ~= wanted.count or entry.price ~= wanted.price then
        abortCheckout("a seller's GUID, stack count or price changed after approval")
        return false
    end
    if not buyOne(entry, wanted.price) then
        abortCheckout("a seller or item became unavailable, or a trade is still pending")
        return false
    end
    status("Checkout " .. queue.nextIndex .. "/" .. queue.total .. ": " ..
        entry.name .. ", " .. moneyText(wanted.price) .. "; verifying before next item.")
    return true
end

local function receive(destinationButton)
    local source = dragged
    if not source then return end
    local card = destinationButton.card
    if not card or not card.canInspect then
        status("Destination inventory is private or not yet authorized.")
        return
    end
    local destination = {
        owner = card.character, type = card.characterType, item = destinationButton.item,
        kind = destinationButton.kind, gearSlot = destinationButton.gearSlot,
    }
    if not isInGroup(source.owner) or not isInGroup(destination.owner) then
        status("Party membership changed. Refresh before moving items.")
        return
    end
    if TB._partySelfGearCommand and
        (source.type == "self" or destination.type == "self") then
        TB.SubmitPartySelfGearCommand(nil, nil)
        return
    end
    if source.owner == destination.owner and source.type == "self"
        and source.kind == "bag" and destination.kind == "bag" then
        if source.item ~= destination.item then nativeMove(source, destination) end
        return
    end
    if deferredGuidTransfer then
        status("Synchronizing an earlier stack; no item has moved yet.")
        return
    end
    if pendingTransfer or checkoutQueue then
        status("Another item transfer is still being verified. Try again after refresh.")
        return
    end
    if source.owner == destination.owner then
        if source.kind == destination.kind
            and (source.kind ~= "gear" or source.gearSlot == destination.gearSlot)
            and (source.kind ~= "bag" or source.item == destination.item) then return end
        if source.type == "self" then
            if source.kind == "gear" and destination.kind == "gear"
                and source.gearSlot >= 19 and source.gearSlot <= 22
                and destination.gearSlot >= 19 and destination.gearSlot <= 22 then
                if selfServerEquipmentAvailable then
                    TB.SubmitPartySelfGearCommand("item self bagswap " .. source.gearSlot .. " "
                        .. destination.gearSlot, "bagswap")
                else
                    status("This server cannot safely swap equipped bags. Update TortoiseBots Core.")
                end
            elseif source.kind == "gear" and destination.kind == "bag" then
                if selfServerEquipmentAvailable and source.gearSlot >= 19 and source.gearSlot <= 22 then
                    TB.SubmitPartySelfGearCommand("item self unequip 255 " .. source.gearSlot,
                        "unequip")
                elseif source.gearSlot >= 19 and source.gearSlot <= 22 then
                    status("This server cannot safely unequip a worn bag. Update TortoiseBots Core.")
                else
                    nativeMove(source, destination)
                end
            elseif source.kind == "bag" and destination.kind == "gear" then
                if selfServerEquipmentAvailable and destination.gearSlot >= 19 and destination.gearSlot <= 22 then
                    TB.SubmitPartySelfGearCommand("item self equip " .. source.item.bag .. " "
                        .. source.item.slot .. " " .. destination.gearSlot, "equip")
                elseif destination.gearSlot >= 19 and destination.gearSlot <= 22 then
                    status("This server cannot safely equip a carried bag. Update TortoiseBots Core.")
                else
                    nativeMove(source, destination)
                end
            else
                nativeMove(source, destination)
            end
        elseif source.type == "own" or source.type == "ai" then
            if source.kind == "bag" and destination.kind == "bag"
                and destination.item and destination.item.bag ~= nil then
                local targetGuid = destination.item.guid or 0
                local targetCount = destination.item.count or 0
                local commandText = "item " .. source.owner .. " place "
                    .. source.item.bag .. " " .. source.item.slot .. " "
                    .. (source.item.guid or 0) .. " " .. (source.item.count or 0) .. " "
                    .. destination.item.bag .. " " .. destination.item.slot .. " "
                    .. targetGuid .. " " .. targetCount
                if source.item.guid and source.item.guid > 0 then
                    optimisticPlacements[norm(source.owner)] = {
                        name = source.owner,
                        sourceBag = source.item.bag, sourceSlot = source.item.slot,
                        destinationBag = destination.item.bag,
                        destinationSlot = destination.item.slot,
                        sourceGuid = source.item.guid, sourceId = source.item.id,
                        targetGuid = targetGuid, startedAt = GetTime(),
                    }
                end
                command(commandText)
                if render then render(false) end
            elseif source.kind == "bag" and destination.kind == "gear" and source.type == "own" then
                command("item " .. source.owner .. " equip " .. source.item.bag .. " "
                    .. source.item.slot .. " " .. destination.gearSlot)
            elseif source.kind == "gear" and destination.kind == "bag" and source.type == "own" then
                command("item " .. source.owner .. " unequip 255 " .. source.gearSlot)
            elseif source.kind == "gear" and destination.kind == "gear" and source.type == "own"
                and source.gearSlot >= 19 and source.gearSlot <= 22
                and destination.gearSlot >= 19 and destination.gearSlot <= 22 then
                command("item " .. source.owner .. " bagswap " .. source.gearSlot
                    .. " " .. destination.gearSlot)
            else
                status("Use inventory slots to place items, or gear slots to equip them.")
            end
        else
            status("Non-owned bots require an authorized item transaction.")
        end
        return
    end
    if source.kind == "gear" or destination.kind == "gear" then
        status("Cross-character equipment swaps need server equipment-transfer support.")
        return
    end
    if source.item and source.item.noTrade then
        status("This bound item cannot be transferred.")
        return
    end
    if source.type == "ai" then
        stagePaid(source, destination)
        return
    end
    if destination.type == "ai" then
        status("Giving items to non-owned bots requires a separate trade protocol.")
        return
    end
    local args = commandArgs(source.item)
    if source.type == "self" and selfServerProtocolAvailable == false then
        status("This realm lacks the current self-inventory trade protocol. Update server Core.")
        return
    end
    if not args then
        if source.kind == "bag" and destination.kind == "bag"
            and source.item and source.item.id and source.item.count > 0
            and destination.item and destination.item.bag ~= nil
            and not destination.item.id
            and not deferredGuidTransfer then
            -- Native BAG_UPDATE can arrive before the server inventory reply,
            -- so the UI knows a valid local item but not its database GUID.
            -- Queue the user's exact intent and execute it only after a
            -- matching authoritative source snapshot has supplied the GUID.
            deferredGuidTransfer = {
                from = source.owner, to = destination.owner,
                fromType = source.type, toType = destination.type,
                bag = source.item.bag, slot = source.item.slot,
                id = source.item.id, count = source.item.count,
                playerBag = source.item.playerBag,
                playerSlot = source.item.playerSlot,
                toBag = destination.item.bag, toSlot = destination.item.slot,
                targetId = destination.item.id,
                targetCount = destination.item.count,
                startedAt = GetTime(),
                visual = {from = source.owner, to = destination.owner,
                    source = source.item, target = destination.item},
            }
            if guidResolveCapable then
                local from = source.type == "self" and "self" or source.owner
                command("item " .. from .. " resolve " .. source.item.bag .. " "
                    .. source.item.slot .. " " .. source.item.id .. " " .. source.item.count)
                status("Checking the exact stack GUID; moving automatically after confirmation.")
            elseif source.type == "self" then
                TB.SendBotCommand("inv self")
            else
                TB.RequestInventory(source.owner)
            end
            status("Synchronizing the selected stack; the exact move is queued.")
            if render then render(false) end
            return
        end
        status("Source GUID unavailable; requested a fresh inventory snapshot.")
        if source.type == "self" then
            TB.SendBotCommand("inv self")
        else
            TB.RequestInventory(source.owner)
        end
        return
    end
    local from = source.type == "self" and "self" or source.owner
    local to = destination.type == "self" and "self" or destination.owner
    local prefix = "item " .. from .. " transfer " .. to .. " "
    if not destination.item or not destination.item.id then
        pendingTransfer = {
            kind = "transfer", from = source.owner, to = destination.owner,
            startedAt = GetTime(),
        }
        if destination.item and destination.item.bag ~= nil then
            pendingTransfer.visual = {from = source.owner, to = destination.owner,
                source = source.item, target = destination.item}
            command(prefix .. "put " .. args .. " "
                .. destination.item.bag .. " " .. destination.item.slot)
            if render then render(false) end
        else
            command(prefix .. "move " .. args)
        end
    elseif destination.item.guid and not destination.item.noTrade then
        local destArgs = commandArgs(destination.item)
        if not destArgs then
            status("Destination stack has no server GUID.")
            return
        end
        local dialog = StaticPopup_Show("TBM_PARTY_SWAP", source.owner, destination.owner)
        if dialog then
            dialog.data = prefix .. "swap " .. args .. " " .. destArgs
            dialog.from, dialog.to = source.owner, destination.owner
        end
    else
        status("Destination has no swappable server stack GUID.")
    end
end

local function wireSlot(button)
    button.receiveStack = receive
    button:SetScript("OnDragStart", function()
        if IsAltKeyDown and IsAltKeyDown() and this.kind == "bag"
            and this.card and this.card.characterType == "own" then return end
        beginDrag(this)
    end)
    button:SetScript("OnDragStop", function()
        local target = GetMouseFocus and GetMouseFocus() or nil
        if target and target.receiveStack then target.receiveStack(target) end
        stopDrag()
    end)
    button:SetScript("OnClick", function()
        local card = this.card
        if card and card.canInspect and arg1 == "LeftButton"
            and this.kind == "bag" and IsAltKeyDown and IsAltKeyDown() then
            if toggleSaleMark then toggleSaleMark(this) end
            return
        end
        if not card or not card.canInspect or arg1 ~= "RightButton"
            or not this.item or not this.item.id then return end
        if this.kind == "gear" then
            if card.characterType == "self" then
                unequipLocalGear(this.gearSlot)
            elseif card.characterType == "own" then
                command("item " .. card.character .. " unequip 255 " .. this.gearSlot)
            end
        elseif this.kind == "bag" then
            if card.characterType == "own" then
                -- Auto-equip selects the correct class slot on the bot.
                command("item " .. card.character .. " equip " .. this.item.bag
                    .. " " .. this.item.slot)
            elseif card.characterType == "self" and this.item.playerBag ~= nil then
                if TB._partySelfGearCommand then
                    TB.SubmitPartySelfGearCommand(nil, nil)
                    return
                end
                local bag, slot = this.item.playerBag, this.item.playerSlot
                if CursorHasItem and CursorHasItem() then
                    status("Put the item on your cursor away before equipping.")
                    return
                end
                local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
                -- Some custom 1.12 clients return false for a complete item
                -- hyperlink even though the server item is wearable. Check
                -- its numeric ID and the item's EQUIP location independently.
                local linkedId = itemIdFromLink(link)
                if linkedId and linkedId ~= this.item.id then
                    status("The item in that slot changed. Try again.")
                    return
                end
                local nativeId = linkedId or this.item.id
                local nativeEquipment = linkedId and TB._partyWornItemIds and
                    TB._partyWornItemIds[linkedId]
                local equippable = nativeEquipment or this.item.equippable == true or (IsEquippableItem and
                    (IsEquippableItem(nativeId) or (link and IsEquippableItem(link)))
                    )
                if GetItemInfo then
                    local _, _, _, _, _, _, _, _, location = GetItemInfo(nativeId)
                    if type(location) == "string" and string.sub(location, 1, 8) == "INVTYPE_" then
                        equippable = location ~= "INVTYPE_NON_EQUIP"
                        nativeEquipment = linkedId ~= nil and location ~= "INVTYPE_NON_EQUIP"
                            and location ~= "INVTYPE_BAG" and location ~= "INVTYPE_QUIVER"
                    end
                end
                if equippable and (UseContainerItem or selfServerEquipmentAvailable) then
                    pendingSelfEquip = nil
                    if selfServerEquipmentAvailable and not (nativeEquipment and UseContainerItem) then
                        if not TB.SubmitPartySelfGearCommand("item self equip "
                            .. this.item.bag .. " " .. this.item.slot, "equip") then return end
                        status("Equipping your character through the server.")
                    else
                        invalidateSelfSnapshot()
                        UseContainerItem(this.item.playerBag, this.item.playerSlot)
                        status("Quick-equipping to your character.")
                    end
                    if repaintSelf then repaintSelf() end
                    refreshAt = GetTime() + 0.04
                else
                    -- Actual Turtle 1.18.1 bug: a genuine wearable sword
                    -- can have a valid tooltip while BOTH GetItemInfo and
                    -- IsEquippableItem are nil. Never interpret nil/false
                    -- cache information as permission to use a potion.
                    -- User's explicit right-click requests ONE authoritative
                    -- server eligibility check; only a matching `e` flag
                    -- can resume equip, without another manual click.
                    pendingSelfEquip = {
                        id = nativeId, count = this.item.count,
                        playerBag = bag, playerSlot = slot,
                        serverBag = this.item.bag, serverSlot = this.item.slot,
                        startedAt = GetTime(),
                    }
                    if selfServerProtocolAvailable == false then
                        pendingSelfEquip = nil
                        status("This server cannot verify self equipment. Update TortoiseBots Core.")
                    else
                        TB.SendBotCommand("inv self")
                        status("Checking actual server equipment eligibility; equip will resume automatically.")
                    end
                end
            end
        end
    end)
end

-- Outline the original source item and the intended drop cell during a paid
-- AI trade. This is only a preview: native trade must still finish and pass
-- item/money verification. Edges are created only for staged cells.
local function previewOutline(button, kind, seller)
    if not button.preview then
        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(button:GetFrameLevel() + 3)
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local edge = overlay:CreateTexture(nil, "OVERLAY")
            if side == "TOP" then
                edge:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
                edge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
                edge:SetHeight(2)
            elseif side == "BOTTOM" then
                edge:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
                edge:SetHeight(2)
            elseif side == "LEFT" then
                edge:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
                edge:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
                edge:SetWidth(2)
            else
                edge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
                edge:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
                edge:SetWidth(2)
            end
            overlay[side] = edge
        end
        button.preview = overlay
    end
    button.previewKind = kind
    local shade = sellerColor(seller)
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        colorTexture(button.preview[side], shade)
    end
    button.preview:Show()
end

local function previewForSlot(card, button)
    if not button.item or button.kind ~= "bag" then return end
    for _, offer in ipairs(pendingTrade) do
        if norm(card.character) == norm(offer.name) and
            button.item.guid == offer.guid and
            button.item.bag == offer.bag and button.item.slot == offer.slot then
            previewOutline(button, "source", offer.name)
            return
        end
        if norm(card.character) == norm(offer.targetOwner) and
            offer.targetBag == button.item.bag and
            offer.targetSlot == button.item.slot then
            previewOutline(button, "destination", offer.name)
            return
        end
    end
end

local function markedCount(name)
    local selected = markedForSale[norm(name)] or {}
    local count = 0
    for _ in pairs(selected) do count = count + 1 end
    return count
end

-- The ornamental TGA has an alpha-transparent middle and an integrated
-- money pouch badge. Keep a classic-client fallback border so an absent
-- addon texture can never hide the marking itself.
local function showSaleFrame(button, selected)
    if not button.saleOverlay then
        local edges = CreateFrame("Frame", nil, button)
        edges:SetAllPoints(button)
        edges:SetFrameLevel(button:GetFrameLevel() + 4)
        local art = edges:CreateTexture(nil, "OVERLAY")
        art:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        art:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        art:SetTexture("Interface\\AddOns\\TortoiseBotsPartyInventory\\Assets\\SellMarked")
        edges.art = art
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local line = edges:CreateTexture(nil, "OVERLAY")
            if side == "TOP" then
                line:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                line:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
                line:SetHeight(1)
            elseif side == "BOTTOM" then
                line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
                line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
                line:SetHeight(1)
            elseif side == "LEFT" then
                line:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
                line:SetWidth(1)
            else
                line:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
                line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
                line:SetWidth(1)
            end
            colorTexture(line, {0.98, 0.73, 0.12, 1})
        end
        button.saleOverlay = edges
    end
    button.saleSelected = selected and true or false
    if selected then button.saleOverlay:Show() else button.saleOverlay:Hide() end
end

updateSellButton = function(card)
    if not card.sellButton then return end
    if card.canInspect and card.characterType == "own" and card.character then
        local n = markedCount(card.character)
        card.sellButton.caption:SetText("Sell Marked (" .. n .. ")")
        card.sellButton:Show()
        setControlEnabled(card.sellButton, n > 0 and sellMarkedCapable
            and not activeMarkedSale[norm(card.character)])
    else
        card.sellButton:Hide()
    end
end

toggleSaleMark = function(button)
    local card, item = button.card, button.item
    if not card or card.characterType ~= "own" or not card.canInspect then
        status("Only ALTs owned by your account can receive vendor orders.")
        return
    end
    if not item or not item.id or not item.guid or item.guid <= 0
        or item.bag == nil or item.slot == nil then
        status("The item is not yet identified by the server. Refresh first.")
        return
    end
    local key = norm(card.character)
    if markedForSale[key] and markedForSale[key][item.guid] then
        -- A previously selected item must always be removable, even if its
        -- vendor metadata or quest status was learned after marking it.
        markedForSale[key][item.guid] = nil
        status("Removed item from " .. card.character .. "'s vendor list.")
        showSaleFrame(button, false)
        updateSellButton(card)
        return
    end
    local itemClass
    if GetItemInfo then
        local _, _, _, _, _, nativeClass = GetItemInfo(item.id)
        itemClass = nativeClass
    end
    if item.quest or itemClass == "Quest" or item.count <= 0 then
        status("Quest and invalid items cannot be marked for vendor sale.")
        return
    end
    if item.vendorEligible == false then
        status("The server confirms that this item cannot be sold to a vendor.")
        return
    end
    markedForSale[key] = markedForSale[key] or {}
    markedForSale[key][item.guid] = {
        bag = item.bag, slot = item.slot, id = item.id,
        guid = item.guid, count = item.count,
    }
    status("Marked item for sale. The ALT will only sell explicitly marked instances.")
    showSaleFrame(button, true)
    updateSellButton(card)
end

-- Create real bag cells on demand. The old fixed grid allocated hundreds of
-- hidden buttons for characters with only a 16-slot backpack, adding
-- unnecessary frame and texture work on every redraw.
local function ensureBagCells(card, required)
    required = math.min(required, MAX_BAG_CELLS)
    for i = table.getn(card.bags) + 1, required do
        local row = math.floor((i - 1) / BAG_COLUMNS)
        local x = (card.gridX or 4) + (i - 1 - row * BAG_COLUMNS) * BAG_CELL
        local y = BAG_GRID_TOP - row * BAG_CELL
        local b = createButton(card, x, y, BAG_CELL, BAG_CELL)
        b.card, b.kind, b.slotLabel = card, "bag", "Empty bag slot"
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function()
            -- Mouse-wheel events are captured by slot buttons in some custom
            -- 1.12 clients and do not reliably bubble to the enclosing card.
            if not card.canInspect then return end
            card.offset = math.max(0, math.min(card.maxOffset or 0,
                card.offset - (arg1 or 0) * BAG_COLUMNS))
            if render then render(false) end
        end)
        wireSlot(b)
        card.bags[i] = b
    end
end

for index = 1, 5 do
    local card = CreateFrame("Frame", nil, frame)
    card:SetWidth(CARD_WIDTH)
    card:SetHeight(460)
    card:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (index - 1) * CARD_STEP, -45)
    panelOutline(card, COLORS.card, COLORS.outline)
    card.nameHeader = card:CreateTexture(nil, "BACKGROUND")
    card.nameHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    card.nameHeader:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
    card.nameHeader:SetHeight(23)
    colorTexture(card.nameHeader, COLORS.header)
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetPoint("TOP", card, "TOP", 0, -9)
    tintText(card.name, COLORS.gold)
    -- Three native Blizzard MoneyFrame coin textures and ordinary inventory
    -- denomination labels, shown even for AI sellers (read-only for AI).
    card.moneyBar = CreateFrame("Frame", nil, card)
    card.moneyBar:SetWidth(145)
    card.moneyBar:SetHeight(19)
    card.moneyBar:SetPoint("BOTTOM", card, "BOTTOM", 0, 112)
    -- DressUpModel is created after this bar; guarantee the real coin art
    -- renders in front of its 3D viewport, not invisibly behind the model.
    card.moneyBar:SetFrameLevel(card:GetFrameLevel() + 8)
    card.moneyBackground = card.moneyBar:CreateTexture(nil, "BACKGROUND")
    card.moneyBackground:SetAllPoints(card.moneyBar)
    colorTexture(card.moneyBackground, {0.018, 0.018, 0.020, 0.83})
    card.coinTexts = {}
    for i, spec in ipairs({{x=2, width=39}, {x=62, width=24}, {x=103, width=24}}) do
        local icon = card.moneyBar:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(13)
        icon:SetHeight(13)
        icon:SetPoint("LEFT", card.moneyBar, "LEFT", spec.x, 0)
        setPathTexture(icon, COIN_TEXTURES[i])
        icon:SetTexCoord((i - 1) * 0.25, i * 0.25, 0, 1)
        local amount = card.moneyBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        amount:SetPoint("LEFT", icon, "RIGHT", 1, 0)
        amount:SetWidth(spec.width)
        amount:SetJustifyH("LEFT")
        tintText(amount, COLORS.text)
        amount:SetText("-")
        card.coinTexts[i] = amount
    end
    card.moneyBar:Hide()
    -- One entry point on the player's column; all owned ALTs are selectable
    -- together in the single dynamic transfer window.
    card.transferMoney = controlButton(card, "Transfer", 62, 19)
    card.transferMoney:SetPoint("LEFT", card.moneyBar, "RIGHT", 4, 0)
    card.transferMoney:SetFrameLevel(card:GetFrameLevel() + 9)
    card.transferMoney:SetScript("OnClick", function()
        if openCoinDialog then openCoinDialog(card.character) end
    end)
    card.transferMoney:Hide()
    card.sellerDot = card:CreateTexture(nil, "OVERLAY")
    card.sellerDot:SetWidth(7)
    card.sellerDot:SetHeight(7)
    card.sellerDot:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -9)
    card.sellerDot:Hide()
    card.modelBackdrop = card:CreateTexture(nil, "BACKGROUND")
    card.modelBackdrop:SetPoint("TOPLEFT", card, "TOPLEFT", 29, -28)
    card.modelBackdrop:SetPoint("TOPRIGHT", card, "TOPRIGHT", -29, -28)
    card.modelBackdrop:SetHeight(230)
    colorTexture(card.modelBackdrop, COLORS.inset)
    card.model = CreateFrame("DressUpModel", nil, card)
    card.model:SetWidth(174)
    card.model:SetHeight(236)
    card.model:SetPoint("TOP", card, "TOP", 0, -25)
    card.modelRotation = 0
    card.modelZoom = 1
    card.model:EnableMouse(true)
    card.model:EnableMouseWheel(true)
    card.model:RegisterForDrag("LeftButton")
    card.model:SetScript("OnDragStart", function()
        if not GetCursorPosition then return end
        local x = GetCursorPosition()
        card.model.dragStartX, card.model.dragStartRotation = x, card.modelRotation
        card.model:SetScript("OnUpdate", function()
            local currentX = GetCursorPosition()
            local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            if not scale or scale <= 0 then scale = 1 end
            card.modelRotation = card.model.dragStartRotation +
                (currentX - card.model.dragStartX) / scale * 0.012
            if card.model.SetRotation then card.model:SetRotation(card.modelRotation) end
        end)
    end)
    card.model:SetScript("OnDragStop", function()
        card.model:SetScript("OnUpdate", nil)
    end)
    card.model:SetScript("OnMouseWheel", function()
        card.modelZoom = math.max(0.60, math.min(1.85,
            card.modelZoom + (arg1 or 0) * 0.12))
        if card.model.SetModelScale then
            card.model:SetModelScale(card.modelZoom * (fullscreen and 0.76 or 1))
        elseif card.model.SetPortraitZoom then
            card.model:SetPortraitZoom(math.max(0, math.min(1, card.modelZoom - 0.6)))
        end
    end)
    card.gear = {}
    for i, id in ipairs(EQUIPMENT) do
        local side = math.floor((i - 1) / 10)
        local x = 4 + side * (CARD_WIDTH - 32)
        local y = -25 - (i - 1 - side * 10) * 24
        local b = createButton(card, x, y, 24, 24)
        b.card, b.kind, b.gearSlot, b.slotLabel = card, "gear", id, GEAR_NAMES[id]
        b.emptyLabel = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.emptyLabel:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.emptyLabel:SetText(GEAR_EMPTY_LABELS[id] or "+")
        tintText(b.emptyLabel, COLORS.muted)
        wireSlot(b)
        card.gear[id] = b
    end
    card.bagGear = {}
    for bagIndex = 1, 4 do
        local slot = 18 + bagIndex
        local b = createButton(card, 59 + (bagIndex - 1) * 31, -265, 28, 28)
        b.card, b.kind, b.gearSlot = card, "gear", slot
        b.slotLabel = "Bag " .. bagIndex
        b.emptyLabel = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.emptyLabel:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.emptyLabel:SetText(GEAR_EMPTY_LABELS[slot])
        tintText(b.emptyLabel, COLORS.muted)
        wireSlot(b)
        card.gear[slot] = b
        card.bagGear[bagIndex] = b
    end
    -- Under the paper doll, four conventional weapons/ammunition controls;
    -- four actual equipped bags move below the scrolling inventory grid.
    for i, slot in ipairs({15, 16, 17}) do
        local b = card.gear[slot]
        b:ClearAllPoints()
        b:SetWidth(28)
        b:SetHeight(28)
        b:SetPoint("TOPLEFT", card, "TOPLEFT", 59 + (i - 1) * 31, -265)
    end
    card.ammo = createButton(card, 59 + 3 * 31, -265, 28, 28)
    card.ammo.card, card.ammo.kind, card.ammo.slotLabel = card, "ammo", "Ammo"
    card.ammo:EnableMouse(false)
    card.sectionLine = card:CreateTexture(nil, "BORDER")
    card.sectionLine:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -296)
    card.sectionLine:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -296)
    card.sectionLine:SetHeight(1)
    colorTexture(card.sectionLine, COLORS.outline)
    card.bagsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.bagsLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -305)
    card.bagsLabel:SetText("INVENTORY")
    tintText(card.bagsLabel, COLORS.muted)
    -- This redundant label overlaps the first large item cell in fullscreen.
    -- The layout and item textures make the section self-explanatory.
    card.bagsLabel:Hide()
    card.bags = {}
    card.offset = 0
    card:EnableMouseWheel(true)
    ensureBagCells(card, 16)
    -- Narrow scrollbar in the otherwise unused 10px strip beside the seven
    -- 32px inventory columns. Only show when there are more than 56 slots.
    local track = CreateFrame("Button", nil, card)
    track:SetWidth(8)
    track:SetHeight(64)
    track:SetPoint("TOPLEFT", card, "TOPLEFT", 233, BAG_GRID_TOP)
    track:EnableMouse(true)
    track:RegisterForDrag("LeftButton")
    track.background = track:CreateTexture(nil, "BACKGROUND")
    track.background:SetAllPoints(track)
    colorTexture(track.background, COLORS.inset)
    track.thumb = track:CreateTexture(nil, "ARTWORK")
    track.thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    track.thumb:SetWidth(6)
    track.thumb:SetHeight(24)
    colorTexture(track.thumb, COLORS.accent)
    local function seekFromCursor()
        if not card.canInspect or not GetCursorPosition or not track.GetTop then return end
        local scale = track.GetEffectiveScale and track:GetEffectiveScale() or 1
        if not scale or scale <= 0 then scale = 1 end
        local _, y = GetCursorPosition()
        local top = track:GetTop()
        if not top then return end
        local travel = math.max(1, track:GetHeight() - (track.thumbHeight or 24))
        local fraction = math.max(0, math.min(1,
            (top - y / scale - (track.thumbHeight or 24) / 2) / travel))
        local maxRows = math.floor((card.maxOffset or 0) / BAG_COLUMNS)
        card.offset = math.floor(fraction * maxRows + 0.5) * BAG_COLUMNS
        if render then render(false) end
    end
    track:SetScript("OnMouseDown", seekFromCursor)
    track:SetScript("OnDragStart", function()
        track:SetScript("OnUpdate", seekFromCursor)
    end)
    track:SetScript("OnDragStop", function()
        track:SetScript("OnUpdate", nil)
    end)
    track:Hide()
    card.scrollTrack = track
    card.status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.status:SetPoint("BOTTOM", card, "BOTTOM", 0, 6)
    card.status:SetWidth(CARD_WIDTH - 8)
    tintText(card.status, COLORS.muted)
    card.tradeInfo = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.tradeInfo:SetPoint("BOTTOM", card, "BOTTOM", 0, 95)
    card.tradeInfo:SetWidth(CARD_WIDTH - 14)
    tintText(card.tradeInfo, COLORS.gold)
    card.tradeInfo:Hide()
    if index > 1 then
        card.actions = {}
        local actions = {
            { label = "Orders", open = TB.OpenOrderWindow },
            { label = "Trainer", open = TB.OpenNpc },
        }
        for i, action in ipairs(actions) do
            local b = controlButton(card, action.label, 53, 22)
            local open = action.open
            b:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 7 + (i - 1) * 59, 24)
            b:SetScript("OnClick", function()
                if card.canInspect and card.character and open then
                    local result = open(card.character)
                    if result ~= false then
                        -- The opened Orders/Trainer view owns the screen now.
                        -- OnHide must not resurrect the TBM manager underneath
                        -- that newly opened view.
                        managerWasVisible = false
                        frame:Hide()
                    end
                end
            end)
            table.insert(card.actions, b)
        end
    end
    card.sortButton = controlButton(card, "Auto Sort", 72, 22)
    card.sortButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 24)
    card.sortButton:SetScript("OnClick", function()
        if pendingTransfer or deferredGuidTransfer or pendingSelfEquip
            or not card.character then return end
        local eligible = card.characterType == "self"
            or card.characterType == "own" or card.characterType == "ai"
        if not eligible then return end
        local who = card.characterType == "self" and "self" or card.character
        -- Sorting can change bag slots targeted by a queued self equip.
        -- Serialize both directions using the native sort ACK + self snapshot.
        if who == "self" and selfServerEquipmentAvailable then
            if not TB.SubmitPartySelfGearCommand("item self sort", "sort") then return end
        else
            if who ~= "self" and optimisticPlacements[norm(who)] then
                status("Wait for the previous ALT placement to finish before sorting.")
                return
            end
            command("item " .. who .. " sort")
        end
        status("Sorting " .. card.character .. "'s standard bags. Special bags are unchanged.")
    end)
    card.sellButton = controlButton(card, "Sell Marked (0)", 112, 22, true)
    card.sellButton:SetPoint("BOTTOM", card, "BOTTOM", 0, 53)
    card.sellButton:SetScript("OnClick", function()
        if not card.canInspect or card.characterType ~= "own"
            or activeMarkedSale[norm(card.character)] or not sellMarkedCapable then return end
        local key = norm(card.character)
        local chosen = markedForSale[key] or {}
        local inventory = TB.GetInventory(card.character)
        if not inventory or not inventory.items then
            status("No authoritative ALT inventory. Refresh and try again.")
            return
        end
        local confirmed, tokens, count = {}, {}, 0
        for _, item in ipairs(inventory.items) do
            local selection = item.guid and chosen[item.guid]
            if selection and item.id == selection.id and item.count == selection.count
                and item.bag == selection.bag and item.slot == selection.slot then
                count = count + 1
                confirmed[item.guid] = selection
                table.insert(tokens, item.bag .. " " .. item.slot .. " "
                    .. item.guid .. " " .. item.id .. " " .. item.count)
            end
        end
        if count == 0 or count ~= markedCount(card.character) or count > 12 then
            status("Marked stacks changed. Verify the current items before selling (max 12).")
            requestFreshInventory(card.character, true)
            return
        end
        -- The server checks ownership, vendor accessibility, sell price,
        -- exact GUID/item/count/slot and that none are equipped or quest items.
        activeMarkedSale[key] = { selected = confirmed, startedAt = GetTime(),
            name = card.character, count = count }
        updateSellButton(card)
        local request = "sellmarked " .. card.character .. " " .. count
            .. " " .. table.concat(tokens, " ")
        if not command(request, "Sending verified vendor order for " ..
            card.character .. "; awaiting server acceptance...") then
            activeMarkedSale[key] = nil
            updateSellButton(card)
        end
    end)
    card.privacy = CreateFrame("Frame", nil, card)
    card.privacy:SetAllPoints(card)
    card.privacy:SetFrameLevel(card:GetFrameLevel() + 10)
    card.privacy:SetBackdrop({ bgFile = EMPTY })
    card.privacy:SetBackdropColor(0.015, 0.021, 0.031, 0.92)
    card.privacy.text = card.privacy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.privacy.text:SetPoint("CENTER", card.privacy, "CENTER", 0, 0)
    card.privacy.text:SetWidth(CARD_WIDTH - 20)
    tintText(card.privacy.text, COLORS.muted)
    card.privacy:Hide()
    card:SetScript("OnMouseWheel", function()
        if not card.canInspect then return end
        card.offset = math.max(0, math.min(card.maxOffset or 0,
            card.offset - (arg1 or 0) * BAG_COLUMNS))
        if render then render(false) end
    end)
    columns[index] = card
end

refreshCoinBars = function()
    for _, card in ipairs(columns) do
        local name = card.character
        if name and card.canInspect and (card.characterType == "self"
            or card.characterType == "own" or card.characterType == "ai") then
            local actual = confirmedMoney(name)
            local gold, silver, copper = coinAmounts(actual)
            local formatted = actual and {gold, silver, copper} or {"-", "-", "-"}
            for i, value in ipairs(formatted) do
                card.coinTexts[i]:SetText(tostring(value))
            end
            card.moneyBar:ClearAllPoints()
            card.moneyBar:SetPoint("BOTTOM", card, "BOTTOM",
                card.characterType == "self" and -29 or 0,
                fullscreen and table.getn(groupMembers()) >= 3 and 101 or 115)
            card.moneyBar:Show()
            if card.characterType == "self"
                and moneyCapable and not pendingCoinTransfer then
                card.transferMoney:Show()
            else
                card.transferMoney:Hide()
            end
        else
            card.moneyBar:Hide()
            card.transferMoney:Hide()
        end
    end
end
TB.RefreshCoinBars = refreshCoinBars

local tradeFrame = CreateFrame("Frame", nil, frame)
tradeFrame:SetWidth(FRAME_WIDTH - 24)
tradeFrame:SetHeight(34)
tradeFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -656)
panelOutline(tradeFrame, COLORS.card, COLORS.outline)
local tradeTitle = tradeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tradeTitle:SetPoint("TOPLEFT", tradeFrame, "TOPLEFT", 10, -8)
tradeTitle:SetText("Trade")
tintText(tradeTitle, COLORS.gold)
local tradeItems = tradeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tradeItems:SetPoint("LEFT", tradeTitle, "RIGHT", 12, 0)
tradeItems:SetWidth(360)
tradeItems:SetHeight(22)
tradeItems:SetJustifyH("LEFT")
tintText(tradeItems, COLORS.muted)
local tradeAmounts = tradeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tradeAmounts:SetPoint("TOPRIGHT", tradeFrame, "TOPRIGHT", -10, -26)
tradeAmounts:SetWidth(1)
tradeAmounts:SetHeight(1)
tradeAmounts:Hide()
tradeAmounts:SetJustifyH("RIGHT")
tradeAmounts:SetJustifyV("TOP")
local noPartyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
noPartyText:SetPoint("CENTER", frame, "CENTER", 0, 60)
noPartyText:SetText("You are not in a party.")
tintText(noPartyText, COLORS.muted)
noPartyText:Hide()

local function tradeButton(label, x, width)
    local b = controlButton(tradeFrame, label, width, 23, label == "Review / Pay")
    b:SetPoint("BOTTOMRIGHT", tradeFrame, "BOTTOMRIGHT", x, 7)
    return b
end
local clearTrade = tradeButton("Clear", -204, 55)
local fillTrade = tradeButton("Fill", -140, 55)
local completeTrade = tradeButton("Review / Pay", -10, 122)

-- The confirmation window has editable currency fields for each staged seller.
-- The native backend accepts one quoted stack at a time, never a batch purchase.
local tradeDialog = CreateFrame("Frame", "TBMPartyInventoryTradeDialog", UIParent)
tradeDialog:SetWidth(590)
tradeDialog:SetHeight(176)
tradeDialog:SetPoint("CENTER", UIParent, "CENTER")
tradeDialog:SetFrameStrata("FULLSCREEN_DIALOG")
tradeDialog:SetFrameLevel(250)
if tradeDialog.SetToplevel then tradeDialog:SetToplevel(true) end
tradeDialog:EnableMouse(true)
panelOutline(tradeDialog, COLORS.panel, COLORS.outline, true)
tradeDialog:Hide()
-- The dialog is a sibling of the full-screen panel. Both use the same strata
-- in Classic, therefore explicit frame level is essential: parentage alone
-- does not put this sibling above five deep inventory column hierarchies.
tradeDialog:SetScript("OnShow", function()
    tradeDialog:SetFrameStrata("FULLSCREEN_DIALOG")
    tradeDialog:SetFrameLevel(math.max(250, frame:GetFrameLevel() + 120))
    local scale = frame:GetScale() or 1
    tradeDialog:SetScale(math.max(0.70, math.min(1.20, scale)))
    if tradeDialog.Raise then tradeDialog:Raise() end
end)
local dialogHeader = tradeDialog:CreateTexture(nil, "BACKGROUND")
dialogHeader:SetPoint("TOPLEFT", tradeDialog, "TOPLEFT", 2, -3)
dialogHeader:SetPoint("TOPRIGHT", tradeDialog, "TOPRIGHT", -2, -3)
dialogHeader:SetHeight(45)
colorTexture(dialogHeader, COLORS.header)
local dialogTitle = tradeDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dialogTitle:SetPoint("TOPLEFT", tradeDialog, "TOPLEFT", 14, -12)
dialogTitle:SetText("Complete Trade")
tintText(dialogTitle, COLORS.gold)
local dialogSubtitle = tradeDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dialogSubtitle:SetPoint("TOPLEFT", tradeDialog, "TOPLEFT", 14, -37)
dialogSubtitle:SetText("Server price - Enter gold, silver and copper")
tintText(dialogSubtitle, COLORS.muted)
local dialogHint = tradeDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dialogHint:SetPoint("BOTTOMLEFT", tradeDialog, "BOTTOMLEFT", 14, 39)
dialogHint:SetWidth(540)
dialogHint:SetJustifyH("LEFT")
tintText(dialogHint, COLORS.muted)
local dialogRows = {}
local refreshDialog
local fillDialog
local fillWhenQuoted = false

local function dialogButton(text, x, w)
    local b = controlButton(tradeDialog, text, w, 25, text == "Confirm Purchase")
    b:SetPoint("BOTTOMRIGHT", tradeDialog, "BOTTOMRIGHT", x, 10)
    return b
end
local dialogClose = dialogButton("Close", -12, 70)
local dialogBuy = dialogButton("Confirm Purchase", -93, 148)
local dialogFill = dialogButton("Fill", -252, 70)
dialogClose:SetScript("OnClick", function() tradeDialog:Hide() end)

-- Coin transfers are kept completely separate from paid AI item checkout.
-- The only permitted endpoints are this authenticated player and an owned,
-- currently grouped ALT. The server independently rechecks real trade range.
coinDialog = CreateFrame("Frame", "TBMPartyInventoryCoinsDialog", UIParent)
coinDialog:SetWidth(454)
coinDialog:SetHeight(236)
coinDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
coinDialog:SetFrameStrata("FULLSCREEN_DIALOG")
coinDialog:SetFrameLevel(340)
if coinDialog.SetToplevel then coinDialog:SetToplevel(true) end
coinDialog:EnableMouse(true)
panelOutline(coinDialog, COLORS.panel, COLORS.outline, true)
coinDialog:Hide()
coinDialog:SetScript("OnShow", function()
    coinDialog:SetFrameStrata("FULLSCREEN_DIALOG")
    coinDialog:SetFrameLevel(math.max(340, frame:GetFrameLevel() + 150))
    coinDialog:SetScale(math.max(0.75, math.min(1.15, frame:GetScale() or 1)))
    if coinDialog.Raise then coinDialog:Raise() end
end)
local function setupCoinDialogControls()
    -- Each visible row is one own-account ALT; two independent triplets
    -- represent simultaneous YOU->ALT and ALT->YOU copper flows.
    coinDialog:SetWidth(855)
    local rowFrames = {}
    local activeCount = 0
    local loading = false
    local updateCoinDialog
    local function makeLabel(parent, caption, x, y, width, color)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(caption)
        tintText(label, color or COLORS.muted)
        return label
    end
    local heading = makeLabel(coinDialog, "Transfer Coins - All Party ALTs",
        16, -13, 540, COLORS.gold)
    if heading.SetFontObject then heading:SetFontObject(GameFontNormalLarge) end
    makeLabel(coinDialog, "One secure transaction for all selected rows. Each ALT must stand beside you.",
        16, -39, 790, COLORS.muted)
    makeLabel(coinDialog, "ALT / AVAILABLE", 26, -67, 128, COLORS.gold)
    makeLabel(coinDialog, "YOU  >  ALT", 197, -67, 200, COLORS.gold)
    makeLabel(coinDialog, "ALT  >  YOU", 518, -67, 200, COLORS.gold)

    local function createTriplet(row, x)
        local fields = {}
        for j = 1, 3 do
            local icon = row.frame:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(16)
            icon:SetHeight(16)
            icon:SetPoint("TOPLEFT", row.frame, "TOPLEFT", x + (j - 1) * 85, -26)
            setPathTexture(icon, COIN_TEXTURES[j])
            icon:SetTexCoord((j - 1) * 0.25, j * 0.25, 0, 1)
            local field = CreateFrame("EditBox", nil, row.frame)
            field:SetWidth(57)
            field:SetHeight(24)
            field:SetPoint("LEFT", icon, "RIGHT", 3, 0)
            panelOutline(field, COLORS.inset, COLORS.outline)
            if field.SetFontObject then field:SetFontObject(GameFontHighlightSmall) end
            if field.SetJustifyH then field:SetJustifyH("CENTER") end
            field:SetNumeric(true)
            field:SetMaxLetters(j == 1 and 9 or 2)
            field:SetAutoFocus(false)
            field:SetText("0")
            field:SetScript("OnEscapePressed", function() this:ClearFocus() end)
            field:SetScript("OnEnterPressed", function() this:ClearFocus() end)
            field:SetScript("OnTextChanged", function()
                if not loading and updateCoinDialog then updateCoinDialog() end
            end)
            fields[j] = field
        end
        return fields
    end
    for i = 1, 4 do
        local row = {}
        row.frame = CreateFrame("Frame", nil, coinDialog)
        row.frame:SetWidth(827)
        row.frame:SetHeight(58)
        row.frame:SetPoint("TOPLEFT", coinDialog, "TOPLEFT", 14, -86 - (i - 1) * 64)
        panelOutline(row.frame, COLORS.card, COLORS.outline)
        row.title = makeLabel(row.frame, "", 8, -7, 121, COLORS.gold)
        row.balance = makeLabel(row.frame, "", 8, -31, 121, COLORS.muted)
        row.send = createTriplet(row, 140)
        makeLabel(row.frame, "  >  ", 416, -25, 43, COLORS.gold)
        row.receive = createTriplet(row, 470)
        row.frame:Hide()
        rowFrames[i] = row
    end
    local summary = coinDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("BOTTOMLEFT", coinDialog, "BOTTOMLEFT", 17, 67)
    summary:SetWidth(818)
    summary:SetJustifyH("LEFT")
    tintText(summary, COLORS.gold)
    local hint = coinDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", coinDialog, "BOTTOMLEFT", 17, 46)
    hint:SetWidth(818)
    hint:SetJustifyH("LEFT")
    tintText(hint, COLORS.muted)
    local copy = controlButton(coinDialog, "Copy send to all", 136, 24)
    copy:SetPoint("BOTTOMLEFT", coinDialog, "BOTTOMLEFT", 16, 10)
    local collect = controlButton(coinDialog, "Collect all", 88, 24)
    collect:SetPoint("LEFT", copy, "RIGHT", 7, 0)
    local clear = controlButton(coinDialog, "Clear", 49, 24)
    clear:SetPoint("LEFT", collect, "RIGHT", 7, 0)
    local transfer = controlButton(coinDialog, "Transfer all", 116, 25, true)
    transfer:SetPoint("BOTTOMRIGHT", coinDialog, "BOTTOMRIGHT", -74, 10)
    local close = controlButton(coinDialog, "Close", 60, 24)
    close:SetPoint("BOTTOMRIGHT", coinDialog, "BOTTOMRIGHT", -8, 10)
    close:SetScript("OnClick", function() coinDialog:Hide() end)

    local function tripletCopper(fields)
        local values = {}
        for j = 1, 3 do
            local value = tonumber(fields[j]:GetText() or "")
            if not value or value < 0 or value ~= math.floor(value) then return nil end
            if j > 1 and value >= 100 then return nil end
            values[j] = value
        end
        local amount = values[1] * 10000 + values[2] * 100 + values[3]
        if amount > 2147483646 then return nil end
        return amount
    end
    local function setTriplet(fields, amount)
        local gold, silver, copper = coinAmounts(amount)
        fields[1]:SetText(tostring(gold))
        fields[2]:SetText(tostring(silver))
        fields[3]:SetText(tostring(copper))
    end
    local function planBatch()
        if not moneyCapable or not batchMoneyCapable then
            return nil, "This server has not confirmed grouped currency transfer support."
        end
        if pendingCoinTransfer then
            return nil, "A previous batch is pending. Verify balances before trying again."
        end
        local selfMoney = confirmedMoney(UnitName("player"))
        if not selfMoney then return nil, "Your current balance is not available." end
        local result = {rows = {}, give = 0, take = 0, before = selfMoney}
        for i = 1, activeCount do
            local row = rowFrames[i]
            local give, take = tripletCopper(row.send), tripletCopper(row.receive)
            local altMoney = confirmedMoney(row.alt)
            if give == nil or take == nil then
                return nil, row.alt .. ": enter valid gold, silver and copper."
            end
            if altMoney == nil then
                return nil, row.alt .. ": wait for the server inventory snapshot."
            end
            if not isInGroup(row.alt) or not owned(row.alt) then
                return nil, row.alt .. " is no longer an ALT in your group."
            end
            if take > altMoney then
                return nil, row.alt .. " cannot send more than their available balance."
            end
            if altMoney + give - take > 2147483646 then
                return nil, row.alt .. " would exceed the server gold cap."
            end
            result.give = result.give + give
            result.take = result.take + take
            if give > 0 or take > 0 then
                table.insert(result.rows, {
                    name = row.alt, give = give, take = take,
                    after = altMoney + give - take
                })
            end
        end
        if table.getn(result.rows) == 0 then
            return nil, "Enter at least one amount to transfer."
        end
        if result.give > selfMoney then
            return nil, "Total outgoing amount exceeds your available balance."
        end
        result.after = selfMoney - result.give + result.take
        if result.after > 2147483646 then
            return nil, "Your final balance would exceed the server gold cap."
        end
        return result
    end
    updateCoinDialog = function()
        if not coinDialog:IsShown() and not loading then
            -- This still updates the button's state before the dialog shows.
        end
        for i = 1, activeCount do
            local row = rowFrames[i]
            row.balance:SetText("Balance: " ..
                (confirmedMoney(row.alt) and moneyText(confirmedMoney(row.alt))
                or "refreshing..."))
        end
        local plan, reason = planBatch()
        if plan then
            summary:SetText("You send " .. moneyText(plan.give) .. "    |    You receive "
                .. moneyText(plan.take) .. "    |    After: " .. moneyText(plan.after))
            hint:SetText("One confirmation transfers all " ..
                table.getn(plan.rows) .. " selected ALT row(s).")
        else
            summary:SetText("Balances are verified before all transfers are committed.")
            hint:SetText(reason or "Enter the required copper amounts.")
        end
        setControlEnabled(transfer, plan ~= nil)
        setControlEnabled(copy, not pendingCoinTransfer)
        setControlEnabled(collect, not pendingCoinTransfer)
        setControlEnabled(clear, not pendingCoinTransfer)
    end
    TB.RefreshMoneyBatchDialog = function()
        if coinDialog:IsShown() then updateCoinDialog() end
    end
    copy:SetScript("OnClick", function()
        if pendingCoinTransfer or activeCount == 0 then return end
        local value = tripletCopper(rowFrames[1].send)
        if not value then status("Enter a valid amount in the first YOU > ALT row.") return end
        loading = true
        for i = 2, activeCount do setTriplet(rowFrames[i].send, value) end
        loading = false
        updateCoinDialog()
    end)
    collect:SetScript("OnClick", function()
        if pendingCoinTransfer then return end
        loading = true
        for i = 1, activeCount do
            setTriplet(rowFrames[i].send, 0)
            local amount = confirmedMoney(rowFrames[i].alt)
            if amount then setTriplet(rowFrames[i].receive, amount) end
        end
        loading = false
        updateCoinDialog()
    end)
    clear:SetScript("OnClick", function()
        if pendingCoinTransfer then return end
        loading = true
        for i = 1, activeCount do
            setTriplet(rowFrames[i].send, 0)
            setTriplet(rowFrames[i].receive, 0)
        end
        loading = false
        updateCoinDialog()
    end)
    transfer:SetScript("OnClick", function()
        if pendingCoinTransfer then return end
        local plan, reason = planBatch()
        if not plan then status(reason or "Cannot process the transfer.") return end
        nextCoinRequest = nextCoinRequest + 1
        local nonce = math.floor(GetTime() * 1000) * 65536 + math.random(1, 65000)
        if nonce <= lastCoinNonce then nonce = lastCoinNonce + 1 end
        lastCoinNonce = nonce
        local words = {"item self moneybatch", string.format("%.0f", nonce),
            tostring(table.getn(plan.rows))}
        local expected = {}
        for _, row in ipairs(plan.rows) do
            table.insert(words, row.name)
            table.insert(words, tostring(row.give))
            table.insert(words, tostring(row.take))
            expected[norm(row.name)] = {
                name = row.name, give = row.give, take = row.take,
                after = row.after, received = false
            }
        end
        local message = table.concat(words, " ")
        if string.len(message) > 230 then
            status("The transfer command exceeds the old WoW chat limit.")
            return
        end
        pendingCoinTransfer = {
            kind = "batch", nonce = nonce, rows = expected, rowCount = table.getn(plan.rows),
            receiptCount = 0, ownerBefore = plan.before, ownerAfter = plan.after,
            started = GetTime()
        }
        coinDialog:Hide()
        refreshCoinBars()
        if not command(message, "Sending one verified currency batch for " ..
            table.getn(plan.rows) .. " ALT(s)...") then
            pendingCoinTransfer = nil
            refreshCoinBars()
        end
    end)
    openCoinDialog = function()
        if pendingCoinTransfer then
            status("Your previous transfer has not been confirmed. Do not send twice.")
            return
        end
        if not batchMoneyCapable then
            status("The server has not confirmed multi-ALT money transfers.")
            return
        end
        local names = {}
        for _, member in ipairs(groupMembers()) do
            if owned(member.name) then table.insert(names, member.name) end
        end
        if table.getn(names) == 0 then
            status("Join a party with at least one ALT on your own account.")
            return
        end
        activeCount = math.min(4, table.getn(names))
        loading = true
        for i = 1, 4 do
            local row = rowFrames[i]
            if i <= activeCount then
                row.alt = names[i]
                row.title:SetText(names[i])
                setTriplet(row.send, 0)
                setTriplet(row.receive, 0)
                row.frame:Show()
                TB.RequestInventory(names[i])
            else
                row.alt = nil
                row.frame:Hide()
            end
        end
        loading = false
        coinDialog:SetHeight(173 + activeCount * 64)
        coinDialog:Show()
        updateCoinDialog()
    end
end
setupCoinDialogControls()

for i = 1, 4 do
    local y = -57 - (i - 1) * 30
    local row = CreateFrame("Frame", nil, tradeDialog)
    row:SetWidth(540)
    row:SetHeight(31)
    row:SetPoint("TOPLEFT", tradeDialog, "TOPLEFT", 12, y)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(100)
    row.name:SetJustifyH("LEFT")
    tintText(row.name, COLORS.gold)
    row.quote = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.quote:SetPoint("LEFT", row, "LEFT", 108, 0)
    row.quote:SetWidth(143)
    row.quote:SetJustifyH("LEFT")
    tintText(row.quote, COLORS.muted)
    row.inputs = {}
    for j = 1, 3 do
        local input = CreateFrame("EditBox", nil, row)
        input:SetWidth(54)
        input:SetHeight(22)
        input:SetPoint("LEFT", row, "LEFT", 268 + (j - 1) * 78, 0)
        panelOutline(input, COLORS.inset, COLORS.outline)
        if input.SetFontObject then input:SetFontObject(GameFontHighlightSmall) end
        if input.SetTextColor then
            input:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
        end
        if input.SetJustifyH then input:SetJustifyH("CENTER") end
        input:SetNumeric(true)
        input:SetMaxLetters(8)
        input:SetAutoFocus(false)
        input:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        input:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        input:SetScript("OnTextChanged", function()
            if refreshDialog then refreshDialog() end
        end)
        local denomination = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        denomination:SetPoint("LEFT", input, "RIGHT", 3, 0)
        denomination:SetText(j == 1 and "g" or (j == 2 and "s" or "c"))
        tintText(denomination, COLORS.muted)
        row.inputs[j] = input
    end
    row:Hide()
    dialogRows[i] = row
end

local function sellerQuotes()
    local groups, order = {}, {}
    for _, entry in ipairs(pendingTrade) do
        local key = norm(entry.name)
        if not groups[key] then
            groups[key] = { name = entry.name, copper = 0, count = 0, pending = false }
            table.insert(order, groups[key])
        end
        local group = groups[key]
        group.count = group.count + 1
        if entry.price then
            group.copper = group.copper + entry.price
        else
            group.pending = true
        end
    end
    return order
end

local function enteredAmount(row)
    if not row or not row.group then return nil end
    local numbers = {}
    for i = 1, 3 do
        local value = row.inputs[i]:GetText()
        if not string.find(value or "", "^%d+$") then return nil end
        numbers[i] = tonumber(value)
        if not numbers[i] then return nil end
    end
    if numbers[2] > 99 or numbers[3] > 99 then return nil end
    return numbers[1] * 10000 + numbers[2] * 100 + numbers[3]
end

refreshDialog = function()
    if not tradeDialog:IsShown() then return end
    local sellers = sellerQuotes()
    tradeDialog:SetHeight(math.max(165, 110 + 31 * math.min(4, table.getn(sellers))))
    for i, row in ipairs(dialogRows) do
        local seller = sellers[i]
        row.group = seller
        if seller then
            row.name:SetText(seller.name)
            row.quote:SetText(seller.pending and "Price pending" or moneyText(seller.copper))
            row:Show()
        else
            row:Hide()
        end
    end
    local allQuoted = table.getn(pendingTrade) > 0 and table.getn(sellers) > 0
    local approvedTotal = 0
    for i, seller in ipairs(sellers) do
        if seller.pending or seller.copper <= 0
            or enteredAmount(dialogRows[i]) ~= seller.copper then allQuoted = false end
        approvedTotal = approvedTotal + seller.copper
    end
    for _, entry in ipairs(pendingTrade) do
        if type(entry.price) ~= "number" or entry.price <= 0 or entry.pending
            or botType(entry.name) ~= "ai" or not isInGroup(entry.name) then
            allQuoted = false
        end
    end
    if not quoteCapable then
        dialogHint:SetText("Price requests require the server's verified quote protocol.")
    elseif checkoutQueue or pendingTransfer then
        dialogHint:SetText("Checkout is settling one exact server trade at a time. Do not pay twice.")
    elseif not allQuoted then
        dialogHint:SetText("Click Fill, then match EACH seller's exact total quote.")
    elseif table.getn(pendingTrade) > 1 then
        dialogHint:SetText("Confirm the batch. Each stack is paid separately, after the previous one is verified.")
    else
        dialogHint:SetText("Confirm this item at the server quote. Its exact GUID and price are rechecked.")
    end
    dialogBuy.caption:SetText(table.getn(pendingTrade) > 1 and "Pay All" or "Confirm Purchase")
    setControlEnabled(dialogBuy, tradeCapable and allQuoted
        and approvedTotal <= (GetMoney and GetMoney() or 0)
        and not pendingTransfer and not checkoutQueue)
    setControlEnabled(dialogFill, quoteCapable and table.getn(pendingTrade) > 0
        and not pendingTransfer and not checkoutQueue)
end

fillDialog = function()
    local sellers = sellerQuotes()
    for i, row in ipairs(dialogRows) do
        local seller = sellers[i]
        if seller and not seller.pending then
            local amount = seller.copper
            row.inputs[1]:SetText(tostring(math.floor(amount / 10000)))
            row.inputs[2]:SetText(tostring(math.floor(math.mod(amount, 10000) / 100)))
            row.inputs[3]:SetText(tostring(math.mod(amount, 100)))
        end
    end
    refreshDialog()
end

fillTradeAmount = function()
    if checkoutQueue then return end
    if pendingTransfer and pendingTransfer.kind == "buy" then
        -- A TRADE_CAPS refresh must not mutate a previously accepted quote.
        return
    end
    if not quoteCapable then
        status("Fill is disabled until the server quote protocol is validated.")
        return
    end
    local outstanding = false
    for _, entry in ipairs(pendingTrade) do
        if not isInGroup(entry.name) or botType(entry.name) ~= "ai" then
            entry.price = nil
            entry.pending = nil
        elseif not entry.price then
            outstanding = true
            if not entry.pending then
                entry.pending = true
                entry.requestedAt = GetTime()
                entry.error = nil
                TB.SendBotCommand("item " .. entry.name .. " quote " .. entry.bag
                    .. " " .. entry.slot .. " " .. entry.guid .. " " .. entry.count)
                -- False means the transport queued the request. Do not resend it.
            end
        end
    end
    fillWhenQuoted = outstanding
    if not outstanding then
        fillDialog()
        status("Currency fields filled with server-quoted prices.")
    else
        status("Waiting for actual bot prices; currency fields will fill after the quotes arrive.")
    end
    refreshTrade()
end

clearTrade:SetScript("OnClick", function()
    if checkoutQueue or (pendingTransfer and pendingTransfer.kind == "buy") then return end
    pendingTrade = {}
    fillWhenQuoted = false
    status("Staged trades cleared. Nothing was transferred.")
    refreshTrade()
    if render then render(false) end
end)

fillTrade:SetScript("OnClick", fillTradeAmount)
dialogFill:SetScript("OnClick", fillTradeAmount)

completeTrade:SetScript("OnClick", function()
    if table.getn(pendingTrade) == 0 then return end
    tradeDialog:Show()
    refreshDialog()
end)
dialogBuy:SetScript("OnClick", function()
    if checkoutQueue or pendingTransfer or not tradeCapable
        or table.getn(pendingTrade) == 0 then return end
    local sellers = sellerQuotes()
    local approved = {}
    local sellerTotals = {}
    local grandTotal = 0
    for i, seller in ipairs(sellers) do
        if seller.pending or seller.copper <= 0
            or enteredAmount(dialogRows[i]) ~= seller.copper then
            status("A seller total differs from the exact quoted price. No money moved.")
            return
        end
        sellerTotals[norm(seller.name)] = seller.copper
        grandTotal = grandTotal + seller.copper
    end
    if grandTotal <= 0 or grandTotal > (GetMoney and GetMoney() or 0) then
        status("Insufficient funds or invalid quoted total. No purchase submitted.")
        return
    end
    local verifiedTotals = {}
    for _, entry in ipairs(pendingTrade) do
        if not isInGroup(entry.name) or botType(entry.name) ~= "ai"
            or type(entry.price) ~= "number" or entry.price <= 0
            or entry.price ~= math.floor(entry.price) or entry.pending
            or not entry.guid or entry.guid <= 0 or entry.count <= 0 then
            status("A staged item has no valid seller, GUID, stack or quote. No purchase submitted.")
            return
        end
        local key = norm(entry.name)
        verifiedTotals[key] = (verifiedTotals[key] or 0) + entry.price
        table.insert(approved, { entry = entry, guid = entry.guid, id = entry.id,
            count = entry.count, price = entry.price })
    end
    for name, total in pairs(sellerTotals) do
        if verifiedTotals[name] ~= total then
            status("Seller totals changed during confirmation. No purchase submitted.")
            return
        end
    end
    if table.getn(approved) == 1 then
        -- Preserve the proven single-item native trade path exactly; a queue
        -- is only needed when there is a subsequent item to settle.
        if buyOne(approved[1].entry, approved[1].price) then
            tradeDialog:Hide()
        end
        return
    end
    checkoutQueue = { entries = approved, total = table.getn(approved),
        nextIndex = 1 }
    tradeDialog:Hide()
    startQueuedCheckout()
end)

refreshTrade = function()
    local groups, order = {}, {}
    local awaiting = 0
    for i, entry in ipairs(pendingTrade) do
        if not groups[entry.name] then
            groups[entry.name] = { count = 0, copper = 0, pending = false }
            table.insert(order, entry.name)
        end
        local g = groups[entry.name]
        g.count = g.count + 1
        if entry.price then g.copper = g.copper + entry.price
        else
            g.pending = true
            awaiting = awaiting + 1
        end
    end
    local amount = table.getn(pendingTrade)
    if amount > 0 then
        tradeItems:SetText("From " .. table.concat(order, ", ") .. " to you"
            .. " / " .. amount .. " item" .. (amount == 1 and "" or "s")
            .. (awaiting > 0 and (" / " .. awaiting .. " awaiting prices") or " / prices ready"))
    else
        tradeItems:SetText("")
    end
    local amounts = {}
    for _, name in ipairs(order) do
        local group = groups[name]
        table.insert(amounts, name .. ": " .. (group.pending and "Price pending" or moneyText(group.copper)))
    end
    tradeAmounts:SetText(table.concat(amounts, "\n"))
    setControlEnabled(clearTrade, table.getn(pendingTrade) > 0
        and not pendingTransfer and not checkoutQueue)
    setControlEnabled(fillTrade, table.getn(pendingTrade) > 0
        and quoteCapable and not pendingTransfer and not checkoutQueue)
    setControlEnabled(completeTrade, table.getn(pendingTrade) > 0
        and not pendingTransfer and not checkoutQueue)
    if fillWhenQuoted then
        local allQuoted = true
        for _, entry in ipairs(pendingTrade) do
            if not entry.price then allQuoted = false end
        end
        if allQuoted then
            fillWhenQuoted = false
            fillDialog()
        end
    end
    if refreshDialog then refreshDialog() end
end

local function clearSlot(button, placeholder)
    button.item = nil
    if button.questMarker then button.questMarker:Hide() end
    if button.icon.SetVertexColor then button.icon:SetVertexColor(1, 1, 1) end
    button.previewKind = nil
    if button.preview then button.preview:Hide() end
    if button.kind == "gear" then
        -- Use only MPQ-verified native 1.12 PaperDoll images, never the
        -- client's unvalidated slotInfo fallback or a question-mark icon.
        setPathTexture(button.icon, emptyGearTexture(button.gearSlot))
        colorTexture(button.border, COLORS.emptyEdge)
        if button.emptyLabel then button.emptyLabel:Hide() end
        button._tbEmptyGear = true
    else
        setPathTexture(button.icon, EMPTY_SLOT)
        colorTexture(button.border, COLORS.emptyEdge)
    end
    setAlpha(button.icon, button.kind == "gear" and 0.77 or 1)
    if button.count and button.count:GetText() ~= "" then button.count:SetText("") end
end

local function populateSelf()
    local items, actual = {}, {}
    local snapshot = selfSnapshotValid and TB.GetInventory(UnitName("player")) or nil
    for _, item in ipairs(snapshot and snapshot.items or {}) do
        local key = item.bag * 256 + item.slot
        actual[key] = item
    end
    for bag = 0, 4 do
        for position = 1, GetContainerNumSlots(bag) do
            local texture, count = GetContainerItemInfo(bag, position)
            local remoteBag, remoteSlot = serverBag(bag), serverSlot(bag, position)
            local item = actual[remoteBag * 256 + remoteSlot]
            -- Native items have priority over potentially stale INV_SELF data.
            -- Probe links only for occupied slots, never all empty containers.
            local nativeId = texture and GetContainerItemLink and
                itemIdFromLink(GetContainerItemLink(bag, position))
            local id = texture and (nativeId or (item and item.id)) or nil
            local matchingServerItem = item and item.id == id
                and item.count == (count or 1)
            table.insert(items, {
                id = id, texture = validTexturePath(texture)
                    or resolvedItemTexture(id, matchingServerItem and item.texture),
                count = count or 0,
                playerBag = bag, playerSlot = position, bag = remoteBag, slot = remoteSlot,
                guid = matchingServerItem and item.guid or nil,
                -- Equippability belongs to the item prototype, NOT to a bag
                -- position. It remains safe after a native move even though
                -- the prior position->GUID association was invalidated.
                equippable = selfEquippableItemIds[id] == true or
                    (matchingServerItem and item.equippable == true) or false,
                wearable = matchingServerItem and item.wearable or nil,
                quality = matchingServerItem and item.quality or nil,
                quest = matchingServerItem and item.quest or nil,
            })
        end
    end
    return items
end

local function populateBot(inventory)
    local result, byPosition = {}, {}
    if not inventory then return result end
    local equipped = inventory.equipped or {}
    for _, item in ipairs(inventory.items or {}) do
        if item.bag and item.slot then
            byPosition[item.bag * 256 + item.slot] = item
        end
    end
    local function append(bag, position)
        local item = byPosition[bag * 256 + position]
        if item then
            table.insert(result, item)
        else
            table.insert(result, { bag = bag, slot = position, count = 0, empty = true })
        end
    end
    -- Backpack positions are world-server inventory slots, not container 1..16.
    for position = 23, 38 do append(255, position) end
    for bag = 19, 22 do
        local wornBag = equipped[bag]
        local slots = wornBag and wornBag.slots or 0
        for _, item in ipairs(inventory.items or {}) do
            if item.bag == bag then slots = math.max(slots, item.slot + 1) end
        end
        -- Server bag content uses 0..N-1, unlike the native 1.12 player
        -- container UI (1..N). Preserve the true slot; never compact it.
        for position = 0, slots - 1 do append(bag, position) end
    end
    -- Do not hide unexpected protocol slots. They remain visible after the known bags.
    for _, item in ipairs(inventory.items or {}) do
        local listed = (item.bag == 255 and item.slot >= 23 and item.slot <= 38)
        if item.bag >= 19 and item.bag <= 22 then listed = true end
        if not listed then table.insert(result, item) end
    end
    local preview = inventory.name and optimisticPlacements[norm(inventory.name)]
    if preview then
        local sourceIndex, targetIndex
        for index, item in ipairs(result) do
            if item.bag == preview.sourceBag and item.slot == preview.sourceSlot then
                sourceIndex = index
            elseif item.bag == preview.destinationBag and item.slot == preview.destinationSlot then
                targetIndex = index
            end
        end
        if sourceIndex and targetIndex
            and result[sourceIndex].guid == preview.sourceGuid
            and (result[targetIndex].guid or 0) == preview.targetGuid then
            local source, target = result[sourceIndex], result[targetIndex]
            local sourceVisual, targetVisual = {}, {}
            for k, v in pairs(source) do sourceVisual[k] = v end
            for k, v in pairs(target) do targetVisual[k] = v end
            sourceVisual.bag, sourceVisual.slot = target.bag, target.slot
            targetVisual.bag, targetVisual.slot = source.bag, source.slot
            result[sourceIndex], result[targetIndex] = targetVisual, sourceVisual
        end
    end
    return result
end

function TB.PartyInventoryPreview(card, item)
    local move = TB._partyLocalBagMove
    if move and GetTime() < move.expires and card.characterType == "self" then
        if item.bag == move.source.bag and item.slot == move.source.slot and
            item.id == move.source.id then return move.target end
        if item.bag == move.target.bag and item.slot == move.target.slot and
            item.id == move.target.id then return move.source end
    end
    move = (pendingTransfer and pendingTransfer.visual) or
        (deferredGuidTransfer and deferredGuidTransfer.visual)
    if not move then return nil end
    if card.character == move.to and item.bag == move.target.bag and
        item.slot == move.target.slot and not item.id then return move.source end
    if card.character == move.from and item.bag == move.source.bag and
        item.slot == move.source.slot and item.id == move.source.id then return move.target end
end

local function paint(card, member, request)
    local name = member and member.name
    if card.character ~= name then
        card.offset = 0
        card.modelUnit = nil
        card.modelAppearance = nil
    end
    card.character = name
    card.unit = member and member.unit
    local own = member and member.unit == "player"
    local characterType = own and "self" or botType(name)
    card.characterType = characterType
    card.canInspect = (own or authorizedBot(name)) and true or false
    local displayName = name or (card == columns[1] and "You" or "No party member")
    if card.name:GetText() ~= displayName then card.name:SetText(displayName) end
    local inventory = name and card.canInspect and TB.GetInventory(name) or nil
    if member and request and not own then TB.RequestInventory(name) end
    if own and request and selfServerProtocolAvailable ~= false then
        TB.SendBotCommand("inv self")
    end
    for _, b in ipairs(card.actions or {}) do
        if name and card.canInspect and not own then b:Show() else b:Hide() end
    end
    if name and card.canInspect and (characterType == "self"
        or characterType == "own" or characterType == "ai") then
        card.sortButton:Show()
    else
        card.sortButton:Hide()
    end
    -- Every SetUnit recreates a 3D paper-doll model. On some HD clients this
    -- costs more than painting all item icons and visibly freezes each move.
    -- Rebuild only on unit identity or actual equipped-item changes.
    local modelUnit = member and member.unit
    -- Our own paper doll is native to this client; the last server INV_SELF
    -- response can still reflect the PREVIOUS equipment state after rapid
    -- equip/unequip. Never re-dress self using that stale remote snapshot.
    local modelItems = not own and inventory and inventory.equipped or nil
    local modelSignature = ""
    if modelUnit and (own or not modelItems) then
        local names = {}
        for id = 0, 18 do
            local slot = id + 1
            local link = GetInventoryItemLink and GetInventoryItemLink(modelUnit, slot)
            local texture = GetInventoryItemTexture(modelUnit, slot)
            names[id + 1] = link or texture or "0"
            local itemId = own and itemIdFromLink(link)
            if itemId then
                TB._partyWornItemIds = TB._partyWornItemIds or {}
                TB._partyWornItemIds[itemId] = true
            end
        end
        modelSignature = table.concat(names, ",")
    elseif modelItems and card.canInspect then
        local names = {}
        for id = 0, 18 do
            local item = modelItems[id]
            names[id + 1] = tostring(item and item.id or 0)
        end
        modelSignature = table.concat(names, ",")
    end
    if modelUnit and card.model.SetUnit then
        if card.modelUnit ~= modelUnit or card.modelAppearance ~= modelSignature then
            card.modelCacheAttempts = 0
            card.model:SetUnit(modelUnit)
            local uncached, ready = 0, 0
            if modelItems and card.canInspect and card.model.TryOn then
                local links = {}
                for id = 0, 18 do
                    local item = modelItems[id]
                    if item and item.id then
                        -- A texture icon from the server does NOT mean the
                        -- local WoW client knows the item's wearable display.
                        -- GetItemInfo primes its native cache; pass the full
                        -- cached item hyperlink to vanilla TryOn when ready.
                        local _, link
                        if GetItemInfo then _, link = GetItemInfo(item.id) end
                        if type(link) == "string" and link ~= "" then
                            ready = ready + 1
                            links[id] = link
                        else
                            uncached = uncached + 1
                            links[id] = "item:" .. item.id .. ":0:0:0"
                        end
                    end
                end
                -- NEVER Undress after SetUnit. In the real 1.12 client, even
                -- cached item links are not guaranteed to restore every armor
                -- model via TryOn; that made all party models appear naked.
                -- Let SetUnit supply complete native worn gear and overlay
                -- server items only where the model can resolve them.
                for id = 0, 18 do
                    if links[id] then card.model:TryOn(links[id]) end
                end
            end
            card.modelUncached = uncached
            card.modelReady = ready
            card.modelRetryAt = uncached > 0 and (GetTime() + 0.8) or nil
            if card.model.SetRotation then
                card.model:SetRotation(card.modelRotation or 0)
            end
            if card.model.SetModelScale then
                card.model:SetModelScale(card.modelZoom or 1)
            end
            card.modelUnit = modelUnit
            card.modelAppearance = modelSignature
        end
        if not card.model:IsShown() then card.model:Show() end
    else
        if card.model:IsShown() then card.model:Hide() end
        card.modelUnit = nil
        card.modelAppearance = nil
    end
    for id, button in pairs(card.gear) do
        local item
        local texture
        if card.canInspect then
            local current = inventory and inventory.equipped and inventory.equipped[id] or nil
            if own then
                texture = validTexturePath(GetInventoryItemTexture("player", id + 1))
                local link = GetInventoryItemLink and GetInventoryItemLink("player", id + 1)
                local itemId = texture and (itemIdFromLink(link) or (current and current.id))
                if itemId then
                    item = {
                        id = itemId, texture = texture or resolvedItemTexture(itemId, current and current.texture),
                        bag = 255, slot = id,
                        count = 1, ownerGear = true,
                    }
                end
            elseif current and current.id then
                texture = resolvedItemTexture(current.id, current.texture)
                item = {
                    id = current.id, texture = texture, bag = 255, slot = id,
                    guid = current.guid, count = 1, equipped = true,
                }
            end
        end
        if item then
            button.item = item
            setPathTexture(button.icon, texture or item.texture)
            setAlpha(button.icon, 1)
            paintItemAppearance(button, item)
            if button.emptyLabel then button.emptyLabel:Hide() end
            button._tbEmptyGear = nil
        else
            if button.item or not button._tbEmptyGear then clearSlot(button) end
        end
    end
    if card.ammo then
        local tex = card.canInspect and validTexturePath(
            GetInventoryItemTexture and GetInventoryItemTexture(card.unit or "player", 0))
        if tex then
            setPathTexture(card.ammo.icon, tex)
            colorTexture(card.ammo.border, COLORS.slotOccupied)
        else
            setPathTexture(card.ammo.icon, emptyGearTexture(17))
            colorTexture(card.ammo.border, COLORS.emptyEdge)
        end
    end
    local items
    if card.canInspect then
        if own then items = populateSelf() else items = populateBot(inventory) end
    else
        items = {}
    end
    local total = table.getn(items)
    -- The actual equipped bags determine capacity. Never invent unused slots
    -- based on cached totals or leave placeholder cells beyond real capacity.
    card.slotCount = card.canInspect and total or 0
    card.maxOffset = math.max(0, math.ceil((total - visibleBagCells) / BAG_COLUMNS) * BAG_COLUMNS)
    card.offset = math.min(card.offset, card.maxOffset)
    if card.scrollTrack then
        if card.canInspect and card.maxOffset > 0 then
            local rows = math.ceil(math.min(total, visibleBagCells) / BAG_COLUMNS)
            local trackHeight = rows * BAG_CELL
            local thumbHeight = math.max(28, math.floor(trackHeight * visibleBagCells / total))
            local travel = math.max(0, trackHeight - thumbHeight - 2)
            local topOffset = math.floor(travel * card.offset / card.maxOffset + 0.5)
            card.scrollTrack:SetHeight(trackHeight)
            card.scrollTrack.thumbHeight = thumbHeight
            card.scrollTrack.thumb:SetHeight(thumbHeight)
            card.scrollTrack.thumb:ClearAllPoints()
            card.scrollTrack.thumb:SetPoint("TOPLEFT", card.scrollTrack,
                "TOPLEFT", 1, -1 - topOffset)
            card.scrollTrack:Show()
        else
            card.scrollTrack:Hide()
        end
    end
    if card.canInspect then ensureBagCells(card, math.min(total, visibleBagCells)) end
    for index, cell in ipairs(card.bags) do
        local item = items[card.offset + index]
        if card.canInspect and index <= visibleBagCells and item then
            if not cell:IsShown() then cell:Show() end
            cell.item = item
            local preview = TB.PartyInventoryPreview(card, item)
            local visual = preview or item
            if visual.id then
                setPathTexture(cell.icon, resolvedItemTexture(visual.id, visual.texture))
            else
                -- Full-size genuine WoW backpack art instead of the dark
                -- featureless blocks introduced in the previous update.
                setPathTexture(cell.icon, EMPTY_SLOT)
            end
            setAlpha(cell.icon, preview and 0.65 or 1)
            local count = visual.count and visual.count > 1 and tostring(visual.count) or ""
            if cell.count:GetText() ~= count then cell.count:SetText(count) end
            if item.id then
                paintItemAppearance(cell, item)
            else
                colorTexture(cell.border, COLORS.emptyEdge)
                if cell.questMarker then cell.questMarker:Hide() end
                if cell.icon.SetVertexColor then cell.icon:SetVertexColor(1, 1, 1) end
            end
            cell.previewKind = nil
            if cell.preview then cell.preview:Hide() end
            previewForSlot(card, cell)
            local chosen = markedForSale[norm(card.character)] or {}
            showSaleFrame(cell, card.characterType == "own" and item.guid
                and chosen[item.guid] ~= nil)
        else
            if cell:IsShown() then cell:Hide() end
            if cell.item or cell.previewKind then clearSlot(cell) end
            if cell.saleOverlay then cell.saleOverlay:Hide() end
            cell.saleSelected = nil
        end
    end
    updateSellButton(card)
    local selling, receiving = 0, {}
    for _, offer in ipairs(pendingTrade) do
        if norm(offer.name) == norm(name) then selling = selling + 1 end
        if norm(offer.targetOwner) == norm(name) then
            receiving[norm(offer.name)] = offer.name
        end
    end
    if selling > 0 then
        colorTexture(card.sellerDot, sellerColor(name))
        card.sellerDot:Show()
        card.tradeInfo:SetText("SELLING TO YOU  |  " .. selling .. " STAGED")
        card.tradeInfo:Show()
    elseif next(receiving) then
        local from = {}
        for _, seller in pairs(receiving) do table.insert(from, seller) end
        card.tradeInfo:SetText("FROM: " .. table.concat(from, ", "))
        card.tradeInfo:Show()
    else
        card.tradeInfo:Hide()
    end
    if selling == 0 then card.sellerDot:Hide() end
    if card.canInspect and card.maxOffset > 0 then
        card.status:SetText((card.offset + 1) .. "-" .. math.min(card.offset + visibleBagCells, total)
            .. " / " .. total .. "  Scroll")
    elseif card.canInspect and inventory then
        card.status:SetText(total .. " inventory slots")
    elseif card.canInspect and own then
        card.status:SetText(total .. " inventory slots")
    else
        card.status:SetText("")
    end
    if card.canInspect then
        card.privacy:Hide()
    else
        if not name then
            card.privacy.text:SetText("No party member")
        elseif characterType == "human" then
            card.privacy.text:SetText(name .. "\n\nPrivate player inventory")
        else
            card.privacy.text:SetText(name .. "\n\nChecking server authorization...")
        end
        card.privacy:Show()
    end
end

-- Fit real bag slots into the available display, scrolling when a readable
-- cell cannot fit. The compact trade bar is hidden when nothing is staged.
local function layoutCards()
    local largest = 16
    local visible = 0
    for _, card in ipairs(columns) do
        if card:IsShown() and (card.slotCount or 0) > largest then
            largest = card.slotCount
        end
        if card:IsShown() then visible = visible + 1 end
    end
    visible = math.max(1, visible)
    local compactFullscreen = fullscreen and visible >= 4
    local gridTop = compactFullscreen and COMPACT_BAG_GRID_TOP or BAG_GRID_TOP
    local hasTrade = table.getn(pendingTrade) > 0
    local footerMargin = 12
    local cardFooter = compactFullscreen and COMPACT_BAG_FOOTER
        or BAG_FOOTER_RESERVED
    local tradeMargin = hasTrade and 43 or 0
    local layoutWidth = CARD_WIDTH
    local panelWidth, frameHeight, cardHeight, rows, fullScale
    if fullscreen then
        -- WoW 1.12 adjusts UIParent's root scale down to 0.90 at e.g. 1080p
        -- while keeping its reported virtual dimensions at 1365x767.
        -- Multiplying a CENTER-anchored frame's dimensions by its *own*
        -- scale alone therefore leaves exactly 10% black borders. Convert
        -- UIParent's virtual dimensions back to the unscaled fullscreen
        -- canvas before computing the window and the inventory cell sizes.
        local rootScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
            or (UIParent.GetScale and UIParent:GetScale()) or 1
        if rootScale < 0.5 or rootScale > 2 then rootScale = 1 end
        local screenWidth = (UIParent.GetWidth and UIParent:GetWidth() or 1024) / rootScale
        local screenHeight = (UIParent.GetHeight and UIParent:GetHeight() or 768) / rootScale
        -- The old implementation scaled a fixed-size panel, leaving huge
        -- black margins. Fullscreen now gets an edge-to-edge logical canvas;
        -- each live party card occupies an equal share of its actual width.
        local baselineWidth = math.max(274, 24 + visible * CARD_STEP - 8)
        -- Fit the real grid *before* choosing scale. Scaling a tiny 18px
        -- logical cell to a 24px onscreen icon technically filled the screen
        -- but made inventory less legible. Budget three 40px grid rows before
        -- selecting the uniform fullscreen scale; use a scrollbar for the rest.
        local minimumHeight = 45 - gridTop + 3 * 40 + cardFooter
            + footerMargin + tradeMargin
        fullScale = math.max(0.30, math.min(FULLSCREEN_MAX_SCALE,
            (screenWidth - 4) / baselineWidth,
            (screenHeight - 4) / minimumHeight))
        panelWidth = (screenWidth - 4) / fullScale
        frameHeight = (screenHeight - 4) / fullScale
        layoutWidth = (panelWidth - 24 - (visible - 1) * 8) / visible
        cardHeight = frameHeight - 45 - footerMargin - tradeMargin
        local widthCell = math.floor((layoutWidth - 20) / BAG_COLUMNS)
        local availableGridHeight = math.max(20, cardHeight + gridTop - cardFooter)
        local desiredRows = math.max(1, math.min(math.floor(MAX_BAG_CELLS / BAG_COLUMNS),
            math.ceil(largest / BAG_COLUMNS)))
        -- At larger five-card fullscreen sizes, never shrink items below
        -- 34 physical pixels just to display more rows simultaneously.
        -- Preserve the compact layout for smaller screens and other counts;
        -- rows that cannot fit remain reachable through the bag scrollbar.
        local minCell = visible == 5 and fullScale >= 1.1
            and math.max(21, math.ceil(34 / fullScale))
            or (visible >= 4 and 21 or 26)
        BAG_CELL = math.max(16, math.min(widthCell,
            math.max(minCell, math.floor(availableGridHeight / desiredRows)), 96))
        rows = math.max(1, math.min(desiredRows,
            math.floor(availableGridHeight / BAG_CELL)))
    else
        layoutWidth = CARD_WIDTH
        BAG_CELL = math.max(22, math.min(96,
            math.floor((layoutWidth - 16) / BAG_COLUMNS)))
        rows = math.max(1, math.min(8, math.floor(MAX_BAG_CELLS / BAG_COLUMNS),
            math.ceil(largest / BAG_COLUMNS)))
        cardHeight = -gridTop + rows * BAG_CELL + cardFooter
        frameHeight = 45 + cardHeight + footerMargin + tradeMargin
        panelWidth = math.max(274, 24 + visible * CARD_STEP - 8)
    end
    visibleBagCells = math.min(MAX_BAG_CELLS, rows * BAG_COLUMNS)
    FRAME_WIDTH = panelWidth
    frame:SetWidth(panelWidth)
    frame:SetHeight(frameHeight)
    for index, card in ipairs(columns) do
        card:SetWidth(layoutWidth)
        card:SetHeight(cardHeight)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame, "TOPLEFT",
            12 + (index - 1) * (layoutWidth + 8), -45)
        card.gridX = math.max(4, math.floor((layoutWidth - BAG_COLUMNS * BAG_CELL) / 2))
        -- Enlarging the DressUpModel WIDTH alone stretches/zooms WoW's native
        -- camera until heads are cropped off. Preserve its proven aspect
        -- ratio; the parent panel's uniform scale enlarges the entire paper
        -- doll without slicing away the helmet or boots.
        card.model:SetWidth(174)
        card.model:ClearAllPoints()
        card.model:SetPoint("TOP", card, "TOP", 0, -25)
        if card.model.SetModelScale then
            -- DressUpModel uses its own 3D camera: stretching its PARENT
            -- fullscreen scale can crop heads even when slot geometry fits.
            -- Scale the displayed actor down inside the bigger viewport,
            -- without changing the native model frame's height/width ratio.
            card.model:SetModelScale(card.modelZoom *
                (compactFullscreen and 0.70 or (fullscreen and 0.76 or 1)))
        end
        card.status:SetWidth(layoutWidth - 10)
        card.tradeInfo:SetWidth(layoutWidth - 14)
        card.tradeInfo:ClearAllPoints()
        card.tradeInfo:SetPoint("BOTTOM", card, "BOTTOM", 0,
            compactFullscreen and 76 or 95)
        card.privacy.text:SetWidth(layoutWidth - 20)
        for i, id in ipairs(EQUIPMENT) do
            local button = card.gear[id]
            if button and id ~= 15 and id ~= 16 and id ~= 17 then
                local side = math.floor((i - 1) / 10)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", card, "TOPLEFT",
                    4 + side * (layoutWidth - 32),
                    -25 - (i - 1 - side * 10) * 24)
            end
        end
        local equipX = math.floor((layoutWidth - 4 * 31) / 2)
        for i, slot in ipairs({15, 16, 17}) do
            local button = card.gear[slot]
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", card, "TOPLEFT", equipX + (i - 1) * 31,
                compactFullscreen and -240 or -265)
        end
        card.ammo:ClearAllPoints()
        card.ammo:SetPoint("TOPLEFT", card, "TOPLEFT", equipX + 3 * 31,
            compactFullscreen and -240 or -265)
        card.scrollTrack:ClearAllPoints()
        card.scrollTrack:SetPoint("TOPLEFT", card, "TOPLEFT", layoutWidth - 10, gridTop)
        for i, button in ipairs(card.bags) do
            local row = math.floor((i - 1) / BAG_COLUMNS)
            button:ClearAllPoints()
            button:SetWidth(BAG_CELL)
            button:SetHeight(BAG_CELL)
            button:SetPoint("TOPLEFT", card, "TOPLEFT",
                card.gridX + (i - 1 - row * BAG_COLUMNS) * BAG_CELL,
                gridTop - row * BAG_CELL)
        end
        -- Bag equipment belongs to the reserved footer. Anchoring it to the
        -- final inventory row made it collide with Sell Marked at 4-8 rows
        -- and different fullscreen resolutions.
        for i, button in ipairs(card.bagGear) do
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT",
                equipX + (i - 1) * 31, compactFullscreen and 137 or 157)
        end
    end
    tradeFrame:ClearAllPoints()
    tradeFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(45 + cardHeight + 7))
    if hasTrade then tradeFrame:Show() else tradeFrame:Hide() end
    tradeFrame:SetWidth(FRAME_WIDTH - 24)
    transferStatus:SetWidth(math.max(60, FRAME_WIDTH - 355))
    moveStrip:SetWidth(math.max(140, FRAME_WIDTH - 125))
    if fullscreen then
        frame:SetScale(fullScale)
    else
        -- The normal window remains movable and respects the manual scale.
        frame:SetScale(fitFrameScale(requestedScale))
    end
end
updateViewport = layoutCards

render = function(request)
    local members = groupMembers()
    noPartyText:Hide()
    -- A five-character party fits on one screen. No empty placeholders,
    -- artificial pages or previous/next toolbar below the inventory.
    page = 1
    columns[1]:Show()
    for index = 2, 5 do
        local member = members[index - 1]
        if member then
            columns[index]:Show()
        else
            columns[index]:Hide()
            columns[index].character = nil
            columns[index].characterType = nil
            columns[index].canInspect = false
        end
    end
    -- Work out the fullscreen canvas and column geometry before creating
    -- any new slot buttons, including after an option/party-size change.
    layoutCards()
    local initialCell, initialVisible = BAG_CELL, visibleBagCells
    paint(columns[1], {name = UnitName("player"), unit = "player"}, request)
    for index = 2, 5 do
        if members[index - 1] then paint(columns[index], members[index - 1], request) end
    end
    refreshTrade()
    layoutCards()
    if BAG_CELL ~= initialCell or visibleBagCells ~= initialVisible then
        paint(columns[1], {name = UnitName("player"), unit = "player"}, false)
        for index = 2, 5 do
            if members[index - 1] then paint(columns[index], members[index - 1], false) end
        end
    end
    refreshCoinBars()
end

local function repaintMember(name)
    if not frame:IsShown() then return end
    local wanted = norm(name)
    for _, card in ipairs(columns) do
        if card.character and norm(card.character) == wanted then
            local was = card.slotCount
            paint(card, {name = card.character, unit = card.unit}, false)
            if card.slotCount ~= was then
                local oldCount, oldCell = visibleBagCells, BAG_CELL
                layoutCards()
                if visibleBagCells ~= oldCount or BAG_CELL ~= oldCell then
                    paint(card, {name = card.character, unit = card.unit}, false)
                end
            end
            return
        end
    end
end

repaintSelf = function()
    repaintMember(UnitName("player"))
end

requestFreshInventory = function(name, force)
    if not name or not isInGroup(name) then return end
    local key = norm(name)
    if key == norm(UnitName("player"))
        and selfServerProtocolAvailable == false then return end
    local now = GetTime()
    if not force and inventoryRequestedAt[key]
        and now - inventoryRequestedAt[key] < 4 then
        return
    end
    inventoryRequestedAt[key] = now
    if norm(name) == norm(UnitName("player")) then
        TB.SendBotCommand("inv self")
    else
        -- Let the server re-authorize new party members. A missing cached
        -- INV_TYPE never implies a denial of permission to request a snapshot.
        TB.RequestInventory(name)
    end
end

-- Native trades may complete AFTER TRADE_PENDING and before any new
-- INV_END packet. BAG_UPDATE and PLAYER_MONEY are therefore equally important
-- completion signals. Never consider a purchase complete until ALL three
-- observable facts agree: received quantity, exact money and absent seller GUID.
verifyActivePurchase = function()
    local active = pendingTransfer
    if not active or active.kind ~= "buy"
        or not (active.serverPending or active.serverComplete) then return false end
    local nowCount = countLocalItem(active.sourceId)
    local nowMoney = GetMoney and GetMoney() or nil
    if not (active.botSeen and type(nowCount) == "number"
        and type(nowMoney) == "number"
        and type(active.price) == "number" and active.price > 0
        and nowCount >= active.beforeCount + active.sourceCount
        and nowMoney == active.beforeMoney - active.price) then return false end
    for i = table.getn(pendingTrade), 1, -1 do
        if pendingTrade[i] == active.entry then table.remove(pendingTrade, i) end
    end
    pendingTransfer = nil
    if checkoutQueue then
        checkoutQueue.nextIndex = checkoutQueue.nextIndex + 1
        status("Purchase verified " .. (checkoutQueue.nextIndex - 1) .. "/"
            .. checkoutQueue.total .. ". Next item starts only after this settlement.")
    else
        status("Purchase verified: item received, exact payment made, seller stack removed.")
    end
    if frame:IsShown() and render then render(false) end
    return true
end

-- A canceled native trade must not permanently block the entire interface.
-- Clear its pending lock ONLY after the closed trade has produced fresh,
-- independent seller+buyer snapshots proving that the seller still holds the
-- exact original GUID/stack and the buyer lost neither money nor received an
-- item. Any partial or contradictory evidence stays blocked for safety.
local function verifyCanceledPurchase()
    local active = pendingTransfer
    if not active or active.kind ~= "buy" or not active.tradeClosed
        or not active.sellerSeenAfterClose or not active.buyerSeenAfterClose
        or not active.sellerStillHas then return false end
    local count = countLocalItem(active.sourceId)
    local money = GetMoney and GetMoney() or nil
    if count ~= active.beforeCount or money ~= active.beforeMoney then
        return false
    end
    pendingTransfer = nil
    if checkoutQueue then
        abortCheckout("the server canceled an item; remaining purchases were not sent")
    end
    for i = table.getn(pendingTrade), 1, -1 do
        if pendingTrade[i] == active.entry then table.remove(pendingTrade, i) end
    end
    status("Trade canceled: seller still has the item, and no money or items moved. You may stage it again.")
    if frame:IsShown() and render then render(false) end
    return true
end

-- Only a matching INV_BEGIN/INV_ITEM/INV_END carries a trustworthy GUID snapshot.
local snapshot
local previousSystemMessage = TB.OnSystemMessage
-- Keep batch messages in a separate closure: the native WoW 1.12 Lua 5.0
-- runtime limits any one function to 32 upvalues.
local function consumeCoinBatchProtocol(message)
    if message == "TBM:MONEYBATCH_CAP|v1|4" then
        batchMoneyCapable = true
        return true
    end
    local _, _, receiptId, altName, sent, received, altAfter = string.find(message,
        "^TBM:MONEYBATCH_ROW|(%d+)|([^|]+)|(%d+)|(%d+)|(%d+)$")
    if receiptId then
        local active = pendingCoinTransfer
        if active and active.kind == "batch" and
            tonumber(receiptId) == active.nonce then
            local row = active.rows[norm(altName)]
            if row and not row.received and tonumber(sent) == row.give and
                tonumber(received) == row.take and tonumber(altAfter) == row.after then
                row.received = true
                active.receiptCount = active.receiptCount + 1
            else
                active.invalidReceipt = true
                status("Unexpected ALT receipt. Verify balances before trying another batch.")
            end
        end
        return true
    end
    local _, _, doneId, ownerBefore, ownerAfter, rowCount = string.find(message,
        "^TBM:MONEYBATCH_COMPLETE|(%d+)|(%d+)|(%d+)|(%d+)$")
    if doneId then
        local active = pendingCoinTransfer
        if active and active.kind == "batch" and not active.invalidReceipt
            and tonumber(doneId) == active.nonce
            and tonumber(ownerBefore) == active.ownerBefore
            and tonumber(ownerAfter) == active.ownerAfter
            and tonumber(rowCount) == active.rowCount
            and active.receiptCount == active.rowCount then
            pendingCoinTransfer = nil
            for _, row in pairs(active.rows) do
                requestFreshInventory(row.name, true)
            end
            TB.SendBotCommand("inv self")
            status("Confirmed: all " .. active.rowCount ..
                " ALT transfers completed together. New balance " ..
                moneyText(active.ownerAfter) .. ".")
            refreshCoinBars()
        else
            status("Batch receipt incomplete or mismatched. Recheck all balances before any retry.")
        end
        return true
    end
    local _, _, reason = string.find(message,
        "^TBM:ACTION_ERR|item moneybatch|[^|]+|(.+)$")
    if reason then
        local active = pendingCoinTransfer
        if active and active.kind == "batch" then
            pendingCoinTransfer = nil
            for _, row in pairs(active.rows) do requestFreshInventory(row.name, true) end
            TB.SendBotCommand("inv self")
        end
        status("Currency batch rejected (no transfers): " .. reason)
        refreshCoinBars()
        return true
    end
    return false
end
-- Vanilla/Turtle embeds Lua 5.0, which caps a single closure at 32 upvalues.
-- Keep coin protocol as a narrow separate callback instead of adding the
-- entire feature's state to the mature inventory/chat protocol handler.
local function consumeCoinProtocol(message)
    if consumeCoinBatchProtocol(message) then return true end
    if message == "TBM:MONEY_CAP|v1|nearby-owned-alt" then
        moneyCapable = true
        refreshCoinBars()
        return true
    end
    local _, _, coinNonce, coinFrom, coinTo, coinValue, coinAfterFrom, coinAfterTo =
        string.find(message,
            "^TBM:MONEY_COMPLETE|(%d+)|([^|]+)|([^|]+)|(%d+)|(%d+)|(%d+)$")
    if coinNonce then
        local active = pendingCoinTransfer
        if active and tonumber(coinNonce) == active.nonce and
            norm(coinFrom) == norm(active.from) and norm(coinTo) == norm(active.to)
            and tonumber(coinValue) == active.amount
            and tonumber(coinAfterFrom) == active.senderBefore - active.amount
            and tonumber(coinAfterTo) == active.receiverBefore + active.amount then
            pendingCoinTransfer = nil
            status("Confirmed: " .. moneyText(active.amount) ..
                " transferred from " .. coinFrom .. " to " .. coinTo .. ".")
            requestFreshInventory(active.from, true)
            requestFreshInventory(active.to, true)
            refreshCoinBars()
        else
            status("Unexpected coin receipt; no further transfers. Refresh balances.")
        end
        return true
    end
    local _, _, reason = string.find(message, "^TBM:ACTION_ERR|item money|[^|]+|(.+)$")
    if reason then
        local active = pendingCoinTransfer
        pendingCoinTransfer = nil
        status(reason)
        if active then
            local altName = norm(active.from) == norm(UnitName("player"))
                and active.to or active.from
            requestFreshInventory(altName, true)
        end
        TB.SendBotCommand("inv self")
        refreshCoinBars()
        return true
    end
    return false
end
TB.OnSystemMessage = function(message)
    if type(message) ~= "string" then return previousSystemMessage(message) end
    if consumeCoinProtocol(message) then return end
    if message == "TBM:SELLMARKED_CAP|v1" then
        sellMarkedCapable = true
        for _, card in ipairs(columns) do updateSellButton(card) end
        return
    end
    -- The previous client never consumed the server's immediate ACTION_ACK
    -- for a vendor errand. As a result users saw "Waiting for server..." even
    -- after the order was accepted and the bot began traveling. Acknowledged
    -- is NOT the same as sold: only SELLMARKED_DONE clears specific GUIDs.
    local _, _, startedName, startedCount, startedDetail = string.find(message,
        "^TBM:ACTION_ACK|sellmarked|bot:([^|]+)|(%d+)|(.+)$")
    if startedName then
        local active = activeMarkedSale[norm(startedName)]
        if active then
            active.acknowledgedAt = GetTime()
            status(startedName .. " accepted the vendor order (" .. startedCount
                .. " stacks). Walking to a merchant; sold items will be confirmed separately.")
        end
        return
    end
    local _, _, doneName, doneCount, doneGuids =
        string.find(message, "^TBM:SELLMARKED_DONE|([^|]+)|(%d+)|([^|]*)$")
    if doneName then
        local key = norm(doneName)
        local active = activeMarkedSale[key]
        if active then
            local sold = 0
            for id in string.gfind(doneGuids or "", "(%d+)") do
                local guid = tonumber(id)
                if guid and active.selected[guid] then
                    if markedForSale[key] then markedForSale[key][guid] = nil end
                    sold = sold + 1
                end
            end
            activeMarkedSale[key] = nil
            status(doneName .. " sold " .. sold .. " marked stacks and is returning. "
                .. "Unsuccessful markings remain selected.")
            requestFreshInventory(doneName, true)
            if frame:IsShown() then render(false) end
        end
        return
    end
    local _, _, failedName, why = string.find(message,
        "^TBM:SELLMARKED_FAILED|([^|]+)|(.+)$")
    if failedName then
        activeMarkedSale[norm(failedName)] = nil
        status(failedName .. ": vendor trip failed - " .. why)
        if frame:IsShown() then render(false) end
        return
    end
    local _, _, version, capabilities = string.find(message, "^TBM:TRADE_CAPS|([^|]+)|([^|]+)$")
    if version then
        -- Only a tested versioned server contract enables economic actions.
        local caps = "," .. string.lower(capabilities) .. ","
        quoteCapable = version == "v1" and string.find(caps, ",quote,", 1, true) ~= nil
        tradeCapable = quoteCapable and string.find(caps, ",buy,", 1, true) ~= nil
        if quoteCapable and table.getn(pendingTrade) > 0
            and not pendingTransfer and fillTradeAmount then
            fillTradeAmount()
        end
    end
    local _, _, misplacedTarget = string.find(message, "^TBM:TRANSFER_PLACEMENT|([^|]+)|auto$")
    if misplacedTarget then
        status("Transfer completed, but WoW chose a different free slot on " ..
            misplacedTarget .. ". Refresh to locate the item.")
    end
    local _, _, person, kind = string.find(message, "^TBM:INV_TYPE|([^|]+)|([^|]+)$")
    if person and (kind == "human" or kind == "ai" or kind == "own") then
        if isInGroup(person) then
            partyTypes[norm(person)] = kind
            if kind == "human" then
                -- Never display old snapshots if the party member was a human.
                for i = table.getn(pendingTrade), 1, -1 do
                    if norm(pendingTrade[i].name) == norm(person) then
                        table.remove(pendingTrade, i)
                    end
                end
            end
            if frame:IsShown() then render(false) end
        end
    end
    -- Protocol: the server can append an authoritative icon name from its
    -- item_display_info table. Legacy servers omit both the price and icon.
    local _, _, bag, position, itemId, count, flags, guid, tail =
        string.find(message, "^TBM:INV_ITEM|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|(%d+)(.*)$")
    local saleCopper, itemIcon, itemQuality
    if tail and string.sub(tail, 1, 1) == "|" then
        local _, _, price, icon, quality = string.find(tail,
            "^|(%d*)|([^|]*)|(%d+)$")
        if not price then
            _, _, price, icon = string.find(tail, "^|(%d*)|?(.*)$")
        end
        saleCopper = price ~= "" and tonumber(price) or nil
        itemIcon = validTexturePath(icon)
        itemQuality = tonumber(quality)
        if not itemIcon and price == "" then
            itemIcon = validTexturePath(string.sub(tail, 2))
        end
    end
    local _, _, equipSlot, equipItemId, eqDur, eqMax, eqTail =
        string.find(message, "^TBM:INV_EQ|(%d+)|(%d+)|(%d+)|(%d+)(.*)$")
    local equipIcon
    if eqTail and string.sub(eqTail, 1, 1) == "|" then
        local _, _, _, icon = string.find(eqTail, "^|(%d*)|?(.*)$")
        equipIcon = validTexturePath(icon)
    end
    local _, _, beginName = string.find(message, "^TBM:INV_BEGIN|([^|]+)|")
    if beginName then
        if norm(beginName) == norm(UnitName("player")) then
            selfServerProtocolAvailable = true
        end
        snapshot = { name = norm(beginName), items = {}, equipped = {},
            receivedAt = GetTime(), selfRevision = selfInventoryRevision }
    elseif guid and snapshot then
        local vendorEligible
        -- WoW 1.12 GetItemInfo has no reliable vendor-price return value.
        -- New servers send authoritative v/n flags, while old servers omit
        -- both (unknown eligibility, always checked again before sale).
        if string.find(flags, "v", 1, true) then vendorEligible = true
        elseif string.find(flags, "n", 1, true) then vendorEligible = false end
        snapshot.items[tonumber(bag) * 256 + tonumber(position)] = {
            id = tonumber(itemId), count = tonumber(count), guid = tonumber(guid),
            salePrice = saleCopper, texture = itemIcon,
            quality = itemQuality,
            wearable = string.find(flags, "w", 1, true) ~= nil,
            quest = string.find(flags, "q", 1, true) ~= nil,
            vendorEligible = vendorEligible,
        }
    elseif equipSlot and snapshot then
        snapshot.equipped[tonumber(equipSlot)] = {
            id = tonumber(equipItemId), texture = equipIcon,
        }
    end
    local _, _, quoteName, quoteBag, quoteSlot, quoteId, quoteGuid, quoteCount, quotePrice =
        string.find(message,
            "^TBM:TRADE_QUOTE|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
    if quoteName and isInGroup(quoteName) and botType(quoteName) == "ai" then
        for _, entry in ipairs(pendingTrade) do
            if norm(entry.name) == norm(quoteName)
                and entry.bag == tonumber(quoteBag) and entry.slot == tonumber(quoteSlot)
                and entry.id == tonumber(quoteId) and entry.guid == tonumber(quoteGuid)
                and entry.count == tonumber(quoteCount) and entry.pending then
                entry.price = tonumber(quotePrice)
                entry.pending = nil
                entry.error = nil
                status("Server quote received: " .. moneyText(entry.price) .. ".")
            end
        end
    end
    local _, _, pendingName, pendingGuid, pendingCount, pendingCopper =
        string.find(message, "^TBM:TRADE_PENDING|([^|]+)|(%d+)|(%d+)|(%d+)$")
    local _, _, completeName, completeGuid, completeCount, completeCopper =
        string.find(message, "^TBM:TRADE_COMPLETE|([^|]+)|(%d+)|(%d+)|(%d+)$")
    local active = pendingTransfer
    if active and active.kind == "buy" then
        local entry = active.entry
        if pendingName and norm(pendingName) == norm(entry.name)
            and tonumber(pendingGuid) == entry.guid and tonumber(pendingCount) == entry.count
            and tonumber(pendingCopper) == active.price then
            active.serverPending = true
            status("The server is processing the purchase; no completion confirmed.")
        elseif completeName and norm(completeName) == norm(entry.name)
            and tonumber(completeGuid) == entry.guid and tonumber(completeCount) == entry.count
            and tonumber(completeCopper) == active.price then
            active.serverComplete = true
            status("Server reported completion; verifying items and money...")
            TB.RequestInventory(entry.name)
            TB.SendBotCommand("inv self")
            refreshAt = GetTime() + 0.4
        end
    end
    local _, _, intent, result = string.find(message, "^TBM:ACTION_ERR|([^|]+)|[^|]+|(.+)$")
    if intent == "sellmarked" then
        for key in pairs(activeMarkedSale) do activeMarkedSale[key] = nil end
        status(result or "The vendor errand could not be started.")
        if frame:IsShown() then render(false) end
    elseif intent == "item transfer" or intent == "item buy" then
        if intent == "item buy" and checkoutQueue then
            abortCheckout(result or "the server rejected one purchase")
        end
        status(result)
        if intent == "item transfer" and pendingTransfer
            and pendingTransfer.kind == "transfer"
            and result and string.find(string.lower(result), "stale", 1, true) then
            requestFreshInventory(pendingTransfer.from, true)
            requestFreshInventory(pendingTransfer.to, true)
            status("Item positions changed on server; resyncing both inventories.")
        end
        pendingTransfer = nil
        if frame:IsShown() then render(false) end
    elseif intent == "item quote" then
        -- The core reports failed quotes without an item name. Retire the
        -- oldest outstanding quote instead of leaving 'Price pending' forever.
        for _, entry in ipairs(pendingTrade) do
            if entry.pending then
                entry.pending = nil
                entry.error = result or "This item has no valid seller price."
                break
            end
        end
        fillWhenQuoted = false
        status(result or "Seller declined the price request.")
    elseif intent == "item place" or intent == "item sort" then
        if intent == "item place" then
            -- Older cores omit the actor name in ACTION_ERR. We cannot
            -- identify which pending owner was refused. Retire all previews,
            -- refresh each affected ALT once and repaint from the last
            -- server inventory. Never leave unrelated ALTs visually stuck.
            local affected = {}
            for _, placement in pairs(optimisticPlacements) do
                if placement.name then table.insert(affected, placement.name) end
            end
            optimisticPlacements = {}
            if frame:IsShown() then render(false) end
            for _, name in ipairs(affected) do
                requestFreshInventory(name, true)
            end
        end
        status(result or "The inventory change was refused.")
    elseif intent == "inv" and result then
        -- ACTION_ERR|inv|no-bot does not identify WHICH requested member
        -- failed. An ALT can join just as the UI requests its first snapshot,
        -- returning no-bot even on a server that fully supports `inv self`.
        -- Never permanently disable every self transfer from this ambiguous
        -- error. Safety still requires a complete current self GUID snapshot.
        status("Inventory request rejected; participant may still be joining. Refresh if needed.")
    elseif intent and string.find(intent, "^item ") then
        -- Equip/unequip/bagswap errors previously left the top strip stuck on
        -- 'Waiting for server...', even when the server explicitly rejected it.
        status(result or "The server refused the equipment change.")
    elseif string.find(message, "^TBM:ACTION_ACK|item transfer|") then
        if pendingTransfer and pendingTransfer.kind == "transfer" then
            pendingTransfer.acked = true
            status("Transfer confirmed. Applying the server's inventory snapshots.")
        else
            status("Transfer acknowledged by server; refreshing snapshots.")
        end
    elseif string.find(message, "^TBM:ACTION_ACK|item place|") then
        local _, _, acknowledgedName = string.find(message,
            "^TBM:ACTION_ACK|item place|bot:([^|]+)")
        if acknowledgedName then
            local placement = optimisticPlacements[norm(acknowledgedName)]
            if placement then
                placement.acked = true
                placement.ackAt = GetTime()
            end
        else
            local single
            for _, placement in pairs(optimisticPlacements) do
                if single then single = nil; break end
                single = placement
            end
            if single then
                single.acked = true
                single.ackAt = GetTime()
            end
        end
        status("ALT placement accepted; awaiting its confirmed inventory.")
    elseif string.find(message, "^TBM:ACTION_ACK|item sort|") then
        status("Inventory sorted. Special-purpose bags were preserved.")
    elseif string.find(message, "^TBM:ACTION_ACK|item equip|")
        or string.find(message, "^TBM:ACTION_ACK|item unequip|")
        or string.find(message, "^TBM:ACTION_ACK|item bagswap|") then
        status("Equipment change confirmed by server. Updating character model...")
        -- An INV_END follows these acknowledgements; its equipment signature
        -- is authoritative, not the pre-command cached party unit appearance.
        refreshAt = GetTime() + 0.06
    end
    -- Older TortoiseBots Core.lua parsers anchor INV_EQ at the final numeric
    -- bag size. Forward its legacy prefix so the base addon still populates
    -- equipped slots; keep the validated extended icon in our own snapshot.
    local forwarded = message
    if equipSlot and eqTail then
        local _, _, bagSize, extended = string.find(eqTail, "^|(%d*)|(.+)$")
        if extended then
            forwarded = "TBM:INV_EQ|" .. equipSlot .. "|" .. equipItemId
                .. "|" .. eqDur .. "|" .. eqMax .. "|" .. (bagSize ~= "" and bagSize or "0")
        end
    end
    local reply = previousSystemMessage(forwarded)
    local _, _, endName = string.find(message, "^TBM:INV_END|([^|]+)|")
    if endName then
        snapshot = nil
        if frame:IsShown() then TB.RefreshCoinBars() end
    end
    -- Inventory packets can arrive by the hundreds. Repainting the payment
    -- dialog after every INV_ITEM was a major source of UI stutter.
    if frame:IsShown() and
        (version or quoteName or pendingName or completeName or intent) then
        refreshTrade()
    end
    return reply
end

-- Separate small system-message wrapper to avoid WoW 1.12's 32-upvalue
-- limit in the already complex inventory packet parser above.
local previousChatSystemMessage = TB.OnSystemMessage
TB.OnSystemMessage = function(message)
    if type(message) == "string" then
        local _, _, on, ambient = string.find(message,
            "^TBM:CHAT_STATUS|([01])|([01])$")
        if on then
            chatEnabled = on == "1"
            -- In WoW 1.12 controlButton uses a custom FontString caption:
            -- calling the raw Button:SetText does not update visible text.
            local label = chatEnabled and "AI Chat: ON" or "AI Chat: OFF"
            chatToggle.caption:SetText(label)
            chatToggle.controlLabel = label
            status("AI chat " .. (chatEnabled and "enabled" or "disabled") ..
                "; ambient " .. (ambient == "1" and "enabled" or "disabled") .. ".")
            return
        end
    end
    return previousChatSystemMessage(message)
end

-- One small, read-only source lookup avoids flooding the 1.12 chat channel
-- with a complete inventory before a main->ALT drag. All mutations still use
-- the server's strict item GUID/native trade path; a lost reply moves nothing.
local previousGuidSystemMessage = TB.OnSystemMessage
TB.OnSystemMessage = function(message)
    if message == "TBM:SELF_ITEM_CAP|v1" then
        selfServerEquipmentAvailable = true
        return
    end
    if message == "TBM:ITEM_GUID_CAP|v1" then
        guidResolveCapable = true
        return
    end
    if type(message) == "string" then
        local _, _, owner, bag, slot, id, count, guid = string.find(message,
            "^TBM:ITEM_GUID|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
        if owner then
            local wanted = deferredGuidTransfer
            if wanted and norm(owner) == norm(wanted.from)
                and tonumber(bag) == wanted.bag and tonumber(slot) == wanted.slot
                and tonumber(id) == wanted.id and tonumber(count) == wanted.count
                and tonumber(guid) > 0 then
                deferredGuidTransfer = nil
                local nativeMatches = true
                if wanted.fromType == "self" then
                    local _, currentCount = GetContainerItemInfo(
                        wanted.playerBag, wanted.playerSlot)
                    local currentLink = GetContainerItemLink and
                        GetContainerItemLink(wanted.playerBag, wanted.playerSlot)
                    nativeMatches = currentCount == wanted.count
                        and itemIdFromLink(currentLink) == wanted.id
                end
                if nativeMatches and not pendingTransfer
                    and isInGroup(wanted.from) and isInGroup(wanted.to) then
                    local from = wanted.fromType == "self" and "self" or wanted.from
                    local to = wanted.toType == "self" and "self" or wanted.to
                    pendingTransfer = {kind="transfer", from=wanted.from,
                        to=wanted.to, startedAt=GetTime(), visual=wanted.visual}
                    command("item " .. from .. " transfer " .. to .. " put "
                        .. wanted.bag .. " " .. wanted.slot .. " " .. guid .. " "
                        .. wanted.count .. " " .. wanted.toBag .. " " .. wanted.toSlot)
                    status("Exact server GUID confirmed; transfer sent, awaiting receipt.")
                else
                    status("The selected stack changed before the server reply. Nothing moved.")
                    if frame:IsShown() then render(false) end
                end
            end
            return
        end
        if string.find(message, "^TBM:ACTION_ERR|item resolve|") then
            local wanted = deferredGuidTransfer
            if wanted then
                deferredGuidTransfer = nil
                requestFreshInventory(wanted.from, true)
                status("The source stack changed. Refreshed without transferring anything.")
                if frame:IsShown() then render(false) end
            end
            return
        end
    end
    return previousGuidSystemMessage(message)
end

-- Distinguish the authenticated player's equipment receipt from matching
-- equipment actions issued to other party members. The native server sends
-- ACTION_ACK before its authoritative INV_BEGIN/INV_END inventory response.
TB._partyPreviousSelfGearSystemMessage = TB.OnSystemMessage
TB.OnSystemMessage = function(message)
    local active = TB._partySelfGearCommand
    if active and type(message) == "string" then
        local _, _, action, actor = string.find(message,
            "^TBM:ACTION_ACK|item ([^|]+)|bot:([^|]+)|")
        if action == active.op and norm(actor) == norm(UnitName("player")) then
            active.ackAt = GetTime()
        else
            local _, _, rejected = string.find(message,
                "^TBM:ACTION_ERR|item ([^|]+)|")
            if rejected == active.op then
                -- Older cores omit which actor failed. An ALT error can
                -- share this verb, so do not treat it as proof our SELF
                -- command failed. Require an explicit recovery snapshot
                -- after the safe command queue has had time to drain.
                active.possibleErrorAt = GetTime()
            end
        end
    end
    return TB._partyPreviousSelfGearSystemMessage(message)
end

local previousSetInventory = TB.SetInventory
TB.SetInventory = function(name, inventory)
    local previousStagedCount = table.getn(pendingTrade)
    local snapshotStartedAt = snapshot and snapshot.name == norm(name)
        and snapshot.receivedAt or nil
    if snapshot and norm(name) == snapshot.name and inventory and inventory.items then
        for _, item in ipairs(inventory.items) do
            local source = snapshot.items[item.bag * 256 + item.slot]
            if source and source.id == item.id and source.count == item.count then
                item.guid = source.guid
                item.salePrice = source.salePrice
                item.texture = source.texture or item.texture
                item.quality = source.quality
                item.wearable = source.wearable
                item.quest = source.quest
                item.vendorEligible = source.vendorEligible
            end
        end
        for slot, item in pairs(inventory.equipped or {}) do
            local source = snapshot.equipped[slot]
            if source and source.id == item.id then
                item.texture = source.texture or item.texture
            end
        end
    end
    if inventory then
        for _, item in ipairs(inventory.items or {}) do
            item.texture = resolvedItemTexture(item.id, item.texture)
        end
        for _, item in pairs(inventory.equipped or {}) do
            item.texture = resolvedItemTexture(item.id, item.texture)
        end
    end
    previousSetInventory(name, inventory)
    if TB._partySelfGearCommand and inventory and name
        and norm(name) == norm(UnitName("player")) and snapshotStartedAt then
        local active = TB._partySelfGearCommand
        if (active.ackAt and snapshotStartedAt >= active.ackAt)
            or (active.recoverySentAt and snapshotStartedAt >= active.recoverySentAt) then
            TB._partySelfGearCommand = nil
        end
    end
    local visual = name and optimisticPlacements[norm(name)]
    if visual and inventory then
        -- The server's actual item GUID and destination decide success. A
        -- newer snapshot that disagrees with the preview reverses it safely.
        local confirmed, stillAtSource = false, false
        for _, item in ipairs(inventory.items or {}) do
            if item.guid == visual.sourceGuid
                and item.bag == visual.destinationBag
                and item.slot == visual.destinationSlot then
                confirmed = true
            elseif item.guid == visual.sourceGuid
                and item.bag == visual.sourceBag and item.slot == visual.sourceSlot then
                stillAtSource = true
            end
        end
        local afterAck = visual.acked and snapshotStartedAt
            and snapshotStartedAt >= (visual.ackAt or 0)
        if confirmed or (not stillAtSource and snapshotStartedAt
            and snapshotStartedAt >= visual.startedAt) or afterAck then
            optimisticPlacements[norm(name)] = nil
            if not confirmed and afterAck then
                status("ALT inventory differs from the preview; restored server state.")
            end
        end
    end
    if inventory and TB.RefreshMoneyBatchDialog then
        TB.RefreshMoneyBatchDialog()
    end
    if inventory and frame:IsShown() then refreshCoinBars() end
    if inventory and name and markedForSale[norm(name)] then
        -- Preserve a marked exact GUID across an ordinary bag rearrangement,
        -- but drop a mark if its stack count or item ID changed.
        local original = markedForSale[norm(name)]
        local updated = {}
        for _, item in ipairs(inventory.items or {}) do
            local old = item.guid and original[item.guid]
            if old and old.id == item.id and old.count == item.count
                and item.vendorEligible ~= false and not item.quest then
                updated[item.guid] = {guid=item.guid, id=item.id,
                    count=item.count, bag=item.bag, slot=item.slot}
            end
        end
        markedForSale[norm(name)] = updated
    end
    if inventory and name then inventoryCachedAt[norm(name)] = GetTime() end
    if inventory and norm(name) == norm(UnitName("player")) then
        for _, item in ipairs(inventory.items or {}) do
            if item.id and item.equippable == true then
                selfEquippableItemIds[item.id] = true
            end
        end
        -- An in-flight INV_SELF that started before a native slot change must
        -- not become the current GUID authority after that change.
        selfSnapshotValid = snapshot and snapshot.name == norm(name)
            and snapshot.selfRevision == selfInventoryRevision or false
        -- The only safe way to resume a self right-click that lacks local
        -- item-cache metadata is a fresh, complete, revision-matched SELF
        -- snapshot. An equippable server prototype is never inferred from the
        -- icon or tooltip. Perform native action later on OnUpdate, after
        -- the current inventory packet batch has finished.
        if pendingSelfEquip and selfSnapshotValid then
            local wanted = pendingSelfEquip
            local matching
            for _, item in ipairs(inventory.items or {}) do
                if item.bag == wanted.serverBag and item.slot == wanted.serverSlot then
                    matching = item
                    break
                end
            end
            if matching and matching.id == wanted.id
                and matching.count == wanted.count and matching.equippable == true then
                wanted.confirmed = true
            else
                pendingSelfEquip = nil
                status(matching and matching.id == wanted.id
                    and matching.count == wanted.count
                    and "This character cannot equip that item (skill, class or level). Nothing was used." or
                    "This item moved or changed during verification; nothing was used.")
            end
        end
    end
    if deferredGuidTransfer and inventory
        and norm(name) == norm(deferredGuidTransfer.from) then
        local wanted = deferredGuidTransfer
        deferredGuidTransfer = nil
        local serverItem
        for _, item in ipairs(inventory.items or {}) do
            if item.bag == wanted.bag and item.slot == wanted.slot then
                serverItem = item
                break
            end
        end
        local nativeStillMatches = true
        if wanted.fromType == "self" then
            local _, currentCount = GetContainerItemInfo(
                wanted.playerBag, wanted.playerSlot)
            local currentLink = GetContainerItemLink and
                GetContainerItemLink(wanted.playerBag, wanted.playerSlot)
            nativeStillMatches = currentCount == wanted.count
                and itemIdFromLink(currentLink) == wanted.id
        end
        if not serverItem or serverItem.id ~= wanted.id
            or serverItem.count ~= wanted.count
            or type(serverItem.guid) ~= "number" or serverItem.guid <= 0 then
            if nativeStillMatches and wanted.fromType == "self"
                and isInGroup(wanted.from) and isInGroup(wanted.to)
                and not pendingTransfer and (wanted.retries or 0) < 3 then
                -- The client can show a new physical position before the
                -- queued INV_SELF snapshot reflects it. Requery, but never
                -- reuse a GUID from the old server position or move blindly.
                wanted.retries = (wanted.retries or 0) + 1
                wanted.retryAt = GetTime() + 0.30
                deferredGuidTransfer = wanted
                status("Server still has the prior bag order. Resynchronizing ("
                    .. wanted.retries .. "/3); no item moved yet.")
            else
                status(nativeStillMatches and
                    "Server did not confirm this stack after three refreshes. No transfer sent." or
                    "The source stack moved or changed. Re-select its current slot.")
            end
        else
            if not nativeStillMatches or pendingTransfer
                or not isInGroup(wanted.from) or not isInGroup(wanted.to) then
                status("The player item or party changed before transfer. Nothing moved.")
            else
                local from = wanted.fromType == "self" and "self" or wanted.from
                local to = wanted.toType == "self" and "self" or wanted.to
                pendingTransfer = {
                    kind = "transfer", from = wanted.from, to = wanted.to,
                    startedAt = GetTime(), visual = wanted.visual,
                }
                command("item " .. from .. " transfer " .. to .. " put "
                    .. wanted.bag .. " " .. wanted.slot .. " " .. serverItem.guid
                    .. " " .. wanted.count .. " " .. wanted.toBag .. " " .. wanted.toSlot)
                status("Server GUID verified. Queued inventory transfer submitted.")
            end
        end
    end
    local active = pendingTransfer
    if active and active.kind == "buy" and inventory then
        if norm(name) == norm(active.entry.name) and authorizedBot(name) then
            local remaining = 0
            local stillExact = false
            for _, item in ipairs(inventory.items or {}) do
                if item.guid == active.entry.guid or
                    (item.bag == active.entry.bag and item.slot == active.entry.slot
                        and item.id == active.entry.id) then
                    remaining = remaining + (item.count or 0)
                end
                if item.bag == active.entry.bag and item.slot == active.entry.slot
                    and item.id == active.sourceId and item.guid == active.sourceGuid
                    and item.count == active.sourceCount then
                    stillExact = true
                end
            end
            active.botSeen = remaining <= 0
            if active.tradeClosed and snapshotStartedAt
                and snapshotStartedAt >= active.closedAt then
                active.sellerSeenAfterClose = true
                active.sellerStillHas = stillExact
            end
        elseif active.tradeClosed and norm(name) == norm(UnitName("player"))
            and snapshotStartedAt and snapshotStartedAt >= active.closedAt then
            active.buyerSeenAfterClose = true
        end
        if not verifyActivePurchase() then verifyCanceledPurchase() end
    end
    if active and active == pendingTransfer and active.kind == "transfer"
        and active.acked and inventory then
        if norm(name) == norm(active.from) then active.fromSeen = true end
        if norm(name) == norm(active.to) then active.toSeen = true end
        if active.fromSeen and active.toSeen then
            pendingTransfer = nil
            status("Both inventories refreshed after transfer.")
            if frame:IsShown() then render(false) end
        end
    end
    -- Retire paid-trade previews when a newer authorized seller snapshot no
    -- longer contains the exact source GUID. Do not change an in-flight buy.
    if inventory and botType(name) == "ai" then
        for i = table.getn(pendingTrade), 1, -1 do
            local entry = pendingTrade[i]
            if norm(entry.name) == norm(name) and
                (not pendingTransfer or pendingTransfer.entry ~= entry) then
                local stillThere = false
                for _, item in ipairs(inventory.items or {}) do
                    if item.bag == entry.bag and item.slot == entry.slot
                        and item.id == entry.id and item.guid == entry.guid
                        and item.count == entry.count then
                        stillThere = true
                        if (not pendingTransfer or pendingTransfer.entry ~= entry)
                            and entry.price ~= item.salePrice and item.salePrice ~= nil then
                            entry.price = item.salePrice
                        end
                        break
                    end
                end
                if not stillThere then table.remove(pendingTrade, i) end
            end
        end
    end
    if frame:IsShown() then
        repaintMember(name)
        if table.getn(pendingTrade) ~= previousStagedCount then
            -- Seller removal also changes the buyer's preview outline and
            -- trade strip height; those did not receive a server snapshot.
            repaintSelf()
            layoutCards()
        end
        refreshTrade()
    end
end

frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("UNIT_MODEL_CHANGED")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:SetScript("OnEvent", function()
    if event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        -- These native events also fire while Party Inventory is closed.
        -- The retained GUID map must still be invalidated before reopening.
        invalidateSelfSnapshot()
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        -- Party authorization must expire even while this panel is hidden.
        -- Otherwise an old 'own/ai' marker could be reused after a leave,
        -- reinvite or group replacement. Keep item data, not permission.
        partyTypes = {}
        pendingSelfEquip = nil
        inventoryRequestedAt = {}
        pendingTrade = {}
        if checkoutQueue then
            -- Do not dispatch remaining paid orders after the party or
            -- seller roster changes. An in-flight trade must still be
            -- independently verified before another manual purchase.
            abortCheckout("the party roster changed")
        end
        if frame:IsShown() then render(true) end
        return
    end
    if event == "TRADE_CLOSED" and pendingTransfer and pendingTransfer.kind == "buy" then
        pendingTransfer.tradeClosed = true
        pendingTransfer.closedAt = GetTime()
        pendingTransfer.sellerSeenAfterClose = nil
        pendingTransfer.buyerSeenAfterClose = nil
        status("Trade closed. Refreshing both sides and verifying payment...")
        TB.RequestInventory(pendingTransfer.entry.name)
        TB.SendBotCommand("inv self")
        refreshAt = GetTime() + 0.4
        verifyActivePurchase()
        return
    end
    if not frame:IsShown() then return end
    if event == "PLAYER_TARGET_CHANGED" then
        -- Party membership and equipment did not change.
        return
    elseif event == "BAG_UPDATE" then
        TB._partyLocalBagMove = nil
        repaintSelf()
        verifyActivePurchase()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        repaintSelf()
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_MODEL_CHANGED" then
        if arg1 and UnitExists(arg1) then
            for _, card in ipairs(columns) do
                if card.unit == arg1 then
                    -- Inventory notifications can repeat for one change.
                    -- Compare the actual costume before rebuilding the model.
                    if event == "UNIT_MODEL_CHANGED" then card.modelUnit = nil end
                    repaintMember(card.character)
                    break
                end
            end
        end
    elseif event == "PLAYER_MONEY" then
        if frame:IsShown() then refreshCoinBars() end
        if pendingTransfer and pendingTransfer.kind == "buy" then
            repaintSelf()
            verifyActivePurchase()
        end
    else
        refreshAt = GetTime() + 0.05
    end
end)

local function finishVerifiedSelfEquip(wanted)
    local texture, count = GetContainerItemInfo(wanted.playerBag, wanted.playerSlot)
    local link = GetContainerItemLink and
        GetContainerItemLink(wanted.playerBag, wanted.playerSlot)
    if CursorHasItem and CursorHasItem() then
        status("Clear the item currently on your cursor before equipping.")
        return
    end
    if not texture or count ~= wanted.count or itemIdFromLink(link) ~= wanted.id then
        status("Item changed before equip; no action taken.")
        return
    end
    if selfServerEquipmentAvailable then
        if not TB.SubmitPartySelfGearCommand("item self equip "
            .. wanted.serverBag .. " " .. wanted.serverSlot, "equip") then return end
        status("Server confirmed wearable item; equipping character.")
    elseif UseContainerItem then
        invalidateSelfSnapshot()
        UseContainerItem(wanted.playerBag, wanted.playerSlot)
        status("Server confirmed wearable item; quick-equip requested.")
    end
    if repaintSelf then repaintSelf() end
    refreshAt = GetTime() + 0.04
end

local function recoverMissingPlacementSnapshots()
    local now = GetTime()
    for _, placement in pairs(optimisticPlacements) do
        -- Successful place sends its own INV_END. Query again only if that
        -- native reply has been delayed or lost; avoid duplicating large
        -- snapshots on every fast ALT bag move.
        if placement.acked and not placement.recoveryRequested
            and now - (placement.ackAt or placement.startedAt) >= 1.1 then
            placement.recoveryRequested = true
            requestFreshInventory(placement.name, true)
        end
    end
end

frame:SetScript("OnUpdate", function()
    syncNativeTradeFrame()
    if TB._partyLocalBagMove and GetTime() >= TB._partyLocalBagMove.expires then
        TB._partyLocalBagMove = nil
        repaintSelf()
    end
    recoverMissingPlacementSnapshots()
    if pendingCoinTransfer and
        GetTime() - pendingCoinTransfer.started > 10 and
        not pendingCoinTransfer.timeoutWarned then
        pendingCoinTransfer.timeoutWarned = true
        status("Coin transfer receipt delayed. Refresh or relog, but DO NOT pay again until verified.")
    end
    if checkoutQueue and not pendingTransfer then
        startQueuedCheckout()
    end
    if pendingSelfEquip then
        local wanted = pendingSelfEquip
        if wanted.confirmed then
            pendingSelfEquip = nil
            finishVerifiedSelfEquip(wanted)
        elseif GetTime() - wanted.startedAt > 8 then
            pendingSelfEquip = nil
            status("Equipment verification timed out; no item was used.")
        end
    end
    if frame:IsShown() and GetTime() >= nextIconRetryAt
        and next(unresolvedIconIds) then
        nextIconRetryAt = GetTime() + 1.4
        local hydrated = false
        for id in pairs(unresolvedIconIds) do
            if itemTexture(id) ~= UNKNOWN then hydrated = true end
        end
        if hydrated then render(false) end
    end
    if frame:IsShown() and GetTime() >= nextVisibleRefreshAt then
        nextVisibleRefreshAt = GetTime() + 15
        for _, member in ipairs(groupMembers()) do
            if member.name and authorizedBot(member.name)
                and (not inventoryCachedAt[norm(member.name)]
                    or GetTime() - inventoryCachedAt[norm(member.name)] > 12) then
                requestFreshInventory(member.name)
            end
        end
    end
    for key, sale in pairs(activeMarkedSale) do
        if not sale.acknowledgedAt and not sale.noAckNotified
            and GetTime() - (sale.sentAt or sale.startedAt) > 7 then
            sale.noAckNotified = true
            status((sale.name or key) .. " has not acknowledged the vendor order. "
                .. "Check server messages; do not submit a duplicate sale.")
        elseif sale.acknowledgedAt and not sale.slowNotified
            and GetTime() - sale.acknowledgedAt > 35 then
            sale.slowNotified = true
            status((sale.name or key) .. " is still on the vendor errand. "
                .. "The server must confirm sale or failure; no repeat order was sent.")
        end
    end
    if deferredGuidTransfer and deferredGuidTransfer.retryAt
        and GetTime() >= deferredGuidTransfer.retryAt then
        deferredGuidTransfer.retryAt = nil
        TB.SendBotCommand("inv self")
    end
    if pendingTransfer and pendingTransfer.kind == "buy" then
        local active = pendingTransfer
        if not verifyActivePurchase() and active == pendingTransfer
            and (active.serverPending or active.serverComplete)
            and (not active.lastRefreshAt or GetTime() - active.lastRefreshAt > 1.6) then
            active.lastRefreshAt = GetTime()
            requestFreshInventory(active.entry.name, true)
            TB.SendBotCommand("inv self")
            if GetTime() - active.startedAt > 12 then
                status("Purchase still unverified. Checking seller and buyer; do not pay twice.")
            end
        end
    end
    if deferredGuidTransfer
        and GetTime() - (deferredGuidTransfer.startedAt or GetTime()) > 8 then
        deferredGuidTransfer = nil
        if frame:IsShown() then render(false) end
        status("Inventory synchronization expired; no item was transferred.")
    end
    -- Delayed item-cache hydration is common after an alt is first invited.
    -- Retry ONLY when new wearable links have become cached. Do not trigger
    -- SetUnit every frame or before any new item details are available.
    if frame:IsShown() then
        for _, card in ipairs(columns) do
            if card.modelRetryAt and GetTime() >= card.modelRetryAt then
                card.modelRetryAt = GetTime() + 0.8
                card.modelCacheAttempts = (card.modelCacheAttempts or 0) + 1
                local inventory = card.character and TB.GetInventory(card.character)
                local ready = 0
                for id = 0, 18 do
                    local item = inventory and inventory.equipped and inventory.equipped[id]
                    if item and item.id and GetItemInfo then
                        local _, link = GetItemInfo(item.id)
                        if type(link) == "string" and link ~= "" then
                            ready = ready + 1
                        end
                    end
                end
                if ready > (card.modelReady or 0) then
                    card.modelAppearance = nil
                    repaintMember(card.character)
                elseif card.modelCacheAttempts >= 16 then
                    card.modelRetryAt = nil
                end
                if card.modelUncached == 0 then card.modelRetryAt = nil end
            end
        end
    end
    -- A lost quote response must become retryable rather than stay pending.
    -- No automatic repeat: retransmission requires the explicit Fill action.
    if table.getn(pendingTrade) > 0 then
        for _, entry in ipairs(pendingTrade) do
            if entry.pending and entry.requestedAt
                and GetTime() - entry.requestedAt > 8 then
                entry.pending = nil
                entry.error = "Price reply timed out. Use Fill to retry."
                fillWhenQuoted = false
                status(entry.error)
                if frame:IsShown() then refreshTrade() end
            end
        end
    end
    if pendingTransfer and pendingTransfer.kind == "transfer"
        and GetTime() - (pendingTransfer.startedAt or GetTime()) > 8 then
        requestFreshInventory(pendingTransfer.from, true)
        requestFreshInventory(pendingTransfer.to, true)
        pendingTransfer = nil
        if frame:IsShown() then render(false) end
        status("Transfer confirmation timed out; requested updated inventories.")
    end
    if not refreshAt or GetTime() < refreshAt then return end
    refreshAt = nil
    -- Only local native data can have changed here. Remote panels are updated
    -- by a completed server snapshot or their own unit equipment event.
    repaintSelf()
end)
frame:SetScript("OnHide", function()
    syncNativeTradeFrame(true)
    adjustInventoryQueue(false)
    fullscreenBackdrop:Hide()
    fullscreen = false
    fullscreenButton.caption:SetText("Maximize")
    frame:SetFrameStrata("DIALOG")
    stopDrag()
    deferredGuidTransfer = nil
    pendingSelfEquip = nil
    tradeDialog:Hide()
    snapshot = nil
    refreshAt = nil
    if managerWasVisible and TortoiseBotsManagerFrame then
        TortoiseBotsManagerFrame:Show()
    end
    managerWasVisible = false
end)

local function toggleInventory()
    if frame:IsShown() then frame:Hide(); return end
    local manager = TortoiseBotsManagerFrame
    managerWasVisible = manager and manager:IsShown() or false
    if managerWasVisible then manager:Hide() end
    page = 1
    frame:Show()
    adjustInventoryQueue(true)
    -- Paint from the last authorized server snapshot immediately, and refresh
    -- only stale characters in the background. The explicit Refresh button
    -- remains available for a guaranteed on-demand update.
    render(false)
    local ownName = UnitName("player")
    if ownName and (not selfSnapshotValid or not inventoryCachedAt[norm(ownName)]
        or GetTime() - inventoryCachedAt[norm(ownName)] > 10) then
        requestFreshInventory(ownName, not selfSnapshotValid)
    end
    for _, member in ipairs(groupMembers()) do
        if member.name and (not inventoryCachedAt[norm(member.name)]
            or GetTime() - inventoryCachedAt[norm(member.name)] > 10) then
            requestFreshInventory(member.name)
        end
    end
end

local function attachToManager()
    local manager = TortoiseBotsManagerFrame
    if not manager or manager.partyInventoryButton then return end
    local button = controlButton(manager, "Party Inventory", 132, 25, true)
    button:SetPoint("BOTTOMRIGHT", manager, "TOPRIGHT", -8, 3)
    button:SetScript("OnClick", toggleInventory)
    manager.partyInventoryButton = button
end
local previousInitUI = TB.InitUI
TB.InitUI = function()
    if previousInitUI then previousInitUI() end
    attachToManager()
end
attachToManager()
refreshTrade()

SLASH_TBMPARTYINVENTORY1 = "/tbminv"
SlashCmdList.TBMPARTYINVENTORY = toggleInventory
