--[[
    SkyridingUI - Speedometer Module
    An analog speedometer-style display for Skyriding speed

    Uses custom PNG textures for a polished appearance.
    Textures are located in Textures/ and generated via create_speedometer_svg.py
]]

local addonName, addon = ...

-- Get reference to main addon (created in SkyridingUI.lua)
local SUI = SkyridingUI

--------------------------------------------------------------------------------
-- Asset Configuration
--------------------------------------------------------------------------------

local ASSET_BASE = "Interface/AddOns/SkyridingUI/Textures/"

-- Texture asset names (without extension)
local TEX_BACKGROUND   = "speedometer_background"
local TEX_ARC          = "speedometer_arc"
local TEX_RIM          = "speedometer_rim"
local TEX_NEEDLE       = "speedometer_needle"
local TEX_CENTER_CAP   = "speedometer_center_cap"
local TEX_GLOW         = "speedometer_glow"

--- Resolves texture path for PNG assets.
local function Tex(baseName)
    return ASSET_BASE .. baseName .. ".png"
end

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

-- Speedometer-specific variables
local speedometerFrame
local needleFrame
local digitalDisplay
local surgeArc
local secondWindBars = {}
local tickMarks = {}
local tickLabels = {}

-- Needle smoothing
local currentNeedleAngle = 225  -- Start at 0% position
local targetNeedleAngle = 225
local NEEDLE_SMOOTHING = 0.15   -- Lower = smoother but slower (0-1)

-- Constants for speedometer
local SPEEDOMETER_SIZE = 200
local NEEDLE_LENGTH = 70
local ARC_START_ANGLE = 225  -- Bottom left (in degrees)
local ARC_END_ANGLE = -45    -- Bottom right (in degrees)
local ARC_SWEEP = 270        -- Total sweep angle
local MIN_SPEED = 0
local MAX_SPEED = 1200       -- Max display speed %
local THRILL_SPEED = 789     -- Speed at 12 o'clock position
local CENTER_SPEED = THRILL_SPEED  -- What speed should be at 12 o'clock

