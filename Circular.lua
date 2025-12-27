--[[
    SkyridingUI - Circular Module
    A minimalistic radial meter display for Skyriding
    
    Layout:
    - Outer Ring: Flight Speed fill arc (nearly full circle)
    - Inner Ring: Movement Skill Charges (6 smooth arc segments)
    - Center: Second Wind triangle indicator
    - Inner thin arc: Whirling Surge cooldown visualization
    - Center Glow: Acceleration state indicator
]]

local addonName, addon = ...

-- Get reference to main addon (created in SkyridingUI.lua)
local SUI = SkyridingUI

-- Circular-specific variables
local circularFrame
local speedArcSegments = {}
local chargeArcs = {}
local secondWindDots = {}
local surgeArcSegments = {}
local accelGlow

-- Constants for circular display
local CIRCULAR_SIZE = 140  -- Slightly larger for better visuals
local OUTER_RADIUS = 62    -- Speed ring outer edge
local OUTER_THICKNESS = 6  -- Thinner for cleaner look
local CHARGE_RADIUS = 48   -- Charge arcs radius
local CHARGE_THICKNESS = 8 -- Charge arc thickness
local SURGE_RADIUS = 34    -- Surge arc radius (inside charges)
local SURGE_THICKNESS = 4  -- Surge arc thickness
local CENTER_RADIUS = 20   -- Center area radius

