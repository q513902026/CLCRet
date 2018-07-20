local addonName, L = ...; 
local function defaultFunc(L, key) 
return key; 
end 
setmetatable(L, {__index=defaultFunc});
local _, trueclass = UnitClass("player")
if trueclass ~= "PALADIN" then return end

clcret.optionsLoaded = true

local MAX_AURAS = 20
local MAX_SOVBARS = 5

local db = clcret.db.profile
local root

local strataLevels = {
	L["BACKGROUND"],
	L["LOW"],
	L["MEDIUM"],
	L["HIGH"],
	L["DIALOG"],
	L["FULLSCREEN"],
	L["FULLSCREEN_DIALOG"],
	L["TOOLTIP"],
}

local anchorPoints = {
	CENTER = L["CENTER"],
	TOP = L["TOP"],
	BOTTOM = L["BOTTOM"],
	LEFT = L["LEFT"],
	RIGHT = L["RIGHT"],
	TOPLEFT = L["TOPLEFT"],
	TOPRIGHT = L["TOPRIGHT"],
	BOTTOMLEFT = L["BOTTOMLEFT"],
	BOTTOMRIGHT = L["BOTTOMRIGHT"]
}
local execList = {
	AuraButtonExecNone = L["None"],
	AuraButtonExecSkillVisibleAlways = L["Skill always visible"],
	AuraButtonExecSkillVisibleNoCooldown = L["Skill visible when available"],
	AuraButtonExecSkillVisibleOnCooldown = L["Skill visible when not available"],
	AuraButtonExecItemVisibleAlways = L["OnUse item always visible"],
	AuraButtonExecItemVisibleNoCooldown = L["OnUse item visible when available"],
	AuraButtonExecGenericBuff = L["Generic buff"],
	AuraButtonExecGenericDebuff = L["Generic debuff"],
	AuraButtonExecPlayerMissingBuff = L["Missing player buff"],
	AuraButtonExecICDItem = L["ICD Proc"],
}
local skillButtonNames = { L["Main skill"], L["Secondary skill"] }


-- index lookup for aura buttons
local ilt = {}
for i = 1, MAX_AURAS do
	ilt["aura" .. i] = i
end

-- aura buttons get/set functions
local abgs = {}

function abgs:UpdateAll()
	clcret:UpdateEnabledAuraButtons()
	clcret:UpdateAuraButtonsCooldown()
	clcret:AuraButtonUpdateICD()
	clcret:AuraButtonResetTextures()
end

-- enabled toggle
function abgs:EnabledGet()
	local i = ilt[self[2]]
	
	return db.auras[i].enabled
end
function abgs:EnabledSet(val)
	local i = ilt[self[2]]
	
	clcret.temp = info
	if db.auras[i].data.spell == "" then
		val = false
		print(L["Not a valid spell name/id or buff name!"])
	end
	db.auras[i].enabled = val
	if not val then clcret:AuraButtonHide(i) end
	abgs:UpdateAll()
end

-- id/name field
function abgs:SpellGet()
	local i = ilt[self[2]]
	
	-- special case for items since link is used instead of name
	if (db.auras[i].data.exec == "AuraButtonExecItemVisibleAlways") or (db.auras[i].data.exec == "AuraButtonExecItemVisibleNoCooldown") then
		return db.auras[i].data.spell
	elseif db.auras[i].data.exec == "AuraButtonExecICDItem" then
		return GetSpellInfo(db.auras[i].data.spell)
	end
	return db.auras[i].data.spell
end

