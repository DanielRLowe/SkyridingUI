--[[
    SkyridingUI - Horizontal Bars Module
    Displays Skyriding data as horizontal status bars (the "Bars" UI mode).
    
    This module handles:
    - Speed bar (green/blue with Thrill buff)
    - Charge bars (6 purple bars for ability charges)
    - Acceleration bar (red/green based on accel/decel)
    - Whirling Surge bar (countdown timer)
    - Second Wind bars (3 small bars above frame)
]]

local addonName, addon = ...
local SUI = SkyridingUI

--------------------------------------------------------------------------------
-- Constants (shared with main file via SUI)
--------------------------------------------------------------------------------

local ASCENT_SPELL_ID = 372610
local THRILL_BUFF_ID = 377234
local WHIRLING_SURGE_ID = 361584
local SECOND_WIND_ID = 425782
local MAX_PASSIVE_GLIDE_SPEED = 65
local ASCENT_DURATION = 3.5
local MAX_UNBOOSTED_SPEED = 789  -- Max speed % without ability boosts (non-Dragonflight zones)

-- Skyriding ability spell IDs
local SKYRIDING_ABILITIES = {
    [372610] = "Skyward Ascent",
    [361584] = "Surge Forward",
}

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local mainFrame
local speedBar, speedText, speedMaxMarker
local accelBar, surgBar
local chargeBars = {}
local chargeBarBgs = {}
local secondWindBars = {}
local secondWindBgs = {}
local mainBg

--------------------------------------------------------------------------------
-- Default Settings (horizontal-specific)
--------------------------------------------------------------------------------

local defaults = {
    barPadding = 5,
    chargeBarPadding = 0,
    secondWindBarPadding = 3,
    speedBarWidth = 390,
    speedBarHeight = 20,
    chargeBarWidth = 390,
    chargeBarHeight = 15,
    accelBarWidth = 390,
    accelBarHeight = 15,
    surgeBarWidth = 390,
    surgeBarHeight = 15,
    secondWindBarWidth = 60,
    secondWindBarHeight = 6,
    showBackground = false,
    backgroundOpacity = 0.5,
    showChargeBarBg = true,
    chargeBarBgOpacity = 0.8,
    chargeColorFull = {0.7, 0, 0.9, 1},
    chargeColorCharging = {0.5, 0, 0.7, 0.8},
    chargeColorEmpty = {0.3, 0, 0.5, 0.6},
    showSpeedBar = true,
    showChargeBars = true,
    showAccelBar = true,
    showSurgeBar = true,
    showSecondWindBars = true,
    showSpeedMaxMarker = true,
    maxSpeedMarkerAlwaysVisible = false,
}

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

