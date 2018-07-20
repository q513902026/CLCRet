local _, trueclass = UnitClass("player")
if trueclass ~= "PALADIN" then return end

local sovName, sovId, sovSpellTexture
sovId = 31803
sovName, _, sovSpellTexture = GetSpellInfo(sovId)

local BGTEX = "Interface\\AddOns\\clcret\\textures\\minimalist"
local BORDERTEX = "Interface\\AddOns\\clcret\\textures\\border"
local borderType = {
	"Interface\\AddOns\\clcret\\textures\\border",					-- light
	"Interface\\AddOns\\clcret\\textures\\border_medium",			-- medium
	"Interface\\AddOns\\clcret\\textures\\border_heavy"				-- heavy
}

-- bars for sov tracking
local sovBars = {}
local MAX_SOVBARS = 5
local sovAnchor
clcret.showSovAnchor = false
local playerName

local db


-- ---------------------------------------------------------------------------------------------------------------------
-- MULTIPLE TARGET SOV TRACKING - Experimental
-- ---------------------------------------------------------------------------------------------------------------------
-- CLUE EVENTS TO TRACK
-- SPELL_AURA_APPLIED -> dot applied 
-- SPELL_AURA_APPLIED_DOSE -> dot stacks
-- SPELL_AURA_REMOVED_DOSE -> dot stacks get removed
-- SPELL_AURA_REFRESH -> dot refresh at 5 stacks
-- SPELL_AURA_REMOVED -> dot removed
-- ---------------------------------------------------------------------------------------------------------------------

local refreshers = {
	[24275]	= true, -- hammer of wrath
	[35395]	= true, 	-- crusader strike
	[85256]	= true, 	-- templar's verdict
	[20271]	= true, 	-- judgement
	[31804] = true, 	-- judgement of truth
	[879]	= true, 		-- exorcism
}

function clcret:SOV_COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, spellType, dose, ...)
	if sourceName == playerName then
		if spellId == sovId then
			if combatEvent == "SPELL_AURA_APPLIED" then
				self:Sov_SPELL_AURA_APPLIED(destGUID, destName)
			elseif combatEvent == "SPELL_AURA_APPLIED_DOSE" then
				self:Sov_SPELL_AURA_APPLIED_DOSE(destGUID, destName, dose)
			elseif combatEvent == "SPELL_AURA_REMOVED_DOSE" then
				self:Sov_SPELL_AURA_REMOVED_DOSE(destGUID, destName, dose)
			elseif combatEvent == "SPELL_AURA_REMOVED" then
				self:Sov_SPELL_AURA_REMOVED(destGUID)
			end
		else
			if combatEvent == "SWING_DAMAGE" then
				self:Sov_SPELL_AURA_REFRESH(destGUID, destName)
			elseif combatEvent == "SPELL_DAMAGE" and refreshers[spellId] then
				self:Sov_SPELL_AURA_REFRESH(destGUID, destName)
			end
		end
	end
end

-- starts to track the hot for that guid
function clcret:Sov_SPELL_AURA_APPLIED(guid, name, dose)
	dose = dose or 1
	for i = 1, MAX_SOVBARS do
		if sovBars[i].active == false then
			local bar = sovBars[i]
			bar.active = true
			bar.guid = guid
			bar.label:SetText(name)
			bar.start = GetTime()
			bar.duration = 15
			bar.labelStack:SetText(dose)
			return
		end
	end
end

-- updates the stack for the guid if it founds it, also refreshes timer
function clcret:Sov_SPELL_AURA_APPLIED_DOSE(guid, name, dose)
	for i = 1, MAX_SOVBARS do
		if sovBars[i].guid == guid then
			sovBars[i].labelStack:SetText(dose)
			sovBars[i].start = GetTime()
			sovBars[i].active = true
			return
		end
	end
	
	-- not found, but try to apply it
	-- clcret:Sov_SPELL_AURA_APPLIED(guid, name, dose)
end

-- updates the stack for the guid if it founds it
function clcret:Sov_SPELL_AURA_REMOVED_DOSE(guid, name, dose)
	for i = 1, MAX_SOVBARS do
		if sovBars[i].guid == guid then
			sovBars[i].labelStack:SetText(dose)
			sovBars[i].active = true
			return
		end
	end
	
	-- not found, but try to apply it
	clcret:Sov_SPELL_AURA_APPLIED(guid, name, dose)
end

-- refreshes the timer
function clcret:Sov_SPELL_AURA_REFRESH(guid, name)
	for i = 1, MAX_SOVBARS do
		if sovBars[i].guid == guid then
			sovBars[i].start = GetTime()
			sovBars[i].active = true
			return
		end
	end
	
	-- not found, but try to apply it
	-- clcret:Sov_SPELL_AURA_APPLIED(guid, name, 5)
end

-- deactivates the bar
function clcret:Sov_SPELL_AURA_REMOVED(guid)
	for i = 1, MAX_SOVBARS do
		if sovBars[i].guid == guid then
			sovBars[i].active = false
			sovBars[i]:Hide()
			return
		end
	end
