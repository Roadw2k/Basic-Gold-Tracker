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

-- Helper function to format gold
function GoldTracker:FormatGold(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local bronze = copper % 100
    
    return string.format("|cFFFFD700%dg|r |cFFC7C7CF%ds|r |cFFB87333%dc|r", gold, silver, bronze)
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
    self.frame.sessionSpent:SetText("Spent: " .. self:FormatGold(data.sessionSpent))
    self.frame.totalEarned:SetText("Earned: " .. self:FormatGold(data.totalEarned))
    self.frame.totalSpent:SetText("Spent: " .. self:FormatGold(data.totalSpent))
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
    
    frame:SetSize(400, 300)
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
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    
    -- Current gold display
    local currentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    currentLabel:SetPoint("TOP", content, "TOP", 0, -10)
    currentLabel:SetText("Current Gold:")
    
    frame.currentValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.currentValue:SetPoint("TOP", currentLabel, "BOTTOM", 0, -5)
    
    -- Session stats
    local sessionLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sessionLabel:SetPoint("TOP", frame.currentValue, "BOTTOM", 0, -20)
    sessionLabel:SetText("This Session:")
    
    frame.sessionEarned = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionEarned:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -5)
    
    frame.sessionSpent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.sessionSpent:SetPoint("TOPLEFT", frame.sessionEarned, "BOTTOMLEFT", 0, -2)
    
    -- Total stats
    local totalLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    totalLabel:SetPoint("TOP", frame.sessionSpent, "BOTTOM", 0, -20)
    totalLabel:SetText("All Time:")
    
    frame.totalEarned = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalEarned:SetPoint("TOPLEFT", totalLabel, "BOTTOMLEFT", 0, -5)
    
    frame.totalSpent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.totalSpent:SetPoint("TOPLEFT", frame.totalEarned, "BOTTOMLEFT", 0, -2)
    
    -- Reset button
    local resetBtn = CreateFrame("Button", nil, content, "GameMenuButtonTemplate")
    resetBtn:SetPoint("BOTTOM", content, "BOTTOM", 0, 10)
    resetBtn:SetSize(120, 25)
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