local function CreateHorizontalFrame()
    if mainFrame then return mainFrame end
    
    mainFrame = CreateFrame("Frame", "SkyridingUIMainFrame", UIParent)
    mainFrame:SetSize(400, 85)
    mainFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(false)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()
    
    -- Main frame background
    mainBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    mainBg:SetPoint("TOP", mainFrame, "TOP", 0, 0)
    mainBg:SetColorTexture(0, 0, 0, 0.5)
    mainBg:Hide()
    
    -- Drag functionality
    mainFrame:SetScript("OnDragStart", function(self)
        if not SkyridingUIDB.locked then
            self:StartMoving()
        end
    end)
    
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOffset, yOffset = self:GetPoint()
        SkyridingUIDB.point = point
        SkyridingUIDB.relativePoint = relativePoint
        SkyridingUIDB.xOffset = xOffset
        SkyridingUIDB.yOffset = yOffset
    end)
    
    -- Speed bar (top bar - green)
    speedBar = CreateFrame("StatusBar", nil, mainFrame)
    speedBar:SetSize(390, 20)
    speedBar:SetPoint("TOP", mainFrame, "TOP", 0, 0)
    speedBar:SetMinMaxValues(0, 100)
    speedBar:SetValue(0)
    speedBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    speedBar:GetStatusBarTexture():SetHorizTile(false)
    speedBar:SetStatusBarColor(0, 0.8, 0, 1)
    
    -- Speed text
    speedText = speedBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    speedText:SetPoint("CENTER")
    speedText:SetText("0")

    -- Max unboosted speed marker (vertical white line at 789%)
    speedMaxMarker = speedBar:CreateTexture(nil, "BACKGROUND")
    speedMaxMarker:SetColorTexture(1, 1, 1, 1)
    speedMaxMarker:SetSize(2, 20)
    local markerOffset = (MAX_UNBOOSTED_SPEED / 1200) * 390
    speedMaxMarker:SetPoint("RIGHT", speedBar, "LEFT", markerOffset, 0)

    -- Charge bars (6 bars for charges)
    local totalBarWidth = 390
    local chargeBarWidth = totalBarWidth / 6
    local chargeBarHeight = 15
    local startX = -totalBarWidth / 2
    
    for i = 1, 6 do
        local bar = CreateFrame("StatusBar", nil, mainFrame)
        bar:SetSize(chargeBarWidth, chargeBarHeight)
        bar:SetPoint("TOPLEFT", mainFrame, "TOP", startX + ((i - 1) * chargeBarWidth), -25)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:GetStatusBarTexture():SetHorizTile(false)
        bar:SetStatusBarColor(0.7, 0, 0.9, 1)
        
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        chargeBarBgs[i] = barBg
        
        chargeBars[i] = bar
    end
    
    -- Acceleration indicator
    accelBar = CreateFrame("StatusBar", nil, mainFrame)
    accelBar:SetSize(390, 15)
    accelBar:SetPoint("TOP", mainFrame, "TOP", 0, -45)
    accelBar:SetMinMaxValues(0, 1)
    accelBar:SetValue(0)
    accelBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    accelBar:GetStatusBarTexture():SetHorizTile(false)
    accelBar:SetStatusBarColor(0, 0.8, 0, 1)
    
    -- Whirling Surge cooldown bar
    surgBar = CreateFrame("StatusBar", nil, mainFrame)
    surgBar:SetSize(390, 15)
    surgBar:SetPoint("TOP", mainFrame, "TOP", 0, -65)
    surgBar:SetMinMaxValues(0, 1)
    surgBar:SetValue(0)
    surgBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    surgBar:GetStatusBarTexture():SetHorizTile(false)
    surgBar:GetStatusBarTexture():SetRotation(math.pi)
    surgBar:SetStatusBarColor(0.4, 0.8, 0.4, 1)
    surgBar:Hide()
    
    local surgLabel = surgBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    surgLabel:SetPoint("CENTER")
    surgLabel:SetText("Whirling Surge")
    surgLabel:SetTextColor(1, 1, 1, 0.9)
    
    -- Second Wind bars (3 thin bars above the main frame)
    local windBarWidth = 60
    local windBarHeight = 6
    local windBarSpacing = 3
    local totalWindWidth = (windBarWidth * 3) + (windBarSpacing * 2)
    local windStartX = -totalWindWidth / 2
    
    for i = 1, 3 do
        local bar = CreateFrame("StatusBar", nil, mainFrame)
        bar:SetSize(windBarWidth, windBarHeight)
        bar:SetPoint("BOTTOMLEFT", mainFrame, "TOP", windStartX + ((i - 1) * (windBarWidth + windBarSpacing)), 5)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:GetStatusBarTexture():SetHorizTile(false)
        bar:SetStatusBarColor(0.7, 0.5, 0.9, 1)
        
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.2, 0.1, 0.3, 0.8)
        secondWindBgs[i] = barBg
        
        secondWindBars[i] = bar
    end
    
    -- Store references in SUI for external access
    SUI.mainFrame = mainFrame
    SUI.mainBg = mainBg
    SUI.speedBar = speedBar
    SUI.speedText = speedText
    SUI.accelBar = accelBar
    SUI.surgBar = surgBar
    SUI.chargeBars = chargeBars
    SUI.chargeBarBgs = chargeBarBgs
    SUI.secondWindBars = secondWindBars
    SUI.secondWindBgs = secondWindBgs
    
    return mainFrame
end

--------------------------------------------------------------------------------
-- Layout Management
--------------------------------------------------------------------------------