-- Arc configuration - full circle
local ARC_START_ANGLE = 270   -- Start at bottom (6 o'clock position)
local ARC_SWEEP = 360         -- Full circle
local NUM_SPEED_SEGMENTS = 1080 -- Ultra-high for silky smooth appearance
local SEGMENTS_PER_CHARGE = 36 -- Higher per charge wedge
local NUM_SURGE_SEGMENTS = 180  -- Surge arc segments

-- Overlap factor to eliminate gaps between segments (more overlap for seamless look)
local SEGMENT_OVERLAP = 1.0  -- Degrees of overlap - increased for seamless blending

-- Speed thresholds
local MIN_SPEED = 0
local MAX_SPEED = 1200
local THRILL_SPEED = 789

-- Convert degrees to radians
local function DegToRad(degrees)
    return degrees * math.pi / 180
end

-- Create the circular frame
local function CreateCircularFrame()
    if circularFrame then return circularFrame end
    
    -- Main container
    circularFrame = CreateFrame("Frame", "SkyridingCircularFrame", UIParent)
    circularFrame:SetSize(CIRCULAR_SIZE, CIRCULAR_SIZE)
    circularFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
    circularFrame:SetFrameStrata("MEDIUM")
    circularFrame:SetMovable(true)
    circularFrame:EnableMouse(false)
    circularFrame:RegisterForDrag("LeftButton")
    circularFrame:SetClampedToScreen(true)
    circularFrame:Hide()
    
    circularFrame:SetScript("OnDragStart", function(self)
        if not SkyridingUIDB.circularLocked then
            self:StartMoving()
        end
    end)
    
    circularFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SkyridingUIDB.circularPoint = point
        SkyridingUIDB.circularRelativePoint = relativePoint
        SkyridingUIDB.circularXOffset = x
        SkyridingUIDB.circularYOffset = y
    end)
    
    -- Subtle background circle
    local bg = circularFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(CIRCULAR_SIZE - 10, CIRCULAR_SIZE - 10)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0, 0, 0, 0.3)
    circularFrame.bg = bg
    
    -- ==================== OUTER RING: Speed Arc (smooth, nearly full circle) ====================
    local segmentSweep = ARC_SWEEP / NUM_SPEED_SEGMENTS
    
    -- Create background arc segments
    for i = 1, NUM_SPEED_SEGMENTS do
        local segment = circularFrame:CreateLine(nil, "BORDER")
        segment:SetThickness(OUTER_THICKNESS)
        segment:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        
        local startAngle = ARC_START_ANGLE - ((i - 1) * segmentSweep)
        local endAngle = ARC_START_ANGLE - (i * segmentSweep) - SEGMENT_OVERLAP  -- Extend slightly
        
        local startRad = DegToRad(startAngle)
        local endRad = DegToRad(endAngle)
        
        local x1 = math.cos(startRad) * OUTER_RADIUS
        local y1 = math.sin(startRad) * OUTER_RADIUS
        local x2 = math.cos(endRad) * OUTER_RADIUS
        local y2 = math.sin(endRad) * OUTER_RADIUS
        
        segment:SetStartPoint("CENTER", circularFrame, x1, y1)
        segment:SetEndPoint("CENTER", circularFrame, x2, y2)
        
        speedArcSegments[i] = {
            bg = segment,
            fill = nil,
            startAngle = startAngle,
            endAngle = endAngle,
            speedStart = ((i - 1) / NUM_SPEED_SEGMENTS) * MAX_SPEED,
            speedEnd = (i / NUM_SPEED_SEGMENTS) * MAX_SPEED
        }
    end
    
    -- Create fill arc segments (on top of background)
    for i = 1, NUM_SPEED_SEGMENTS do
        local segment = circularFrame:CreateLine(nil, "ARTWORK")
        segment:SetThickness(OUTER_THICKNESS)
        segment:SetColorTexture(0.8, 0.8, 0.8, 0)  -- Start invisible
        segment:SetBlendMode("BLEND")  -- Smooth blending for overlapping segments
        
        local startAngle = speedArcSegments[i].startAngle
        local endAngle = speedArcSegments[i].endAngle
        
        local startRad = DegToRad(startAngle)
        local endRad = DegToRad(endAngle)
        
        local x1 = math.cos(startRad) * OUTER_RADIUS
        local y1 = math.sin(startRad) * OUTER_RADIUS
        local x2 = math.cos(endRad) * OUTER_RADIUS
        local y2 = math.sin(endRad) * OUTER_RADIUS
        
        segment:SetStartPoint("CENTER", circularFrame, x1, y1)
        segment:SetEndPoint("CENTER", circularFrame, x2, y2)
        
        speedArcSegments[i].fill = segment
    end
    
    -- ==================== INNER RING: Charge Arcs (6 smooth segments) ====================
    local numCharges = 6
    local chargeGap = 3  -- Smaller gap between charge arcs
    local totalGaps = chargeGap * numCharges
    local chargeSweep = (ARC_SWEEP - totalGaps) / numCharges
    local chargeSegmentSweep = chargeSweep / SEGMENTS_PER_CHARGE
    
    for chargeIdx = 1, numCharges do
        local chargeStartAngle = ARC_START_ANGLE - ((chargeIdx - 1) * (chargeSweep + chargeGap))
        local chargeEndAngle = chargeStartAngle - chargeSweep
        
        chargeArcs[chargeIdx] = {
            bgSegments = {},
            fillSegments = {},
            startAngle = chargeStartAngle,
            endAngle = chargeEndAngle
        }
        
        for segIdx = 1, SEGMENTS_PER_CHARGE do
            local startAngle = chargeStartAngle - ((segIdx - 1) * chargeSegmentSweep)
            local endAngle = chargeStartAngle - (segIdx * chargeSegmentSweep) - SEGMENT_OVERLAP
            
            local startRad = DegToRad(startAngle)
            local endRad = DegToRad(endAngle)
            
            local x1 = math.cos(startRad) * CHARGE_RADIUS
            local y1 = math.sin(startRad) * CHARGE_RADIUS
            local x2 = math.cos(endRad) * CHARGE_RADIUS
            local y2 = math.sin(endRad) * CHARGE_RADIUS
            
            -- Background segment
            local bgSeg = circularFrame:CreateLine(nil, "BORDER")
            bgSeg:SetThickness(CHARGE_THICKNESS)
            bgSeg:SetColorTexture(0.15, 0.08, 0.2, 0.5)
            bgSeg:SetStartPoint("CENTER", circularFrame, x1, y1)
            bgSeg:SetEndPoint("CENTER", circularFrame, x2, y2)
            chargeArcs[chargeIdx].bgSegments[segIdx] = bgSeg
            
            -- Fill segment
            local fillSeg = circularFrame:CreateLine(nil, "ARTWORK")
            fillSeg:SetThickness(CHARGE_THICKNESS)
            fillSeg:SetColorTexture(0.7, 0, 0.9, 0)
            fillSeg:SetBlendMode("BLEND")  -- Smooth blending
            fillSeg:SetStartPoint("CENTER", circularFrame, x1, y1)
            fillSeg:SetEndPoint("CENTER", circularFrame, x2, y2)
            chargeArcs[chargeIdx].fillSegments[segIdx] = fillSeg
        end
    end
    
    -- ==================== SURGE ARC: Inner thin ring (inside charges) ====================
    local surgeSegmentSweep = ARC_SWEEP / NUM_SURGE_SEGMENTS
    for i = 1, NUM_SURGE_SEGMENTS do
        local segment = circularFrame:CreateLine(nil, "ARTWORK", nil, 2)
        segment:SetThickness(SURGE_THICKNESS)
        segment:SetColorTexture(0, 1, 0, 0)
        segment:SetBlendMode("BLEND")  -- Smooth blending
        
        local startAngle = ARC_START_ANGLE - ((i - 1) * surgeSegmentSweep)
        local endAngle = ARC_START_ANGLE - (i * surgeSegmentSweep) - SEGMENT_OVERLAP
        
        local startRad = DegToRad(startAngle)
        local endRad = DegToRad(endAngle)
        
        local x1 = math.cos(startRad) * SURGE_RADIUS
        local y1 = math.sin(startRad) * SURGE_RADIUS
        local x2 = math.cos(endRad) * SURGE_RADIUS
        local y2 = math.sin(endRad) * SURGE_RADIUS
        
        segment:SetStartPoint("CENTER", circularFrame, x1, y1)
        segment:SetEndPoint("CENTER", circularFrame, x2, y2)
        
        surgeArcSegments[i] = segment
    end
    
    -- ==================== RIGHT SIDE: Second Wind Bars (3 vertical bars) ====================
    local windBarWidth = 6
    local windBarHeight = 16
    local windBarSpacing = 4
    local windStartX = OUTER_RADIUS + 10  -- Just outside the speed ring on the right
    local windStartY = (windBarHeight + windBarSpacing)  -- Start above center
    
    for i = 1, 3 do
        local y = windStartY - ((i - 1) * (windBarHeight + windBarSpacing))
        
        -- Background bar
        local bgBar = circularFrame:CreateTexture(nil, "BORDER")
        bgBar:SetSize(windBarWidth, windBarHeight)
        bgBar:SetPoint("CENTER", circularFrame, "CENTER", windStartX, y)
        bgBar:SetColorTexture(0.2, 0.1, 0.3, 0.6)
        
        -- Fill bar
        local fillBar = circularFrame:CreateTexture(nil, "ARTWORK")
        fillBar:SetSize(windBarWidth - 2, windBarHeight - 2)
        fillBar:SetPoint("CENTER", circularFrame, "CENTER", windStartX, y)
        fillBar:SetColorTexture(0.7, 0.5, 0.9, 0)
        
        secondWindDots[i] = {
            bg = bgBar,
            fill = fillBar
        }
    end
    
    -- ==================== CENTER: Acceleration Glow ====================
    accelGlow = circularFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    accelGlow:SetSize(CENTER_RADIUS * 2, CENTER_RADIUS * 2)
    accelGlow:SetPoint("CENTER")
    accelGlow:SetColorTexture(1, 1, 0, 0)
    circularFrame.accelGlow = accelGlow
    
    return circularFrame
