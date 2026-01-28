--[[
    SkyridingUI: A modern UI for tracking Skyriding speed and ability charges
    Main addon file - handles initialization, events, and options menu
]]

local addonName, addon = ...

-- Create main addon table
SkyridingUI = {}
local SUI = SkyridingUI

-- Initialize saved variables with defaults early
if not SkyridingUIDB then
    SkyridingUIDB = {}
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local ASCENT_SPELL_ID = 372610
local THRILL_BUFF_ID = 377234
local WHIRLING_SURGE_ID = 361584
local WHIRLING_SURGE_DURATION = 30
local UPDATE_PERIOD = 0.05

-- Skyriding ability spell IDs
local SKYRIDING_ABILITIES = {
    [372610] = "Skyward Ascent",
    [361584] = "Surge Forward",
}

-- Druid flight form spell IDs
local DRUID_FLIGHT_FORMS = {
    [783] = true,
    [165962] = true,
    [276029] = true,
}

-- Fast flying zones
local FAST_FLYING_ZONES = {
    [2444] = true, [2454] = true, [2548] = true, [2516] = true,
    [2522] = true, [2569] = true, [2601] = true,
}

--------------------------------------------------------------------------------
-- Default Settings (shared across all modules)
--------------------------------------------------------------------------------

local defaults = {
    scale = 1.0,
    locked = false,
    point = "TOP",
    relativeTo = "UIParent",
    relativePoint = "TOP",
    xOffset = 0,
    yOffset = -100,
    uiMode = "bars",
    showMinimapButton = true,
    minimapPos = 220,
    showBackground = false,
    backgroundOpacity = 0.5,
    -- Speedometer
    speedometerDangerZone = false,
    -- Vigor
    vigorShowWings = true,
    vigorOrbSpacing = 6,
    vigorShowSwirl = true,
}

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

SUI.active = false
SUI.updateTimer = nil
SUI.ascentStart = 0
SUI.whirlingSurgeStart = 0
SUI.whirlingSurgeDuration = 0
SUI.samples = 0
SUI.lastSpeed = 0
SUI.lastT = 0
SUI.smoothAccel = 0
SUI.isSlowSkyriding = true
SUI.currentSpeed = 0
SUI.rawSpeed = 0
SUI.abilityCharges = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function IsSkyriding()
    local isGliding = C_PlayerInfo.GetGlidingInfo()
    return isGliding
end

