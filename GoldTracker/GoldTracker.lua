-- GoldTracker: A simple gold tracking addon for WoW Retail using Ace3
local GoldTracker = LibStub("AceAddon-3.0"):NewAddon("GoldTracker", "AceConsole-3.0", "AceEvent-3.0")
local icon = LibStub("LibDBIcon-1.0")

local currentGold = 0
local lastKnownGold = 0
local playerName = nil

-- Default settings
local defaults = {
    profile = {
        minimap = {
            hide = false,
        },
        window = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    },
    global = {
        characters = {},
        minimapAngle = 225,
    }
}

-- Data broker object for minimap icon
local GoldTrackerLDB = LibStub("LibDataBroker-1.1"):NewDataObject("GoldTracker", {
    type = "data source",
    text = "GoldTracker",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    OnClick = function(clickedframe, button)
        GoldTracker:HideMinimapTooltip()

        if button == "LeftButton" then
            GoldTracker:ToggleWindow()
        elseif button == "RightButton" then
            GoldTracker:ResetStats()
        end
    end,
    OnEnter = function(anchor)
        GoldTracker:ShowMinimapTooltip(anchor)
    end,
    OnLeave = function()
        GoldTracker:HideMinimapTooltip()
    end,
})

function GoldTracker:OnInitialize()
    -- Set up database
    self.db = LibStub("AceDB-3.0"):New("GoldTrackerDB", defaults, true)
    
    -- Register minimap icon
    icon:Register("GoldTracker", GoldTrackerLDB, self.db.profile.minimap)
    
    -- Register slash commands
    self:RegisterChatCommand("goldtracker", "SlashCommand")
    self:RegisterChatCommand("gt", "SlashCommand")
end

function GoldTracker:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_MONEY", "UpdateGold")
    self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
    
    -- Create the main window
    self:CreateWindow()
    
    -- Initialize character on a slight delay to ensure player data is ready
    C_Timer.After(0.5, function()
        self:InitCharacter()
    end)
end

function GoldTracker:SlashCommand(input)
    if input == "reset" then
        self:ResetStats()
    elseif input == "debug" then
        self:Print("Frame exists: " .. tostring(self.frame ~= nil))
        self:Print("Frame shown: " .. tostring(self.frame and self.frame:IsShown()))
        self:Print("Player name: " .. tostring(playerName))
    else
        self:ToggleWindow()
    end
end

-- Helper function to format gold (copper -> colored string)
function GoldTracker:FormatGold(copper)
    copper = copper or 0
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local bronze = copper % 100
    
    return string.format("|cFFFFD700%dg|r |cFFC7C7CF%ds|r |cFFB87333%dc|r", gold, silver, bronze)
end

-- Return a colored profit string (positive green, negative red)
function GoldTracker:FormatProfit(copper)
    copper = copper or 0
    local prefix = ""
    if copper > 0 then
        prefix = "+ "
    elseif copper < 0 then
        prefix = "- "
        copper = math.abs(copper)
    end

    local colored = self:FormatGold(copper)
    if prefix == "+ " then
        return "|cFF00FF00" .. prefix .. colored .. "|r"
    elseif prefix == "- " then
        return "|cFFFF4444" .. prefix .. colored .. "|r"
    else
        return "|cFFFFFFFF" .. self:FormatGold(0) .. "|r"
    end
end