local function UpdateLayout()
    if not mainFrame then return end
    
    local yOffset = 0
    local totalHeight = 0
    local padding = SkyridingUIDB.barPadding or defaults.barPadding
    
    -- Get individual bar dimensions
    local speedW = SkyridingUIDB.speedBarWidth or defaults.speedBarWidth
    local speedH = SkyridingUIDB.speedBarHeight or defaults.speedBarHeight
    local chargeW = SkyridingUIDB.chargeBarWidth or defaults.chargeBarWidth
    local chargeH = SkyridingUIDB.chargeBarHeight or defaults.chargeBarHeight
    local accelW = SkyridingUIDB.accelBarWidth or defaults.accelBarWidth
    local accelH = SkyridingUIDB.accelBarHeight or defaults.accelBarHeight
    local surgeW = SkyridingUIDB.surgeBarWidth or defaults.surgeBarWidth
    local surgeH = SkyridingUIDB.surgeBarHeight or defaults.surgeBarHeight
    local windW = SkyridingUIDB.secondWindBarWidth or defaults.secondWindBarWidth
    local windH = SkyridingUIDB.secondWindBarHeight or defaults.secondWindBarHeight
    
    -- Update bar sizes
    speedBar:SetSize(speedW, speedH)
    accelBar:SetSize(accelW, accelH)
    surgBar:SetSize(surgeW, surgeH)

    -- Update max speed marker position and height
    speedMaxMarker:SetSize(2, speedH)
    speedMaxMarker:ClearAllPoints()
    local markerOffset = (MAX_UNBOOSTED_SPEED / 1200) * speedW
    speedMaxMarker:SetPoint("RIGHT", speedBar, "LEFT", markerOffset, 0)

    -- Scale speed bar font based on bar height
    local baseFontSize = 14
    local baseHeight = 20
    local scaledFontSize = math.max(8, math.min(32, math.floor(baseFontSize * (speedH / baseHeight))))
    speedText:SetFont("Fonts\\FRIZQT__.TTF", scaledFontSize, "OUTLINE")
    
    -- Update charge bar sizes
    local chargePadding = SkyridingUIDB.chargeBarPadding or 0
    local totalChargePadding = chargePadding * 5  -- 5 gaps between 6 bars
    local chargeBarWidth = (chargeW - totalChargePadding) / 6
    for i = 1, 6 do
        chargeBars[i]:SetSize(chargeBarWidth, chargeH)
    end
    
    -- Update Second Wind bar sizes
    local windSpacing = SkyridingUIDB.secondWindBarPadding or 3
    local totalWindWidth = (windW * 3) + (windSpacing * 2)
    local windStartX = -totalWindWidth / 2
    for i = 1, 3 do
        secondWindBars[i]:SetSize(windW, windH)
        secondWindBars[i]:ClearAllPoints()
        secondWindBars[i]:SetPoint("BOTTOMLEFT", mainFrame, "TOP", windStartX + ((i - 1) * (windW + windSpacing)), 5)
    end
    
    -- Speed bar
    if SkyridingUIDB.showSpeedBar ~= false then
        speedBar:ClearAllPoints()
        speedBar:SetPoint("TOP", mainFrame, "TOP", 0, -yOffset)
        speedBar:Show()
        yOffset = yOffset + speedH + padding
        totalHeight = totalHeight + speedH + padding
    else
        speedBar:Hide()
    end

    -- Speed max marker visibility and draw layer
    if SkyridingUIDB.showSpeedBar ~= false and SkyridingUIDB.showSpeedMaxMarker ~= false then
        speedMaxMarker:Show()
        -- Set draw layer based on always visible setting
        if SkyridingUIDB.maxSpeedMarkerAlwaysVisible then
            speedMaxMarker:SetDrawLayer("OVERLAY")
        else
            speedMaxMarker:SetDrawLayer("BACKGROUND")
        end
    else
        speedMaxMarker:Hide()
    end
    
    -- Charge bars
    if SkyridingUIDB.showChargeBars ~= false then
        local startX = -chargeW / 2
        for i = 1, 6 do
            chargeBars[i]:ClearAllPoints()
            chargeBars[i]:SetPoint("TOPLEFT", mainFrame, "TOP", startX + ((i - 1) * (chargeBarWidth + chargePadding)), -yOffset)
            chargeBars[i]:Show()
        end
        yOffset = yOffset + chargeH + padding
        totalHeight = totalHeight + chargeH + padding
    else
        for i = 1, 6 do
            chargeBars[i]:Hide()
        end
    end
    
    -- Acceleration bar
    if SkyridingUIDB.showAccelBar ~= false then
        accelBar:ClearAllPoints()
        accelBar:SetPoint("TOP", mainFrame, "TOP", 0, -yOffset)
        accelBar:Show()
        yOffset = yOffset + accelH + padding
        totalHeight = totalHeight + accelH + padding
    else
        accelBar:Hide()
    end
    
    -- Whirling Surge bar
    surgBar:ClearAllPoints()
    surgBar:SetPoint("TOP", mainFrame, "TOP", 0, -yOffset)
    if SkyridingUIDB.showSurgeBar ~= false then
        yOffset = yOffset + surgeH + padding
        totalHeight = totalHeight + surgeH + padding
    else
        surgBar:Hide()
    end
    
    -- Second Wind bars
    if SkyridingUIDB.showSecondWindBars ~= false then
        for i = 1, 3 do
            secondWindBars[i]:Show()
        end
    else
        for i = 1, 3 do
            secondWindBars[i]:Hide()
        end
    end
    
    -- Update main frame height
    mainFrame:SetHeight(math.max(20, totalHeight))
    
    -- Calculate max width for background
    local maxWidth = 0
    if SkyridingUIDB.showSpeedBar ~= false then maxWidth = math.max(maxWidth, speedW) end
    if SkyridingUIDB.showChargeBars ~= false then maxWidth = math.max(maxWidth, chargeW) end
    if SkyridingUIDB.showAccelBar ~= false then maxWidth = math.max(maxWidth, accelW) end
    if SkyridingUIDB.showSurgeBar ~= false then maxWidth = math.max(maxWidth, surgeW) end
    
    -- Update background size
    local bgPadding = 5
    local bgWidth = maxWidth + (bgPadding * 2)
    local bgHeight = totalHeight + bgPadding
    mainBg:SetSize(bgWidth, bgHeight)