local function IsInDruidFlightForm()
    local _, className = UnitClass("player")
    if className ~= "DRUID" then return false end
    if not IsFlyableArea() then return false end
    
    for spellID, _ in pairs(DRUID_FLIGHT_FORMS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
            for skySpellID, _ in pairs(SKYRIDING_ABILITIES) do
                local usable = C_Spell.IsSpellUsable(skySpellID)
                if usable then return true end
            end
        end
    end
    return false
end

local function IsOnSkyridingMount()
    if IsInDruidFlightForm() then return true end
    if not IsMounted() then return false end
    if not IsFlyableArea() then return false end
    
    for spellID, _ in pairs(SKYRIDING_ABILITIES) do
        local usableNoMana, noMana = C_Spell.IsSpellUsable(spellID)
        if usableNoMana then return true end
    end
    return false
end

local function HasFullVigorCharges()
    for spellID, _ in pairs(SKYRIDING_ABILITIES) do
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if chargeInfo then
            return chargeInfo.currentCharges >= chargeInfo.maxCharges
        end
    end
    return true  -- Default to true if we can't get charge info
end

local function ShouldHideWhenGrounded()
    if not SkyridingUIDB.hideWhenGroundedFull then return false end
    local isGliding = C_PlayerInfo.GetGlidingInfo()
    if isGliding then return false end  -- In the air, don't hide
    return HasFullVigorCharges()
end

local function ShouldHideSpeedAccelWhenGrounded()
    if not SkyridingUIDB.hideSpeedAccelWhenGrounded then return false end
    local isGliding = C_PlayerInfo.GetGlidingInfo()
    return not isGliding  -- Hide when not gliding (i.e., grounded)
end

-- Expose to modules
function SUI:ShouldHideSpeedAccelWhenGrounded()
    return ShouldHideSpeedAccelWhenGrounded()
end

--------------------------------------------------------------------------------
-- Active State Management
--------------------------------------------------------------------------------

function SUI:SetActive(state)
    self.active = state
    
    if state then
        local instanceID = select(8, GetInstanceInfo())
        self.isSlowSkyriding = not FAST_FLYING_ZONES[instanceID]
        
        local uiMode = SkyridingUIDB.uiMode or "bars"
        
        -- Hide all first
        if self.SetHorizontalActive then self:SetHorizontalActive(false) end
        if self.SetSpeedometerActive then self:SetSpeedometerActive(false) end
        if self.SetCircularActive then self:SetCircularActive(false) end
        if self.SetVigorActive then self:SetVigorActive(false) end
        
        -- Show the active mode
        if uiMode == "speedometer" then
            self:SetSpeedometerActive(true)
        elseif uiMode == "circular" then
            self:SetCircularActive(true)
        elseif uiMode == "vigor" then
            self:SetVigorActive(true)
        else
            self:SetHorizontalActive(true)
        end
        
        -- Start update timer
        if not self.updateTimer then
            self.updateTimer = C_Timer.NewTicker(UPDATE_PERIOD, function()
                if SUI.active then
                    -- Check if we should hide when grounded with full charges
                    local shouldHide = ShouldHideWhenGrounded()
                    SUI:SetUIVisible(not shouldHide)
                    
                    local mode = SkyridingUIDB.uiMode or "bars"
                    if mode == "bars" and SUI.UpdateHorizontal then
                        SUI:UpdateHorizontal()
                    elseif mode == "speedometer" and SUI.UpdateSpeedometer then
                        SUI:UpdateSpeedometer()
                    elseif mode == "circular" and SUI.UpdateCircular then
                        SUI:UpdateCircular()
                    end
                    -- Vigor has its own timer
                end
            end)
        end
    else
        -- Hide all
        if self.SetHorizontalActive then self:SetHorizontalActive(false) end
        if self.SetSpeedometerActive then self:SetSpeedometerActive(false) end
        if self.SetCircularActive then self:SetCircularActive(false) end
        if self.SetVigorActive then self:SetVigorActive(false) end
        
        if self.updateTimer then
            self.updateTimer:Cancel()
            self.updateTimer = nil
        end
    end
end

-- Show/hide UI without changing active state (for grounded+full feature)
function SUI:SetUIVisible(visible)
    local uiMode = SkyridingUIDB.uiMode or "bars"
    local frame
    
    if uiMode == "speedometer" then
        frame = self:GetSpeedometerFrame()
    elseif uiMode == "circular" then
        frame = self:GetCircularFrame()
    elseif uiMode == "vigor" then
        frame = self:GetVigorFrame()
    else
        frame = self:GetHorizontalFrame()
    end
    
    if frame then
        if visible then
            frame:Show()
        else
            frame:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Toggle Lock (affects all UI modes)
--------------------------------------------------------------------------------

local function ToggleLock()
    SkyridingUIDB.locked = not SkyridingUIDB.locked
    SkyridingUIDB.speedometerLocked = SkyridingUIDB.locked
    SkyridingUIDB.circularLocked = SkyridingUIDB.locked
    SkyridingUIDB.vigorLocked = SkyridingUIDB.locked
    
    -- Apply to all modules
    if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
    if SUI.ApplySpeedometerSettings then SUI:ApplySpeedometerSettings() end
    if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
    if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    
    local status = SkyridingUIDB.locked and "locked" or "unlocked"
    print("|cff00ff00SkyridingUI|r: Frame " .. status)
end

--------------------------------------------------------------------------------
-- Minimap Button (using LibDBIcon for compatibility with all minimap shapes)
--------------------------------------------------------------------------------

local LibDBIcon = LibStub("LibDBIcon-1.0")
local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("SkyridingUI", {
    type = "launcher",
    icon = "Interface\\Icons\\ability_druid_flightform",
    OnClick = function(self, button)
        if button == "LeftButton" then
            SUI:ToggleOptionsFrame()
        elseif button == "RightButton" then
            ToggleLock()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Skyriding UI", 1, 0.82, 0)
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffffffffLeft-click|r to open options", 0.8, 0.8, 0.8)
        tooltip:AddLine("|cffffffffRight-click|r to toggle lock", 0.8, 0.8, 0.8)
        tooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
    end,
})

local minimapButton = nil

local function RegisterMinimapButton()
    -- Initialize minimap settings in db if not present
    if not SkyridingUIDB.minimap then
        SkyridingUIDB.minimap = { hide = false }
    end
    -- Migrate old minimapPos to new format if needed
    if SkyridingUIDB.minimapPos and not SkyridingUIDB.minimap.minimapPos then
        SkyridingUIDB.minimap.minimapPos = SkyridingUIDB.minimapPos
    end
    -- Migrate old showMinimapButton setting
    if SkyridingUIDB.showMinimapButton == false then
        SkyridingUIDB.minimap.hide = true
    end
    
    LibDBIcon:Register("SkyridingUI", LDB, SkyridingUIDB.minimap)
    minimapButton = LibDBIcon:GetMinimapButton("SkyridingUI")
end

local function ShowMinimapButton()
    if SkyridingUIDB.minimap then
        SkyridingUIDB.minimap.hide = false
    end
    LibDBIcon:Show("SkyridingUI")
end

local function HideMinimapButton()
    if SkyridingUIDB.minimap then
        SkyridingUIDB.minimap.hide = true
    end
    LibDBIcon:Hide("SkyridingUI")
end

local function IsMinimapButtonShown()
    return not (SkyridingUIDB.minimap and SkyridingUIDB.minimap.hide)
end

--------------------------------------------------------------------------------
-- Addon Compartment Functions
--------------------------------------------------------------------------------

function SkyridingUI_AddonCompartment_OnClick(addonName, buttonName)
    SUI:ToggleOptionsFrame()
end

function SkyridingUI_AddonCompartment_OnEnter(addonName, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("Skyriding UI", 1, 0.82, 0)
    GameTooltip:AddLine("Click to open options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function SkyridingUI_AddonCompartment_OnLeave()
    GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Blizzard Interface Options Panel
--------------------------------------------------------------------------------

local blizzOptionsPanel

local function CreateBlizzardOptionsPanel()
    if blizzOptionsPanel then return end
    
    blizzOptionsPanel = CreateFrame("Frame", "SkyridingUIBlizzPanel")
    blizzOptionsPanel.name = "Skyriding UI"
    
    local title = blizzOptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Skyriding UI")
    
    local version = blizzOptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    version:SetText("Version 1.5.0")
    version:SetTextColor(0.5, 0.5, 0.5)
    
    local desc = blizzOptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    desc:SetWidth(550)
    desc:SetJustifyH("LEFT")
    desc:SetText("Track your Skyriding speed and ability charges with customizable bar, speedometer, circular, or vigor display modes.")
    
    local openBtn = CreateFrame("Button", nil, blizzOptionsPanel, "UIPanelButtonTemplate")
    openBtn:SetSize(180, 26)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    openBtn:SetText("Open SkyridingUI Options")
    openBtn:SetScript("OnClick", function()
        SUI:ToggleOptionsFrame()
        if Settings and Settings.CloseUI then Settings.CloseUI() end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    end)
    
    local cmdsTitle = blizzOptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmdsTitle:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -20)
    cmdsTitle:SetText("Slash Commands:")
    
    local cmdsText = blizzOptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cmdsText:SetPoint("TOPLEFT", cmdsTitle, "BOTTOMLEFT", 10, -8)
    cmdsText:SetJustifyH("LEFT")
    cmdsText:SetText(
        "|cffffd100/sui options|r - Open the options menu\n" ..
        "|cffffd100/sui lock|r - Lock the frame position\n" ..
        "|cffffd100/sui unlock|r - Unlock the frame for moving\n" ..
        "|cffffd100/sui toggle|r - Toggle the UI visibility\n" ..
        "|cffffd100/sui reset|r - Reset all settings to defaults"
    )
    
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(blizzOptionsPanel, "Skyriding UI")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(blizzOptionsPanel)
    end
end

--------------------------------------------------------------------------------
-- Options Frame
--------------------------------------------------------------------------------

local optionsFrame

-- Helper functions for color picker
local function RGBToHex(r, g, b)
    return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function HexToRGB(hex)
    hex = hex:gsub("#", "")
    if #hex == 6 then
        return tonumber(hex:sub(1, 2), 16) / 255,
               tonumber(hex:sub(3, 4), 16) / 255,
               tonumber(hex:sub(5, 6), 16) / 255
    end
    return nil, nil, nil
end

local function ShowColorPicker(colorKey, defaultColor, callback)
    local color = SkyridingUIDB[colorKey] or defaultColor
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    
    local info = {
        swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            SkyridingUIDB[colorKey] = {newR, newG, newB, newA}
            if callback then callback(newR, newG, newB, newA) end
        end,
        opacityFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = ColorPickerFrame:GetColorAlpha()
            SkyridingUIDB[colorKey] = {newR, newG, newB, newA}
            if callback then callback(newR, newG, newB, newA) end
        end,
        cancelFunc = function(previousValues)
            SkyridingUIDB[colorKey] = {previousValues.r, previousValues.g, previousValues.b, previousValues.a}
            if callback then callback(previousValues.r, previousValues.g, previousValues.b, previousValues.a) end
        end,
        hasOpacity = true,
        opacity = a,
        r = r, g = g, b = b,
    }
    
    ColorPickerFrame:SetupColorPickerAndShow(info)
end

local function CreateColorButton(parent, x, y, label, colorKey, defaultColor, updateCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(200, 50)
    frame:SetPoint("TOPLEFT", x, y)
    
    local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", 0, 0)
    labelText:SetText(label)
    
    local colorBtn = CreateFrame("Button", nil, frame)
    colorBtn:SetSize(24, 24)
    colorBtn:SetPoint("TOPLEFT", 0, -15)
    
    local colorTex = colorBtn:CreateTexture(nil, "ARTWORK")
    colorTex:SetAllPoints()
    local color = SkyridingUIDB[colorKey] or defaultColor
    colorTex:SetColorTexture(color[1], color[2], color[3], 1)
    
    local border = colorBtn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 1)
    
    local hexBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    hexBox:SetSize(70, 20)
    hexBox:SetPoint("LEFT", colorBtn, "RIGHT", 10, 0)
    hexBox:SetAutoFocus(false)
    hexBox:SetMaxLetters(7)
    hexBox:SetText("#" .. RGBToHex(color[1], color[2], color[3]))
    
    local function UpdateColor(r, g, b, a)
        colorTex:SetColorTexture(r, g, b, 1)
        hexBox:SetText("#" .. RGBToHex(r, g, b))
        if updateCallback then updateCallback() end
    end
    
    colorBtn:SetScript("OnClick", function()
        ShowColorPicker(colorKey, defaultColor, UpdateColor)
    end)
    
    hexBox:SetScript("OnEnterPressed", function(self)
        local hex = self:GetText()
        local r, g, b = HexToRGB(hex)
        if r and g and b then
            local currentColor = SkyridingUIDB[colorKey] or defaultColor
            SkyridingUIDB[colorKey] = {r, g, b, currentColor[4] or 1}
            colorTex:SetColorTexture(r, g, b, 1)
            if updateCallback then updateCallback() end
        end
        self:ClearFocus()
    end)
    
    hexBox:SetScript("OnEscapePressed", function(self)
        local clr = SkyridingUIDB[colorKey] or defaultColor
        self:SetText("#" .. RGBToHex(clr[1], clr[2], clr[3]))
        self:ClearFocus()
    end)
    
    frame.colorTex = colorTex
    frame.hexBox = hexBox
    frame.UpdateDisplay = function()
        local c = SkyridingUIDB[colorKey] or defaultColor
        colorTex:SetColorTexture(c[1], c[2], c[3], 1)
        hexBox:SetText("#" .. RGBToHex(c[1], c[2], c[3]))
    end
    
    return frame
end

local function CreateBarDimensionSliders(parent, yPos, label, widthKey, heightKey, widthDefault, heightDefault, widthMin, widthMax, heightMin, heightMax)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", 20, yPos)
    labelText:SetText(label)
    labelText:SetTextColor(1, 0.82, 0)
    
    local wLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wLabel:SetPoint("TOPLEFT", 30, yPos - 18)
    wLabel:SetText("Width:")
    
    local wSlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    wSlider:SetSize(120, 14)
    wSlider:SetPoint("TOPLEFT", 70, yPos - 18)
    wSlider:SetMinMaxValues(widthMin or 100, widthMax or 600)
    wSlider:SetValue(SkyridingUIDB[widthKey] or widthDefault)
    wSlider:SetValueStep(10)
    wSlider:SetObeyStepOnDrag(true)
    wSlider.Low:SetText(""); wSlider.High:SetText(""); wSlider.Text:SetText("")
    
    local wBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    wBox:SetSize(35, 18)
    wBox:SetPoint("LEFT", wSlider, "RIGHT", 5, 0)
    wBox:SetAutoFocus(false)
    wBox:SetText(tostring(SkyridingUIDB[widthKey] or widthDefault))
    
    local hLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hLabel:SetPoint("TOPLEFT", 240, yPos - 18)
    hLabel:SetText("Height:")
    
    local hSlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    hSlider:SetSize(80, 14)
    hSlider:SetPoint("TOPLEFT", 285, yPos - 18)
    hSlider:SetMinMaxValues(heightMin or 4, heightMax or 40)
    hSlider:SetValue(SkyridingUIDB[heightKey] or heightDefault)
    hSlider:SetValueStep(1)
    hSlider:SetObeyStepOnDrag(true)
    hSlider.Low:SetText(""); hSlider.High:SetText(""); hSlider.Text:SetText("")
    
    local hBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    hBox:SetSize(30, 18)
    hBox:SetPoint("LEFT", hSlider, "RIGHT", 5, 0)
    hBox:SetAutoFocus(false)
    hBox:SetText(tostring(SkyridingUIDB[heightKey] or heightDefault))
    
    wSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        SkyridingUIDB[widthKey] = value
        wBox:SetText(tostring(value))
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    wBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(widthMin or 100, math.min(widthMax or 600, math.floor(value / 10 + 0.5) * 10))
            SkyridingUIDB[widthKey] = value
            wSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
        end
        self:ClearFocus()
    end)
    
    hSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SkyridingUIDB[heightKey] = value
        hBox:SetText(tostring(value))
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    hBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(heightMin or 4, math.min(heightMax or 40, math.floor(value + 0.5)))
            SkyridingUIDB[heightKey] = value
            hSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
        end
        self:ClearFocus()
    end)
    
    return yPos - 40