-- Convert speed percentage to angle (with Thrill speed at 12 o'clock / 90 degrees)
local function SpeedToAngle(speedPercent)
    -- We want THRILL_SPEED (789%) to be at 90 degrees (12 o'clock)
    -- Arc goes from 225 degrees (0%) to -45 degrees (1200%)
    -- 90 degrees should map to 789%
    
    -- Calculate the proportion: where is speedPercent in the 0-1200 range?
    local proportion = speedPercent / MAX_SPEED
    
    -- But we want 789/1200 to be at the middle (90 degrees)
    -- So we need to adjust the mapping
    local thrillProportion = THRILL_SPEED / MAX_SPEED  -- ~0.657
    
    if speedPercent <= THRILL_SPEED then
        -- Map 0-789% to 225-90 degrees (bottom-left to top)
        local localProp = speedPercent / THRILL_SPEED
        return ARC_START_ANGLE - (localProp * (ARC_START_ANGLE - 90))
    else
        -- Map 789-1200% to 90-(-45) degrees (top to bottom-right)
        local localProp = (speedPercent - THRILL_SPEED) / (MAX_SPEED - THRILL_SPEED)
        return 90 - (localProp * (90 - ARC_END_ANGLE))
    end
end

-- Convert angle to radians
local function DegToRad(degrees)
    return degrees * math.pi / 180
end

-- Create the speedometer frame
local function CreateSpeedometerFrame()
    if speedometerFrame then return speedometerFrame end

    -- Main container
    speedometerFrame = CreateFrame("Frame", "SkyridingSpeedometerFrame", UIParent)
    speedometerFrame:SetSize(SPEEDOMETER_SIZE, SPEEDOMETER_SIZE)
    speedometerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    speedometerFrame:SetFrameStrata("MEDIUM")
    speedometerFrame:SetMovable(true)
    speedometerFrame:EnableMouse(false)
    speedometerFrame:RegisterForDrag("LeftButton")
    speedometerFrame:SetClampedToScreen(true)
    speedometerFrame:Hide()

    speedometerFrame:SetScript("OnDragStart", function(self)
        if not SkyridingUIDB.speedometerLocked then
            self:StartMoving()
        end
    end)

    speedometerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SkyridingUIDB.speedometerPoint = point
        SkyridingUIDB.speedometerRelativePoint = relativePoint
        SkyridingUIDB.speedometerXOffset = x
        SkyridingUIDB.speedometerYOffset = y
    end)

    -- Layer 1: Circular background (with gradient)
    local bg = speedometerFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(SPEEDOMETER_SIZE, SPEEDOMETER_SIZE)
    bg:SetPoint("CENTER")
    bg:SetTexture(Tex(TEX_BACKGROUND))
    speedometerFrame.bg = bg

    -- Layer 2: Arc gauge area (the 270° arc)
    local arcBg = speedometerFrame:CreateTexture(nil, "BORDER")
    arcBg:SetSize(SPEEDOMETER_SIZE - 10, SPEEDOMETER_SIZE - 10)
    arcBg:SetPoint("CENTER")
    arcBg:SetTexture(Tex(TEX_ARC))
    speedometerFrame.arcBg = arcBg

    -- Layer 3: Outer rim (metallic border)
    local rim = speedometerFrame:CreateTexture(nil, "BORDER", nil, 1)
    rim:SetSize(SPEEDOMETER_SIZE - 6, SPEEDOMETER_SIZE - 6)
    rim:SetPoint("CENTER")
    rim:SetTexture(Tex(TEX_RIM))
    speedometerFrame.rim = rim

    -- Layer 4: Glow effect (for Thrill state, initially hidden)
    local glow = speedometerFrame:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetSize(SPEEDOMETER_SIZE * 1.1, SPEEDOMETER_SIZE * 1.1)
    glow:SetPoint("CENTER")
    glow:SetTexture(Tex(TEX_GLOW))
    glow:SetAlpha(0)
    speedometerFrame.glow = glow

    -- Create tick marks and labels
    local tickSpeeds = {0, 200, 400, 600, 789, 900, 1000, 1100, 1200}
    local labelSpeeds = {0, 400, 789, 1000, 1200}

    for i, speed in ipairs(tickSpeeds) do
        local angle = SpeedToAngle(speed)
        local angleRad = DegToRad(angle)

        -- Tick mark
        local tickLength = 8
        local tickWidth = 2

        -- Check if this speed should have a label
        local hasLabel = false
        for _, labelSpeed in ipairs(labelSpeeds) do
            if speed == labelSpeed then hasLabel = true break end
        end

        if hasLabel then
            tickLength = 12
            tickWidth = 3
        end

        local innerRadius = (SPEEDOMETER_SIZE / 2) - 25
        local outerRadius = innerRadius + tickLength

        local tick = speedometerFrame:CreateLine(nil, "ARTWORK", nil, 2)
        tick:SetThickness(tickWidth)

        local innerX = math.cos(angleRad) * innerRadius
        local innerY = math.sin(angleRad) * innerRadius
        local outerX = math.cos(angleRad) * outerRadius
        local outerY = math.sin(angleRad) * outerRadius

        tick:SetStartPoint("CENTER", speedometerFrame, innerX, innerY)
        tick:SetEndPoint("CENTER", speedometerFrame, outerX, outerY)

        -- Color ticks: Blue for Thrill (789), White for normal
        if speed == 789 then
            tick:SetColorTexture(0.2, 0.6, 1, 1)  -- Blue for Thrill
        else
            tick:SetColorTexture(0.8, 0.8, 0.8, 1)  -- White for normal
        end

        tick.baseSpeed = speed  -- Store speed for later updates
        tickMarks[i] = tick

        -- Labels
        if hasLabel then
            local labelRadius = innerRadius - 15
            local labelX = math.cos(angleRad) * labelRadius
            local labelY = math.sin(angleRad) * labelRadius

            local label = speedometerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER", speedometerFrame, "CENTER", labelX, labelY)

            if speed == 789 then
                label:SetText("789")
                label:SetTextColor(0.2, 0.6, 1, 1)  -- Blue for Thrill
            else
                label:SetText(tostring(speed))
                label:SetTextColor(0.7, 0.7, 0.7, 1)  -- White for normal
            end

            label.baseSpeed = speed  -- Store speed for later updates
            tickLabels[#tickLabels + 1] = label
        end
    end

    -- Create needle using texture (for smooth rotation)
    needleFrame = CreateFrame("Frame", nil, speedometerFrame)
    needleFrame:SetSize(SPEEDOMETER_SIZE, SPEEDOMETER_SIZE)
    needleFrame:SetPoint("CENTER", speedometerFrame, "CENTER", 0, 0)
    needleFrame:SetFrameLevel(speedometerFrame:GetFrameLevel() + 5)

    local needle = needleFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    needle:SetSize(SPEEDOMETER_SIZE * 0.9, SPEEDOMETER_SIZE * 0.9)
    needle:SetPoint("CENTER")
    needle:SetTexture(Tex(TEX_NEEDLE))
    -- Initialize rotation to 0% position (225 degrees = bottom-left)
    -- Texture points UP (90°), WoW rotation is clockwise-positive
    -- To point at angle A, rotate by (A - 90) degrees
    needle:SetRotation(DegToRad(ARC_START_ANGLE - 90))
    speedometerFrame.needle = needle

    -- Needle center cap (polished metallic cap)
    local cap = speedometerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    cap:SetSize(28, 28)
    cap:SetPoint("CENTER")
    cap:SetTexture(Tex(TEX_CENTER_CAP))
    speedometerFrame.cap = cap
    
    -- Digital speed display in center
    digitalDisplay = speedometerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    digitalDisplay:SetPoint("CENTER", speedometerFrame, "CENTER", 0, -20)
    digitalDisplay:SetText("0%")
    digitalDisplay:SetTextColor(1, 1, 1, 1)
    speedometerFrame.digitalDisplay = digitalDisplay
    
    -- "SPEED" label below digital display
    local speedLabel = speedometerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    speedLabel:SetPoint("TOP", digitalDisplay, "BOTTOM", 0, -2)
    speedLabel:SetText("SPEED")
    speedLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    speedometerFrame.speedLabel = speedLabel
    
    -- Second Wind bars (3 horizontal bars below SPEED label)
    local windBarWidth = 16
    local windBarHeight = 6
    local windBarSpacing = 4
    local totalWindWidth = (windBarWidth * 3) + (windBarSpacing * 2)
    local windStartX = -totalWindWidth / 2 + windBarWidth / 2
    
    for i = 1, 3 do
        -- Background frame with border
        local barBg = CreateFrame("Frame", nil, speedometerFrame, "BackdropTemplate")
        barBg:SetSize(windBarWidth, windBarHeight)
        barBg:SetPoint("TOP", speedLabel, "BOTTOM", windStartX + ((i - 1) * (windBarWidth + windBarSpacing)), -4)
        barBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        barBg:SetBackdropColor(0.2, 0.1, 0.3, 0.8)
        barBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        local bar = barBg:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("LEFT", barBg, "LEFT", 1, 0)
        bar:SetWidth(1)
        bar:SetHeight(windBarHeight - 2)
        bar:SetColorTexture(0.7, 0.5, 0.9, 1)
        
        secondWindBars[i] = {
            bg = barBg,
            bar = bar,
            width = windBarWidth - 2
        }
    end
    
    -- Charges display (below Second Wind bars)
    local chargeLabel = speedometerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chargeLabel:SetPoint("TOP", speedLabel, "BOTTOM", 0, -18)
    chargeLabel:SetText("Charges: 0")
    chargeLabel:SetTextColor(0.8, 0.6, 0.2, 1)
    speedometerFrame.chargeLabel = chargeLabel
    
    -- Charge progress bar (below charges text)
    local chargeBarBg = CreateFrame("Frame", nil, speedometerFrame, "BackdropTemplate")
    chargeBarBg:SetSize(50, 6)
    chargeBarBg:SetPoint("TOP", chargeLabel, "BOTTOM", 0, -2)
    chargeBarBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    chargeBarBg:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    chargeBarBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    speedometerFrame.chargeBarBg = chargeBarBg
    
    local chargeBar = chargeBarBg:CreateTexture(nil, "OVERLAY")
    chargeBar:SetPoint("LEFT", chargeBarBg, "LEFT", 1, 0)
    chargeBar:SetWidth(1)
    chargeBar:SetHeight(4)
    chargeBar:SetColorTexture(0.8, 0.6, 0.2, 1)
    speedometerFrame.chargeBar = chargeBar
    
    -- Whirling Surge horizontal bar (below charge bar)
    local surgeBarBg = CreateFrame("Frame", nil, speedometerFrame, "BackdropTemplate")
    surgeBarBg:SetSize(50, 6)
    surgeBarBg:SetPoint("TOP", chargeBarBg, "BOTTOM", 0, -4)
    surgeBarBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    surgeBarBg:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    surgeBarBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    surgeBarBg:Hide()
    speedometerFrame.surgeBarBg = surgeBarBg
    
    local surgeBar = surgeBarBg:CreateTexture(nil, "OVERLAY")
    surgeBar:SetPoint("LEFT", surgeBarBg, "LEFT", 1, 0)
    surgeBar:SetWidth(48)
    surgeBar:SetHeight(4)
    surgeBar:SetColorTexture(0.4, 0.8, 0.4, 1)
    speedometerFrame.surgeBar = surgeBar
    
    -- Whirling Surge label (below surge bar)
    local surgeLabel = speedometerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    surgeLabel:SetPoint("TOP", surgeBarBg, "BOTTOM", 0, -2)
    surgeLabel:SetText("")
    surgeLabel:SetTextColor(0.4, 0.8, 0.4, 1)
    speedometerFrame.surgeLabel = surgeLabel
    
    return speedometerFrame
end

-- Update needle position based on speed (with smooth interpolation)
local function UpdateNeedle(speedPercent)
    if not speedometerFrame or not speedometerFrame:IsShown() then return end

    -- Calculate target angle (clamped to valid speed range)
    local clampedSpeed = math.min(MAX_SPEED, math.max(0, speedPercent))
    targetNeedleAngle = SpeedToAngle(clampedSpeed)

    -- Smooth interpolation towards target angle
    -- No wrapping needed - our 270° arc goes from 225° to -45° without crossing 0°/360°
    local angleDiff = targetNeedleAngle - currentNeedleAngle

    -- Apply smoothing (lerp toward target)
    currentNeedleAngle = currentNeedleAngle + angleDiff * NEEDLE_SMOOTHING

    -- Clamp to valid arc range to prevent overshooting
    currentNeedleAngle = math.min(ARC_START_ANGLE, math.max(ARC_END_ANGLE, currentNeedleAngle))

    -- Convert to rotation for the texture
    -- Texture points UP (90°), WoW rotation is clockwise-positive
    -- To point at angle A, we rotate by (A - 90) degrees
    local rotationRad = DegToRad(currentNeedleAngle - 90)
    speedometerFrame.needle:SetRotation(rotationRad)

    -- Update digital display
    digitalDisplay:SetText(string.format("%.0f%%", speedPercent))

    -- Color and glow based on Thrill buff
    local showThrillGlow = SkyridingUIDB.speedometerThrillGlow ~= false  -- Default to true

    local showNeedlePulse = SkyridingUIDB.speedometerNeedlePulse ~= false  -- Default to true

    if SUI.hasThrillBuff then
        digitalDisplay:SetTextColor(0.2, 0.6, 1, 1)  -- Blue text with Thrill

        if showNeedlePulse then
            -- Pulsing needle effect: oscillates between bright red and very bright red
            local pulse = 0.5 + 0.5 * math.sin(GetTime() * 5)  -- Pulses ~0.8 times per second
            local brightness = 0.85 + 0.15 * pulse  -- Range: 0.85 to 1.0
            local warmth = 0.5 + 0.3 * pulse        -- Range: 0.5 to 0.8 (adds orange when bright)
            speedometerFrame.needle:SetVertexColor(brightness, warmth, warmth * 0.6, 1)
        else
            speedometerFrame.needle:SetVertexColor(1, 1, 1, 1)  -- Normal appearance
        end

        if showThrillGlow then
            -- Set glow to blue color (Thrill theme)
            speedometerFrame.glow:SetVertexColor(0.3, 0.5, 1, 1)
            -- Fade in blue aura glow
            local targetAlpha = 0.7
            local currentAlpha = speedometerFrame.glow:GetAlpha()
            if currentAlpha < targetAlpha then
                speedometerFrame.glow:SetAlpha(math.min(targetAlpha, currentAlpha + 0.05))
            end
        else
            -- Glow disabled - immediately hide it
            speedometerFrame.glow:SetAlpha(0)
        end
    else
        -- No Thrill buff - normal appearance
        digitalDisplay:SetTextColor(1, 1, 1, 1)  -- White normally
        speedometerFrame.needle:SetVertexColor(1, 1, 1, 1)  -- Normal red from texture

        -- Fade out glow (or keep it hidden)
        local currentAlpha = speedometerFrame.glow:GetAlpha()
        if currentAlpha > 0 then
            speedometerFrame.glow:SetAlpha(math.max(0, currentAlpha - 0.08))
        end
    end
end

-- Update Whirling Surge horizontal bar
local function UpdateSurgeArc(progress)
    if not speedometerFrame or not speedometerFrame.surgeBar then return end
    
    if progress > 0 then
        -- Show the surge bar
        speedometerFrame.surgeBarBg:Show()
        
        -- Update bar width based on progress (48 is max width inside the border)
        local maxWidth = 48
        speedometerFrame.surgeBar:SetWidth(math.max(1, maxWidth * progress))
        
        -- Update label with remaining time
        local remaining = progress * SUI.whirlingSurgeDuration
        speedometerFrame.surgeLabel:SetText(string.format("Surge: %.1fs", remaining))
    else
        -- Hide when not active
        speedometerFrame.surgeBarBg:Hide()
        speedometerFrame.surgeLabel:SetText("")
    end
end

-- Update tick mark and label colors based on danger zone setting
local function UpdateTickColors()
    if not speedometerFrame then return end
    
    local showDangerZone = SkyridingUIDB.speedometerDangerZone or false
    
    -- Update tick marks
    for i, tick in ipairs(tickMarks) do
        if tick.baseSpeed then
            if tick.baseSpeed == 789 then
                tick:SetColorTexture(0.2, 0.6, 1, 1)  -- Blue for Thrill
            elseif showDangerZone and tick.baseSpeed >= 1000 then
                tick:SetColorTexture(1, 0.2, 0.2, 1)  -- Red for danger zone
            else
                tick:SetColorTexture(0.8, 0.8, 0.8, 1)  -- White for normal
            end
        end
    end
    
    -- Update labels
    for i, label in ipairs(tickLabels) do
        if label.baseSpeed then
            if label.baseSpeed == 789 then
                label:SetTextColor(0.2, 0.6, 1, 1)  -- Blue for Thrill
            elseif showDangerZone and label.baseSpeed >= 1000 then
                label:SetTextColor(1, 0.2, 0.2, 1)  -- Red for danger zone
            else
                label:SetTextColor(0.7, 0.7, 0.7, 1)  -- White for normal
            end
        end
    end
end

-- Update Second Wind bars (horizontal)
local function UpdateSecondWindBars()
    local chargeInfo = C_Spell.GetSpellCharges(425782)  -- SECOND_WIND_ID
    
    if chargeInfo then
        local currentCharges = chargeInfo.currentCharges
        local maxCharges = chargeInfo.maxCharges
        local chargeProgress = 0
        
        if currentCharges < maxCharges and chargeInfo.cooldownStartTime > 0 then
            local elapsed = GetTime() - chargeInfo.cooldownStartTime
            chargeProgress = math.min(1, elapsed / chargeInfo.cooldownDuration)
        end
        
        for i = 1, 3 do
            local barData = secondWindBars[i]
            if barData then
                if i <= currentCharges then
                    -- Full charge - completely filled
                    barData.bar:SetWidth(barData.width)
                    barData.bar:SetColorTexture(0.7, 0.5, 0.9, 1)
                elseif i == currentCharges + 1 and currentCharges < maxCharges then
                    -- This is the NEXT charge being regenerated - show progress
                    barData.bar:SetWidth(math.max(1, barData.width * chargeProgress))
                    barData.bar:SetColorTexture(0.5, 0.3, 0.7, 0.8)
                else
                    -- Empty - any bar beyond the charging one should be empty
                    barData.bar:SetWidth(1)
                    barData.bar:SetColorTexture(0.3, 0.2, 0.4, 0.4)
                end
            end
        end
    else
        -- No Second Wind, show empty bars
        for i = 1, 3 do
            if secondWindBars[i] then
                secondWindBars[i].bar:SetWidth(1)
                secondWindBars[i].bar:SetColorTexture(0.3, 0.2, 0.4, 0.4)
            end
        end
    end
end

-- Update ability charges display
local function UpdateChargesDisplay()
    if not speedometerFrame or not speedometerFrame.chargeLabel then return end
    
    local chargeInfo = C_Spell.GetSpellCharges(372610)  -- SKYWARD_ASCENT_ID
    
    if chargeInfo then
        local currentCharges = chargeInfo.currentCharges
        local maxCharges = chargeInfo.maxCharges
        
        -- Update charges text
        speedometerFrame.chargeLabel:SetText(string.format("Charges: %d", currentCharges))
        
        -- Update progress bar for charging
        local chargeProgress = 0
        if currentCharges < maxCharges and chargeInfo.cooldownStartTime > 0 then
            local elapsed = GetTime() - chargeInfo.cooldownStartTime
            chargeProgress = elapsed / chargeInfo.cooldownDuration
        end
        
        -- Only show progress bar if not at max charges
        if currentCharges < maxCharges then
            local maxWidth = speedometerFrame.chargeBarBg:GetWidth() - 2
            speedometerFrame.chargeBar:SetWidth(math.max(1, maxWidth * chargeProgress))
            speedometerFrame.chargeBarBg:Show()
        else
            speedometerFrame.chargeBarBg:Hide()
        end
    else
        speedometerFrame.chargeLabel:SetText("Charges: 0")
        speedometerFrame.chargeBarBg:Hide()
    end
end

-- Main update function for speedometer (called from SkyridingUI's update loop)
function SUI:UpdateSpeedometer()
    if not speedometerFrame or not speedometerFrame:IsShown() then return end
    
    -- Get flying speed directly
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    local speed = forwardSpeed or 0
    
    -- Store raw speed for other uses
    self.rawSpeed = speed
    
    -- Calculate speed percentage
    local speedPercent = (self.rawSpeed or 0) / 7 * 100
    
    -- Store thrill buff state for needle coloring
    self.hasThrillBuff = C_UnitAuras.GetPlayerAuraBySpellID(377234) ~= nil
    
    -- Check if speed display should be hidden when grounded
    local hideSpeedAccel = self:ShouldHideSpeedAccelWhenGrounded()
    
    -- Update needle and digital display (hide if grounded and setting enabled)
    if hideSpeedAccel then
        if needleFrame then needleFrame:Hide() end
        if digitalDisplay then digitalDisplay:Hide() end
    else
        if needleFrame then needleFrame:Show() end
        if digitalDisplay then digitalDisplay:Show() end
        UpdateNeedle(speedPercent)
    end
    
    -- Update Whirling Surge arc (only if enabled)
    if SkyridingUIDB.showSurgeBar ~= false then
        local time = GetTime()
        if self.whirlingSurgeStart > 0 and self.whirlingSurgeDuration > 0 then
            local elapsed = time - self.whirlingSurgeStart
            local remaining = self.whirlingSurgeDuration - elapsed
            if remaining > 0 then
                UpdateSurgeArc(remaining / self.whirlingSurgeDuration)
            else
                UpdateSurgeArc(0)
                self.whirlingSurgeStart = 0
            end
        else
            UpdateSurgeArc(0)
        end
    end
    
    -- Update Second Wind (only if enabled)
    if SkyridingUIDB.showSecondWindBars ~= false then
        UpdateSecondWindBars()
    end
    
    -- Update charges display (only if enabled)
    if SkyridingUIDB.showChargeBars ~= false then
        UpdateChargesDisplay()
    end
end

-- Apply speedometer settings
function SUI:ApplySpeedometerSettings()
    if not speedometerFrame then
        CreateSpeedometerFrame()
    end
    
    -- Apply position
    speedometerFrame:ClearAllPoints()
    speedometerFrame:SetPoint(
        SkyridingUIDB.speedometerPoint or "CENTER",
        UIParent,
        SkyridingUIDB.speedometerRelativePoint or "CENTER",
        SkyridingUIDB.speedometerXOffset or 0,
        SkyridingUIDB.speedometerYOffset or -100
    )
    
    -- Apply scale (use main UI scale setting)
    speedometerFrame:SetScale(SkyridingUIDB.scale or 1.0)
    
    -- Apply lock state
    if SkyridingUIDB.speedometerLocked then
        speedometerFrame:EnableMouse(false)
    else
        speedometerFrame:EnableMouse(true)
    end
    
    -- Apply background visibility and opacity (uses same settings as bar mode)
    if speedometerFrame.bg then
        local opacity = SkyridingUIDB.backgroundOpacity or 0.5
        if SkyridingUIDB.showBackground then
            speedometerFrame.bg:SetAlpha(opacity)
            speedometerFrame.bg:Show()
            speedometerFrame.arcBg:SetAlpha(opacity)
            speedometerFrame.arcBg:Show()
            if speedometerFrame.rim then
                speedometerFrame.rim:SetAlpha(math.min(1, opacity + 0.3))
                speedometerFrame.rim:Show()
            end
        else
            speedometerFrame.bg:Hide()
            speedometerFrame.arcBg:Hide()
            if speedometerFrame.rim then
                speedometerFrame.rim:Hide()
            end
        end
    end
    
    -- Apply visibility settings for Second Wind bars
    if SkyridingUIDB.showSecondWindBars == false then
        for i = 1, 3 do
            if secondWindBars[i] and secondWindBars[i].bg then
                secondWindBars[i].bg:Hide()
            end
        end
    else
        for i = 1, 3 do
            if secondWindBars[i] and secondWindBars[i].bg then
                secondWindBars[i].bg:Show()
            end
        end
    end
    
    -- Apply visibility settings for Whirling Surge bar
    local showSurge = SkyridingUIDB.showSurgeBar ~= false
    if speedometerFrame.surgeBarBg then
        if not showSurge then
            speedometerFrame.surgeBarBg:Hide()
        end
    end
    if speedometerFrame.surgeLabel then
        if showSurge then
            speedometerFrame.surgeLabel:Show()
        else
            speedometerFrame.surgeLabel:Hide()
        end
    end
    
    -- Apply visibility for charge display
    if SkyridingUIDB.showChargeBars == false then
        if speedometerFrame.chargeLabel then
            speedometerFrame.chargeLabel:Hide()
        end
        if speedometerFrame.chargeBarBg then
            speedometerFrame.chargeBarBg:Hide()
        end
    else
        if speedometerFrame.chargeLabel then
            speedometerFrame.chargeLabel:Show()
        end
        -- chargeBarBg visibility is controlled by UpdateChargesDisplay based on charge state
    end
    
    -- Update tick/label colors based on danger zone setting
    UpdateTickColors()
end

-- Show/hide speedometer
function SUI:SetSpeedometerActive(state)
    if not speedometerFrame then
        CreateSpeedometerFrame()
        self:ApplySpeedometerSettings()
    end

    if state then
        -- Reset needle position to 0% when showing
        currentNeedleAngle = ARC_START_ANGLE
        targetNeedleAngle = ARC_START_ANGLE
        speedometerFrame:Show()
    else
        speedometerFrame:Hide()
    end
end

-- Get speedometer frame (for external access)
function SUI:GetSpeedometerFrame()
    if not speedometerFrame then
        CreateSpeedometerFrame()
    end
    return speedometerFrame
end

-- Initialize speedometer defaults
function SUI:InitSpeedometerDefaults()
    local speedoDefaults = {
        speedometerEnabled = false,
        speedometerScale = 1.0,
        speedometerLocked = false,
        speedometerPoint = "CENTER",
        speedometerRelativePoint = "CENTER",
        speedometerXOffset = 0,
        speedometerYOffset = -100,
        speedometerDangerZone = false,
        speedometerThrillGlow = true,
        speedometerNeedlePulse = true,
    }
    
    for k, v in pairs(speedoDefaults) do
        if SkyridingUIDB[k] == nil then
            SkyridingUIDB[k] = v
        end
    end
    
    -- Sync speedometer lock state with main lock state
    if SkyridingUIDB.locked ~= nil then
        SkyridingUIDB.speedometerLocked = SkyridingUIDB.locked
    end
end