end

-- ==================== UPDATE FUNCTIONS ====================

-- Update speed arc fill
local function UpdateSpeedArc(speedPercent)
    if not circularFrame or not circularFrame:IsShown() then return end
    if SkyridingUIDB.circularShowSpeedRing == false then return end
    
    local hasThrillBuff = SUI.hasThrillBuff
    local fillProportion = math.min(1, math.max(0, speedPercent / MAX_SPEED))
    local fillSegments = fillProportion * NUM_SPEED_SEGMENTS
    local fullSegments = math.floor(fillSegments)
    local partialFill = fillSegments - fullSegments
    
    for i = 1, NUM_SPEED_SEGMENTS do
        local segment = speedArcSegments[i]
        if segment then
            -- Ensure segments are visible (in case they were hidden when grounded)
            if segment.bg then segment.bg:Show() end
            if segment.fill then segment.fill:Show() end
            
            if segment.fill then
                local segmentSpeed = segment.speedEnd
            
                if i <= fullSegments then
                    -- Full segment - determine color based on speed and Thrill buff
                    if hasThrillBuff then
                        -- Blue only when Thrill of the Skies is active
                        segment.fill:SetColorTexture(0.2, 0.7, 1, 1)
                    elseif segmentSpeed > 1000 then
                        -- Red for danger zone (above 1000%)
                        segment.fill:SetColorTexture(1, 0.3, 0.3, 1)
                    elseif segmentSpeed > THRILL_SPEED then
                        -- Green when above thrill threshold but no buff
                        segment.fill:SetColorTexture(0.3, 0.85, 0.3, 1)
                    else
                        -- White/gray gradient for normal speed (no Thrill buff)
                        local intensity = 0.5 + (segmentSpeed / THRILL_SPEED) * 0.4
                        segment.fill:SetColorTexture(intensity, intensity, intensity * 0.9, 1)
                    end
                elseif i == fullSegments + 1 and partialFill > 0 then
                    -- Partial segment
                    local alpha = partialFill * 0.9
                    if hasThrillBuff then
                        segment.fill:SetColorTexture(0.2, 0.7, 1, alpha)
                    elseif segmentSpeed > 1000 then
                        segment.fill:SetColorTexture(1, 0.3, 0.3, alpha)
                    elseif segmentSpeed > THRILL_SPEED then
                        segment.fill:SetColorTexture(0.3, 0.85, 0.3, alpha)
                    else
                        local intensity = 0.5 + (segmentSpeed / THRILL_SPEED) * 0.4
                        segment.fill:SetColorTexture(intensity, intensity, intensity * 0.9, alpha)
                    end
                else
                    -- Empty segment
                    segment.fill:SetColorTexture(0, 0, 0, 0)
                end
            end
        end
    end