end

--------------------------------------------------------------------------------
-- Settings Application
--------------------------------------------------------------------------------

local function ApplyHorizontalSettings()
    if not mainFrame then
        CreateHorizontalFrame()
    end
    
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint(
        SkyridingUIDB.point or "TOP",
        UIParent,
        SkyridingUIDB.relativePoint or "TOP",
        SkyridingUIDB.xOffset or 0,
        SkyridingUIDB.yOffset or -100
    )
    mainFrame:SetScale(SkyridingUIDB.scale or 1.0)
    
    if SkyridingUIDB.locked then
        mainFrame:EnableMouse(false)
    else
        mainFrame:EnableMouse(true)
    end
    
    -- Apply main background settings
    if SkyridingUIDB.showBackground then
        mainBg:SetColorTexture(0, 0, 0, SkyridingUIDB.backgroundOpacity or defaults.backgroundOpacity)
        mainBg:Show()
    else
        mainBg:Hide()
    end
    
    -- Apply charge bar background settings
    for i = 1, 6 do
        if chargeBarBgs[i] then
            if SkyridingUIDB.showChargeBarBg ~= false and SkyridingUIDB.showChargeBars ~= false then
                chargeBarBgs[i]:SetColorTexture(0.15, 0.15, 0.15, SkyridingUIDB.chargeBarBgOpacity or defaults.chargeBarBgOpacity)
                chargeBarBgs[i]:Show()
            else
                chargeBarBgs[i]:Hide()
            end
        end
    end
    
    UpdateLayout()
end

--------------------------------------------------------------------------------
-- Update Functions
--------------------------------------------------------------------------------