-- Build the custom minimap hover panel with the same styling as the main window
function GoldTracker:CreateMinimapTooltip()
    if self.minimapTooltip then return end

    local tooltip = CreateFrame("Frame", "GoldTrackerMinimapTooltip", UIParent, "BackdropTemplate")
    tooltip:SetSize(360, 400)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetClampedToScreen(true)
    tooltip:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tooltip:SetBackdropColor(0.012, 0.014, 0.022, 0.97)
    tooltip:SetBackdropBorderColor(0.72, 0.49, 0.12, 1)
    tooltip:Hide()

    local function CreateCard(parent)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        card:SetBackdropColor(0.025, 0.028, 0.04, 0.92)
        card:SetBackdropBorderColor(0.45, 0.34, 0.12, 0.9)
        return card
    end

    local function AddCardTitle(card, text)
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
        title:SetText("|cFFFFD36A" .. text .. "|r")

        local accent = card:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        accent:SetSize(34, 2)
        accent:SetColorTexture(0.95, 0.66, 0.12, 0.9)
        return title
    end

    local function AddMetric(card, label, y)
        local labelText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, y)
        labelText:SetText(label)
        labelText:SetTextColor(0.72, 0.72, 0.72)

        local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, y)
        value:SetWidth(108)
        value:SetJustifyH("RIGHT")
        return value
    end

    local coin = tooltip:CreateTexture(nil, "ARTWORK")
    coin:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 12, -11)
    coin:SetSize(34, 34)
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", coin, "TOPRIGHT", 10, -1)
    title:SetText("|cFFFFD36AGold Tracker|r")

    tooltip.characterName = tooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tooltip.characterName:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    tooltip.characterName:SetTextColor(0.7, 0.7, 0.7)

    local balanceCard = CreateCard(tooltip)
    balanceCard:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 12, -54)
    balanceCard:SetSize(336, 56)
    balanceCard:SetBackdropColor(0.08, 0.065, 0.025, 0.92)
    balanceCard:SetBackdropBorderColor(0.72, 0.49, 0.12, 1)

    local balanceLabel = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    balanceLabel:SetPoint("TOPLEFT", balanceCard, "TOPLEFT", 12, -9)
    balanceLabel:SetText("CURRENT GOLD")
    balanceLabel:SetTextColor(0.75, 0.68, 0.5)

    tooltip.currentValue = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tooltip.currentValue:SetPoint("TOPLEFT", balanceLabel, "BOTTOMLEFT", 0, -5)

    local sessionCard = CreateCard(tooltip)
    sessionCard:SetPoint("TOPLEFT", balanceCard, "BOTTOMLEFT", 0, -8)
    sessionCard:SetSize(164, 128)
    AddCardTitle(sessionCard, "This Session")
    tooltip.sessionEarned = AddMetric(sessionCard, "Earned", -42)
    tooltip.sessionSpent = AddMetric(sessionCard, "Spent", -66)
    tooltip.sessionNet = AddMetric(sessionCard, "Net", -90)

    local totalCard = CreateCard(tooltip)
    totalCard:SetPoint("TOPLEFT", sessionCard, "TOPRIGHT", 8, 0)
    totalCard:SetSize(164, 128)
    AddCardTitle(totalCard, "All Time")
    tooltip.totalEarned = AddMetric(totalCard, "Earned", -42)
    tooltip.totalSpent = AddMetric(totalCard, "Spent", -66)
    tooltip.totalNet = AddMetric(totalCard, "Net", -90)

    local accountCard = CreateCard(tooltip)
    accountCard:SetPoint("TOPLEFT", sessionCard, "BOTTOMLEFT", 0, -8)
    accountCard:SetSize(336, 94)
    AddCardTitle(accountCard, "Account Overview")
    tooltip.accountGold = AddMetric(accountCard, "Current Total", -42)
    tooltip.accountNet = AddMetric(accountCard, "All-Time Net", -66)

    local footer = tooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOM", tooltip, "BOTTOM", 0, 11)
    footer:SetText("|cFFAAAAAALeft-click:|r Open   |cFFAAAAAARight-click:|r Reset character")

    self.minimapTooltip = tooltip
end

