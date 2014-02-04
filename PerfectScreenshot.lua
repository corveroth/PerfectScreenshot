-- TODO: Reloading UI during the delay on a cinematic shot causes FCT to remain turned off.

--[[
	Welcome to Perfect Screenshot 2.0.
	There are a few significant changes in this version.
	
	I've removed most of the configuration, for the time being. I don't believe in options for their own sake.
	I think there might be room for a few presets, but if you want all of the configuration of the Blizzard Names panel,
	you probably have your choices set there anyways. I don't see a need to duplicate that panel.
	
	The older, pre-2010 versions of PS used UIParent.Hide to remove the gui from shots. This is no longer possible due to in-combat lockdown.
	Instead, I'm using UIParent.SetAlpha, and then manually hiding or setalphaing those handful of frames that aren't parented to the UIParent.
	At the moment, that consists of = {
		MinimapCluster.Hide
		CompactPartyFrameMember##Background.SetAlpha, 1-5
		CompactRaidGroup##Member##Background.SetAlpha, 1-8, 1-5
	}
	There is a new call to SetUIVisibility to hide RaidTargetIcons and nameplates.
	
	The "viewport", aka the dimensions of the WorldFrame, can no longer be altered in combat.
	That code has been removed, along with the references to SunnArt, as the two functions were complementary.
	
	The biggest weakness in this addon comes from Blizzard: there is no way to immediately hide their FloatingCombatText.
	There are CVars controlling the creation of new FCT text, but toggling them does nothing for text already on screen.
	On account of this, there is a new binding available that toggles them and shoots on a timer to allow the existing text to clear.
]]--

PerfectScreenshot = LibStub("AceAddon-3.0"):NewAddon(	"PerfectScreenshot",
														"AceConsole-3.0",
														"AceEvent-3.0",
														"AceTimer-3.0");

-- Binding Variables
BINDING_HEADER_PERFECTSCREENSHOT_HEADER = "Perfect Screenshot";
BINDING_NAME_PERFECTSCREENSHOT_TIMED = "Delayed Cinematic Shot";
BINDING_NAME_PERFECTSCREENSHOT_NAMES = "Names-On, No-UI Shot";
BINDING_NAME_PERFECTSCREENSHOT_WORLD = "Names-Off, No-UI Shot";

-- Gonna leave this here in case I decide to come back and tinker with config again.
--[[
-- Build up the various CVar options using the same data Blizz uses to create their config panels.
-- As of build 17688, NamePanelOptions is at InterfaceOptionsPanels.lua:1173
-- As of build 17688, FCTPanelOptions  is at InterfaceOptionsPanels.lua:1377
do
	for cVar, t in pairs(NamePanelOptions) do
		Options.args[cVar] = {
			name = _G[t.text],
			type = "toggle",
		}
	end

	for cVar, t in pairs(FCTPanelOptions) do
		Options.args[cVar] = {
			name = _G[t.text],
			type = "toggle",
		}
	end
end
--]]

--[[
	There are a few cvars intentionally omitted here.
	UnitName<Friendly|Enemy>CreationName seems to be unused.
	UnitNamePlayerGuild, UnitNameGuildTitle, and UnitNamePlayerPVPTitle are all unnecessary, because names are hidden anyways.
--]]
PerfectScreenshot.nameCVars = {
	"UnitNameOwn",
	"UnitNameNPC",
	"UnitNameNonCombatCreatureName",
	
	"UnitNameEnemyPlayerName",
	"UnitNameEnemyPetName",
	"UnitNameEnemyGuardianName",
	"UnitNameEnemyTotemName",
	
	"UnitNameFriendlyPlayerName",
	"UnitNameFriendlyPetName",
	"UnitNameFriendlyGuardianName",
	"UnitNameFriendlyTotemName",
}

PerfectScreenshot.fctCVars = {
	"CombatDamage",
	"CombatHealing",
	"enableCombatText",
	"fctSpellMechanics",
}

--===================================
-- PerfectScreenshot GUI Functions
--===================================

