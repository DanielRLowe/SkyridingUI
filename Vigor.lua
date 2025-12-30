--[[
    SkyridingUI - Vigor Module
    Displays Skyriding vigor charges using addon-bundled artwork (PNG).
    
    All textures are located in Textures/
    This implementation uses custom art assets that ship with the addon.
]]

local addonName, addon = ...
local SUI = SkyridingUI

--------------------------------------------------------------------------------
-- Asset Configuration
-- All artwork is bundled with the addon. Change these constants to swap skins.
--------------------------------------------------------------------------------

local ASSET_BASE = "Interface/AddOns/SkyridingUI/Textures/"

-- Art asset base names (without extension)
local ORB_ART_EMPTY  = "vigor_pip_empty_bronze"  -- Empty orb with gray center
local ORB_ART_BEZEL  = "vigor_bezel_bronze"      -- Bronze bezel ring only (transparent center)
local ORB_ART_FILL_TEAL = "vigor_fill_teal"      -- Teal fill (no bezel)
local ORB_ART_FILL_GRAY = "vigor_fill_gray"      -- Gray fill for charging (no bezel)
local ORB_ART_GLOW   = "vigor_pip_glow"
local ORB_ART_VIGNETTE = "gem_vignette"          -- Inner vignette for depth
local ORB_ART_MASK   = "circle_mask_96"          -- Circular mask matching bezel hole
local WING_LEFT_ART  = "wing_finial_left"
local WING_RIGHT_ART = "wing_finial_right"

-- Blizzard flipbook atlas for the swirling energy effect (built-in game asset)
local FLIPBOOK_ATLAS = "dragonriding_vigor_fill_flipbook"
local FLIPBOOK_ROWS = 5
local FLIPBOOK_COLS = 4
local FLIPBOOK_FRAMES = 20
local FLIPBOOK_DURATION = 1.0

--- Resolves texture path for PNG assets.
-- @param baseName string - the base filename without extension
-- @return string - full path to texture file
local function Tex(baseName)
    return ASSET_BASE .. baseName .. ".png"
end

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local vigorFrame, wingLeft, wingRight
local orbs = {}

-- Layout settings
local ORB_SIZE = 32
local GLOW_SCALE = 1.5  -- Glow texture extends beyond the orb

-- Dynamic spacing from settings (defaults to 6)
local function GetOrbSpacing()
    return SkyridingUIDB and SkyridingUIDB.vigorOrbSpacing or 6
end

-- Spell IDs
local VIGOR_SPELL_ID = 372610
local THRILL_BUFF_ID = 377234

--------------------------------------------------------------------------------
-- Orb Creation
-- Each orb displays: empty state, charging progress (bottom→top fill), 
-- full state with glow, flash on completion, Thrill pulse, and flipbook swirl.
--------------------------------------------------------------------------------