end

local function InitializeOptionsFrame()
    if optionsFrame then return end
    
    optionsFrame = CreateFrame("Frame", "SkyridingUIOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    optionsFrame:SetSize(450, 540)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:Hide()
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    
    optionsFrame.title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.title:SetPoint("TOP", optionsFrame, "TOP", 0, -5)
    optionsFrame.title:SetText("Skyriding UI Options")
    
    -- Create tab buttons
    local tabs = {}
    local tabNames = {"General", "Horizontal", "Speedometer", "Circular", "Vigor"}
    local tabWidth = 78
    
    local function UpdateTabAppearance(tab, isSelected)
        if isSelected then
            -- Selected: bright red background with gold text
            tab:SetBackdropColor(0.6, 0.1, 0.1, 1)
            tab:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
            tab.text:SetTextColor(1, 0.82, 0)
        else
            -- Unselected: darker red background with lighter text
            tab:SetBackdropColor(0.35, 0.05, 0.05, 0.9)
            tab:SetBackdropBorderColor(0.5, 0.3, 0.1, 1)
            tab.text:SetTextColor(0.9, 0.7, 0.3)
        end
    end
    
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", "SkyridingUITab"..i, optionsFrame, "BackdropTemplate")
        tab:SetSize(tabWidth, 24)
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(name)
        
        if i == 1 then
            tab:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 10, -25)
        else
            tab:SetPoint("LEFT", tabs[i-1], "RIGHT", 2, 0)
        end
        
        tab:SetScript("OnEnter", function(self)
            if not self.isSelected then self:SetBackdropColor(0.5, 0.1, 0.1, 1) end
        end)
        tab:SetScript("OnLeave", function(self)
            if not self.isSelected then self:SetBackdropColor(0.35, 0.05, 0.05, 0.9) end
        end)
        
        UpdateTabAppearance(tab, false)
        tabs[i] = tab
    end
    
    -- Create content frames with scroll functionality
    local contentFrames = {}
    local scrollFrames = {}
    for i = 1, #tabNames do
        -- Create scroll frame container
        local scrollFrame = CreateFrame("ScrollFrame", "SkyridingUIScrollFrame"..i, optionsFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 10, -55)
        scrollFrame:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -30, 40)
        scrollFrame:Hide()
        
        -- Create the actual content frame that will be scrolled
        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(400, 800)  -- Height will be adjusted based on content
        scrollFrame:SetScrollChild(content)
        
        -- Enable mouse wheel scrolling on the content frame
        content:EnableMouseWheel(true)
        content:SetScript("OnMouseWheel", function(self, delta)
            local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName().."ScrollBar"]
            if scrollBar then
                local current = scrollBar:GetValue()
                local minVal, maxVal = scrollBar:GetMinMaxValues()
                local step = 40  -- Pixels to scroll per wheel tick
                if delta > 0 then
                    scrollBar:SetValue(math.max(minVal, current - step))
                else
                    scrollBar:SetValue(math.min(maxVal, current + step))
                end
            end
        end)
        
        scrollFrames[i] = scrollFrame
        contentFrames[i] = content
    end
    
    optionsFrame.contentFrames = contentFrames
    optionsFrame.scrollFrames = scrollFrames
    
    local function SelectTab(tabIndex)
        for i, scrollFrame in ipairs(scrollFrames) do
            if i == tabIndex then
                scrollFrame:Show()
                tabs[i].isSelected = true
                UpdateTabAppearance(tabs[i], true)
            else
                scrollFrame:Hide()
                tabs[i].isSelected = false
                UpdateTabAppearance(tabs[i], false)
            end
        end
    end
    
    for i, tab in ipairs(tabs) do
        tab:SetScript("OnClick", function() SelectTab(i) end)
    end
    
    -- Helper to apply background to all modes
    local function ApplyBackgroundToAll()
        if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
        if SUI.ApplySpeedometerSettings then SUI:ApplySpeedometerSettings() end
        if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    end
    
    -- ==================== TAB 1: GENERAL ====================
    local tab1 = contentFrames[1]
    local yPos = -5
    
    -- UI Scale
    local scaleLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    scaleLabel:SetPoint("TOPLEFT", 10, yPos)
    scaleLabel:SetText("UI Scale")
    scaleLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local scaleTxt = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleTxt:SetPoint("TOPLEFT", 20, yPos)
    scaleTxt:SetText("Scale:")
    
    local scaleSlider = CreateFrame("Slider", nil, tab1, "OptionsSliderTemplate")
    scaleSlider:SetSize(150, 14)
    scaleSlider:SetPoint("TOPLEFT", 65, yPos)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValue(SkyridingUIDB.scale or 1.0)
    scaleSlider:SetValueStep(0.01)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider.Low:SetText("0.5"); scaleSlider.High:SetText("2.0"); scaleSlider.Text:SetText("")
    
    local scaleEditBox = CreateFrame("EditBox", nil, tab1, "InputBoxTemplate")
    scaleEditBox:SetSize(40, 18)
    scaleEditBox:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)
    scaleEditBox:SetAutoFocus(false)
    scaleEditBox:SetText(string.format("%.2f", SkyridingUIDB.scale or 1.0))
    
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        SkyridingUIDB.scale = value
        scaleEditBox:SetText(string.format("%.2f", value))
        ApplyBackgroundToAll()
    end)
    
    scaleEditBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(0.5, math.min(2.0, value))
            SkyridingUIDB.scale = value
            scaleSlider:SetValue(value)
            self:SetText(string.format("%.2f", value))
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 35
    
    -- UI Style
    local styleLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    styleLabel:SetPoint("TOPLEFT", 10, yPos)
    styleLabel:SetText("UI Style")
    styleLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local barsRadio = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    barsRadio:SetPoint("TOPLEFT", 20, yPos)
    barsRadio:SetChecked(SkyridingUIDB.uiMode == "bars" or SkyridingUIDB.uiMode == nil)
    barsRadio.text:SetText("Horizontal Bars")
    
    local speedoRadio = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    speedoRadio:SetPoint("TOPLEFT", 160, yPos)
    speedoRadio:SetChecked(SkyridingUIDB.uiMode == "speedometer")
    speedoRadio.text:SetText("Speedometer")
    
    local circularRadio = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    circularRadio:SetPoint("TOPLEFT", 300, yPos)
    circularRadio:SetChecked(SkyridingUIDB.uiMode == "circular")
    circularRadio.text:SetText("Circular")
    
    yPos = yPos - 25
    
    local vigorRadio = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    vigorRadio:SetPoint("TOPLEFT", 20, yPos)
    vigorRadio:SetChecked(SkyridingUIDB.uiMode == "vigor")
    vigorRadio.text:SetText("Vigor Orbs")
    
    local function SetUIMode(mode)
        SkyridingUIDB.uiMode = mode
        barsRadio:SetChecked(mode == "bars")
        speedoRadio:SetChecked(mode == "speedometer")
        circularRadio:SetChecked(mode == "circular")
        vigorRadio:SetChecked(mode == "vigor")
        
        if SUI.active then
            SUI:SetActive(true)
        end
    end
    
    barsRadio:SetScript("OnClick", function() SetUIMode("bars") end)
    speedoRadio:SetScript("OnClick", function() SetUIMode("speedometer") end)
    circularRadio:SetScript("OnClick", function() SetUIMode("circular") end)
    vigorRadio:SetScript("OnClick", function() SetUIMode("vigor") end)
    
    yPos = yPos - 35
    
    -- Background Settings (applies to ALL modes)
    local bgLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bgLabel:SetPoint("TOPLEFT", 10, yPos)
    bgLabel:SetText("Background")
    bgLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local showBgCheck = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    showBgCheck:SetPoint("TOPLEFT", 20, yPos)
    showBgCheck:SetChecked(SkyridingUIDB.showBackground or false)
    showBgCheck.text:SetText("Show Background")
    showBgCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showBackground = self:GetChecked()
        ApplyBackgroundToAll()
    end)
    
    yPos = yPos - 35
    
    local bgOpacityTxt = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bgOpacityTxt:SetPoint("TOPLEFT", 20, yPos)
    bgOpacityTxt:SetText("Opacity:")
    
    local bgOpacitySlider = CreateFrame("Slider", nil, tab1, "OptionsSliderTemplate")
    bgOpacitySlider:SetSize(150, 14)
    bgOpacitySlider:SetPoint("TOPLEFT", 75, yPos)
    bgOpacitySlider:SetMinMaxValues(0, 1)
    bgOpacitySlider:SetValue(SkyridingUIDB.backgroundOpacity or 0.5)
    bgOpacitySlider:SetValueStep(0.05)
    bgOpacitySlider:SetObeyStepOnDrag(true)
    bgOpacitySlider.Low:SetText("0"); bgOpacitySlider.High:SetText("1"); bgOpacitySlider.Text:SetText("")
    
    local bgOpacityBox = CreateFrame("EditBox", nil, tab1, "InputBoxTemplate")
    bgOpacityBox:SetSize(40, 18)
    bgOpacityBox:SetPoint("LEFT", bgOpacitySlider, "RIGHT", 10, 0)
    bgOpacityBox:SetAutoFocus(false)
    bgOpacityBox:SetText(string.format("%.2f", SkyridingUIDB.backgroundOpacity or 0.5))
    
    bgOpacitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        SkyridingUIDB.backgroundOpacity = value
        bgOpacityBox:SetText(string.format("%.2f", value))
        ApplyBackgroundToAll()
    end)
    
    bgOpacityBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(0, math.min(1, value))
            SkyridingUIDB.backgroundOpacity = value
            bgOpacitySlider:SetValue(value)
            self:SetText(string.format("%.2f", value))
            ApplyBackgroundToAll()
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 35
    
    -- Element Visibility
    local visLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    visLabel:SetPoint("TOPLEFT", 10, yPos)
    visLabel:SetText("Element Visibility")
    visLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local showMinimapCheck = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    showMinimapCheck:SetPoint("TOPLEFT", 20, yPos)
    showMinimapCheck:SetChecked(IsMinimapButtonShown())
    showMinimapCheck.text:SetText("Show Minimap Button")
    showMinimapCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            ShowMinimapButton()
        else
            HideMinimapButton()
        end
    end)
    
    yPos = yPos - 25
    
    local hideGroundedCheck = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    hideGroundedCheck:SetPoint("TOPLEFT", 20, yPos)
    hideGroundedCheck:SetChecked(SkyridingUIDB.hideWhenGroundedFull or false)
    hideGroundedCheck.text:SetText("Hide UI when grounded with full charges")
    hideGroundedCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.hideWhenGroundedFull = self:GetChecked()
    end)
    
    yPos = yPos - 25
    
    local hideSpeedAccelCheck = CreateFrame("CheckButton", nil, tab1, "UICheckButtonTemplate")
    hideSpeedAccelCheck:SetPoint("TOPLEFT", 20, yPos)
    hideSpeedAccelCheck:SetChecked(SkyridingUIDB.hideSpeedAccelWhenGrounded or false)
    hideSpeedAccelCheck.text:SetText("Hide Speed/Acceleration when grounded")
    hideSpeedAccelCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.hideSpeedAccelWhenGrounded = self:GetChecked()
    end)
    
    yPos = yPos - 35
    
    -- Position buttons
    local lockButton = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
    lockButton:SetSize(100, 22)
    lockButton:SetPoint("TOPLEFT", 20, yPos)
    lockButton:SetText(SkyridingUIDB.locked and "Unlock Frame" or "Lock Frame")
    lockButton:SetScript("OnClick", function(self)
        ToggleLock()
        self:SetText(SkyridingUIDB.locked and "Unlock Frame" or "Lock Frame")
    end)
    
    local resetPosButton = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
    resetPosButton:SetSize(100, 22)
    resetPosButton:SetPoint("LEFT", lockButton, "RIGHT", 10, 0)
    resetPosButton:SetText("Reset Position")
    resetPosButton:SetScript("OnClick", function()
        SkyridingUIDB.point = defaults.point
        SkyridingUIDB.relativePoint = defaults.relativePoint
        SkyridingUIDB.xOffset = defaults.xOffset
        SkyridingUIDB.yOffset = defaults.yOffset
        ApplyBackgroundToAll()
    end)
    
    -- ==================== TAB 2: HORIZONTAL ====================
    local tab2 = contentFrames[2]
    yPos = -5
    
    -- Bar Padding
    local paddingLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    paddingLabel:SetPoint("TOPLEFT", 10, yPos)
    paddingLabel:SetText("Bar Padding")
    paddingLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local padTxt = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    padTxt:SetPoint("TOPLEFT", 20, yPos)
    padTxt:SetText("Padding:")
    
    local paddingSlider = CreateFrame("Slider", nil, tab2, "OptionsSliderTemplate")
    paddingSlider:SetSize(150, 14)
    paddingSlider:SetPoint("TOPLEFT", 80, yPos)
    paddingSlider:SetMinMaxValues(-10, 15)
    paddingSlider:SetValue(SkyridingUIDB.barPadding or 5)
    paddingSlider:SetValueStep(1)
    paddingSlider:SetObeyStepOnDrag(true)
    paddingSlider.Low:SetText("-10"); paddingSlider.High:SetText("15"); paddingSlider.Text:SetText("")
    
    local paddingBox = CreateFrame("EditBox", nil, tab2, "InputBoxTemplate")
    paddingBox:SetSize(35, 18)
    paddingBox:SetPoint("LEFT", paddingSlider, "RIGHT", 10, 0)
    paddingBox:SetAutoFocus(false)
    paddingBox:SetText(tostring(SkyridingUIDB.barPadding or 5))
    
    paddingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SkyridingUIDB.barPadding = value
        paddingBox:SetText(tostring(value))
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    paddingBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(-10, math.min(15, math.floor(value + 0.5)))
            SkyridingUIDB.barPadding = value
            paddingSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 25
    
    -- Charge Bar Padding
    local chargePadTxt = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chargePadTxt:SetPoint("TOPLEFT", 20, yPos)
    chargePadTxt:SetText("Charge Bars:")
    
    local chargePaddingSlider = CreateFrame("Slider", nil, tab2, "OptionsSliderTemplate")
    chargePaddingSlider:SetSize(150, 14)
    chargePaddingSlider:SetPoint("TOPLEFT", 100, yPos)
    chargePaddingSlider:SetMinMaxValues(0, 10)
    chargePaddingSlider:SetValue(SkyridingUIDB.chargeBarPadding or 0)
    chargePaddingSlider:SetValueStep(1)
    chargePaddingSlider:SetObeyStepOnDrag(true)
    chargePaddingSlider.Low:SetText("0"); chargePaddingSlider.High:SetText("10"); chargePaddingSlider.Text:SetText("")
    
    local chargePaddingBox = CreateFrame("EditBox", nil, tab2, "InputBoxTemplate")
    chargePaddingBox:SetSize(35, 18)
    chargePaddingBox:SetPoint("LEFT", chargePaddingSlider, "RIGHT", 10, 0)
    chargePaddingBox:SetAutoFocus(false)
    chargePaddingBox:SetText(tostring(SkyridingUIDB.chargeBarPadding or 0))
    
    chargePaddingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SkyridingUIDB.chargeBarPadding = value
        chargePaddingBox:SetText(tostring(value))
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    chargePaddingBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(0, math.min(10, math.floor(value + 0.5)))
            SkyridingUIDB.chargeBarPadding = value
            chargePaddingSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 25
    
    -- Second Wind Bar Padding
    local windPadTxt = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    windPadTxt:SetPoint("TOPLEFT", 20, yPos)
    windPadTxt:SetText("Second Wind:")
    
    local windPaddingSlider = CreateFrame("Slider", nil, tab2, "OptionsSliderTemplate")
    windPaddingSlider:SetSize(150, 14)
    windPaddingSlider:SetPoint("TOPLEFT", 100, yPos)
    windPaddingSlider:SetMinMaxValues(0, 10)
    windPaddingSlider:SetValue(SkyridingUIDB.secondWindBarPadding or 3)
    windPaddingSlider:SetValueStep(1)
    windPaddingSlider:SetObeyStepOnDrag(true)
    windPaddingSlider.Low:SetText("0"); windPaddingSlider.High:SetText("10"); windPaddingSlider.Text:SetText("")
    
    local windPaddingBox = CreateFrame("EditBox", nil, tab2, "InputBoxTemplate")
    windPaddingBox:SetSize(35, 18)
    windPaddingBox:SetPoint("LEFT", windPaddingSlider, "RIGHT", 10, 0)
    windPaddingBox:SetAutoFocus(false)
    windPaddingBox:SetText(tostring(SkyridingUIDB.secondWindBarPadding or 3))
    
    windPaddingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SkyridingUIDB.secondWindBarPadding = value
        windPaddingBox:SetText(tostring(value))
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    windPaddingBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(0, math.min(10, math.floor(value + 0.5)))
            SkyridingUIDB.secondWindBarPadding = value
            windPaddingSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 35
    
    -- Bar Dimensions
    local dimLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dimLabel:SetPoint("TOPLEFT", 10, yPos)
    dimLabel:SetText("Bar Dimensions")
    dimLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 20
    
    yPos = CreateBarDimensionSliders(tab2, yPos, "Speed Bar", "speedBarWidth", "speedBarHeight", 390, 20, 100, 600, 8, 40)
    yPos = CreateBarDimensionSliders(tab2, yPos, "Charge Bars", "chargeBarWidth", "chargeBarHeight", 390, 15, 100, 600, 6, 30)
    yPos = CreateBarDimensionSliders(tab2, yPos, "Acceleration Bar", "accelBarWidth", "accelBarHeight", 390, 15, 100, 600, 6, 30)
    yPos = CreateBarDimensionSliders(tab2, yPos, "Surge Bar", "surgeBarWidth", "surgeBarHeight", 390, 15, 100, 600, 6, 30)
    yPos = CreateBarDimensionSliders(tab2, yPos, "Second Wind Bars", "secondWindBarWidth", "secondWindBarHeight", 60, 6, 20, 150, 4, 20)
    
    yPos = yPos - 10
    
    -- Element Visibility
    local visibilityLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    visibilityLabel:SetPoint("TOPLEFT", 10, yPos)
    visibilityLabel:SetText("Element Visibility")
    visibilityLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local visibilityUpdateCallback = function()
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end
    
    local showSpeedCheck = CreateFrame("CheckButton", nil, tab2, "UICheckButtonTemplate")
    showSpeedCheck:SetPoint("TOPLEFT", 20, yPos)
    showSpeedCheck:SetChecked(SkyridingUIDB.showSpeedBar ~= false)
    showSpeedCheck.text:SetText("Show Speed Bar")
    showSpeedCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showSpeedBar = self:GetChecked()
        visibilityUpdateCallback()
    end)
    
    local showChargesCheck = CreateFrame("CheckButton", nil, tab2, "UICheckButtonTemplate")
    showChargesCheck:SetPoint("TOPLEFT", 200, yPos)
    showChargesCheck:SetChecked(SkyridingUIDB.showChargeBars ~= false)
    showChargesCheck.text:SetText("Show Charge Bars")
    showChargesCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showChargeBars = self:GetChecked()
        visibilityUpdateCallback()
    end)
    
    yPos = yPos - 25
    
    local showAccelCheck = CreateFrame("CheckButton", nil, tab2, "UICheckButtonTemplate")
    showAccelCheck:SetPoint("TOPLEFT", 20, yPos)
    showAccelCheck:SetChecked(SkyridingUIDB.showAccelBar ~= false)
    showAccelCheck.text:SetText("Show Acceleration Bar")
    showAccelCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showAccelBar = self:GetChecked()
        visibilityUpdateCallback()
    end)
    
    local showSurgeCheck = CreateFrame("CheckButton", nil, tab2, "UICheckButtonTemplate")
    showSurgeCheck:SetPoint("TOPLEFT", 200, yPos)
    showSurgeCheck:SetChecked(SkyridingUIDB.showSurgeBar ~= false)
    showSurgeCheck.text:SetText("Show Whirling Surge Bar")
    showSurgeCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showSurgeBar = self:GetChecked()
        visibilityUpdateCallback()
    end)
    
    yPos = yPos - 25
    
    local showSecondWindCheck = CreateFrame("CheckButton", nil, tab2, "UICheckButtonTemplate")
    showSecondWindCheck:SetPoint("TOPLEFT", 20, yPos)
    showSecondWindCheck:SetChecked(SkyridingUIDB.showSecondWindBars ~= false)
    showSecondWindCheck.text:SetText("Show Second Wind Bars")
    showSecondWindCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showSecondWindBars = self:GetChecked()
        visibilityUpdateCallback()
    end)
    
    yPos = yPos - 35
    
    -- Bar Colors
    local colorLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    colorLabel:SetPoint("TOPLEFT", 10, yPos)
    colorLabel:SetText("Charge Bar Colors")
    colorLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local colorDefaults = {
        chargeColorFull = {0.7, 0, 0.9, 1},
        chargeColorCharging = {0.5, 0, 0.7, 0.8},
        chargeColorEmpty = {0.3, 0, 0.5, 0.6},
    }
    
    local colorUpdateCallback = function()
        if SUI.active and SUI.UpdateHorizontalChargeDisplay then
            SUI:UpdateHorizontalChargeDisplay()
        end
    end
    
    local fullColorBtn = CreateColorButton(tab2, 15, yPos, "Full Charge:", "chargeColorFull", colorDefaults.chargeColorFull, colorUpdateCallback)
    local chargingColorBtn = CreateColorButton(tab2, 220, yPos, "Charging:", "chargeColorCharging", colorDefaults.chargeColorCharging, colorUpdateCallback)
    
    yPos = yPos - 55
    
    local emptyColorBtn = CreateColorButton(tab2, 15, yPos, "Empty:", "chargeColorEmpty", colorDefaults.chargeColorEmpty, colorUpdateCallback)
    
    -- ==================== TAB 3: SPEEDOMETER ====================
    local tab3 = contentFrames[3]
    yPos = -5
    
    local speedoLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    speedoLabel:SetPoint("TOPLEFT", 10, yPos)
    speedoLabel:SetText("Speedometer Options")
    speedoLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 30
    
    local dangerZoneCheck = CreateFrame("CheckButton", nil, tab3, "UICheckButtonTemplate")
    dangerZoneCheck:SetPoint("TOPLEFT", 20, yPos)
    dangerZoneCheck:SetChecked(SkyridingUIDB.speedometerDangerZone or false)
    dangerZoneCheck.text:SetText("Highlight Danger Zone (1000-1200% in Red)")
    dangerZoneCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.speedometerDangerZone = self:GetChecked()
        if SUI.ApplySpeedometerSettings then SUI:ApplySpeedometerSettings() end
    end)
    
    yPos = yPos - 40
    
    local speedoNote = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    speedoNote:SetPoint("TOPLEFT", 20, yPos)
    speedoNote:SetWidth(380)
    speedoNote:SetJustifyH("LEFT")
    speedoNote:SetText("The Speedometer displays your current speed as a dial gauge with needle indicator.")
    speedoNote:SetTextColor(0.7, 0.7, 0.7)
    
    -- ==================== TAB 4: CIRCULAR ====================
    local tab4 = contentFrames[4]
    yPos = -5
    
    local circLabel = tab4:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    circLabel:SetPoint("TOPLEFT", 10, yPos)
    circLabel:SetText("Circular Options")
    circLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 30
    
    -- Element Visibility
    local circVisLabel = tab4:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    circVisLabel:SetPoint("TOPLEFT", 10, yPos)
    circVisLabel:SetText("Element Visibility")
    circVisLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local circVisUpdateCallback = function()
        if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
    end
    
    local circShowSpeedCheck = CreateFrame("CheckButton", nil, tab4, "UICheckButtonTemplate")
    circShowSpeedCheck:SetPoint("TOPLEFT", 20, yPos)
    circShowSpeedCheck:SetChecked(SkyridingUIDB.circularShowSpeedRing ~= false)
    circShowSpeedCheck.text:SetText("Show Speed Ring")
    circShowSpeedCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.circularShowSpeedRing = self:GetChecked()
        circVisUpdateCallback()
    end)
    
    local circShowChargesCheck = CreateFrame("CheckButton", nil, tab4, "UICheckButtonTemplate")
    circShowChargesCheck:SetPoint("TOPLEFT", 200, yPos)
    circShowChargesCheck:SetChecked(SkyridingUIDB.showChargeBars ~= false)
    circShowChargesCheck.text:SetText("Show Charge Arcs")
    circShowChargesCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showChargeBars = self:GetChecked()
        circVisUpdateCallback()
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    yPos = yPos - 25
    
    local circShowAccelCheck = CreateFrame("CheckButton", nil, tab4, "UICheckButtonTemplate")
    circShowAccelCheck:SetPoint("TOPLEFT", 20, yPos)
    circShowAccelCheck:SetChecked(SkyridingUIDB.showAccelBar ~= false)
    circShowAccelCheck.text:SetText("Show Center Glow")
    circShowAccelCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showAccelBar = self:GetChecked()
        circVisUpdateCallback()
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    local circShowSurgeCheck = CreateFrame("CheckButton", nil, tab4, "UICheckButtonTemplate")
    circShowSurgeCheck:SetPoint("TOPLEFT", 200, yPos)
    circShowSurgeCheck:SetChecked(SkyridingUIDB.showSurgeBar ~= false)
    circShowSurgeCheck.text:SetText("Show Surge Arc")
    circShowSurgeCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showSurgeBar = self:GetChecked()
        circVisUpdateCallback()
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    yPos = yPos - 25
    
    local circShowSecondWindCheck = CreateFrame("CheckButton", nil, tab4, "UICheckButtonTemplate")
    circShowSecondWindCheck:SetPoint("TOPLEFT", 20, yPos)
    circShowSecondWindCheck:SetChecked(SkyridingUIDB.showSecondWindBars ~= false)
    circShowSecondWindCheck.text:SetText("Show Second Wind")
    circShowSecondWindCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.showSecondWindBars = self:GetChecked()
        circVisUpdateCallback()
        if SUI.UpdateHorizontalLayout then SUI:UpdateHorizontalLayout() end
    end)
    
    yPos = yPos - 35
    
    -- Charge Arc Colors
    local circColorLabel = tab4:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    circColorLabel:SetPoint("TOPLEFT", 10, yPos)
    circColorLabel:SetText("Charge Arc Colors")
    circColorLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local circColorDefaults = {
        chargeColorFull = {0.7, 0, 0.9, 1},
        chargeColorCharging = {0.5, 0, 0.7, 0.8},
        chargeColorEmpty = {0.3, 0, 0.5, 0.6},
    }
    
    local circColorUpdateCallback = function()
        if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
        if SUI.UpdateHorizontalChargeDisplay then SUI:UpdateHorizontalChargeDisplay() end
    end
    
    local circFullColorBtn = CreateColorButton(tab4, 15, yPos, "Full Charge:", "chargeColorFull", circColorDefaults.chargeColorFull, circColorUpdateCallback)
    local circChargingColorBtn = CreateColorButton(tab4, 220, yPos, "Charging:", "chargeColorCharging", circColorDefaults.chargeColorCharging, circColorUpdateCallback)
    
    yPos = yPos - 55
    
    local circEmptyColorBtn = CreateColorButton(tab4, 15, yPos, "Empty:", "chargeColorEmpty", circColorDefaults.chargeColorEmpty, circColorUpdateCallback)
    
    yPos = yPos - 55
    
    local circNote = tab4:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    circNote:SetPoint("TOPLEFT", 20, yPos)
    circNote:SetWidth(380)
    circNote:SetJustifyH("LEFT")
    circNote:SetText("Note: Charge colors are shared with Horizontal mode.")
    circNote:SetTextColor(0.7, 0.7, 0.7)
    
    -- ==================== TAB 5: VIGOR ====================
    local tab5 = contentFrames[5]
    yPos = -5
    
    local vigorLabel = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    vigorLabel:SetPoint("TOPLEFT", 10, yPos)
    vigorLabel:SetText("Vigor Orbs Options")
    vigorLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 30
    
    local showWingsCheck = CreateFrame("CheckButton", nil, tab5, "UICheckButtonTemplate")
    showWingsCheck:SetPoint("TOPLEFT", 20, yPos)
    showWingsCheck:SetChecked(SkyridingUIDB.vigorShowWings ~= false)
    showWingsCheck.text:SetText("Show Wing Decorations")
    showWingsCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.vigorShowWings = self:GetChecked()
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    end)
    
    yPos = yPos - 35
    
    -- Vigor Orb Padding
    local vigorPadLabel = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    vigorPadLabel:SetPoint("TOPLEFT", 10, yPos)
    vigorPadLabel:SetText("Orb Spacing")
    vigorPadLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local vigorPadTxt = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vigorPadTxt:SetPoint("TOPLEFT", 20, yPos)
    vigorPadTxt:SetText("Spacing:")
    
    local vigorPadSlider = CreateFrame("Slider", nil, tab5, "OptionsSliderTemplate")
    vigorPadSlider:SetSize(150, 14)
    vigorPadSlider:SetPoint("TOPLEFT", 80, yPos)
    vigorPadSlider:SetMinMaxValues(-5, 20)
    vigorPadSlider:SetValue(SkyridingUIDB.vigorOrbSpacing or 6)
    vigorPadSlider:SetValueStep(1)
    vigorPadSlider:SetObeyStepOnDrag(true)
    vigorPadSlider.Low:SetText("-5"); vigorPadSlider.High:SetText("20"); vigorPadSlider.Text:SetText("")
    
    local vigorPadBox = CreateFrame("EditBox", nil, tab5, "InputBoxTemplate")
    vigorPadBox:SetSize(35, 18)
    vigorPadBox:SetPoint("LEFT", vigorPadSlider, "RIGHT", 10, 0)
    vigorPadBox:SetAutoFocus(false)
    vigorPadBox:SetText(tostring(SkyridingUIDB.vigorOrbSpacing or 6))
    
    vigorPadSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SkyridingUIDB.vigorOrbSpacing = value
        vigorPadBox:SetText(tostring(value))
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    end)
    
    vigorPadBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(-5, math.min(20, math.floor(value + 0.5)))
            SkyridingUIDB.vigorOrbSpacing = value
            vigorPadSlider:SetValue(value)
            self:SetText(tostring(value))
            if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
        end
        self:ClearFocus()
    end)
    
    yPos = yPos - 35
    
    -- Effects
    local effectsLabel = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    effectsLabel:SetPoint("TOPLEFT", 10, yPos)
    effectsLabel:SetText("Effects")
    effectsLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local showSwirlCheck = CreateFrame("CheckButton", nil, tab5, "UICheckButtonTemplate")
    showSwirlCheck:SetPoint("TOPLEFT", 20, yPos)
    showSwirlCheck:SetChecked(SkyridingUIDB.vigorShowSwirl ~= false)
    showSwirlCheck.text:SetText("Show Energy Swirl Effect")
    showSwirlCheck:SetScript("OnClick", function(self)
        SkyridingUIDB.vigorShowSwirl = self:GetChecked()
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    end)
    
    yPos = yPos - 40
    
    -- Orb Color
    local orbColorLabel = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    orbColorLabel:SetPoint("TOPLEFT", 10, yPos)
    orbColorLabel:SetText("Orb Color")
    orbColorLabel:SetTextColor(1, 0.82, 0)
    yPos = yPos - 25
    
    local orbColorTxt = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    orbColorTxt:SetPoint("TOPLEFT", 20, yPos)
    orbColorTxt:SetText("Energy Color:")
    
    local orbColorSwatch = CreateFrame("Button", nil, tab5, "BackdropTemplate")
    orbColorSwatch:SetSize(24, 24)
    orbColorSwatch:SetPoint("LEFT", orbColorTxt, "RIGHT", 10, 0)
    orbColorSwatch:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    local orbCol = SkyridingUIDB.vigorOrbColor or {0.22, 0.58, 0.78}
    orbColorSwatch:SetBackdropColor(orbCol[1], orbCol[2], orbCol[3], 1)
    orbColorSwatch:SetBackdropBorderColor(0, 0, 0, 1)
    
    orbColorSwatch:SetScript("OnClick", function()
        local currentCol = SkyridingUIDB.vigorOrbColor or {0.22, 0.58, 0.78}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = currentCol[1],
            g = currentCol[2],
            b = currentCol[3],
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                SkyridingUIDB.vigorOrbColor = {r, g, b}
                orbColorSwatch:SetBackdropColor(r, g, b, 1)
                if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
            end,
            cancelFunc = function(previousValues)
                SkyridingUIDB.vigorOrbColor = {previousValues.r, previousValues.g, previousValues.b}
                orbColorSwatch:SetBackdropColor(previousValues.r, previousValues.g, previousValues.b, 1)
                if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
            end,
        })
    end)
    
    -- Reset to default button
    local resetOrbColorBtn = CreateFrame("Button", nil, tab5, "UIPanelButtonTemplate")
    resetOrbColorBtn:SetSize(60, 20)
    resetOrbColorBtn:SetPoint("LEFT", orbColorSwatch, "RIGHT", 10, 0)
    resetOrbColorBtn:SetText("Reset")
    resetOrbColorBtn:SetScript("OnClick", function()
        SkyridingUIDB.vigorOrbColor = {0.22, 0.58, 0.78}
        orbColorSwatch:SetBackdropColor(0.22, 0.58, 0.78, 1)
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
    end)
    
    yPos = yPos - 35
    
    local vigorNote = tab5:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vigorNote:SetPoint("TOPLEFT", 20, yPos)
    vigorNote:SetWidth(380)
    vigorNote:SetJustifyH("LEFT")
    vigorNote:SetText("The Vigor Orbs display shows your charges as gemstone orbs with animated energy effects.")
    vigorNote:SetTextColor(0.7, 0.7, 0.7)
    
    -- ==================== CLOSE BUTTON ====================
    local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 22)
    closeButton:SetPoint("BOTTOM", 0, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() optionsFrame:Hide() end)
    
    -- Select first tab by default
    SelectTab(1)