function abgs:SpellSet(val)
	local i = ilt[self[2]]
	
	-- skill
	if (db.auras[i].data.exec == "AuraButtonExecSkillVisibleAlways") or (db.auras[i].data.exec == "AuraButtonExecSkillVisibleNoCooldown") or (db.auras[i].data.exec == "AuraButtonExecSkillVisibleOnCooldown") then
		local name = GetSpellInfo(val)
		if name then
			db.auras[i].data.spell = name
		else
			db.auras[i].data.spell = ""
			db.auras[i].enabled = false
			clcret:AuraButtonHide(i)
			print(L["Not a valid spell name or id !"])
		end
	-- item
	elseif (db.auras[i].data.exec == "AuraButtonExecItemVisibleAlways") or (db.auras[i].data.exec == "AuraButtonExecItemVisibleNoCooldown") then
		local name, link = GetItemInfo(val)
		if name then
			db.auras[i].data.spell = val
		else
			db.auras[i].data.spell = ""
			db.auras[i].enabled = false
			clcret:AuraButtonHide(i)
			print(L["Not a valid item name or id !"])
		end
	-- icd stuff
	elseif (db.auras[i].data.exec == "AuraButtonExecICDItem") then
		local tid = tonumber(val)
		local name = GetSpellInfo(tid)
		if name then
			db.auras[i].data.spell = tid
		else
			db.auras[i].data.spell = ""
			db.auras[i].enabled = false
			clcret:AuraButtonHide(i)
			print(L["Not a valid spell id!"])
		end
	else
		db.auras[i].data.spell = val
	end
	
	abgs:UpdateAll()
end

-- type select
function abgs:ExecGet()
	local i = ilt[self[2]]
	
	return db.auras[i].data.exec
end

function abgs:ExecSet(val)
	local i = ilt[self[2]]
	local aura = db.auras[i]
	
	-- reset every other setting when this is changed
	aura.enabled = false
	aura.data.spell = ""
	aura.data.unit = ""
	aura.data.byPlayer = false
	clcret:AuraButtonHide(i)
	
	aura.data.exec = val
	
	abgs:UpdateAll()
end

-- target field
function abgs:UnitGet()
	local i = ilt[self[2]]
	
	return db.auras[i].data.unit
end

function abgs:UnitSet(val)
	local i = ilt[self[2]]
	
	db.auras[i].data.unit = val
	abgs:UpdateAll()
end

-- cast by player toggle
function abgs:ByPlayerGet()
	local i = ilt[self[2]]
	
	return db.auras[i].data.byPlayer
end

function abgs:ByPlayerSet(val)
	local i = ilt[self[2]]
	
	db.auras[i].data.byPlayer = val
	abgs:UpdateAll()
end

