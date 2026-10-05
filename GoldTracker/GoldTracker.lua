-- GoldTracker: A lightweight gold tracking addon using only Blizzard APIs
local addonName, GoldTracker = ...
GoldTracker = type(GoldTracker) == "table" and GoldTracker or {}
_G.GoldTracker = GoldTracker

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

local function CopyDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = type(value) == "table" and {} or value
        end
        if type(value) == "table" then
            CopyDefaults(target[key], value)
        end
    end
end

function GoldTracker:Print(message)
    print("|cFFFFD36AGoldTracker:|r " .. tostring(message))
end

local function GetDayKey(timestamp)
    return date("%Y-%m-%d", timestamp or time())
end

function GoldTracker:PruneHistory(data)
    if not data.history then return end
    local cutoff = GetDayKey(time() - (89 * 86400))
    for dayKey in pairs(data.history) do
        if dayKey < cutoff then
            data.history[dayKey] = nil
        end
    end
end

function GoldTracker:RecordDailyChange(data, diff, openingGold, closingGold)
    data.history = data.history or {}
    local dayKey = GetDayKey()
    local day = data.history[dayKey]
    if not day then
        day = {
            earned = 0,
            spent = 0,
            openingGold = openingGold or closingGold or 0,
            closingGold = closingGold or openingGold or 0,
        }
        data.history[dayKey] = day
    end

    if diff > 0 then
        day.earned = (day.earned or 0) + diff
    elseif diff < 0 then
        day.spent = (day.spent or 0) + math.abs(diff)
    end
    day.closingGold = closingGold or day.closingGold
    self:PruneHistory(data)
end

function GoldTracker:InitializeDatabase()
    GoldTrackerDB = GoldTrackerDB or {}

    -- Preserve data created by older AceDB-based releases.
    local legacyProfile
    if GoldTrackerDB.profiles then
        local profileKey = GoldTrackerDB.profileKeys and GoldTrackerDB.profileKeys[UnitName("player") .. " - " .. GetRealmName()]
        local _, firstProfile = next(GoldTrackerDB.profiles)
        legacyProfile = GoldTrackerDB.profiles[profileKey or "Default"] or firstProfile
    end

    GoldTrackerDB.profile = GoldTrackerDB.profile or legacyProfile or {}
    GoldTrackerDB.global = GoldTrackerDB.global or {}
    CopyDefaults(GoldTrackerDB, defaults)
    self.db = GoldTrackerDB
end