end

function SUI:ToggleOptionsFrame()
    InitializeOptionsFrame()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not SkyridingUIDB then SkyridingUIDB = {} end
        
        -- Apply defaults
        for k, v in pairs(defaults) do
            if SkyridingUIDB[k] == nil then
                if type(v) == "table" then
                    SkyridingUIDB[k] = {v[1], v[2], v[3], v[4]}
                else
                    SkyridingUIDB[k] = v
                end
            end
        end
        
        -- Initialize all modules
        if SUI.InitHorizontalDefaults then SUI:InitHorizontalDefaults() end
        if SUI.InitSpeedometerDefaults then SUI:InitSpeedometerDefaults() end
        if SUI.InitCircularDefaults then SUI:InitCircularDefaults() end
        if SUI.InitVigorDefaults then SUI:InitVigorDefaults() end
        
        -- Apply settings
        if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
        if SUI.ApplySpeedometerSettings then SUI:ApplySpeedometerSettings() end
        if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
        
        RegisterMinimapButton()
        CreateBlizzardOptionsPanel()
        
        print("|cff00ff00SkyridingUI|r loaded! Type /sui options for settings.")
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            if IsSkyriding() or IsOnSkyridingMount() then
                SUI:SetActive(true)
            else
                SUI:SetActive(false)
            end
        end)
        
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            if spellID == ASCENT_SPELL_ID then
                SUI.ascentStart = GetTime()
            elseif spellID == WHIRLING_SURGE_ID then
                SUI.whirlingSurgeStart = GetTime()
                SUI.whirlingSurgeDuration = WHIRLING_SURGE_DURATION
            end
        end
        
    elseif event == "SPELL_UPDATE_CHARGES" then
        if SUI.active and SUI.UpdateHorizontalChargeDisplay then
            SUI:UpdateHorizontalChargeDisplay()
        end
        
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        C_Timer.After(0.3, function()
            if IsSkyriding() or IsOnSkyridingMount() then
                SUI:SetActive(true)
            else
                SUI:SetActive(false)
            end
        end)
        
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local shouldBeActive = IsSkyriding() or IsOnSkyridingMount()
            if shouldBeActive and not SUI.active then
                SUI:SetActive(true)
            elseif not shouldBeActive and SUI.active then
                C_Timer.After(0.2, function()
                    if not IsSkyriding() and not IsOnSkyridingMount() and SUI.active then
                        SUI:SetActive(false)
                    end
                end)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_SKYRIDINGUI1 = "/skyridingui"