local function RotationGet(info)
	local xdb = clcret.db.profile.rotation
	return xdb[info[#info]]
end

local function RotationSet(info, val)
	local xdb = clcret.db.profile.rotation
	xdb[info[#info]] = val
	
	if info[#info] == "prio" then
		clcret.RR_UpdateQueue()
	end
end

local tx = {}
for k, v in pairs(clcret.RR_actions) do
	table.insert(tx, format("\n%s - %s", k, v.info))
end
table.sort(tx)
local prioInfo = "Legend:\n" .. table.concat(tx)

local options = {
	type = "group",
	name = "CLCRet",
	args = {
		global = {
			type = "group",
			name = L["Global"],
			order = 1,
			args = {
				-- lock frame
				lock = {
					order = 1,
					width = "full",
					type = "toggle",
					name = L["Lock Frame"],
					get = function(info) return clcret.locked end,
					set = function(info, val)
						clcret:ToggleLock()
					end,
				},
				
				show = {
					order = 10,
					type = "select",
					name = L["Show"],
					get = function(info) return db.show end,
					set = function(info, val)
						db.show = val
						clcret:UpdateShowMethod()
					end,
					values = { always = L["Always"], combat = L["In Combat"], valid = L["Valid Target"], boss = L["Boss"] }
				},
				
				__strata = {
					order = 15,
					type = "header",
					name = "",
				},
				____strata = {
					order = 16,
					type = "description",
					name = L["|cffff0000WARNING|cffffffff Changing Strata value will automatically reload your UI."]
				},
				strata = {
					order = 17,
					type = "select",
					name = L["Frame Strata"],
					get = function(info) return db.strata end,
					set = function(info, val)
						db.strata = val
						ReloadUI()
					end,
					values = strataLevels,
				},
				
				-- full disable toggle
				__fulldisable = {
					order = 20,
					type = "header",
					name = "",
				},
				fullDisable = {
					order = 21,
					width = L["full"],
					type = "toggle",
					name = L["Addon disabled"],
					get = function(info) return db.fullDisable end,
					set = function(info, val) clcret:FullDisableToggle() end,
				},
			},
		},
	
		-- appearance
		appearance = {
			order = 10,
			name = L["Appearance"],
			type = "group",
			args = {
				__buttonAspect = {
					type = "header",
					name = L["Button Aspect"],
					order = 2,
				},
				zoomIcons = {
					order = 3,
					type = "toggle",
					name = L["Zoomed icons"],
					get = function(info) return db.zoomIcons end,
					set = function(info, val)
						db.zoomIcons = val
						clcret:UpdateSkillButtonsLayout()
						clcret:UpdateAuraButtonsLayout()
						clcret:UpdateSovBarsLayout()
					end,
				},
				noBorder = {
					order = 4,
					type = "toggle",
					name = L["Hide border"],
					get = function(info) return db.noBorder end,
					set = function(info, val)
						db.noBorder = val
						clcret:UpdateSkillButtonsLayout()
						clcret:UpdateAuraButtonsLayout()
						clcret:UpdateSovBarsLayout()
					end,
				},
				borderColor = {
					order = 5,
					type = "color",
					name = L["Border color"],
					hasAlpha = true,
					get = function(info) return unpack(db.borderColor) end,
					set = function(info, r, g, b, a)
						db.borderColor = {r, g, b, a}
						clcret:UpdateSkillButtonsLayout()
						clcret:UpdateAuraButtonsLayout()
						clcret:UpdateSovBarsLayout()
					end,
				},
				borderType = {
					order = 6,
					type = "select",
					name = L["Border type"],
					get = function(info) return db.borderType end,
					set = function(info, val)
						db.borderType = val
						clcret:UpdateSkillButtonsLayout()
						clcret:UpdateAuraButtonsLayout()
						clcret:UpdateSovBarsLayout()
					end,
					values = { L["Light"], L["Medium"], L["Heavy"] }
				},
				grayOOM = {
					order = 7,
					type = "toggle",
					name = L["Gray when OOM"],
					get = function(info) return db.grayOOM end,
					set = function(info, val)
						db.grayOOM = val
						clcret:ResetButtonVertexColor()
					end,
				},
				
				__hudAspect = {
					type = "header",
					name = L["HUD Aspect"],
					order = 10,
				},
				scale = {
					order = 11,
					type = "range",
					name = L["Scale"],
					min = 0.01,
					max = 3,
					step = 0.01,
					get = function(info) return db.scale end,
					set = function(info, val)
						db.scale = val
						clcret:UpdateFrameSettings()
					end,
				},
				alpha = {
					order = 12,
					type = "range",
					name = L["Alpha"],
					min = 0,
					max = 1,
					step = 0.001,
					get = function(info) return db.alpha end,
					set = function(info, val)
						db.alpha = val
						clcret:UpdateFrameSettings()
					end,
				},
				_hudPosition = {
					type = "header",
					name = L["HUD Position"],
					order = 13,
				},
				x = {
					order = 20,
					type = "range",
					name = "X",
					min = 0,
					max = 5000,
					step = 21,
					get = function(info) return db.x end,
					set = function(info, val)
						db.x = val
						clcret:UpdateFrameSettings()
					end,
				},
				y = {
					order = 22,
					type = "range",
					name = "Y",
					min = 0,
					max = 3000,
					step = 1,
					get = function(info) return db.y end,
					set = function(info, val)
						db.y = val
						clcret:UpdateFrameSettings()
					end,
				},
				align = {
					order = 23,
					type = "execute",
					name = L["Center Horizontally"],
					func = function()
						clcret:CenterHorizontally()
					end,
				},
				
				__icd = {
					order = 50,
					type = "header",
					name = L["ICD Visibility"],
				},
				____icd = {
					order = 51,
					type = "description",
					name = L["Controls the way ICD Aura Buttons are displayed while the proc is ready or on cooldown."],
				},
				icdReady = {
					order = 52,
					type = "select",
					name = L["Ready"],
					values = { [1] = L["Visible"], [2] = L["Faded"], [3] = L["Invisible"] },
					get = function(info) return db.icd.visibility.ready end,
					set = function(info, val)
						db.icd.visibility.ready = val
					end,
				},
				icdCooldown = {
					order = 53,
					type = "select",
					name = L["On cooldown"],
					values = { [1] = L["Visible"], [2] = L["Faded"], [3] = L["Invisible"] },
					get = function(info) return db.icd.visibility.cd end,
					set = function(info, val)
						db.icd.visibility.cd = val
					end,
				}
			},
		},
	
		-- behavior
		behavior = {
			order = 15,
			name = L["Behavior"],
			type = "group",
			args = {
				__updateRates = {
					order = 1,
					type = "header",
					name = L["Updates per Second"],
				},
				ups = {
					order = 5,
					type = "range",
					name = L["FCFS Detection"],
					min = 1,
					max = 100,
					step = 1,
					get = function(info) return db.updatesPerSecond end,
					set = function(info, val)
						db.updatesPerSecond = val
						clcret.scanFrequency = 1 / val
					end,
				},
				upsAuras = {
					order = 6,
					type = "range",
					name = L["Aura Detection"],
					min = 1,
					max = 100,
					step = 1,
					get = function(info) return db.updatesPerSecondAuras end,
					set = function(info, val)
						db.updatesPerSecondAuras = val
						clcret.scanFrequencyAuras = 1 / val
					end,
				},
			},
		},
		
		rotation = clcret.RR_BuildOptions(),
		
		-- aura buttons
		auras = {
			order = 30,
			name = L["Aura Buttons"],
			type = "group",
			args = {
				____info = {
					order = 1,
					type = "description",
					name = L["These are cooldown watchers. You can select a player skill, an item or a buff/debuff (on a valid target) to watch.\nItems and skills only need a valid item/spell id (or name) and the type. Target (the target to scan) and Cast by player (filters or not buffs cast by others) are specific to buffs/debuffs.\nValid targets are the ones that work with /cast [target=name] macros. For example: player, target, focus, raid1, raid1target.\n\nICD Proc:\nYou need to specify a valid proc ID (example: 60229 for Greatness STR proc) Name doesn't work, if the ID is valid it will be replaced by the name after the edit.\nIn the \"Target unit\" field you have to enter the ICD and duration of the proc separated by \":\" (example: for Greatness the value should be 45:15)."],
				},
			},
		},
	
		-- layout
		layout = {
			order = 31,
			name = L["Layout"],
			type = "group",
			args = {},
		},
	},
}

	-- add main buttons to layout
for i = 1, 2 do
	options.args.layout.args["button" .. i] = {
		order = i,
		name = skillButtonNames[i],
		type = "group",
		args = {
			size = {
				order = 1,
				type = "range",
				name = L["Size"],
				min = 1,
				max = 300,
				step = 1,
				get = function(info) return db.layout["button" .. i].size end,
				set = function(info, val)
					db.layout["button" .. i].size = val
					clcret:UpdateSkillButtonsLayout()
				end,
			},
			alpha = {
				order = 2,
				type = "range",
				name = L["Alpha"],
				min = 0,
				max = 1,
				step = 0.01,
				get = function(info) return db.layout["button" .. i].alpha end,
				set = function(info, val)
					db.layout["button" .. i].alpha = val
					clcret:UpdateSkillButtonsLayout()
				end,
			},
			anchor = {
				order = 6,
				type = "select",
				name = L["Anchor"],
				get = function(info) return db.layout["button" .. i].point end,
				set = function(info, val)
					db.layout["button" .. i].point = val
					clcret:UpdateSkillButtonsLayout()
				end,
				values = anchorPoints,
			},
			anchorTo = {
				order = 6,
				type = "select",
				name = L["Anchor To"],
				get = function(info) return db.layout["button" .. i].pointParent end,
				set = function(info, val)
					db.layout["button" .. i].pointParent = val
					clcret:UpdateSkillButtonsLayout()
				end,
				values = anchorPoints,
			},
			x = {
				order = 10,
				type = "range",
				name = "X",
				min = -1000,
				max = 1000,
				step = 1,
				get = function(info) return db.layout["button" .. i].x end,
				set = function(info, val)
					db.layout["button" .. i].x = val
					clcret:UpdateSkillButtonsLayout()
				end,
			},
			y = {
				order = 11,
				type = "range",
				name = "Y",
				min = -1000,
				max = 1000,
				step = 1,
				get = function(info) return db.layout["button" .. i].y end,
				set = function(info, val)
					db.layout["button" .. i].y = val
					clcret:UpdateSkillButtonsLayout()
				end,
			},
		},
	}
end

-- add the buttons to options
for i = 1, MAX_AURAS do
	-- aura options
	options.args.auras.args["aura" .. i] = {
		order = i + 10,
		type = "group",
		name = L["Aura Button"] .. i,
		args = {
			enabled = {
				order = 1,
				type = "toggle",
				name = L["Enabled"],
				get = abgs.EnabledGet,
				set = abgs.EnabledSet,
			},
			spell = {
				order = 5,
				type = "input",
				name = L["Spell/item name/id or buff to track"],
				get = abgs.SpellGet,
				set = abgs.SpellSet,
			},
			exec = {
				order = 10,
				type = "select",
				name = L["Type"],
				get = abgs.ExecGet,
				set = abgs.ExecSet,
				values = execList,
			},
			unit = {
				order = 15,
				type = "input",
				name = L["Target unit"],
				get = abgs.UnitGet,
				set = abgs.UnitSet,
			},
			byPlayer = {
				order = 16,
				type = "toggle",
				name = L["Cast by player"],
				get = abgs.ByPlayerGet,
				set = abgs.ByPlayerSet,
			}
		},
	}
	
	-- layout
	options.args.layout.args["aura" .. i] = {
		order = 10 + i,
		type = "group",
		name = L["Aura Button"] .. i,
		args = {
			size = {
				order = 1,
				type = "range",
				name = L["Size"],
				min = 1,
				max = 300,
				step = 1,
				get = function(info) return db.auras[i].layout.size end,
				set = function(info, val)
					db.auras[i].layout.size = val
					clcret:UpdateAuraButtonLayout(i)
				end,
			},
			anchor = {
				order = 6,
				type = "select",
				name = L["Anchor"],
				get = function(info) return db.auras[i].layout.point end,
				set = function(info, val)
					db.auras[i].layout.point = val
					clcret:UpdateAuraButtonLayout(i)
				end,
				values = anchorPoints,
			},
			anchorTo = {
				order = 6,
				type = "select",
				name = L["Anchor To"],
				get = function(info) return db.auras[i].layout.pointParent end,
				set = function(info, val)
					db.auras[i].layout.pointParent = val
					clcret:UpdateAuraButtonLayout(i)
				end,
				values = anchorPoints,
			},
			x = {
				order = 10,
				type = "range",
				name = "X",
				min = -1000,
				max = 1000,
				step = 1,
				get = function(info) return db.auras[i].layout.x end,
				set = function(info, val)
					db.auras[i].layout.x = val
					clcret:UpdateAuraButtonLayout(i)
				end,
			},
			y = {
				order = 11,
				type = "range",
				name = "Y",
				min = -1000,
				max = 1000,
				step = 1,
				get = function(info) return db.auras[i].layout.y end,
				set = function(info, val)
					db.auras[i].layout.y = val
					clcret:UpdateAuraButtonLayout(i)
				end,
			},
		},
	}
end

-- remove the first one we added
for i = 1, #INTERFACEOPTIONS_ADDONCATEGORIES do
	if 	INTERFACEOPTIONS_ADDONCATEGORIES[i]
	and INTERFACEOPTIONS_ADDONCATEGORIES[i].name
	and INTERFACEOPTIONS_ADDONCATEGORIES[i].name == "CLCRet"
	then
		table.remove(INTERFACEOPTIONS_ADDONCATEGORIES, i)
	end
end

local AceConfig = LibStub("AceConfig-3.0")
AceConfig:RegisterOptionsTable("CLCRet", options)

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
AceConfigDialog:AddToBlizOptions("CLCRet", "CLCRet", nil, "global")
AceConfigDialog:AddToBlizOptions("CLCRet", L["Appearance"], "CLCRet", "appearance")
AceConfigDialog:AddToBlizOptions("CLCRet", L["Rotation"], "CLCRet", "rotation")
AceConfigDialog:AddToBlizOptions("CLCRet", L["Behavior"], "CLCRet", "behavior")
AceConfigDialog:AddToBlizOptions("CLCRet", L["Aura Buttons"], "CLCRet", "auras")
AceConfigDialog:AddToBlizOptions("CLCRet", L["Layout"], "CLCRet", "layout")

-- profiles
options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(clcret.db)
options.args.profiles.order = 900
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("CLCRet", L["Profiles"], "CLCRet", L["profiles"])

InterfaceOptionsFrame_OpenToCategory("CLCRet")