end


-- update the bars
function clcret:UpdateSovBars()
	self.targetGUID = UnitGUID("target")

	for i = 1, MAX_SOVBARS do
		self:UpdateSovBar(i)
	end
end
function clcret:UpdateSovBar(index)
	local bar = sovBars[index]
	if not bar.active then return end
	
	local opt = db.sov
	
	local remaining = bar.duration - (GetTime() - bar.start)
	if remaining <= 0 then
		bar.active = false
		bar:Hide()
		return
	end
	bar:Show()
	
	if opt.useButtons then
		-- alpha difference in targeted units
		if db.sov.targetDifference then
			if bar.guid ~= self.targetGUID then
				bar:SetAlpha(self.sovNonTargetAlpha)
			else
				bar:SetAlpha(1)
			end
		end
		if bar.duration > 0 then
			bar.cooldown:SetCooldown(bar.start, bar.duration)
		end
	else
		-- alpha difference in targeted units
		if db.sov.targetDifference then
			if bar.guid == self.targetGUID then
				bar.texture:SetVertexColor(unpack(opt.color))
			else
				bar.texture:SetVertexColor(unpack(opt.colorNonTarget))
			end
		end
		
		local width, height
		width = opt.width - opt.height
		height = opt.height
		
		local progress = width * remaining / bar.duration - width
		local texture = bar.texture
		texture:SetPoint("RIGHT", bar, "RIGHT", progress, 0)
		
		bar.labelTimer:SetText(floor(remaining + 0.5))
	end	
end

-- updates everything
function clcret:UpdateSovBarsLayout()
	local opt = db.sov
	local bar, fontFace, fontFlags
	
	_, _, _, self.sovNonTargetAlpha = unpack(db.sov.colorNonTarget)
	self.sovNonTargetAlpha = 0.5 * self.sovNonTargetAlpha
	
	if opt.useButtons then
		clcretSovAnchor:SetWidth(opt.height)
		clcretSovAnchor:SetHeight(opt.height)
		clcretSovAnchor:ClearAllPoints()
		clcretSovAnchor:SetPoint(opt.point, clcretFrame, opt.pointParent, opt.x, opt.y)
	else
		clcretSovAnchor:SetWidth(opt.width)
		clcretSovAnchor:SetHeight(opt.height)
		clcretSovAnchor:ClearAllPoints()
		clcretSovAnchor:SetPoint(opt.point, clcretFrame, opt.pointParent, opt.x, opt.y)
	end
	
	for i = 1, MAX_SOVBARS do
		bar = sovBars[i]
		bar:SetAlpha(1)
		bar.texture:SetVertexColor(unpack(opt.color))
		bar.bgtexture:SetAlpha(0.3)
		
		if db.zoomIcons then
			bar.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
		else
			bar.icon:SetTexCoord(0, 1, 0, 1)
		end
		
		bar.icon:SetWidth(opt.height)
		bar.icon:SetHeight(opt.height)
		
		fontFace, _, fontFlags = bar.label:GetFont()
		bar.label:SetFont(fontFace, max(5, opt.height - 3), fontFlags)
		bar.label:SetWidth(max(5, opt.width - 2.2 * opt.height))
		bar.label:SetHeight(max(5, opt.height - 5))
		bar.labelTimer:SetFont(fontFace, max(5, opt.height - 3), fontFlags)
		
		bar:ClearAllPoints()
		bar.icon:ClearAllPoints()
		bar.labelStack:ClearAllPoints()
		if opt.useButtons then
			-- positioning
			if opt.growth == "up" then
				bar:SetPoint("BOTTOM", clcretSovAnchor, "BOTTOM", 0, (i - 1) * (opt.height + opt.spacing))
			elseif opt.growth == "left" then
				bar:SetPoint("LEFT", clcretSovAnchor, "LEFT", (1 - i) * (opt.height + opt.spacing), 0)
			elseif opt.growth == "right" then
				bar:SetPoint("RIGHT", clcretSovAnchor, "RIGHT", (i - 1) * (opt.height + opt.spacing), 0)
			else
				bar:SetPoint("TOP", clcretSovAnchor, "TOP", 0, (1 - i) * (opt.height + opt.spacing) )
			end
			
			bar:SetWidth(opt.height)
			bar:SetHeight(opt.height)
			
			bar.icon:SetPoint("CENTER", bar, "CENTER", 0, 0)
			bar.labelStack:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", 3, -3)
			
			bar.labelStack:SetParent(bar.cooldown)
			
			fontFace, _, fontFlags = bar.labelStack:GetFont()
			bar.labelStack:SetFont(fontFace, max(5, opt.height / 2), fontFlags)
			
			-- hide bar stuff
			bar.texture:Hide()
			bar.bgtexture:Hide()
			bar.label:Hide()
			bar.labelTimer:Hide()
			
			-- show cooldown
			bar.cooldown:Show()
			
			-- show border
			if db.noBorder then
				bar.border:Hide()
			else
				bar.border:SetAllPoints(bar)
				bar.border:SetVertexColor(unpack(db.borderColor))
				bar.border:SetTexture(borderType[db.borderType])
				bar.border:Show()
			end
			
		else
			-- positioning
			if opt.growth == "up" then
				bar:SetPoint("BOTTOM", clcretSovAnchor, "BOTTOM", opt.height / 2, (i - 1) * (opt.height + opt.spacing))
			elseif opt.growth == "left" then
				bar:SetPoint("LEFT", clcretSovAnchor, "LEFT", (1 - i) * (opt.width + opt.spacing) + opt.height, 0)
			elseif opt.growth == "right" then
				bar:SetPoint("RIGHT", clcretSovAnchor, "RIGHT", (i - 1) * (opt.width + opt.spacing), 0)
			else
				bar:SetPoint("TOP", clcretSovAnchor, "TOP", opt.height / 2, (1 - i) * (opt.height + opt.spacing) )
			end
			
			bar:SetWidth(opt.width - opt.height)
			bar:SetHeight(opt.height)
			
			bar.labelStack:SetParent(bar)
			
			bar.icon:SetPoint("RIGHT", bar, "LEFT", 0, 0)
			bar.labelStack:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
			
			fontFace, _, fontFlags = bar.labelStack:GetFont()
			bar.labelStack:SetFont(fontFace, max(5, opt.height - 2), fontFlags)
			
			-- show bar stuff
			bar.texture:Show()
			bar.bgtexture:Show()
			bar.label:Show()
			bar.labelTimer:Show()
			
			-- hide cooldown
			bar.cooldown:Hide()
			
			-- hide border
			bar.border:Hide()
		end
	end