SLASH_SKYRIDINGUI2 = "/sui"
SlashCmdList["SKYRIDINGUI"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "options" or msg == "config" or msg == "settings" then
        SUI:ToggleOptionsFrame()
    elseif msg == "lock" then
        SkyridingUIDB.locked = true
        SkyridingUIDB.speedometerLocked = true
        SkyridingUIDB.circularLocked = true
        SkyridingUIDB.vigorLocked = true
        if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
        print("|cff00ff00SkyridingUI|r: Frame locked")
    elseif msg == "unlock" then
        SkyridingUIDB.locked = false
        SkyridingUIDB.speedometerLocked = false
        SkyridingUIDB.circularLocked = false
        SkyridingUIDB.vigorLocked = false
        if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
        print("|cff00ff00SkyridingUI|r: Frame unlocked. Drag to move.")
    elseif msg == "reset" then
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                SkyridingUIDB[k] = {v[1], v[2], v[3], v[4]}
            else
                SkyridingUIDB[k] = v
            end
        end
        if SUI.ApplyHorizontalSettings then SUI:ApplyHorizontalSettings() end
        if SUI.ApplySpeedometerSettings then SUI:ApplySpeedometerSettings() end
        if SUI.ApplyCircularSettings then SUI:ApplyCircularSettings() end
        if SUI.ApplyVigorSettings then SUI:ApplyVigorSettings() end
        print("|cff00ff00SkyridingUI|r: All settings reset to defaults")
    elseif msg == "toggle" then
        if SUI.active then
            SUI:SetActive(false)
            print("|cff00ff00SkyridingUI|r: Hidden")
        else
            SUI:SetActive(true)
            print("|cff00ff00SkyridingUI|r: Shown")
        end
    elseif msg == "show" then
        SUI:SetActive(true)
        print("|cff00ff00SkyridingUI|r: Shown")
    elseif msg == "hide" then
        SUI:SetActive(false)
        print("|cff00ff00SkyridingUI|r: Hidden")
    elseif msg == "" or msg == "help" then
        print("|cff00ff00SkyridingUI|r Commands:")
        print("  /sui options - Open options menu")
        print("  /sui lock - Lock the frame")
        print("  /sui unlock - Unlock the frame for moving")
        print("  /sui reset - Reset position and scale")
        print("  /sui toggle - Toggle the UI")
        print("  /sui show - Show the UI")
        print("  /sui hide - Hide the UI")
    else
        print("|cff00ff00SkyridingUI|r: Unknown command '" .. msg .. "'. Type /sui for help.")
    end
end