function GoldTracker:UpdateMinimapButtonPosition()
    if not self.minimapButton then return end
    local angle = math.rad(self.db.global.minimapAngle or 225)
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function GoldTracker:CreateMinimapButton()
    local button = CreateFrame("Button", "GoldTrackerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("CENTER")
    background:SetSize(22, 22)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("CENTER")
    texture:SetSize(20, 20)
    texture:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, mouseButton)
        GoldTracker:HideMinimapTooltip()
        if mouseButton == "LeftButton" then
            GoldTracker:ToggleWindow()
        else
            GoldTracker:ResetStats()
        end
    end)
    button:SetScript("OnEnter", function(anchor) GoldTracker:ShowMinimapTooltip(anchor) end)
    button:SetScript("OnLeave", function() GoldTracker:HideMinimapTooltip() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mapX, mapY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            GoldTracker.db.global.minimapAngle = math.deg(math.atan2(cursorY / scale - mapY, cursorX / scale - mapX))
            GoldTracker:UpdateMinimapButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

function GoldTracker:OnInitialize()
    self:InitializeDatabase()
    self:CreateMinimapButton()

    SLASH_GOLDTRACKER1 = "/goldtracker"
    SLASH_GOLDTRACKER2 = "/gt"
    SlashCmdList.GOLDTRACKER = function(input) GoldTracker:SlashCommand(input) end

    self:CreateWindow()
    C_Timer.After(0.5, function() self:InitCharacter() end)
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
            firstLogin = true,
            history = {},
        }
    end
    
    local data = self.db.global.characters[playerName]
    data.history = data.history or {}
    currentGold = GetMoney()
    
    -- On first login, just set the baseline without tracking
    if self.db.global.characters[playerName].firstLogin then
        self.db.global.characters[playerName].lastGold = currentGold
        self.db.global.characters[playerName].firstLogin = false
        lastKnownGold = currentGold
        self:RecordDailyChange(data, 0, currentGold, currentGold)
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
        self:RecordDailyChange(data, diff, lastKnownGold, currentGold)
        
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
    self:RecordDailyChange(data, diff, lastKnownGold, currentGold)
    
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

    local sortKey = self.accountSortKey or "name"
    local sortAscending = self.accountSortAscending ~= false
    table.sort(characters, function(a, b)
        local left, right = a[sortKey], b[sortKey]
        if left == right then
            return a.name < b.name
        end
        if sortAscending then
            return left < right
        end
        return left > right
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
    self:UpdateTrendDisplay()
end

function GoldTracker:GetAccountTrend(days)
    local totals = { earned = 0, spent = 0, daily = {} }
    for offset = days - 1, 0, -1 do
        local timestamp = time() - (offset * 86400)
        local dayKey = GetDayKey(timestamp)
        local dayTotal = { key = dayKey, timestamp = timestamp, earned = 0, spent = 0 }
        for _, character in pairs(self.db.global.characters) do
            local history = character.history
            local entry = history and history[dayKey]
            if entry then
                dayTotal.earned = dayTotal.earned + (entry.earned or 0)
                dayTotal.spent = dayTotal.spent + (entry.spent or 0)
            end
        end
        dayTotal.net = dayTotal.earned - dayTotal.spent
        totals.earned = totals.earned + dayTotal.earned
        totals.spent = totals.spent + dayTotal.spent
        table.insert(totals.daily, dayTotal)
    end
    totals.net = totals.earned - totals.spent
    return totals
end

function GoldTracker:UpdateTrendDisplay()
    if not self.frame or not self.frame.trendRows then return end

    local periods = {
        self:GetAccountTrend(1),
        self:GetAccountTrend(7),
        self:GetAccountTrend(30),
    }
    for index, totals in ipairs(periods) do
        local row = self.frame.trendRows[index]
        row.earned:SetText(self:FormatGold(totals.earned))
        row.spent:SetText(self:FormatGold(totals.spent))
        row.net:SetText(self:FormatProfit(totals.net))
    end

    local thirtyDays = periods[3]
    local bestNet
    local bestDay
    for _, day in ipairs(thirtyDays.daily) do
        if bestNet == nil or day.net > bestNet then
            bestNet = day.net
            bestDay = day.timestamp
        end
    end
    local average = math.floor(math.abs(thirtyDays.net) / 30)
    if thirtyDays.net < 0 then average = -average end
    self.frame.trendAverage:SetText("30-day daily average: " .. self:FormatProfit(average))
    self.frame.trendBest:SetText("Best day: " .. date("%b %d", bestDay or time()) .. "  " .. self:FormatProfit(bestNet or 0))

    local sevenDays = periods[2]
    local maximum = 1
    for _, day in ipairs(sevenDays.daily) do
        maximum = math.max(maximum, math.abs(day.net))
    end

    for index, day in ipairs(sevenDays.daily) do
        local bar = self.frame.trendBars[index]
        local height = math.max(1, (math.abs(day.net) / maximum) * 42)
        bar.fill:ClearAllPoints()
        bar.fill:SetHeight(height)
        if day.net >= 0 then
            bar.fill:SetPoint("BOTTOM", bar, "CENTER", 0, 0)
            bar.fill:SetColorTexture(0.15, 0.75, 0.28, 0.85)
        else
            bar.fill:SetPoint("TOP", bar, "CENTER", 0, 0)
            bar.fill:SetColorTexture(0.9, 0.2, 0.18, 0.85)
        end
        bar.day = day
        bar.label:SetText(date("%a", day.timestamp):sub(1, 1))
    end
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
            firstLogin = false,
            history = {},
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
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetScript("OnShow", function(self) self:Raise() end)
    frame:SetScript("OnMouseDown", function(self) self:Raise() end)
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

    local function CreateViewButton(label, x)
        local button = CreateFrame("Button", nil, accountCard)
        button:SetPoint("TOPRIGHT", accountCard, "TOPRIGHT", x, -8)
        button:SetSize(66, 24)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetAllPoints()
        button.label:SetText(label)
        button:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.83, 0.35) end)
        button:SetScript("OnLeave", function() GoldTracker:UpdateAccountViewButtons() end)
        return button
    end

    frame.summaryViewButton = CreateViewButton("SUMMARY", -78)
    frame.trendsViewButton = CreateViewButton("TRENDS", -10)
    frame.summaryViewButton:SetScript("OnClick", function() GoldTracker:ShowAccountView("summary") end)
    frame.trendsViewButton:SetScript("OnClick", function() GoldTracker:ShowAccountView("trends") end)

    frame.accountGold = accountCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.accountGold:SetPoint("TOPLEFT", accountTitle, "BOTTOMLEFT", 0, -14)

    frame.accountNet = accountCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.accountNet:SetPoint("TOPLEFT", frame.accountGold, "BOTTOMLEFT", 0, -5)

    local accountSeparator = accountCard:CreateTexture(nil, "ARTWORK")
    accountSeparator:SetPoint("TOPLEFT", frame.accountNet, "BOTTOMLEFT", 0, -11)
    accountSeparator:SetPoint("RIGHT", accountCard, "RIGHT", -16, 0)
    accountSeparator:SetHeight(1)
    accountSeparator:SetColorTexture(0.45, 0.34, 0.12, 0.65)

    local function CreateSortHeader(x, width, label, sortKey, justify)
        local button = CreateFrame("Button", nil, accountCard)
        button:SetPoint("TOPLEFT", accountSeparator, "BOTTOMLEFT", 6 + x, -9)
        button:SetSize(width, 20)

        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetAllPoints()
        button.label:SetJustifyH(justify)
        button.label:SetText(label)
        button.label:SetTextColor(0.65, 0.65, 0.65)

        button:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.83, 0.35) end)
        button:SetScript("OnLeave", function(self)
            if GoldTracker.accountSortKey ~= sortKey then
                self.label:SetTextColor(0.65, 0.65, 0.65)
            end
        end)
        button:SetScript("OnClick", function()
            if GoldTracker.accountSortKey == sortKey then
                GoldTracker.accountSortAscending = not GoldTracker.accountSortAscending
            else
                GoldTracker.accountSortKey = sortKey
                GoldTracker.accountSortAscending = sortKey == "name"
            end
            GoldTracker:UpdateSortHeaders()
            GoldTracker:UpdateAccountSummary()
        end)
        return button
    end

    frame.characterHeader = CreateSortHeader(0, 134, "CHARACTER", "name", "LEFT")
    frame.goldHeader = CreateSortHeader(134, 110, "CURRENT", "gold", "RIGHT")
    frame.netHeader = CreateSortHeader(244, 115, "NET", "net", "RIGHT")
    local characterHeader = frame.characterHeader

    local accountScroll = CreateFrame("ScrollFrame", nil, accountCard, "UIPanelScrollFrameTemplate")
    accountScroll:SetPoint("TOPLEFT", characterHeader, "BOTTOMLEFT", -6, -7)
    accountScroll:SetPoint("BOTTOMRIGHT", accountCard, "BOTTOMRIGHT", -32, 12)

    local accountScrollChild = CreateFrame("Frame", nil, accountScroll)
    accountScrollChild:SetSize(365, 1)
    accountScroll:SetScrollChild(accountScrollChild)

    local trendFrame = CreateFrame("Frame", nil, accountCard)
    trendFrame:SetPoint("TOPLEFT", accountCard, "TOPLEFT", 14, -46)
    trendFrame:SetPoint("BOTTOMRIGHT", accountCard, "BOTTOMRIGHT", -14, 10)
    trendFrame:Hide()

    local headers = { "PERIOD", "EARNED", "SPENT", "NET" }
    local headerX = { 0, 68, 164, 260 }
    local headerWidths = { 66, 94, 94, 105 }
    for index, label in ipairs(headers) do
        local header = trendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", trendFrame, "TOPLEFT", headerX[index], 0)
        header:SetWidth(headerWidths[index])
        header:SetJustifyH(index == 1 and "LEFT" or "RIGHT")
        header:SetText(label)
        header:SetTextColor(0.65, 0.65, 0.65)
    end

    frame.trendRows = {}
    local periodLabels = { "Today", "7 Days", "30 Days" }
    for index, periodLabel in ipairs(periodLabels) do
        local row = CreateFrame("Frame", nil, trendFrame)
        row:SetPoint("TOPLEFT", trendFrame, "TOPLEFT", 0, -(15 + ((index - 1) * 22)))
        row:SetSize(369, 20)

        row.period = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.period:SetPoint("LEFT")
        row.period:SetWidth(66)
        row.period:SetJustifyH("LEFT")
        row.period:SetText(periodLabel)

        local function AddTrendValue(x, width)
            local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetPoint("LEFT", row, "LEFT", x, 0)
            value:SetWidth(width)
            value:SetJustifyH("RIGHT")
            return value
        end
        row.earned = AddTrendValue(68, 94)
        row.spent = AddTrendValue(164, 94)
        row.net = AddTrendValue(260, 105)
        frame.trendRows[index] = row
    end

    local trendSeparator = trendFrame:CreateTexture(nil, "ARTWORK")
    trendSeparator:SetPoint("TOPLEFT", trendFrame, "TOPLEFT", 0, -82)
    trendSeparator:SetPoint("RIGHT", trendFrame, "RIGHT", 0, 0)
    trendSeparator:SetHeight(1)
    trendSeparator:SetColorTexture(0.45, 0.34, 0.12, 0.65)

    frame.trendAverage = trendFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.trendAverage:SetPoint("TOPLEFT", trendSeparator, "BOTTOMLEFT", 0, -7)
    frame.trendBest = trendFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.trendBest:SetPoint("TOPRIGHT", trendSeparator, "BOTTOMRIGHT", 0, -7)

    local chartTitle = trendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chartTitle:SetPoint("TOPLEFT", trendSeparator, "BOTTOMLEFT", 0, -28)
    chartTitle:SetText("7-DAY NET")
    chartTitle:SetTextColor(0.75, 0.68, 0.5)

    local chart = CreateFrame("Frame", nil, trendFrame)
    chart:SetPoint("TOPLEFT", chartTitle, "BOTTOMLEFT", 0, -5)
    chart:SetPoint("BOTTOMRIGHT", trendFrame, "BOTTOMRIGHT", 0, 12)

    local zeroLine = chart:CreateTexture(nil, "ARTWORK")
    zeroLine:SetPoint("LEFT", chart, "LEFT", 0, -2)
    zeroLine:SetPoint("RIGHT", chart, "RIGHT", 0, -2)
    zeroLine:SetHeight(1)
    zeroLine:SetColorTexture(0.5, 0.5, 0.5, 0.45)

    frame.trendBars = {}
    for index = 1, 7 do
        local bar = CreateFrame("Frame", nil, chart)
        bar:SetSize(42, 94)
        bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 13 + ((index - 1) * 50), 0)
        bar:EnableMouse(true)

        bar.fill = bar:CreateTexture(nil, "ARTWORK")
        bar.fill:SetWidth(25)

        bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.label:SetPoint("TOP", bar, "BOTTOM", 0, 7)
        bar.label:SetTextColor(0.65, 0.65, 0.65)

        bar:SetScript("OnEnter", function(self)
            if not self.day then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(date("%A, %b %d", self.day.timestamp), 1, 0.83, 0.35)
            GameTooltip:AddDoubleLine("Earned", GoldTracker:FormatGold(self.day.earned), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Spent", GoldTracker:FormatGold(self.day.spent), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Net", GoldTracker:FormatProfit(self.day.net), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:Show()
        end)
        bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.trendBars[index] = bar
    end

    frame.accountScrollChild = accountScrollChild
    frame.accountRows = {}
    frame.accountTrendFrame = trendFrame
    frame.accountSummaryWidgets = {
        frame.accountGold, frame.accountNet, accountSeparator, characterHeader,
        frame.goldHeader, frame.netHeader, accountScroll,
    }
    self.frame = frame
    self.accountView = "summary"
    self.accountSortKey = self.accountSortKey or "name"
    if self.accountSortAscending == nil then self.accountSortAscending = true end
    self:UpdateSortHeaders()
    self:ShowAccountView("summary")
end

function GoldTracker:UpdateSortHeaders()
    if not self.frame then return end

    -- ASCII carets render reliably in every supported WoW client font.
    local arrow = self.accountSortAscending and " ^" or " v"
    local headers = {
        { button = self.frame.characterHeader, key = "name", label = "CHARACTER" },
        { button = self.frame.goldHeader, key = "gold", label = "CURRENT" },
        { button = self.frame.netHeader, key = "net", label = "NET" },
    }
    for _, header in ipairs(headers) do
        local active = self.accountSortKey == header.key
        header.button.label:SetText(header.label .. (active and arrow or ""))
        header.button.label:SetTextColor(active and 1 or 0.65, active and 0.83 or 0.65, active and 0.35 or 0.65)
    end
end

function GoldTracker:UpdateAccountViewButtons()
    if not self.frame then return end
    local summaryActive = self.accountView == "summary"
    self.frame.summaryViewButton.label:SetTextColor(summaryActive and 1 or 0.55, summaryActive and 0.83 or 0.55, summaryActive and 0.35 or 0.55)
    self.frame.trendsViewButton.label:SetTextColor(not summaryActive and 1 or 0.55, not summaryActive and 0.83 or 0.55, not summaryActive and 0.35 or 0.55)
end

function GoldTracker:ShowAccountView(view)
    if not self.frame then return end
    self.accountView = view == "trends" and "trends" or "summary"
    local showSummary = self.accountView == "summary"
    for _, widget in ipairs(self.frame.accountSummaryWidgets) do
        if showSummary then widget:Show() else widget:Hide() end
    end
    if showSummary then
        self.frame.accountTrendFrame:Hide()
    else
        self.frame.accountTrendFrame:Show()
        self:UpdateTrendDisplay()
    end
    self:UpdateAccountViewButtons()
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        GoldTracker:OnInitialize()
    elseif event == "PLAYER_MONEY" then
        GoldTracker:UpdateGold()
    elseif event == "PLAYER_LOGOUT" then
        GoldTracker:OnLogout()
    end
end)
