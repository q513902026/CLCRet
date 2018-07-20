local addonName, L = ...; 
local function defaultFunc(L, key) 
return key; 
end 
setmetatable(L, {__index=defaultFunc});
-- don't load if class is wrong
local _, class = UnitClass("player")
if class ~= "PALADIN" then return end

local _, xmod = ...
xmod = xmod.retmodule
local db

local function Get(info)
	return db[info[#info]]
end

local function Set(info, val)
	db[info[#info]] = val
	
	if info[#info] == "prio" then
		xmod.Update()
	end
end

function xmod.BuildOptions()
	db = xmod.db

	-- legend for the actions
	local tx = {}
	local actions = xmod.GetActions()
	for k, v in pairs(actions) do
		table.insert(tx, format("\n%s - %s", k, v.info))
	end
	table.sort(tx)
	local prioInfo = L["Legend:\n"] .. table.concat(tx)

	return {
		order = 1, type = "group", childGroups = "tab", name = L["Retribution"],
		args = {
			tabPriority = {
				order = 1, type = "group", name = L["Priority"], args = {
					igPrio = {
						order = 1, type = "group", inline = true, name = "",
						args = {
							info = {
								order = 1, type = "description", name = prioInfo,
							},
							normalPrio = {
								order = 2, type="group", inline = true, name = L["Normal priority"],
								args = {
									prio = {
										order = 2, type = "input", width = "full", name = "",
										get = Get, set = Set,
									},
									infoCMD = {
										order = 3, type = "description", name = L["Sample command line usage: /clcinfo retprio exo cs j (for clcinfo) /clcretlp exo cs j (for clcret)"],
									},
								},
							},
							--[[
							zealPrio = {
								order = 3, type="group", inline = true, name = L["Zealotry priority"],
								args = {
									usePrioZeal = {
										order = 1, type = "toggle", width = "full", name = L["Enable zealotry priority"],
										get = Get, set = Set,
									},
									prioZeal = {
										order = 2, type = "input", width = "full", name = "",
										get = Get, set = Set,
									},
									infoCMD = {
										order = 3, type = "description", name = L["Sample command line usage: /clcinfo retpriozeal inqa tv cs exoud how exo"],
									},
								},
							},
							--]]
							disclaimer = {
								order = 4, type = "description", name = L["|cffff0000These are just examples, make sure you adjust them properly!|cffffffff"],
							},
						},
					},
				},
			},
			tabSettings = {
				order = 2, type = "group", name = L["Settings"], args = {
					igRange = {
						order = 1, type = "group", inline = true, name = L["Range check"],
						args = {
							rangePerSkill = {
								type = "toggle", width = "full", name = L["Range check for each skill instead of only melee range."],
								get = Get, set = Set,
							},
						},
					},
					clashes = {
						order = 3, type = "group", inline = true, name = L["Clashes"],
						args = {
							csclash = {
								order = 1, type = "range", min = 0, max = 2, step = 0.01, name = L["Crusader Strike"],
								get = Get, set = Set,
							},
						},
					},
				},
			},
		},
	}
end