local function CreateVigorOrb(parent, index)
    local orb = CreateFrame("Frame", "SkyridingUIOrb"..index, parent)
    orb:SetSize(ORB_SIZE, ORB_SIZE)
    
    -- Layer 1: Background (shows the empty bronze bezel + gray center)
    -- This is always visible as the base layer when orb is empty
    orb.background = orb:CreateTexture(nil, "BACKGROUND")
    orb.background:SetTexture(Tex(ORB_ART_EMPTY))
    orb.background:SetAllPoints()
    
    -- Layer 1.5: Vignette overlay for depth (reduces center brightness)
    orb.vignette = orb:CreateTexture(nil, "BACKGROUND", nil, 1)
    orb.vignette:SetTexture(Tex(ORB_ART_VIGNETTE))
    orb.vignette:SetAllPoints()
    orb.vignette:SetVertexColor(0, 0, 0)
    orb.vignette:SetAlpha(0.12)
    
    -- Layer 2: Clipping container for the fill (fills bottom→top)
    -- Used for BOTH charging (gray) AND full (teal) states
    orb.clipFrame = CreateFrame("Frame", nil, orb)
    orb.clipFrame:SetClipsChildren(true)
    orb.clipFrame:SetPoint("BOTTOMLEFT")
    orb.clipFrame:SetPoint("BOTTOMRIGHT")
    orb.clipFrame:SetHeight(1)
    orb.clipFrame:SetFrameLevel(orb:GetFrameLevel() + 1)
    
    -- The fill texture inside the clipping frame (gray for charging, teal for full)
    -- Size to cover background but fit inside bezel hole
    local fillSize = ORB_SIZE * 0.92  -- 92% to cover background, fit inside bezel
    orb.fill = orb.clipFrame:CreateTexture(nil, "ARTWORK", nil, 3)  -- Sublayer 3 (above swirl)
    orb.fill:SetTexture(Tex(ORB_ART_FILL_GRAY))  -- Start with gray (charging color)
    orb.fill:SetSize(fillSize, fillSize)
    orb.fill:SetPoint("CENTER", orb, "CENTER")  -- Always centered on orb
    orb.fill:SetVertexColor(0.80, 0.85, 0.90)  -- Slightly darker
    
    -- Layer 3: Flipbook swirl effect (Blizzard's built-in animated energy)
    -- This is clipped to the same area as the fill to only show in filled portion
    orb.swirlClipFrame = CreateFrame("Frame", nil, orb)
    orb.swirlClipFrame:SetClipsChildren(true)
    orb.swirlClipFrame:SetPoint("BOTTOMLEFT")
    orb.swirlClipFrame:SetPoint("BOTTOMRIGHT")
    orb.swirlClipFrame:SetHeight(1)
    orb.swirlClipFrame:SetFrameLevel(orb.clipFrame:GetFrameLevel() + 1)
    
    -- Use Blizzard's flipbook atlas for smooth swirling energy
    -- Size to match fill and cover background
    local swirlSize = ORB_SIZE * 0.92  -- 92% to match fill size
    orb.swirl = orb.swirlClipFrame:CreateTexture(nil, "ARTWORK", nil, 1)  -- Sublayer 1 (below fill)
    orb.swirl:SetAtlas(FLIPBOOK_ATLAS)
    orb.swirl:SetSize(swirlSize, swirlSize)
    orb.swirl:SetPoint("CENTER", orb, "CENTER")  -- Always centered on orb
    orb.swirl:SetBlendMode("ADD")   -- ADD to brighten the fill underneath
    orb.swirl:SetVertexColor(0.2, 0.5, 0.7)  -- Darker teal tint
    orb.swirl:SetAlpha(0.75)  -- Subtle swirl effect
    
    -- Layer 4: Bronze bezel ring (transparent center - goes on top of fill/swirl)
    -- This ensures the swirl and fill don't show through the bezel frame
    orb.bezel = orb:CreateTexture(nil, "OVERLAY", nil, 7)  -- Highest overlay layer
    orb.bezel:SetTexture(Tex(ORB_ART_BEZEL))
    orb.bezel:SetAllPoints()
    -- Bezel always at full alpha for consistency across all orb states
    
    -- Flipbook animation for smooth continuous swirl
    orb.swirlAnimGroup = orb:CreateAnimationGroup()
    orb.swirlAnimGroup:SetLooping("REPEAT")
    
    orb.flipAnim = orb.swirlAnimGroup:CreateAnimation("FlipBook")
    orb.flipAnim:SetTarget(orb.swirl)
    orb.flipAnim:SetDuration(FLIPBOOK_DURATION)
    orb.flipAnim:SetOrder(1)
    orb.flipAnim:SetFlipBookRows(FLIPBOOK_ROWS)
    orb.flipAnim:SetFlipBookColumns(FLIPBOOK_COLS)
    orb.flipAnim:SetFlipBookFrames(FLIPBOOK_FRAMES)
    
    -- Layer 5: Flash effect for charge completion (glow texture)
    -- Put BELOW bezel (sublayer 4) so it doesn't illuminate the frame
    local glowSize = ORB_SIZE * 1.2  -- Smaller glow to avoid bezel
    orb.flash = orb:CreateTexture(nil, "OVERLAY", nil, 4)
    orb.flash:SetTexture(Tex(ORB_ART_GLOW))
    orb.flash:SetSize(glowSize, glowSize)
    orb.flash:SetPoint("CENTER")
    orb.flash:SetBlendMode("ADD")
    orb.flash:SetAlpha(0)
    orb.flash:SetVertexColor(0.4, 0.9, 1.0)  -- Teal tint to match orb
    
    -- Layer 6: Thrill of the Skies glow (blue-tinted pulsing effect)
    orb.thrillGlow = orb:CreateTexture(nil, "OVERLAY", nil, 3)
    orb.thrillGlow:SetTexture(Tex(ORB_ART_GLOW))
    orb.thrillGlow:SetSize(glowSize, glowSize)
    orb.thrillGlow:SetPoint("CENTER")
    orb.thrillGlow:SetVertexColor(0.3, 0.7, 1.0)
    orb.thrillGlow:SetBlendMode("ADD")
    orb.thrillGlow:SetAlpha(0)
    
    -- Animation: Flash on charge complete (quick alpha fade out)
    orb.flashAnim = orb:CreateAnimationGroup()
    local flashIn = orb.flashAnim:CreateAnimation("Alpha")
    flashIn:SetTarget(orb.flash)
    flashIn:SetFromAlpha(0.9)
    flashIn:SetToAlpha(0)
    flashIn:SetDuration(0.4)
    flashIn:SetSmoothing("OUT")
    orb.flashAnim:SetScript("OnFinished", function()
        if orb and orb.flash then
            orb.flash:SetAlpha(0)
            orb.flash:Hide()
        end
    end)
    
    -- Animation: Thrill pulsing glow (looping alpha pulse)
    orb.thrillAnim = orb:CreateAnimationGroup()
    orb.thrillAnim:SetLooping("REPEAT")
    
    local pulseIn = orb.thrillAnim:CreateAnimation("Alpha")
    pulseIn:SetTarget(orb.thrillGlow)
    pulseIn:SetFromAlpha(0.15)
    pulseIn:SetToAlpha(0.5)
    pulseIn:SetDuration(0.5)
    pulseIn:SetOrder(1)
    
    local pulseOut = orb.thrillAnim:CreateAnimation("Alpha")
    pulseOut:SetTarget(orb.thrillGlow)
    pulseOut:SetFromAlpha(0.5)
    pulseOut:SetToAlpha(0.15)
    pulseOut:SetDuration(0.5)
    pulseOut:SetOrder(2)
    
    -- State tracking
    orb.state = "empty"  -- "empty", "charging", "full"
    
    return orb
end

--------------------------------------------------------------------------------
-- Orb State Updates
-- States: empty (gray), charging (blue fills up), full (solid blue)
-- Flash only appears briefly when transitioning TO full state
-- Flipbook swirl effect follows the fill level
--------------------------------------------------------------------------------

local function SetOrbFull(orb, playFlash)
    -- Get custom orb color from settings (default teal)
    local orbColor = SkyridingUIDB.vigorOrbColor or {0.22, 0.58, 0.78}
    local r, g, b = orbColor[1], orbColor[2], orbColor[3]
    
    -- Switch to teal fill for full state
    orb.fill:SetTexture(Tex(ORB_ART_FILL_TEAL))
    -- Darken the fill slightly for depth
    orb.fill:SetVertexColor(r * 0.55, g * 0.55, b * 0.7)

    -- Subtle swirl underneath the fill (ADD mode for glow effect)
    orb.swirl:SetBlendMode("ADD")
    orb.swirl:SetVertexColor(r, g, b)
    orb.swirl:SetAlpha(0.75)
    
    -- Update flash color to match orb color (brighter version)
    orb.flash:SetVertexColor(r * 1.2, g * 1.2, b * 1.2)
    
    -- Show full fill by setting clip to full height
    orb.clipFrame:Show()
    orb.clipFrame:SetHeight(ORB_SIZE)
    
    -- keep the swirl visible and animated at full height
    orb.swirlClipFrame:Show()
    orb.swirlClipFrame:SetHeight(ORB_SIZE)
    if SkyridingUIDB.vigorShowSwirl ~= false and not orb.swirlAnimGroup:IsPlaying() then
        orb.swirlAnimGroup:Play()
    end
    
    -- Flash effect when charge completes (only on transition to full)
    if playFlash and orb.state ~= "full" then
        orb.flash:Show()
        orb.flash:SetAlpha(0.9)
        orb.flashAnim:Stop()
        orb.flashAnim:Play()
    end
    
    orb.state = "full"
    
    -- Stop and hide Thrill animation on full orbs
    orb.thrillAnim:Stop()
    orb.thrillGlow:SetAlpha(0)
    orb.thrillGlow:Hide()
end

local function SetOrbEmpty(orb)
    -- Fully hide fill - hide the clip frame entirely for empty state
    orb.clipFrame:Hide()
    orb.clipFrame:SetHeight(0.001)  -- Minimal height (WoW may enforce minimum)
    
    -- Hide swirl on empty orbs and stop animation
    orb.swirlClipFrame:Hide()
    orb.swirlClipFrame:SetHeight(0.001)
    orb.swirlAnimGroup:Stop()
    
    -- Stop and fully hide ALL glow effects (animations can leave residual state)
    orb.thrillAnim:Stop()
    orb.thrillGlow:SetAlpha(0)
    orb.thrillGlow:Hide()
    
    orb.flashAnim:Stop()
    orb.flash:SetAlpha(0)
    orb.flash:Hide()
    
    orb.state = "empty"
end

local function SetOrbCharging(orb, progress, hasThrillBuff)
    -- Get custom orb color from settings (default teal)
    local orbColor = SkyridingUIDB.vigorOrbColor or {0.22, 0.58, 0.78}
    local r, g, b = orbColor[1], orbColor[2], orbColor[3]
    
    -- Use gray fill for charging state
    orb.fill:SetTexture(Tex(ORB_ART_FILL_GRAY))
    orb.fill:SetVertexColor(0.96, 0.98, 0.8)

    -- Subtle swirl underneath the fill (ADD mode for glow effect)
    orb.swirl:SetBlendMode("ADD")
    orb.swirl:SetVertexColor(r, g, b)
    orb.swirl:SetAlpha(0.75)
    
    -- Update thrill glow color to match orb color
    orb.thrillGlow:SetVertexColor(r, g, b)
    
    -- Clamp progress to valid range (0.01 to 0.99 while charging)
    progress = math.max(0.01, math.min(progress, 0.99))
    
    -- Show clip frame and set height for bottom→top fill effect
    orb.clipFrame:Show()
    orb.clipFrame:SetHeight(ORB_SIZE * progress)
    
    -- Swirl follows fill height and start flipbook animation
    orb.swirlClipFrame:Show()
    orb.swirlClipFrame:SetHeight(ORB_SIZE * progress)
    if SkyridingUIDB.vigorShowSwirl ~= false and not orb.swirlAnimGroup:IsPlaying() then
        orb.swirlAnimGroup:Play()
    end
    
    orb.state = "charging"
    
    -- Thrill of the Skies buff visual (faster regen indicator)
    if hasThrillBuff then
        orb.thrillGlow:Show()
        if not orb.thrillAnim:IsPlaying() then
            orb.thrillGlow:SetAlpha(0.15)
            orb.thrillAnim:Play()
        end
    else
        orb.thrillAnim:Stop()
        orb.thrillGlow:SetAlpha(0)
        orb.thrillGlow:Hide()
    end
end

--------------------------------------------------------------------------------
-- Main Frame Setup
--------------------------------------------------------------------------------

local function CreateVigorFrame()
    if vigorFrame then return vigorFrame end
    
    vigorFrame = CreateFrame("Frame", "SkyridingUIVigorFrame", UIParent)
    vigorFrame:SetFrameStrata("MEDIUM")
    vigorFrame:SetFrameLevel(10)
    vigorFrame:Hide()
    
    -- Dragging support
    vigorFrame:SetMovable(true)
    vigorFrame:EnableMouse(true)
    vigorFrame:RegisterForDrag("LeftButton")
    
    vigorFrame:SetScript("OnDragStart", function(self)
        if not SkyridingUIDB.locked then
            self:StartMoving()
        end
    end)
    
    vigorFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        SkyridingUIDB.vigorPoint = point
        SkyridingUIDB.vigorRelativePoint = relPoint
        SkyridingUIDB.vigorX = x
        SkyridingUIDB.vigorY = y
    end)
    
    -- Wing decorations (finials) - using separate left/right art files
    wingLeft = vigorFrame:CreateTexture(nil, "ARTWORK")
    wingLeft:SetTexture(Tex(WING_LEFT_ART))
    wingLeft:SetSize(64, 64)
    -- No SetTexCoord needed - using dedicated left-facing asset
    
    wingRight = vigorFrame:CreateTexture(nil, "ARTWORK")
    wingRight:SetTexture(Tex(WING_RIGHT_ART))
    wingRight:SetSize(64, 64)
    -- No SetTexCoord needed - using dedicated right-facing asset
    
    return vigorFrame