function GoldTracker:UpdateMinimapTooltip()
    if not self.minimapTooltip or not playerName then return end

    local data = self.db.global.characters[playerName]
    if not data then return end

    local accountGold = 0
    local accountNet = 0
    for _, character in pairs(self.db.global.characters) do
        accountGold = accountGold + (character.lastGold or 0)
        accountNet = accountNet + (character.totalEarned or 0) - (character.totalSpent or 0)
    end

    local tooltip = self.minimapTooltip
    tooltip.characterName:SetText(playerName)
    tooltip.currentValue:SetText(self:FormatGold(data.lastGold))
    tooltip.sessionEarned:SetText(self:FormatGold(data.sessionEarned))
    tooltip.sessionSpent:SetText(self:FormatGold(data.sessionSpent))
    tooltip.sessionNet:SetText(self:FormatProfit((data.sessionEarned or 0) - (data.sessionSpent or 0)))
    tooltip.totalEarned:SetText(self:FormatGold(data.totalEarned))
    tooltip.totalSpent:SetText(self:FormatGold(data.totalSpent))
    tooltip.totalNet:SetText(self:FormatProfit((data.totalEarned or 0) - (data.totalSpent or 0)))
    tooltip.accountGold:SetText(self:FormatGold(accountGold))
    tooltip.accountNet:SetText(self:FormatProfit(accountNet))
end

function GoldTracker:ShowMinimapTooltip(anchor)
    if not anchor then return end

    self:CreateMinimapTooltip()
    self:UpdateMinimapTooltip()

    local tooltip = self.minimapTooltip
    local anchorX, anchorY = anchor:GetCenter()
    if not anchorX or not anchorY then return end

    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()

    tooltip:ClearAllPoints()
    if anchorX < screenWidth / 2 then
        if anchorY < screenHeight / 2 then
            tooltip:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", 8, 8)
        else
            tooltip:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 8, -8)
        end
    elseif anchorY < screenHeight / 2 then
        tooltip:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", -8, 8)
    else
        tooltip:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", -8, -8)
    end

    tooltip:Show()
end

function GoldTracker:HideMinimapTooltip()
    if self.minimapTooltip then
        self.minimapTooltip:Hide()
    end
end

-- Initialize character data
function GoldTracker:InitCharacter()
    playerName = UnitName("player") .. "-" .. GetRealmName()
    
    if not self.db.global.characters[playerName] then
        self.db.global.characters[playerName] = {
            totalEarned = 0,
            totalSpent = 0,
            sessionEarned = 0,
            sessionSpent = 0,
            lastGold = 0,
            firstLogin = true
        }
    end
    
    currentGold = GetMoney()
    
    -- On first login, just set the baseline without tracking
    if self.db.global.characters[playerName].firstLogin then
        self.db.global.characters[playerName].lastGold = currentGold
        self.db.global.characters[playerName].firstLogin = false
        lastKnownGold = currentGold
    else
        -- On subsequent logins, use the saved last gold value
        lastKnownGold = self.db.global.characters[playerName].lastGold or currentGold
        
        -- Calculate any difference from last logout
        local diff = currentGold - lastKnownGold
        if diff > 0 then
            self.db.global.characters[playerName].totalEarned = self.db.global.characters[playerName].totalEarned + diff
        elseif diff < 0 then
            self.db.global.characters[playerName].totalSpent = self.db.global.characters[playerName].totalSpent + math.abs(diff)
        end
        
        -- Update lastKnownGold to current
        lastKnownGold = currentGold
        self.db.global.characters[playerName].lastGold = currentGold
    end
    
    -- Reset session stats on every login
    self.db.global.characters[playerName].sessionEarned = 0
    self.db.global.characters[playerName].sessionSpent = 0
    
    self:Print("Type /goldtracker or /gt to open, or click the minimap button.")
end

-- Update gold tracking
function GoldTracker:UpdateGold()
    if not playerName then return end
    
    local data = self.db.global.characters[playerName]
    if not data then return end
    
    currentGold = GetMoney()
    local diff = currentGold - lastKnownGold
    
    if diff > 0 then
        -- Gained gold
        data.totalEarned = data.totalEarned + diff
        data.sessionEarned = data.sessionEarned + diff
    elseif diff < 0 then
        -- Spent gold
        local spent = math.abs(diff)
        data.totalSpent = data.totalSpent + spent
        data.sessionSpent = data.sessionSpent + spent
    end
    
    lastKnownGold = currentGold
    data.lastGold = currentGold
    
    self:UpdateDisplay()
