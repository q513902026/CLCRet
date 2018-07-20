local addonName, L = ...; 
local function defaultFunc(L, key) 
return key; 
end 
setmetatable(L, {__index=defaultFunc});
-- don't load if class is wrong
local _, class = UnitClass("player")
if class ~= "PALADIN" then return end

local _, xmod = ...

xmod.retmodule = {}
xmod = xmod.retmodule

local qTaint = true -- will force queue check

-- thanks cremor
local GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetActiveSpecGroup, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min =
GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetActiveSpecGroup, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min
local db
local SPELL_POWER_HOLY_POWER = SPELL_POWER_HOLY_POWER or Enum.PowerType.HolyPower
-- debug if clcInfo detected
local debug
if clcInfo then debug = clcInfo.debug end

xmod.version = 8000001
xmod.defaults = {
	version = xmod.version,
	prio = "boj cs2 cs",
	rangePerSkill = false,
	howclash = 0, -- priority time for hammer of wrath
	csclash = 0, -- priority time for cs
	exoclash = 0, -- priority time for exorcism
	ssduration = 0, -- minimum duration on ss buff before suggesting refresh
}

-- @defines
--------------------------------------------------------------------------------
local idGCD = 85256 -- tv for gcd

-- spells
local idTemplarsVerdict = 85256
local idCrusaderStrike = 35395
local idJudgement = 20271
local idConsecration = 205228
local idJusticarsVengeance = 215661
local idWakeOfAshes = 255937
local idExecutionSentence = 267798
local idhammerofwrath =24275

-- tier 4
local idBladeOfJustice = 184575

--local dsId					= 53385 -- divine storm
--local esId					= 267798 -- execution sentence

-- buffs
local ln_buff_TheFiresOfJustice = GetSpellInfo(203316)
local ln_buff_DivinePurpose = GetSpellInfo(223817)
local ln_buff_Crusade = GetSpellInfo(231895)
local ln_buff_ChengPiFeng = GetSpellInfo(207635)

-- debuffs

-- status vars
local s1, s2
local s_ctime, s_otime, s_gcd, s_hp, s_dp, s_aw, s_ss, s_dc, s_fv, s_bc, s_haste, s_in_execute_range
local s_CrusaderStrikeCharges = 0
local s_buff_DivinePurpose, s_buff_TheFiresOfJustice, s_buff_Crusade, s_buff_ChengPiFeng
local s_debuff_Judgement
local s_debuff_ExecutionSentence

local talent_DivinePurpose = false

-- the queue
local qn = {} -- normal queue
local q -- working queue

local function GetCooldown(id)
	local start, duration = GetSpellCooldown(id)
	if start == nil then return 100 end
	local cd = start + duration - s_ctime - s_gcd
	if cd < 0 then return 0 end
	return cd
end

local function GetCSData()
	local charges, maxCharges, start, duration = GetSpellCharges(idCrusaderStrike)
	if (charges >= 2) then
		return 0, 2
	end

	if start == nil then
		return 100, charges
	end
	local cd = start + duration - s_ctime - s_gcd
	if cd < 0 then
		return 0, min(2, charges + 1)
	end

	return cd, charges
end