end

--------------------------------------------------------------------------------
-- Orb Layout
--------------------------------------------------------------------------------

local function LayoutOrbs(count)
    if not vigorFrame then return end
    
    -- Create orbs as needed
    while #orbs < count do
        local newOrb = CreateVigorOrb(vigorFrame, #orbs + 1)
        table.insert(orbs, newOrb)
    end
    
    -- Calculate total width and resize frame
    local spacing = GetOrbSpacing()
    local totalWidth = (ORB_SIZE * count) + (spacing * (count - 1))
    vigorFrame:SetSize(totalWidth, ORB_SIZE)
    
    -- Position each orb
    for i = 1, count do
        local orb = orbs[i]
        orb:ClearAllPoints()
        orb:SetPoint("LEFT", vigorFrame, "LEFT", (i - 1) * (ORB_SIZE + spacing), 0)
        orb:Show()
    end
    
    -- Hide extra orbs
    for i = count + 1, #orbs do
        orbs[i]:Hide()
    end
    
    -- Position wing finials
    wingLeft:SetPoint("RIGHT", vigorFrame, "LEFT", 15, -8)
    wingRight:SetPoint("LEFT", vigorFrame, "RIGHT", -15, -8)
end

--------------------------------------------------------------------------------
-- Update Logic
--------------------------------------------------------------------------------

local function UpdateVigorDisplay()
    if not vigorFrame or not vigorFrame:IsShown() then return end
    
    local info = C_Spell.GetSpellCharges(VIGOR_SPELL_ID)
    if not info then return end
    
    -- On Beta realms in combat, spell charge data may be completely restricted
    -- Use pcall to prevent errors and default to safe values
    local success, current, maximum, cdStart, cdDuration = pcall(function()
        local curr = (info.currentCharges and (info.currentCharges + 0)) or 0
        local max = (info.maxCharges and (info.maxCharges + 0)) or 6
        local start = (info.cooldownStartTime and (info.cooldownStartTime + 0)) or 0
        local dur = (info.cooldownDuration and (info.cooldownDuration + 0)) or 0
        return curr, max, start, dur
    end)
    
    -- If data is restricted (Beta in combat), use defaults
    if not success then
        current = 0
        maximum = 6
        cdStart = 0
        cdDuration = 0
    end
    
    -- Ensure we have the right number of orbs
    if #orbs ~= maximum or not orbs[1] then
        LayoutOrbs(maximum)
    end
    
    -- Check for Thrill of the Skies buff
    local hasThrillBuff = C_UnitAuras.GetPlayerAuraBySpellID(THRILL_BUFF_ID) ~= nil
    
    -- Calculate recharge progress for the SINGLE orb that's actively recharging
    -- Only orb at index (current + 1) should show partial fill
    local chargingOrbIndex = current + 1
    local chargingProgress = 0
    
    if cdDuration > 0 and chargingOrbIndex <= maximum then
        local elapsed = GetTime() - cdStart
        chargingProgress = math.min(0.99, math.max(0.01, elapsed / cdDuration))
    end
    
    -- Update each orb based on charge state
    for i = 1, maximum do
        local orb = orbs[i]
        if not orb then break end
        
        if i <= current then
            -- This orb is fully charged
            SetOrbFull(orb, true)
        elseif i == chargingOrbIndex and cdDuration > 0 then
            -- This is THE orb that's currently recharging (only one at a time)
            SetOrbCharging(orb, chargingProgress, hasThrillBuff)
        else
            -- This orb is empty (beyond the charging orb)
            SetOrbEmpty(orb)
        end
    end
end

--------------------------------------------------------------------------------
-- Settings & Public API
-- These functions are called by the main addon - do not change signatures.
--------------------------------------------------------------------------------

local function ApplySettings()
    if not vigorFrame then return end
    
    vigorFrame:ClearAllPoints()
    vigorFrame:SetPoint(
        SkyridingUIDB.vigorPoint or "TOP",
        UIParent,
        SkyridingUIDB.vigorRelativePoint or "TOP",
        SkyridingUIDB.vigorX or 0,
        SkyridingUIDB.vigorY or -50
    )
    
    vigorFrame:SetScale(SkyridingUIDB.scale or 1.0)
    vigorFrame:EnableMouse(not SkyridingUIDB.locked)
    
    -- Wing visibility toggle
    if wingLeft and wingRight then
        if SkyridingUIDB.vigorShowWings ~= false then
            wingLeft:Show()
            wingRight:Show()
        else
            wingLeft:Hide()
            wingRight:Hide()
        end
    end
end

function SUI:InitVigorDefaults()
    SkyridingUIDB.vigorPoint = SkyridingUIDB.vigorPoint or "TOP"
    SkyridingUIDB.vigorRelativePoint = SkyridingUIDB.vigorRelativePoint or "TOP"
    SkyridingUIDB.vigorX = SkyridingUIDB.vigorX or 0
    SkyridingUIDB.vigorY = SkyridingUIDB.vigorY or -50
    SkyridingUIDB.vigorOrbSpacing = SkyridingUIDB.vigorOrbSpacing or 6
    if SkyridingUIDB.vigorShowWings == nil then
        SkyridingUIDB.vigorShowWings = true
    end
    if SkyridingUIDB.vigorShowSwirl == nil then
        SkyridingUIDB.vigorShowSwirl = true
    end
    if SkyridingUIDB.vigorBezelAlpha == nil then
        SkyridingUIDB.vigorBezelAlpha = 0.92
    end
    -- Orb color (default teal/cyan)
    if SkyridingUIDB.vigorOrbColor == nil then
        SkyridingUIDB.vigorOrbColor = {0.22, 0.58, 0.78}  -- Teal blue
    end
end

function SUI:ApplyVigorSettings()
    ApplySettings()
    
    -- Re-layout orbs in case spacing changed
    if vigorFrame and vigorFrame:IsShown() then
        local info = C_Spell.GetSpellCharges(VIGOR_SPELL_ID)
        LayoutOrbs(info and info.maxCharges or 6)
    end
    
    -- Update swirl visibility and animation state
    for _, orb in ipairs(orbs) do
        if orb.swirl and orb.swirlAnimGroup then
            if SkyridingUIDB.vigorShowSwirl ~= false then
                orb.swirl:Show()
                -- Start animation if orb is charged/charging
                if (orb.state == "full" or orb.state == "charging") and not orb.swirlAnimGroup:IsPlaying() then
                    orb.swirlAnimGroup:Play()
                end
            else
                orb.swirl:Hide()
                orb.swirlAnimGroup:Stop()
            end
        end
    end
end

function SUI:SetVigorActive(active)
    if not vigorFrame then
        CreateVigorFrame()
        ApplySettings()
    end
    
    if active then
        vigorFrame:Show()
        
        -- Initial layout
        local info = C_Spell.GetSpellCharges(VIGOR_SPELL_ID)
        LayoutOrbs(info and info.maxCharges or 6)
        
        -- Start update ticker (flipbook animations are self-running)
        if not vigorFrame.ticker then
            vigorFrame.ticker = C_Timer.NewTicker(0.05, UpdateVigorDisplay)
        end
    else
        vigorFrame:Hide()
        
        -- Stop update ticker
        if vigorFrame.ticker then
            vigorFrame.ticker:Cancel()
            vigorFrame.ticker = nil
        end
        
        -- Stop all flipbook animations
        for _, orb in ipairs(orbs) do
            if orb.swirlAnimGroup then
                orb.swirlAnimGroup:Stop()
            end
        end
    end
end

function SUI:GetVigorFrame()
    if not vigorFrame then
        CreateVigorFrame()
        ApplySettings()
    end
    return vigorFrame
end