end

-- initialize the bars
function clcret:InitSovBars()
	db = clcret.db.profile	
	
	playerName = UnitName("player")

	-- create sov anchor
	sovAnchor = self:CreateSovAnchor()
	for i = 1, MAX_SOVBARS do
		sovBars[i] = self:CreateSovBar(i)
	end
	
	self:UpdateSovBarsLayout()
end
function clcret:CreateSovBar(index)
	local frame = CreateFrame("Frame", "clcretSovBar" .. index, clcretFrame)
	frame:Hide()
	
	local opt = db.sov
	
	-- background
	frame.bgtexture = frame:CreateTexture(nil, "BACKGROUND")
	frame.bgtexture:SetAllPoints()
	frame.bgtexture:SetVertexColor(0, 0, 0, 0.5)
	frame.bgtexture:SetTexture(BGTEX)
	
	-- texture
	frame.texture = frame:CreateTexture(nil, "BACKGROUND")
	frame.texture:SetAllPoints()
	frame.texture:SetTexture(BGTEX)
	
	-- icon
	frame.icon = frame:CreateTexture(nil, "BACKGROUND")
	frame.icon:SetTexture(sovSpellTexture)
	
	frame.border = frame:CreateTexture(nil, "BORDER")
	frame.border:SetTexture(BORDERTEX)
	frame.border:Hide()
	
	local fontFace, fontFlags
	
	-- label for the name of the unit
	frame.label = frame:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
	frame.label:SetPoint("LEFT", frame, "LEFT", 3, 1)
	frame.label:SetJustifyH("LEFT")
	
	-- label for timer
	frame.labelTimer = frame:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
	frame.labelTimer:SetPoint("RIGHT", frame, "RIGHT", -1, 1)
	
	-- cooldown for button mode
	frame.cooldown = CreateFrame("Cooldown", "$parentCooldown", frame)
	frame.cooldown:SetAllPoints(frame)
	frame.cooldown:SetReverse(true)
	
	-- stack
	frame.labelStack = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	
	-- other vars used
	frame.start = 0
	frame.duration = 0
	frame.active = false	-- we can attach a timer to it
	frame.guid = 0

	return frame
end
function clcret:CreateSovAnchor()
	local frame = CreateFrame("Frame", "clcretSovAnchor", clcretFrame)
	frame:Hide()
	
	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetAllPoints()
	texture:SetTexture(BGTEX)
	texture:SetVertexColor(0, 0, 0, 1)

	return frame
end

-- toggle anchor visibility
function clcret:ToggleSovAnchor()
	if self.showSovAnchor then
		-- hide
		self.showSovAnchor = false
		clcretSovAnchor:Hide()
	else
		-- show
		self.showSovAnchor = true
		clcretSovAnchor:Show()
	end
end

-- toggle it on and off
function clcret:ToggleSovTracking()
	if db.sov.enabled then
		-- disable
		db.sov.enabled = false
		self:RegisterCLEU()
		
		-- hide the bars
		for i = 1, MAX_SOVBARS do
			sovBars[i].active = false
			sovBars[i]:Hide()
		end
	else
		-- enable
		db.sov.enabled = true
		self:RegisterCLEU()
	end
end
-- ---------------------------------------------------------------------------------------------------------------------