end

-- Update charge arcs
local function UpdateChargeArcs()
    if not circularFrame or not circularFrame:IsShown() then return end
    if SkyridingUIDB.showChargeBars == false then return end
    
    local chargeInfo = C_Spell.GetSpellCharges(372610)  -- SKYWARD_ASCENT_ID
    
    -- Get colors from settings
    local colorFull = SkyridingUIDB.chargeColorFull or {0.7, 0, 0.9, 1}
    local colorCharging = SkyridingUIDB.chargeColorCharging or {0.5, 0, 0.7, 0.8}
    local colorEmpty = SkyridingUIDB.chargeColorEmpty or {0.3, 0, 0.5, 0.6}
    
    if chargeInfo then
        local currentCharges = chargeInfo.currentCharges
        local maxCharges = chargeInfo.maxCharges
        local chargeProgress = 0
        
        if currentCharges < maxCharges and chargeInfo.cooldownStartTime > 0 then
            local elapsed = GetTime() - chargeInfo.cooldownStartTime
            chargeProgress = elapsed / chargeInfo.cooldownDuration
        end
        
        for chargeIdx = 1, 6 do
            local arc = chargeArcs[chargeIdx]
            if arc then
                for segIdx = 1, SEGMENTS_PER_CHARGE do
                    local fillSeg = arc.fillSegments[segIdx]
                    if fillSeg then
                        if chargeIdx <= currentCharges then
                            -- Full charge - use custom color
                            fillSeg:SetColorTexture(colorFull[1], colorFull[2], colorFull[3], colorFull[4])
                        elseif chargeIdx == currentCharges + 1 then
                            -- Charging - show progress with custom color
                            local segProgress = (segIdx - 1) / SEGMENTS_PER_CHARGE
                            if segProgress < chargeProgress then
                                fillSeg:SetColorTexture(colorCharging[1], colorCharging[2], colorCharging[3], colorCharging[4])
                            else
                                fillSeg:SetColorTexture(colorEmpty[1], colorEmpty[2], colorEmpty[3], colorEmpty[4])
                            end
                        else
                            -- Empty - use custom color
                            fillSeg:SetColorTexture(colorEmpty[1], colorEmpty[2], colorEmpty[3], colorEmpty[4])
                        end
                    end
                end
            end
        end
    else
        -- No charges - use empty color
        local colorEmpty = SkyridingUIDB.chargeColorEmpty or {0.3, 0, 0.5, 0.6}
        for chargeIdx = 1, 6 do
            local arc = chargeArcs[chargeIdx]
            if arc then
                for segIdx = 1, SEGMENTS_PER_CHARGE do
                    local fillSeg = arc.fillSegments[segIdx]
                    if fillSeg then
                        fillSeg:SetColorTexture(colorEmpty[1], colorEmpty[2], colorEmpty[3], colorEmpty[4])
                    end
                end
            end
        end
    end
end