function PerfectScreenshot:ShowStartupTip()
	local startupStrings = {
		[1] = {
				text = "PerfectScreenshot offers you three options for taking screenshots while automatically hiding the interface.",
				rightOffset = 80,
				},
		[2] = {
				text = "Currently bound to SHIFT-PrintScreen is the 'Names-Off, No-UI' shot. This hides just about everything during the screenshot.",
				rightOffset = 80,
				},
		[3] = {
				text = "CTRL-PrintScreen leaves names showing, if you want to see those.\n\n",
				rightOffset = 80,
				},
		[4] = {
				text = "Due to technical limits, those two cannot hide Blizzard's Floating Combat Text, or the names of wild Battle Pets when Pet Tracking is active. If either of those are in the way of your perfect screenshot, ALT-PrintScreen will get you a truly cinematic, clear view on a two second delay. You'll see a timer on-screen!",
				leftOffset = 78,
				},
		[5] = {
				text = "Of course, those are just the default keybindings. You can change them from the normal Key Bindings menu, or use |cffffdd00/ps|r to get there quickly!",
				leftOffset = 78,
				},
		}
	
	local padding = 12
	
	local frame = CreateFrame("Frame", "PerfectScreenshotFrame", UIParent, "HelpPlateBox")
	frame:SetPoint("CENTER", 0, 0)
	frame:SetSize(600, 290)
	frame.BG:SetTexture(0,0,0,0.9)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
	
	local title = frame:CreateFontString("PerfectScreenshotFrameTitle", "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -padding)
	title:SetText(BINDING_HEADER_PERFECTSCREENSHOT_HEADER)
	
	for i, str in ipairs(startupStrings) do
		local fs = frame:CreateFontString("PerfectScreenshotFrameText"..i, "ARTWORK", "GameFontWhite")
		local leftOffset = str.leftOffset or 0
		local rightOffset = str.rightOffset or 0
		
		if i == 1 then
			fs:SetPoint("TOPLEFT", padding + leftOffset, - padding - 30)
		else
			fs:SetPoint("TOPLEFT", _G["PerfectScreenshotFrameText"..(i-1)], "BOTTOMLEFT", - (startupStrings[i-1].leftOffset or 0) + leftOffset, - padding)
		end
		fs:SetWidth(frame:GetWidth() - rightOffset - leftOffset - padding*2 + 2)
		fs:SetJustifyH("LEFT")
		fs:SetText(str.text)
	end
	
	-- Add the Timer Eye
	local eye = frame:CreateTexture()
	eye:SetTexture([[Interface/LFGFRAME/LFG-Eye]])
	eye:SetTexCoord(0.125, 0.25, 0, 0.25)
	-- eye:SetTexCoord(0.25, 0.375, 0, 0.25)
	eye:SetSize(64, 64)
	eye:SetPoint("TOPRIGHT", PerfectScreenshotFrameText4, "TOPLEFT", -padding, 0)
	local eyeText = frame:CreateFontString("PerfectScreenshotFrameEyeText", "ARTWORK", "GameFontRedLarge")
	eyeText:SetFont("Fonts\\FRIZQT__.TTF", 24, "THICKOUTLINE")
	eyeText:SetPoint("TOP", eye, "BOTTOM", 0, 12)
	eyeText:SetText("1.8")
	
	
	
	-- Add the keys
	local keys = { "SHIFT", "PRTSCN", }
	for i, text in ipairs(keys) do
		local texture = frame:CreateTexture("PerfectScreenshotFrameKey"..i, "ARTWORK");
		texture:SetTexture("Interface\\TutorialFrame\\UI-TUTORIAL-FRAME");
		texture:SetTexCoord(0.1542969, 0.3007813, 0.8046875, 0.9433594);
		texture:SetSize(86+12*(i-1), 64+8*(i-1));
		texture:SetDrawLayer("ARTWORK", i)
		texture:SetPoint("TOPLEFT", PerfectScreenshotFrameText1, "TOPRIGHT", -24+16*(i-1), 60 - 40*i)
		local keyString = frame:CreateFontString("PerfectScreenshotFrameKeyString"..i, "ARTWORK", "GameFontBlackSmall");
		keyString:SetPoint("CENTER", texture, "CENTER", 0, 10);
		keyString:SetText(text)
	end
	  
	-- And a pair of close buttons
	local closeButton = CreateFrame("Button", "PerfectScreenshotFrameCloseButton", frame, "UIPanelButtonTemplate")
	closeButton:SetText(CLOSE)
	closeButton:SetSize(60, 22)
	closeButton:SetScript("OnClick", function() self.Frame:Hide() end)
	
	local changeButton = CreateFrame("Button", "PerfectScreenshotFrameChangeButton", frame, "UIPanelButtonTemplate")
	changeButton:SetText("Change Key Bindings")
	changeButton:SetSize(150, 22)
	changeButton:SetScript("OnClick", function() self:SlashCmd() self.Frame:Hide() end)
	
	-- local diff = (changeButton:GetWidth()-closeButton:GetWidth())/2
	
	-- closeButton:SetPoint("BOTTOM", (closeButton:GetWidth()/2)+diff + padding/2, padding)
	closeButton:SetPoint("BOTTOM", (changeButton:GetWidth()/2) + padding/2, padding)
	changeButton:SetPoint("BOTTOM", -(closeButton:GetWidth()/2) - padding/2, padding)
	-- changeButton:SetPoint("BOTTOM", -diff - padding/2, padding)
	
	self.Frame = frame
	frame:Show()
end

function PerfectScreenshot:ShowTimer()
	if not self.timerFrame then
		local frame = CreateFrame("Frame", "PerfectScreenshotTimerFrame", UIParent)
		frame:SetSize(128, 160)
		-- Add the Timer Eye
		local eye = frame:CreateTexture("PerfectScreenshotTimerEye")
		eye:SetTexture([[Interface/LFGFRAME/LFG-Eye]])
		eye:SetTexCoord(0.125, 0.25, 0, 0.25)
		-- eye:SetTexCoord(0.25, 0.375, 0, 0.25)
		eye:SetSize(128, 128)
		eye:SetPoint("CENTER")
		local eyeText = frame:CreateFontString("PerfectScreenshotTimerText", "ARTWORK", "GameFontNormalLeftYellow")
		eyeText:SetFont("Fonts\\FRIZQT__.TTF", 36, "THICKOUTLINE")
		eyeText:SetJustifyH("RIGHT")
		eyeText:SetPoint("TOP", eye, "BOTTOM", 0, 12)
		-- eyeText:SetText("1.8")
		
		frame:SetPoint("CENTER", 0, 40)
		
		self.timerFrame = frame
	end
	
	self.timerState = 0
	self.timer = self:ScheduleRepeatingTimer("UpdateTimer", 0.1)
	-- self.timerFrame
	
end 

function PerfectScreenshot:UpdateTimer()
    local timerStepDuration = 0.1
    local numTimerSteps = (self.fctFadeTime + 0.05)/timerStepDuration
    local numEyeSteps = 5
    local eyeStepDuration = numTimerSteps/numEyeSteps
	local eyeState = math.floor(self.timerState/eyeStepDuration)
    
	PerfectScreenshotTimerEye:SetTexCoord(0.125*eyeState, 0.125 + 0.125*eyeState, 0, 0.25)
    local timerText = math.floor((self.fctFadeTime - self.timerState*timerStepDuration)*10)/10
    print(timerText)
	PerfectScreenshotTimerText:SetText(format("%.1f",timerText))
	
	if timerText < 0 then
		self:HideTimer()
	else
        self.timerFrame:Show()
    end
    self.timerState = self.timerState + 1
end

function PerfectScreenshot:HideTimer()
    self.timerState = 0
	self.timerFrame:Hide()
	self:CancelTimer(self.timer)
end

--===================================
-- Primary Visibility Functions
--===================================

-- Show/Hide most UI elements
function PerfectScreenshot:SetUIParentVisible(isVisible)
	if isVisible then
		UIParent:SetAlpha(1)
	else
		UIParent:SetAlpha(0)
	end
end

-- Hiding just the MinimapCluster also hides the Minimap on the Blizz UI, but some replacements require that it be hid separately.
function PerfectScreenshot:SetNonParentedFramesVisible(isVisible)
	if isVisible then
		MinimapCluster:Show()
		Minimap:Show()
		
		local f
		for i = 1, 5 do
			f = _G["CompactPartyFrameMember"..i.."Background"]
			if f then f:SetAlpha(1) end
		end
		for i = 1, 8 do
			for j = 1, 5 do
				f = _G["CompactRaidGroup"..i.."Member"..j.."Background"]
				if f then f:SetAlpha(1) end
			end
		end
		for i = 1, 2 do
			f = _G["DropDownList"..i]
			if f then f:SetAlpha(1) end
		end
	else
		MinimapCluster:Hide()
		Minimap:Hide()
		local f
		for i = 1, 5 do
			f = _G["CompactPartyFrameMember"..i.."Background"]
			if f then f:SetAlpha(0) end
		end
		for i = 1, 8 do
			for j = 1, 5 do
				f = _G["CompactRaidGroup"..i.."Member"..j.."Background"]
				if f then f:SetAlpha(0) end
			end
		end
		for i = 1, 2 do
			f = _G["DropDownList"..i]
			if f then f:SetAlpha(0) end
		end
	end
end

-- This handles nameplates, raid target icons, and the targeting circle.
function PerfectScreenshot:SetPsuedoWorldGraphicsVisible(isVisible)
	SetUIVisibility(isVisible)
end



--===================================
-- Name Visibility Functions
--===================================

PerfectScreenshot.petTrackingIconPath = [[Interface\Icons\tracking_wildpet]]

-- Battle pet names aren't hidden by the regular CVars. Instead, we need to toggle the tracking.
function PerfectScreenshot:SavePetTracking()
	local path
	for i = 1, GetNumTrackingTypes() do
		_, path, active = GetTrackingInfo(i)
		if path == self.petTrackingIconPath then
			self.temp_petTrackingIndex = i
			self.temp_petTrackingState = active
		end
	end
end

function PerfectScreenshot:RestorePetTracking()
	SetTracking(self.temp_petTrackingIndex,self.temp_petTrackingState)
end

function PerfectScreenshot:DisablePetTracking()
	SetTracking(self.temp_petTrackingIndex, false)
end

function PerfectScreenshot:SaveNameCVars()
	if self.temp_name_cvars and type(self.temp_name_cvars)=="table" then
		table.wipe(self.temp_name_cvars)
	else
		self.temp_name_cvars = {}
	end
	
	for _, cvar in ipairs(self.nameCVars) do
		self.temp_name_cvars[cvar] = GetCVar(cvar)
	end
	
	for i = 1, GetNumTrackingTypes() do
		local _, path, active = GetTrackingInfo(i)
		if path == self.petTrackingIconPath and active then
			self.temp_pettracking = i
		end
	end
end

function PerfectScreenshot:RestoreNameCVars()
	if self.temp_name_cvars then
		for cvar, value in pairs(self.temp_name_cvars) do
			SetCVar(cvar, value)
		end
		
		for i = 1, GetNumTrackingTypes() do
			local _, path, active = GetTrackingInfo(i)
			if path == self.petTrackingIconPath then
				self.temp_pettracking = active
			end
		end
	else

	end
end

function PerfectScreenshot:DisableNameCVars()
	for _, cvar in ipairs(self.nameCVars) do
		SetCVar(cvar, 0)
	end
end



--=============================================
-- Floating Combat Text Visibility Functions
--=============================================

PerfectScreenshot.fctFadeTime = 1.95;

function PerfectScreenshot:SaveFCTCVars()
	if self.temp_fct_cvars and type(self.temp_fct_cvars)=="table" then
		table.wipe(self.temp_fct_cvars)
	else
		self.temp_fct_cvars = {}
	end
	
	for _, cvar in ipairs(self.fctCVars) do
		self.temp_fct_cvars[cvar] = GetCVar(cvar)
	end
end

function PerfectScreenshot:RestoreFCTCVars()
	if self.temp_fct_cvars then
		for cvar, value in pairs(self.temp_fct_cvars) do
			SetCVar(cvar, value)
		end
	else
	
	end
end

function PerfectScreenshot:DisableFCTCVars()
	for _, cvar in ipairs(self.fctCVars) do
		SetCVar(cvar, 0)
	end
end

--===================================
-- Core functionality
--===================================

function PerfectScreenshot:SetInterfaceVisible(isVisible)
	self:SetUIParentVisible(isVisible)
	self:SetNonParentedFramesVisible(isVisible)
	self:SetPsuedoWorldGraphicsVisible(isVisible)
	
	self.hiddenElements.interface = not isVisible
end

function PerfectScreenshot:SetNamesVisible(isVisible)
	if isVisible then
		self:RestoreNameCVars()
	else
		self:SaveNameCVars()
		self:DisableNameCVars()
	end
	
	self.hiddenElements.names = not isVisible
end

-- Disabling FCT requires a delay of fctFadeTime so that the text can clear the screen.
function PerfectScreenshot:SetCombatTextVisible(isVisible)
	if isVisible then
		self:RestoreFCTCVars()
	else
		self:SaveFCTCVars()
		self:DisableFCTCVars()
	end
	
	self.hiddenElements.fct = not isVisible
end

-- Toggling wild battle pet names requires a latency-dependent delay, because tracking is actually an aura.
function PerfectScreenshot:SetPetTrackingVisible(isVisible)
	if isVisible then
		self:RestorePetTracking()
	else
		self:SavePetTracking()
		self:DisablePetTracking()
	end
	
	self.hiddenElements.tracking = not isVisible
end

function PerfectScreenshot:TakeShot(hideUI, hideNames, hideCombatText)
	-- Only allow one screenshot at a time.
	if self.shooting then
		return
	else
		self.shooting = true
	end
	
	-- Non-FCT shots require a delay.
	if hideCombatText then
		self:SetCombatTextVisible(false)
		self:SetPetTrackingVisible(false)
		self:TakeDelayedScreenshot(hideUI, hideNames)
	else
		self:TakeScreenshot(hideUI, hideNames)
	end
end

function PerfectScreenshot:TakeDelayedScreenshot(hideUI, hideNames)
	-- print("Shooting in 2.0s...")
	self:ShowTimer()
	self:ScheduleTimer("TakeScreenshot", self.fctFadeTime, hideUI, hideNames)
end

function PerfectScreenshot:TakeScreenshot(hideUI, hideNames)
	if hideUI then
		self:SetInterfaceVisible(false)
	end
	
	if hideNames then
		self:SetNamesVisible(false)
	end
	
	TakeScreenshot()
end

function PerfectScreenshot:RestoreUI()
	if self.hiddenElements.interface then
		self:SetInterfaceVisible(true)
	end
	if self.hiddenElements.names then
		self:SetNamesVisible(true)
	end
	if self.hiddenElements.fct then
		self:SetCombatTextVisible(true)
	end
	if self.hiddenElements.tracking then
		self:SetPetTrackingVisible(true)
	end
	
	self.shooting = nil
end

function PerfectScreenshot:ADDON_LOADED(e, a)
	if a == "Blizzard_BindingUI" and self.delayedScroll then
		self.delayedScroll = nil
		self:ScrollToBindings()
	end
end

function PerfectScreenshot:SCREENSHOT_FAILED()
	PerfectScreenshot:RestoreUI();
	print("Screenshot failed. Please report this, along with whatever you were doing at the time.");
end

function PerfectScreenshot:SCREENSHOT_SUCCEEDED()
	PerfectScreenshot:RestoreUI();
end

function PerfectScreenshot:ScrollToBindings()
	ShowUIPanel(KeyBindingFrame)
	local numBindings = GetNumBindings()
	local maxScroll = numBindings - KEY_BINDINGS_DISPLAYED
	for i = 1, numBindings do
		if GetBinding(i) == "HEADER_PERFECTSCREENSHOT_HEADER" then
			local scrollValue = i < maxScroll and i or maxScroll
			FauxScrollFrame_OnVerticalScroll(KeyBindingFrameScrollFrame, scrollValue*KEY_BINDING_HEIGHT, KEY_BINDING_HEIGHT)
		end
	end
	KeyBindingFrame_Update()
end

function PerfectScreenshot:SlashCmd()
	if IsAddOnLoaded("Blizzard_BindingUI") then
		self:ScrollToBindings()
	else
		self.delayedScroll = true
		KeyBindingFrame_LoadUI()
	end
end

function PerfectScreenshot:OnInitialize()
	self:RegisterEvent("ADDON_LOADED");
	self:RegisterEvent("SCREENSHOT_FAILED");
	self:RegisterEvent("SCREENSHOT_SUCCEEDED");
	self:RegisterChatCommand("ps", "SlashCmd")
	self.db = LibStub("AceDB-3.0"):New("PerfectScreenshotDB")
	if not self.db.global.tutorialShown then
		self:ShowStartupTip()
		self.db.global.tutorialShown = true
	end
	self.hiddenElements = {
		interface = false,
		names = false,
		fct = false,
		tracking = false,
	}
end