local function UpdateChargeDisplay()
    local chargeData = {}
    local individualCharges = {}
    
    for spellID, name in pairs(SKYRIDING_ABILITIES) do
        if IsSpellKnown(spellID) then
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            if chargeInfo then
                local currentCharges = chargeInfo.currentCharges
                local maxCharges = chargeInfo.maxCharges
                local cooldownStart = chargeInfo.cooldownStartTime
                local cooldownDuration = chargeInfo.cooldownDuration
                
                if currentCharges and maxCharges then
                    for i = 1, maxCharges do
                        table.insert(individualCharges, {
                            isFull = i <= currentCharges,
                            cooldownStart = cooldownStart,
                            cooldownDuration = cooldownDuration,
                            spellID = spellID,
                            chargeIndex = i,
                            totalCharges = currentCharges,
                            maxCharges = maxCharges
                        })
                    end
                end
            end
        end
    end
    
    if #individualCharges > 0 then
        chargeData = individualCharges
    else
        for i = 1, 6 do
            table.insert(chargeData, {
                isFull = false,
                cooldownStart = 0,
                cooldownDuration = 0,
                spellID = nil,
                chargeIndex = i
            })
        end
    end
    
    SUI.abilityCharges = chargeData
    
    -- Update bar display
    for i = 1, 6 do
        local bar = chargeBars[i]
        if bar and chargeData[i] then
            local charge = chargeData[i]
            local fillAmount = 0
            
            if charge.isFull then
                fillAmount = 1
            else
                if charge.cooldownDuration and charge.cooldownDuration > 0 then
                    local elapsed = GetTime() - charge.cooldownStart
                    if charge.chargeIndex == (charge.totalCharges or 0) + 1 then
                        fillAmount = math.min(1, elapsed / charge.cooldownDuration)
                    else
                        fillAmount = 0
                    end
                end
            end
            
            bar:SetValue(fillAmount)
            
            -- Update colors
            local fullColor = SkyridingUIDB.chargeColorFull or defaults.chargeColorFull
            local chargingColor = SkyridingUIDB.chargeColorCharging or defaults.chargeColorCharging
            local emptyColor = SkyridingUIDB.chargeColorEmpty or defaults.chargeColorEmpty
            
            if charge.isFull then
                bar:SetStatusBarColor(fullColor[1], fullColor[2], fullColor[3], fullColor[4])
            elseif fillAmount > 0 then
                bar:SetStatusBarColor(chargingColor[1], chargingColor[2], chargingColor[3], chargingColor[4])
            else
                bar:SetStatusBarColor(emptyColor[1], emptyColor[2], emptyColor[3], emptyColor[4])
            end
        elseif bar then
            bar:SetValue(0)
        end
    end
end

local function UpdateSecondWindDisplay()
    local chargeInfo = C_Spell.GetSpellCharges(SECOND_WIND_ID)
    
    if chargeInfo then
        local currentCharges = chargeInfo.currentCharges or 0
        local cooldownStart = chargeInfo.cooldownStartTime or 0
        local cooldownDuration = chargeInfo.cooldownDuration or 0
        
        for i = 1, 3 do
            local bar = secondWindBars[i]
            if bar then
                if i <= currentCharges then
                    bar:SetValue(1)
                    bar:SetStatusBarColor(0.7, 0.5, 0.9, 1)
                elseif i == currentCharges + 1 and cooldownDuration > 0 then
                    local elapsed = GetTime() - cooldownStart
                    local progress = math.min(1, elapsed / cooldownDuration)
                    bar:SetValue(progress)
                    bar:SetStatusBarColor(0.5, 0.3, 0.7, 0.8)
                else
                    bar:SetValue(0)
                    bar:SetStatusBarColor(0.2, 0.1, 0.3, 0.6)
                end
            end
        end
    else
        for i = 1, 3 do
            local bar = secondWindBars[i]
            if bar then
                bar:SetValue(0)
            end
        end
    end
end