-- Update Second Wind dots (triangle)
local function UpdateSecondWindDots()
    if not circularFrame or not circularFrame:IsShown() then return end
    if SkyridingUIDB.showSecondWindBars == false then return end
    
    local chargeInfo = C_Spell.GetSpellCharges(425782)  -- SECOND_WIND_ID
    
    if chargeInfo then
        local currentCharges = chargeInfo.currentCharges
        local chargeProgress = 0
        
        if currentCharges < chargeInfo.maxCharges and chargeInfo.cooldownStartTime > 0 then
            local elapsed = GetTime() - chargeInfo.cooldownStartTime
            chargeProgress = elapsed / chargeInfo.cooldownDuration
        end
        
        for i = 1, 3 do
            local dot = secondWindDots[i]
            if dot and dot.fill then
                if i <= currentCharges then
                    -- Full
                    dot.fill:SetColorTexture(0.75, 0.55, 0.95, 1)
                elseif i == currentCharges + 1 then
                    -- Charging - pulse effect
                    dot.fill:SetColorTexture(0.5, 0.35, 0.7, chargeProgress)
                else
                    -- Empty
                    dot.fill:SetColorTexture(0.3, 0.2, 0.4, 0.2)
                end
            end
        end
    else
        for i = 1, 3 do
            local dot = secondWindDots[i]
            if dot and dot.fill then
                dot.fill:SetColorTexture(0.3, 0.2, 0.4, 0.2)
            end
        end
    end
end

-- Update Surge arc (inner thin ring)
local function UpdateSurgeArc(progress)
    if not circularFrame or not surgeArcSegments then return end
    if SkyridingUIDB.showSurgeBar == false then return end
    
    local activeSegments = math.floor(progress * NUM_SURGE_SEGMENTS)
    
    for i = 1, NUM_SURGE_SEGMENTS do
        local segment = surgeArcSegments[i]
        if segment then
            if i <= activeSegments then
                segment:SetColorTexture(0.4, 0.85, 0.4, 0.8)
            else
                segment:SetColorTexture(0.2, 0.3, 0.2, 0.2)  -- Dim background when inactive
            end
        end
    end
end

-- Update acceleration glow
local function UpdateAccelGlow()
    if not circularFrame or not accelGlow then return end
    if SkyridingUIDB.showAccelBar == false then
        accelGlow:SetColorTexture(0, 0, 0, 0)
        return
    end
    
    local accel = SUI.smoothAccel or 0
    
    if accel > 5 then
        local intensity = math.min(1, accel / 50)
        accelGlow:SetColorTexture(1, 0.85, 0.2, intensity * 0.5)
    elseif accel < -5 then
        local intensity = math.min(1, math.abs(accel) / 50)
        accelGlow:SetColorTexture(1, 0.3, 0.3, intensity * 0.35)
    else
        accelGlow:SetColorTexture(0, 0, 0, 0)
    end
end

-- ==================== PUBLIC API ====================

function SUI:UpdateCircular()
    if not circularFrame or not circularFrame:IsShown() then return end
    
    local time = GetTime()
    
    -- Get flying speed
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    local speed = forwardSpeed or 0
    
    -- Adjust speed for slow skyriding zones
    local adjustedSpeed = speed
    if self.isSlowSkyriding then
        adjustedSpeed = adjustedSpeed / (705/830)
    end
    
    -- Store raw speed for other uses
    self.rawSpeed = speed
    
    -- Calculate acceleration
    local dt = time - (self.lastT or time)
    self.lastT = time
    
    if dt > 0 then
        self.samples = math.min(2, (self.samples or 0) + 1)
        local lastWeight = (self.samples - 1) / self.samples
        local newWeight = 1 / self.samples
        
        local newAccel = (adjustedSpeed - (self.lastSpeed or 0)) / dt
        self.lastSpeed = adjustedSpeed
        
        self.smoothAccel = (self.smoothAccel or 0) * lastWeight + newAccel * newWeight
        
        -- Reset if at max passive glide speed or not gliding
        local MAX_PASSIVE_GLIDE_SPEED = 65
        if adjustedSpeed >= MAX_PASSIVE_GLIDE_SPEED or not isGliding then
            self.smoothAccel = 0
            self.samples = 0
        end
    end
    
    local speedPercent = (self.rawSpeed or 0) / 7 * 100
    self.hasThrillBuff = C_UnitAuras.GetPlayerAuraBySpellID(377234) ~= nil
    
    -- Check if speed/accel should be hidden when grounded
    local hideSpeedAccel = self:ShouldHideSpeedAccelWhenGrounded()
    
    -- Update speed arc and accel glow (hide if grounded and setting enabled)
    if not hideSpeedAccel then
        UpdateSpeedArc(speedPercent)
        UpdateAccelGlow()
    else
        -- Hide speed ring segments (both background and fill) when grounded
        for i = 1, NUM_SPEED_SEGMENTS do
            if speedArcSegments[i] then
                if speedArcSegments[i].bg then speedArcSegments[i].bg:Hide() end
                if speedArcSegments[i].fill then speedArcSegments[i].fill:Hide() end
            end
        end
        -- Hide accel glow when grounded
        if accelGlow then accelGlow:Hide() end
    end
    
    UpdateChargeArcs()
    UpdateSecondWindDots()
    
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
end