-- actions ---------------------------------------------------------------------
local actions = {
	--3	Justicar's Vengeance	Cast Justicar's Vengeance @5 Holy Power with Divine Purpose proc and Judgment up. Or DP.
	jv_dp = {
		id = idJusticarsVengeance,
		GetCD = function()
			if ((s1 ~= idJusticarsVengeance) and (s_buff_DivinePurpose > 0)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
		end,
		info = L["Justicar's Vengeance with DP and Judgement up"],
		reqTalent = 22483,
	},
	--4	Templar's Verdict	Cast Templar's Verdict with Judgment up and @5 Holy Power.
	tv5 = {
		id = idTemplarsVerdict,
		GetCD = function()
			if ((s_hp >= 5)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			if (s_buff_DivinePurpose > 0) then
				s_buff_DivinePurpose = 0
			else
				s_hp = max(0, s_hp - 3)
			end
		end,
		info = L["Templar's Verdict with HP >= 5"],
	},
	--5	Crusader Strike/Zeal	Cast Crusader Strike or Zeal if @2 charges. Generates 1 Holy Power.
	cs2 = {
		id = idCrusaderStrike,
		GetCD = function()
			if ((s_CrusaderStrikeCharges == 2) and (s_hp <= 4)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_hp = min(5, s_hp + 1)
			s_CrusaderStrikeCharges = max(0, s_CrusaderStrikeCharges - 1)
		end,
		info = L["Crusader Strike stacks = 2"],
	},
	--6	Blade of Justice	Cast Blade of Justice/T4 talent @3 or less Holy Power. Generates 2 Holy Power.
	boj = {
		id = idBladeOfJustice,
		GetCD = function()
			if ((s1 ~= idBladeOfJustice) and (s_hp <= 3)) then
				return GetCooldown(idBladeOfJustice)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_hp = min(5, s_hp + 2)
		end,
		info = L["Blade of Justice"],
	},
	--7	Consecration	Cast Consecration if talented.
	cons = {
		id = idConsecration,
		GetCD = function()
			if (s1 ~= idConsecration) then return GetCooldown(idConsecration)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
		end,
		info = L["Consecration"],
                reqTalent = 22182,
	},
	--8	Crusader Strike/Zeal	Cast Crusader Strike or Zeal if @1 charge. Generates 1 Holy Power.
	cs = {
		id = idCrusaderStrike,
		GetCD = function()
			local cd, charges = GetCSData()
			if ((charges == 1) and (s_hp <= 4)) then
				return 0
			end
			return cd + 0.5
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_hp = min(5, s_hp + 1)
			s_CrusaderStrikeCharges = max(0, s_CrusaderStrikeCharges - 1)
		end,
		info = L["Crusader Strike"],
	},
	--9	Templar's Verdict	Cast with Judgment up and @3 Holy Power when there is nothing else to cast.
	tv = {
		id = idTemplarsVerdict,
		GetCD = function()
			if ((s_hp >= 3)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			if (s_buff_DivinePurpose > 0) then
				s_buff_DivinePurpose = 0
			else
				s_hp = max(0, s_hp - 3)
			end
		end,
		info = L["Templar's Verdict HP >= 3 and Judgement debuff up"],
	},
        --10	Judgment	Keep Judgment on cooldown @4+ Holy Power and/or DP procs.
	j = {
		id = idJudgement,
                GetCD = function()
			if ((s1 ~= idJudgement) and (s_hp <= 4)) then return GetCooldown(idJudgement)
			end
			return 100 -- lazy stuff
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_debuff_Judgement = 8
		end,
		info = L["Judgement when 4 Holy Power"],
	},
        --12	Wake of Ashes
	w1 = {
		id = idWakeOfAshes,
		GetCD = function()
			if ((s1 ~= idWakeOfAshes) and (s_hp <= 1)) then return GetCooldown(idWakeOfAshes)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_hp = min(5, s_hp + 5)
		end,
		info = L["Wake of Ashes when <= 1 Holy Power"],
        reqTalent = 22183,
        },
        --13	Wake of Ashes
	w = {
		id = idWakeOfAshes,
		GetCD = function()
			if ((s1 ~= idWakeOfAshes) and (s_hp <= 0)) then return GetCooldown(idWakeOfAshes)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			s_hp = min(5, s_hp + 5)
		end,
		info = L["Wake of Ashes when 0 Holy Power"],
        reqTalent = 22183,
        },
        --19	Templar's Verdict        Templar's Verdict HP >= 3 and Judgement debuff and ChengPiFeng time < 2s
	tv_cp = {
		id = idTemplarsVerdict,
		GetCD = function()
			if ((s_debuff_Judgement > 0) and (s_hp >= 3) and (s_buff_ChengPiFeng > 0) and (s_buff_ChengPiFeng < 2)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			if (s_buff_DivinePurpose > 0) then
				s_buff_DivinePurpose = 0
			else
				s_hp = max(0, s_hp - 3)
			end
		end,
		info = L["Templar's Verdict HP >= 3 and Judgement debuff and ChengPiFeng time < 2s "],
	},
        --20	Execution Sentence
	es4 = {
		id = idExecutionSentence,
		GetCD = function()
			if ((s_hp >= 4)) then
				return GetCooldown(idExecutionSentence)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			if (s_buff_DivinePurpose > 0) then
				s_buff_DivinePurpose = 0
			else
				s_hp = max(0, s_hp - 3)
			end
		end,
		info = L["Execution Sentence HP >= 4"],
                reqTalent = 22175,
	},
        --25	Templar's Verdict
	tv4 = {
		id = idTemplarsVerdict,
		GetCD = function()
			if ((s_debuff_Judgement > 0) and (s_hp >= 4)) then
				return 0
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5
			if (s_buff_DivinePurpose > 0) then
				s_buff_DivinePurpose = 0
			else
				s_hp = max(0, s_hp - 3)
			end
		end,
		info = L["Templar's Verdict with HP >= 4"],
	},
}
--------------------------------------------------------------------------------
local function UpdateQueue()
	-- normal queue
	qn = {}
	for v in string.gmatch(db.prio, "[^ ]+") do
		if actions[v] then
			table.insert(qn, v)
		else
			print("clcretmodule - invalid action:", v)
		end
	end
	db.prio = table.concat(qn, " ")

	-- force reconstruction for q
	qTaint = true
end

local function GetBuff(buff)
	local left = 0
	local _, expires
	_, _, _, _, _, expires = AuraUtil.FindAuraByName( buff, "player", "PLAYER")
	if expires then
		left = max(0, expires - s_ctime - s_gcd)
	end
	return left
end

local function GetDebuff(debuff)
	local left = 0
	local _, expires
	_, _, _, _, _, expires = AuraUtil.FindAuraByName( buff, "target", "PLAYER")
	if expires then
		left = max(0, expires - s_ctime - s_gcd)
	end
	return left
end

-- reads all the interesting data
local function GetStatus()
	-- current time
	s_ctime = GetTime()

	-- gcd value
	local start, duration = GetSpellCooldown(idGCD)
	s_gcd = start + duration - s_ctime
	if s_gcd < 0 then s_gcd = 0 end

	-- the buffs
	--	s_dp = GetBuff(buffDP)
	--	s_ha = GetBuff(buffHA)
	--	s_aw = GetBuff(buffAW)
	--	s_dc = GetBuff(buffDC)
	--	s_bc = GetBuff(buffBC)

	-- the buffs
	if (talent_DivinePurpose) then
		s_buff_DivinePurpose = GetBuff(ln_buff_DivinePurpose)
	else
		s_buff_DivinePurpose = 0
	end
	s_buff_TheFiresOfJustice = GetBuff(ln_buff_TheFiresOfJustice)
        s_buff_Crusade = GetBuff(ln_buff_Crusade)
        s_buff_ChengPiFeng = GetBuff(ln_buff_ChengPiFeng)

	-- the debuffs
	s_debuff_Judgement = GetDebuff(ln_debuff_Judgement)
        s_debuff_ExecutionSentence = GetDebuff(ln_debuff_ExecutionSentence)

	-- crusader strike stacks
	local cd, charges = GetCSData()
	s_CrusaderStrikeCharges = charges

	-- client hp and haste
	s_hp = UnitPower("player", SPELL_POWER_HOLY_POWER)
	s_haste = 1 + UnitSpellHaste("player") / 100
end

-- remove all talents not available and present in rotation
-- adjust for modified skills present in rotation
local function GetWorkingQueue()
	q = {}
	local name, selected, available
	for k, v in pairs(qn) do
		-- see if it has a talent requirement
		if actions[v].reqTalent then
			-- see if the talent is activated
			_, name, _, selected, available = GetTalentInfoByID(actions[v].reqTalent, GetActiveSpecGroup())
			if name and selected and available then
				table.insert(q, v)
			end
		else
			table.insert(q, v)
		end
	end
end

local function GetNextAction()
	-- check if working queue needs updated due to glyph talent changes
	if qTaint then
		GetWorkingQueue()
		qTaint = false
	end

	local n = #q

	-- parse once, get cooldowns, return first 0
	for i = 1, n do
		local action = actions[q[i]]
		local cd = action.GetCD()
		if debug and debug.enabled then
			debug:AddBoth(q[i], cd)
		end
		if cd == 0 then
			return action.id, q[i]
		end
		action.cd = cd
	end

	-- parse again, return min cooldown
	local minQ = 1
	local minCd = actions[q[1]].cd
	for i = 2, n do
		local action = actions[q[i]]
		if minCd > action.cd then
			minCd = action.cd
			minQ = i
		end
	end
	return actions[q[minQ]].id, q[minQ]
end

-- exposed functions

-- this function should be called from addons
function xmod.Init()
	db = xmod.db
	UpdateQueue()
end

function xmod.GetActions()
	return actions
end

function xmod.Update()
	UpdateQueue()
end

function xmod.Rotation()
	s1 = nil
	GetStatus()
	if debug and debug.enabled then
		debug:Clear()
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("hp", s_hp)
		debug:AddBoth("haste", s_haste)

		debug:AddBoth("dJudgement", s_debuff_Judgement)
		debug:AddBoth("bDivinePurpose", s_buff_DivinePurpose)
		debug:AddBoth("bTFOJ", s_buff_TheFiresOfJustice)
                debug:AddBoth("bC", s_buff_Crusade)
                debug:AddBoth("bCPF", s_buff_ChengPiFeng)
                debug:AddBoth("dExecutionSentence", s_debuff_ExecutionSentence)
	end
	local action
	s1, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s1", action)
		debug:AddBoth("s1Id", s1)
	end
	-- 
	s_otime = s_ctime -- save it so we adjust buffs for next
	actions[action].UpdateStatus()

	s_otime = s_ctime - s_otime

	-- adjust buffs
	s_buff_TheFiresOfJustice = max(0, s_buff_TheFiresOfJustice - s_otime)
	s_buff_DivinePurpose = max(0, s_buff_DivinePurpose - s_otime)
        s_buff_Crusade = max(0, s_buff_Crusade - s_otime)
        s_buff_ChengPiFeng = max(0, s_buff_ChengPiFeng - s_otime)

	-- adjust debuffs
	s_debuff_Judgement = max(0, s_debuff_Judgement - s_otime)
        s_debuff_ExecutionSentence = max(0, s_debuff_ExecutionSentence - s_otime)

	-- crusader strike stacks
	local cd, charges = GetCSData()
	s_CrusaderStrikeCharges = charges
	if (s1 == idCrusaderStrike) then
		s_CrusaderStrikeCharges = s_CrusaderStrikeCharges - 1
	end

	if debug and debug.enabled then
		debug:AddBoth("csc", s_CrusaderStrikeCharges)
	end

	if debug and debug.enabled then
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("otime", s_otime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("hp", s_hp)
		debug:AddBoth("haste", s_haste)
		debug:AddBoth("dJudgement", s_debuff_Judgement)
		debug:AddBoth("bDivinePurpose", s_buff_DivinePurpose)
		debug:AddBoth("bTFOJ", s_buff_TheFiresOfJustice)
                debug:AddBoth("bC", s_buff_Crusade)
                debug:AddBoth("bCPF", s_buff_ChengPiFeng)
                debug:AddBoth("dExecutionSentence", s_debuff_ExecutionSentence)
	end
	s2, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s2", action)
	end

	return s1, s2
end

-- event frame
local ef = CreateFrame("Frame", "clcRetModuleEventFrame") -- event frame
ef:Hide()
local function OnEvent()
	qTaint = true

	-- DivinePurpose talent
	local _, name, _, selected, available = GetTalentInfoByID(22591, GetActiveSpecGroup())
	if name and selected and available then
		talent_DivinePurpose = selected
	end
end


ef:SetScript("OnEvent", OnEvent)
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_TALENT_UPDATE")
ef:RegisterEvent("PLAYER_LEVEL_UP")
--ef:RegisterEvent("GLYPH_ADDED")
--ef:RegisterEvent("GLYPH_UPDATED")
--ef:RegisterEvent("GLYPH_REMOVED")
--ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
