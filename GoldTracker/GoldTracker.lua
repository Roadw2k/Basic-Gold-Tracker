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
    icon = "Interface\\MoneyFrame\\UI-GoldIcon",
    OnClick = function(clickedframe, button)
        if button == "LeftButton" then
            GoldTracker:ToggleWindow()
        elseif button == "RightButton" then
            GoldTracker:ResetStats()
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        tooltip:AddLine("Gold Tracker")
        tooltip:AddLine("|cFFFFFFFFLeft-click|r to toggle window", 0.8, 0.8, 0.8)
        tooltip:AddLine("|cFFFFFFFFRight-click|r to reset stats", 0.8, 0.8, 0.8)

        -- Add quick snapshot if player is initialized
        if playerName and GoldTracker.db and GoldTracker.db.global.characters[playerName] then
            local d = GoldTracker.db.global.characters[playerName]
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFDAA520Session|r")
            tooltip:AddLine("  Earned: " .. GoldTracker:FormatGold(d.sessionEarned))
            tooltip:AddLine("  Spent:  " .. GoldTracker:FormatGold(d.sessionSpent))
            tooltip:AddLine("  Net:    " .. GoldTracker:FormatProfit(d.sessionEarned - d.sessionSpent))

            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFDAA520All Time|r")
            tooltip:AddLine("  Earned: " .. GoldTracker:FormatGold(d.totalEarned))
            tooltip:AddLine("  Spent:  " .. GoldTracker:FormatGold(d.totalSpent))
            tooltip:AddLine("  Net:    " .. GoldTracker:FormatProfit(d.totalEarned - d.totalSpent))
        end
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
    self:Print("Slash command received: " .. (input or "empty"))
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
    
    self:Print("Loaded! Type /goldtracker or /gt to open, or click the minimap button.")
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
    self.frame.sessionEarned:SetText("Earned: " .. self:FormatGold(data.sessionEarned))
    self.frame.sessionSpent:SetText("Spent:  " .. self:FormatGold(data.sessionSpent))
    self.frame.totalEarned:SetText("Earned: " .. self:FormatGold(data.totalEarned))
    self.frame.totalSpent:SetText("Spent:  " .. self:FormatGold(data.totalSpent))
    
    -- Profit / Loss calculations
    local sessionNet = (data.sessionEarned or 0) - (data.sessionSpent or 0)
    local totalNet = (data.totalEarned or 0) - (data.totalSpent or 0)
    self.frame.sessionProfit:SetText("Net: " .. self:FormatProfit(sessionNet))
    self.frame.totalProfit:SetText("Net: " .. self:FormatProfit(totalNet))
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

-- Create the main window
function GoldTracker:CreateWindow()
    self:Print("CreateWindow function started")
    
    local frame = CreateFrame("Frame", "GoldTrackerFrame", UIParent, "BasicFrameTemplateWithInset")
    
    if not frame then
        self:Print("ERROR: CreateFrame returned nil!")
        return
    end
    
    self:Print("Frame created, setting properties...")
    
    frame:SetSize(420, 320)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Make frame closable with ESC key
    table.insert(UISpecialFrames, "GoldTrackerFrame")
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
    frame.title:SetText("Gold Tracker")
    
    -- Create content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    
    -- Current gold display
    local currentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    currentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -6)
    currentLabel:SetText("Current Gold:")
    
    frame.currentValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.currentValue:SetPoint("LEFT", currentLabel, "RIGHT", 8, 0)
    
    -- Session stats block (left)
    local sessionTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionTitle:SetPoint("TOPLEFT", currentLabel, "BOTTOMLEFT", 0, -18)
    sessionTitle:SetText("|cFFDAA520This Session|r")
    
    frame.sessionEarned = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionEarned:SetPoint("TOPLEFT", sessionTitle, "BOTTOMLEFT", 0, -6)
    
    frame.sessionSpent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionSpent:SetPoint("TOPLEFT", frame.sessionEarned, "BOTTOMLEFT", 0, -4)
    
    frame.sessionProfit = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.sessionProfit:SetPoint("TOPLEFT", frame.sessionSpent, "BOTTOMLEFT", 0, -6)
    
    -- Separator line
    local sep = content:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", frame.sessionProfit, "BOTTOMLEFT", -4, -8)
    sep:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -132)
    sep:SetHeight(2)
    sep:SetTexture(0.15, 0.15, 0.15, 0.9)
    
    -- Total stats block (below)
    local totalTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalTitle:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -12)
    totalTitle:SetText("|cFFDAA520All Time|r")
    
    frame.totalEarned = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalEarned:SetPoint("TOPLEFT", totalTitle, "BOTTOMLEFT", 0, -6)
    
    frame.totalSpent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalSpent:SetPoint("TOPLEFT", frame.totalEarned, "BOTTOMLEFT", 0, -4)
    
    frame.totalProfit = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalProfit:SetPoint("TOPLEFT", frame.totalSpent, "BOTTOMLEFT", 0, -6)
    
    -- Reset button
    local resetBtn = CreateFrame("Button", nil, content, "GameMenuButtonTemplate")
    resetBtn:SetPoint("BOTTOM", content, "BOTTOM", 0, 10)
    resetBtn:SetSize(140, 26)
    resetBtn:SetText("Reset Stats")
    resetBtn:SetNormalFontObject("GameFontNormal")
    resetBtn:SetHighlightFontObject("GameFontHighlight")
    resetBtn:SetScript("OnClick", function()
        GoldTracker:ResetStats()
    end)
    
    self.frame = frame
    self:Print("Frame stored in self.frame")
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
        self:UpdateDisplay()
        self.frame:Show()
    end
end