function SUI:ApplyCircularSettings()
    if not circularFrame then
        CreateCircularFrame()
    end
    
    circularFrame:ClearAllPoints()
    circularFrame:SetPoint(
        SkyridingUIDB.circularPoint or "CENTER",
        UIParent,
        SkyridingUIDB.circularRelativePoint or "CENTER",
        SkyridingUIDB.circularXOffset or 0,
        SkyridingUIDB.circularYOffset or -50
    )
    
    -- Apply scale from settings
    local scale = SkyridingUIDB.scale or 1.0
    circularFrame:SetScale(scale)
    
    if SkyridingUIDB.circularLocked then
        circularFrame:EnableMouse(false)
    else
        circularFrame:EnableMouse(true)
    end
    
    if circularFrame.bg then
        local opacity = SkyridingUIDB.backgroundOpacity or 0.5
        if SkyridingUIDB.showBackground then
            circularFrame.bg:SetColorTexture(0, 0, 0, opacity * 0.6)
            circularFrame.bg:Show()
        else
            circularFrame.bg:Hide()
        end
    end
    
    -- Charge arcs visibility
    for chargeIdx = 1, 6 do
        if chargeArcs[chargeIdx] then
            local show = SkyridingUIDB.showChargeBars ~= false
            for segIdx = 1, SEGMENTS_PER_CHARGE do
                if chargeArcs[chargeIdx].bgSegments[segIdx] then
                    if show then
                        chargeArcs[chargeIdx].bgSegments[segIdx]:Show()
                        chargeArcs[chargeIdx].fillSegments[segIdx]:Show()
                    else
                        chargeArcs[chargeIdx].bgSegments[segIdx]:Hide()
                        chargeArcs[chargeIdx].fillSegments[segIdx]:Hide()
                    end
                end
            end
        end
    end
    
    -- Second Wind visibility
    for i = 1, 3 do
        if secondWindDots[i] then
            if SkyridingUIDB.showSecondWindBars == false then
                secondWindDots[i].bg:Hide()
                secondWindDots[i].fill:Hide()
            else
                secondWindDots[i].bg:Show()
                secondWindDots[i].fill:Show()
            end
        end
    end
    
    -- Surge arc visibility
    for i = 1, NUM_SURGE_SEGMENTS do
        if surgeArcSegments[i] then
            if SkyridingUIDB.showSurgeBar == false then
                surgeArcSegments[i]:Hide()
            else
                surgeArcSegments[i]:Show()
            end
        end
    end
    
    -- Accel glow visibility
    if accelGlow then
        if SkyridingUIDB.showAccelBar == false then
            accelGlow:Hide()
        else
            accelGlow:Show()
        end
    end
    
    -- Speed ring visibility (both background and fill segments)
    for i = 1, NUM_SPEED_SEGMENTS do
        if speedArcSegments[i] then
            if SkyridingUIDB.circularShowSpeedRing == false then
                if speedArcSegments[i].bg then speedArcSegments[i].bg:Hide() end
                if speedArcSegments[i].fill then speedArcSegments[i].fill:Hide() end
            else
                if speedArcSegments[i].bg then speedArcSegments[i].bg:Show() end
                if speedArcSegments[i].fill then speedArcSegments[i].fill:Show() end
            end
        end
    end
end

function SUI:SetCircularActive(state)
    if not circularFrame then
        CreateCircularFrame()
        self:ApplyCircularSettings()
    end
    
    if state then
        circularFrame:Show()
    else
        circularFrame:Hide()
    end
end

function SUI:GetCircularFrame()
    if not circularFrame then
        CreateCircularFrame()
    end
    return circularFrame
end

function SUI:InitCircularDefaults()
    local circularDefaults = {
        circularEnabled = false,
        circularLocked = false,
        circularPoint = "CENTER",
        circularRelativePoint = "CENTER",
        circularXOffset = 0,
        circularYOffset = -50,
    }
    
    for k, v in pairs(circularDefaults) do
        if SkyridingUIDB[k] == nil then
            SkyridingUIDB[k] = v
        end
    end
    
    if SkyridingUIDB.locked ~= nil then
        SkyridingUIDB.circularLocked = SkyridingUIDB.locked
    end
end