end

-- Update display
function GoldTracker:UpdateDisplay()
    if not playerName or not self.db.global.characters[playerName] or not self.frame then return end
    
    local data = self.db.global.characters[playerName]
    
    self.frame.currentValue:SetText(self:FormatGold(currentGold))
    self.frame.characterName:SetText(playerName)
    self.frame.sessionEarned:SetText("Earned: " .. self:FormatGold(data.sessionEarned))
    self.frame.sessionSpent:SetText("Spent:  " .. self:FormatGold(data.sessionSpent))
    self.frame.totalEarned:SetText("Earned: " .. self:FormatGold(data.totalEarned))
    self.frame.totalSpent:SetText("Spent:  " .. self:FormatGold(data.totalSpent))
    
    -- Profit / Loss calculations
    local sessionNet = (data.sessionEarned or 0) - (data.sessionSpent or 0)
    local totalNet = (data.totalEarned or 0) - (data.totalSpent or 0)
    self.frame.sessionProfit:SetText("Net: " .. self:FormatProfit(sessionNet))
    self.frame.totalProfit:SetText("Net: " .. self:FormatProfit(totalNet))
    self:UpdateAccountSummary()
end

-- Update the account-wide character list and totals
function GoldTracker:UpdateAccountSummary()
    if not self.frame or not self.frame.accountRows then return end

    local characters = {}
    local accountGold = 0
    local accountNet = 0

    for name, data in pairs(self.db.global.characters) do
        local characterGold = data.lastGold or 0
        local characterNet = (data.totalEarned or 0) - (data.totalSpent or 0)

        table.insert(characters, {
            name = name,
            gold = characterGold,
            net = characterNet,
        })

        accountGold = accountGold + characterGold
        accountNet = accountNet + characterNet
    end

    table.sort(characters, function(a, b)
        return a.name < b.name
    end)

    self.frame.accountGold:SetText("Current Total: " .. self:FormatGold(accountGold))
    self.frame.accountNet:SetText("All-Time Net: " .. self:FormatProfit(accountNet))

    for _, row in ipairs(self.frame.accountRows) do
        row:Hide()
    end

    for index, character in ipairs(characters) do
        local row = self.frame.accountRows[index]
        if not row then
            row = CreateFrame("Frame", nil, self.frame.accountScrollChild)
            row:SetSize(365, 24)

            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints()

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(134)
            row.name:SetJustifyH("LEFT")

            row.gold = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.gold:SetPoint("LEFT", row, "LEFT", 140, 0)
            row.gold:SetWidth(110)
            row.gold:SetJustifyH("RIGHT")

            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.net:SetPoint("LEFT", row, "LEFT", 250, 0)
            row.net:SetWidth(115)
            row.net:SetJustifyH("RIGHT")

            self.frame.accountRows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame.accountScrollChild, "TOPLEFT", 0, -((index - 1) * 24))
        if character.name == playerName then
            row.background:SetColorTexture(0.55, 0.38, 0.08, 0.28)
            row.name:SetTextColor(1, 0.83, 0.35)
        elseif index % 2 == 0 then
            row.background:SetColorTexture(1, 1, 1, 0.035)
            row.name:SetTextColor(0.9, 0.9, 0.9)
        else
            row.background:SetColorTexture(0, 0, 0, 0)
            row.name:SetTextColor(0.9, 0.9, 0.9)
        end
        row.name:SetText(character.name)
        row.gold:SetText(self:FormatGold(character.gold))
        row.net:SetText(self:FormatProfit(character.net))
        row:Show()
    end

    self.frame.accountScrollChild:SetHeight(math.max(#characters * 24, 1))
end

-- Reset stats
function GoldTracker:ResetStats()
    if playerName and self.db.global.characters[playerName] then
        self.db.global.characters[playerName] = {
            totalEarned = 0,
            totalSpent = 0,
            sessionEarned = 0,
            sessionSpent = 0,
            lastGold = currentGold,
            firstLogin = false
        }
        self:UpdateDisplay()
        self:Print("Stats reset!")
    end
end

-- Logout handler
function GoldTracker:OnLogout()
    if playerName and self.db.global.characters[playerName] then
        self.db.global.characters[playerName].lastGold = currentGold
    end
end

-- Save the window anchor so it can be restored after reloads and logins
function GoldTracker:SaveWindowPosition()
    if not self.frame then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    if not point then return end

    local position = self.db.profile.window
    position.point = point
    position.relativePoint = relativePoint or point
    position.x = x or 0
    position.y = y or 0
end

-- Create the main window
function GoldTracker:CreateWindow()
    local frame = CreateFrame("Frame", "GoldTrackerFrame", UIParent, "BasicFrameTemplateWithInset")

    if not frame then
        self:Print("ERROR: CreateFrame returned nil!")
        return
    end

    local function CreateCard(parent)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        card:SetBackdropColor(0.025, 0.028, 0.04, 0.88)
        card:SetBackdropBorderColor(0.45, 0.34, 0.12, 0.9)
        return card
    end

    local function AddCardTitle(card, text)
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
        title:SetText("|cFFFFD36A" .. text .. "|r")

        local accent = card:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        accent:SetSize(42, 2)
        accent:SetColorTexture(0.95, 0.66, 0.12, 0.9)
        return title
    end

    frame:SetSize(800, 440)

    local position = self.db.profile.window
    frame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        position.x or 0,
        position.y or 0
    )
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        GoldTracker:SaveWindowPosition()
    end)
    frame:Hide()

    -- Make frame closable with ESC key
    table.insert(UISpecialFrames, "GoldTrackerFrame")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
    frame.title:SetText("|cFFFFD36AGold Tracker|r")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)

    -- Prominent current-character balance banner
    local balanceCard = CreateCard(content)
    balanceCard:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -4)
    balanceCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -4)
    balanceCard:SetHeight(64)
    balanceCard:SetBackdropColor(0.08, 0.065, 0.025, 0.9)
    balanceCard:SetBackdropBorderColor(0.72, 0.49, 0.12, 1)

    local coin = balanceCard:CreateTexture(nil, "ARTWORK")
    coin:SetPoint("LEFT", balanceCard, "LEFT", 15, 0)
    coin:SetSize(38, 38)
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local currentLabel = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentLabel:SetPoint("TOPLEFT", coin, "TOPRIGHT", 12, -1)
    currentLabel:SetText("CURRENT GOLD")
    currentLabel:SetTextColor(0.75, 0.68, 0.5)

    frame.currentValue = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.currentValue:SetPoint("TOPLEFT", currentLabel, "BOTTOMLEFT", 0, -4)

    frame.characterName = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.characterName:SetPoint("RIGHT", balanceCard, "RIGHT", -18, 0)
    frame.characterName:SetTextColor(0.75, 0.75, 0.75)

    -- Session card
    local sessionCard = CreateCard(content)
    sessionCard:SetPoint("TOPLEFT", balanceCard, "BOTTOMLEFT", 0, -12)
    sessionCard:SetSize(330, 105)
    local sessionTitle = AddCardTitle(sessionCard, "This Session")

    frame.sessionEarned = sessionCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionEarned:SetPoint("TOPLEFT", sessionTitle, "BOTTOMLEFT", 0, -13)

    frame.sessionSpent = sessionCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionSpent:SetPoint("TOPLEFT", frame.sessionEarned, "BOTTOMLEFT", 0, -5)

    frame.sessionProfit = sessionCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.sessionProfit:SetPoint("TOPLEFT", frame.sessionSpent, "BOTTOMLEFT", 0, -6)

    -- All-time card
    local totalCard = CreateCard(content)
    totalCard:SetPoint("TOPLEFT", sessionCard, "BOTTOMLEFT", 0, -10)
    totalCard:SetSize(330, 105)
    local totalTitle = AddCardTitle(totalCard, "All Time")

    frame.totalEarned = totalCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalEarned:SetPoint("TOPLEFT", totalTitle, "BOTTOMLEFT", 0, -13)

    frame.totalSpent = totalCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalSpent:SetPoint("TOPLEFT", frame.totalEarned, "BOTTOMLEFT", 0, -5)

    frame.totalProfit = totalCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalProfit:SetPoint("TOPLEFT", frame.totalSpent, "BOTTOMLEFT", 0, -6)

    local resetBtn = CreateFrame("Button", nil, content, "GameMenuButtonTemplate")
    resetBtn:SetPoint("BOTTOM", totalCard, "BOTTOM", 0, -39)
    resetBtn:SetSize(190, 28)
    resetBtn:SetText("Reset Character Stats")
    resetBtn:SetNormalFontObject("GameFontNormal")
    resetBtn:SetHighlightFontObject("GameFontHighlight")
    resetBtn:SetScript("OnClick", function()
        GoldTracker:ResetStats()
    end)

    -- Account-wide card
    local accountCard = CreateCard(content)
    accountCard:SetPoint("TOPLEFT", balanceCard, "BOTTOMLEFT", 342, -12)
    accountCard:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 10)
    local accountTitle = AddCardTitle(accountCard, "Account Overview")

    frame.accountGold = accountCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.accountGold:SetPoint("TOPLEFT", accountTitle, "BOTTOMLEFT", 0, -14)

    frame.accountNet = accountCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.accountNet:SetPoint("TOPLEFT", frame.accountGold, "BOTTOMLEFT", 0, -5)

    local accountSeparator = accountCard:CreateTexture(nil, "ARTWORK")
    accountSeparator:SetPoint("TOPLEFT", frame.accountNet, "BOTTOMLEFT", 0, -11)
    accountSeparator:SetPoint("RIGHT", accountCard, "RIGHT", -16, 0)
    accountSeparator:SetHeight(1)
    accountSeparator:SetColorTexture(0.45, 0.34, 0.12, 0.65)

    local characterHeader = accountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    characterHeader:SetPoint("TOPLEFT", accountSeparator, "BOTTOMLEFT", 6, -9)
    characterHeader:SetWidth(134)
    characterHeader:SetJustifyH("LEFT")
    characterHeader:SetText("CHARACTER")
    characterHeader:SetTextColor(0.65, 0.65, 0.65)

    local goldHeader = accountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldHeader:SetPoint("LEFT", characterHeader, "LEFT", 134, 0)
    goldHeader:SetWidth(110)
    goldHeader:SetJustifyH("RIGHT")
    goldHeader:SetText("CURRENT")
    goldHeader:SetTextColor(0.65, 0.65, 0.65)

    local netHeader = accountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    netHeader:SetPoint("LEFT", characterHeader, "LEFT", 244, 0)
    netHeader:SetWidth(115)
    netHeader:SetJustifyH("RIGHT")
    netHeader:SetText("NET")
    netHeader:SetTextColor(0.65, 0.65, 0.65)

    local accountScroll = CreateFrame("ScrollFrame", nil, accountCard, "UIPanelScrollFrameTemplate")
    accountScroll:SetPoint("TOPLEFT", characterHeader, "BOTTOMLEFT", -6, -7)
    accountScroll:SetPoint("BOTTOMRIGHT", accountCard, "BOTTOMRIGHT", -32, 12)

    local accountScrollChild = CreateFrame("Frame", nil, accountScroll)
    accountScrollChild:SetSize(365, 1)
    accountScroll:SetScrollChild(accountScrollChild)

    frame.accountScrollChild = accountScrollChild
    frame.accountRows = {}
    self.frame = frame
end

-- Toggle window
function GoldTracker:ToggleWindow()
    if not self.frame then
        self:Print("Error: Frame not created yet!")
        return
    end
    
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:HideMinimapTooltip()
        self.frame:Show()
        self.frame:Raise()
        self:UpdateDisplay()
    end
end