local function UpdateHorizontalDisplay()
    if not mainFrame or not mainFrame:IsShown() then return end
    
    local time = GetTime()
    
    -- Get flying speed
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    local speed = forwardSpeed or 0
    
    local hasThrillBuff = C_UnitAuras.GetPlayerAuraBySpellID(THRILL_BUFF_ID) ~= nil
    
    -- Check if speed/accel should be hidden when grounded
    local hideSpeedAccel = SUI:ShouldHideSpeedAccelWhenGrounded()
    
    -- Adjust speed for slow skyriding zones
    local adjustedSpeed = speed
    if SUI.isSlowSkyriding then
        adjustedSpeed = adjustedSpeed / (705/830)
    end
    
    -- Calculate speed percentage
    local speedPercent = (speed / 7) * 100
    
    -- Update speed bar (hide if grounded and setting enabled)
    if hideSpeedAccel then
        speedBar:Hide()
    elseif SkyridingUIDB.showSpeedBar ~= false then
        speedBar:Show()
        speedBar:SetMinMaxValues(0, 1200)
        speedBar:SetValue(math.min(1200, speedPercent))
        speedText:SetText(speed < 1 and "0%" or string.format("%.0f%%", speedPercent))
        
        -- Speed bar color
        if hasThrillBuff then
            speedBar:SetStatusBarColor(0.2, 0.6, 1, 1)
        else
            speedBar:SetStatusBarColor(0, 0.8, 0, 1)
        end
    end
    
    -- Update acceleration bar
    local dt = time - (SUI.lastT or time)
    SUI.lastT = time
    
    if dt > 0 then
        SUI.samples = math.min(2, (SUI.samples or 0) + 1)
        local lastWeight = (SUI.samples - 1) / SUI.samples
        local newWeight = 1 / SUI.samples
        
        local newAccel = (adjustedSpeed - (SUI.lastSpeed or 0)) / dt
        SUI.lastSpeed = adjustedSpeed
        
        SUI.smoothAccel = (SUI.smoothAccel or 0) * lastWeight + newAccel * newWeight
        
        if adjustedSpeed >= MAX_PASSIVE_GLIDE_SPEED or not isGliding then
            SUI.smoothAccel = 0
            SUI.samples = 0
        end
    end
    
    local accelValue = math.max(0, math.min(1, ((SUI.smoothAccel or 0) * 0.3 + 10) / 20))
    
    -- Update acceleration bar (hide if grounded and setting enabled)
    if hideSpeedAccel then
        accelBar:Hide()
    elseif SkyridingUIDB.showAccelBar ~= false then
        accelBar:Show()
        accelBar:SetValue(accelValue)
        
        if (SUI.smoothAccel or 0) < -0.5 then
            accelBar:SetStatusBarColor(1, 0, 0, 1)
        else
            accelBar:SetStatusBarColor(0, 0.8, 0, 1)
        end
    end
    
    -- Update Whirling Surge bar
    if SkyridingUIDB.showSurgeBar ~= false then
        if SUI.whirlingSurgeDuration > 0 and SUI.whirlingSurgeStart > 0 then
            local elapsed = time - SUI.whirlingSurgeStart
            local remaining = SUI.whirlingSurgeDuration - elapsed
            if remaining > 0 then
                local progress = remaining / SUI.whirlingSurgeDuration
                surgBar:SetValue(progress)
                surgBar:Show()
            else
                surgBar:Hide()
                SUI.whirlingSurgeStart = 0
                SUI.whirlingSurgeDuration = 0
            end
        else
            surgBar:Hide()
        end
    end
    
    -- Update charge bars
    if SkyridingUIDB.showChargeBars ~= false then
        UpdateChargeDisplay()
    end
    
    -- Update Second Wind bars
    if SkyridingUIDB.showSecondWindBars ~= false then
        UpdateSecondWindDisplay()
    end
    
    SUI.currentSpeed = adjustedSpeed
    SUI.rawSpeed = speed
end

--------------------------------------------------------------------------------
-- Active State Management
--------------------------------------------------------------------------------

local function SetHorizontalActive(active)
    if not mainFrame then
        CreateHorizontalFrame()
    end
    
    if active then
        ApplyHorizontalSettings()
        mainFrame:Show()
    else
        mainFrame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function SUI:InitHorizontalDefaults()
    for k, v in pairs(defaults) do
        if SkyridingUIDB[k] == nil then
            if type(v) == "table" then
                SkyridingUIDB[k] = {v[1], v[2], v[3], v[4]}
            else
                SkyridingUIDB[k] = v
            end
        end
    end
end

function SUI:ApplyHorizontalSettings()
    ApplyHorizontalSettings()
end

function SUI:SetHorizontalActive(active)
    SetHorizontalActive(active)
end

function SUI:UpdateHorizontal()
    UpdateHorizontalDisplay()
end

function SUI:GetHorizontalFrame()
    if not mainFrame then
        CreateHorizontalFrame()
    end
    return mainFrame
end

function SUI:UpdateHorizontalLayout()
    UpdateLayout()
end

function SUI:UpdateHorizontalChargeDisplay()
    UpdateChargeDisplay()
end

-- Initialize frame on load
CreateHorizontalFrame()
