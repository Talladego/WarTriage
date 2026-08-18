----------------------------------------------------------------
-- WarTriage.lua 
----------------------------------------------------------------

----------------------------------------------------------------
-- Local variables 
----------------------------------------------------------------

local VERSION = 3.00
local MIN_RANK_CROSSOVER = 5
local MAX_RANK_CROSSOVER = 30
local DEFAULT_RANK_CROSSOVER = 15
local DEFAULT_REZ_SAFETY_THRESHOLD = 90
local REZ_SAFETY_RANK_SCALE = 10
local REZ_SAFETY_DAMAGE_SCALE = 2
local REZ_SAFETY_MAX_URGENCY = 10
local REZ_SAFETY_URGENCY_RANK_FACTOR = 0.05
local WARTRIAGE_MACRO_NAME = "WarTriage"
local WARTRIAGE_MACRO_TEXT = ""
local WARTRIAGE_MACRO_ICON = 20087
local LOCAL_PLAYER_NAME = GameData.Player.name
local MAX_HEAL_DISTANCE = 150
local MAX_RESS_DISTANCE = 100
local DISTANCE_FIX_COEFFICIENT = 1 / 1.06
local MAX_MAP_POINTS = 511
local TIME_DELAY = 0.5
local MACRO_WATCHDOG_INTERVAL = 5
local MANUAL_OVERRIDE_RELEASE_PCT = 90
local DEFAULT_REZ_BLOCK_DURATION = 30
local SNAPSHOT_FALLBACK_INTERVAL = 2
local TRANSIENT_REFRESH_INTERVAL = TIME_DELAY
local TARGET_REFRESH_INTERVAL = TIME_DELAY
local HEALTH_HISTORY_STALE_SECONDS = 10
local RECENT_REZ_GRACE_PERIOD = 4
local DAMAGE_RATE_DECAY_PER_SECOND = 1.2
local MAX_DAMAGE_URGENCY_BONUS = 40
local DAMAGE_URGENCY_SCALE = 3
local RECENT_REZ_URGENCY_PENALTY = 20
local FRIEND_HP_BIAS = 25
local PARTY_AUTO_TARGET_THROTTLE = 0.25
local TRACE_LOG_LIMIT = 150
local TRACE_DUMP_TO_CHAT_LIMIT = 20
local WARTRIAGE_CHAT_PREFIX_TEXT = "WarTriage"
local WARTRIAGE_CHAT_PREFIX_COLOR = { 0, 255, 255 }
local WARTRIAGE_DISABLED_TINT = { 125, 125, 125 }
local WARTRIAGE_ENABLED_TINT = { 255, 255, 255 }
local HEALER = L"HEALER"
local RANGED_DPS = L"RANGED_DPS"
local MELEE_DPS = L"MELEE_DPS"
local TANK = L"TANK"

-- Localized functions
local mathFloor = math.floor
local mathMax = math.max
local mathMin = math.min
local mathExp = math.exp
local tableSort = table.sort
local pairs = pairs
local ipairs = ipairs
local osDate = os and os.date

local timeLeft = TIME_DELAY
local macroWatchdogTimeLeft = 0
local currentTime = 0
local loadingEndEventRegistered = false
local activeEventsRegistered = false
local macroTooltipHookInstalled = false
local actionButtonHooksInstalled = false
local hotbarEventRegistered = false
local ensureMacroAvailable

local MapPointTypeFilter = {
	[SystemData.MapPips.PLAYER] = true,
	[SystemData.MapPips.GROUP_MEMBER] = true,
	[SystemData.MapPips.WARBAND_MEMBER] = true,
	[SystemData.MapPips.DESTRUCTION_ARMY] = true,
	[SystemData.MapPips.ORDER_ARMY] = true
}

local ArcheType = {
	[GameData.CareerLine.ZEALOT] 			= HEALER,
	[GameData.CareerLine.ARCHMAGE] 			= HEALER,
	[GameData.CareerLine.SHAMAN] 			= HEALER,
	[GameData.CareerLine.RUNE_PRIEST] 		= HEALER,
	[GameData.CareerLine.WARRIOR_PRIEST] 	= HEALER,
	[GameData.CareerLine.DISCIPLE] 			= HEALER,
	[GameData.CareerLine.ENGINEER] 			= RANGED_DPS,
	[GameData.CareerLine.SQUIG_HERDER] 		= RANGED_DPS,
	[GameData.CareerLine.BRIGHT_WIZARD] 	= RANGED_DPS,
	[GameData.CareerLine.MAGUS] 			= RANGED_DPS,
	[GameData.CareerLine.SORCERER] 			= RANGED_DPS,
	[GameData.CareerLine.SHADOW_WARRIOR] 	= RANGED_DPS,
	[GameData.CareerLine.SLAYER] 			= MELEE_DPS,
	[GameData.CareerLine.MARAUDER] 			= MELEE_DPS,
	[GameData.CareerLine.CHOPPA] 			= MELEE_DPS,
	[GameData.CareerLine.WHITE_LION] 		= MELEE_DPS,
	[GameData.CareerLine.WITCH_ELF] 		= MELEE_DPS,
	[GameData.CareerLine.WITCH_HUNTER] 		= MELEE_DPS,
	[GameData.CareerLine.IRON_BREAKER] 		= TANK,
	[GameData.CareerLine.KNIGHT] 			= TANK,
	[GameData.CareerLine.SWORDMASTER] 		= TANK,
	[GameData.CareerLine.BLACKGUARD] 		= TANK,
	[GameData.CareerLine.CHOSEN] 			= TANK,
	[GameData.CareerLine.BLACK_ORC] 		= TANK,
}
local CareerIDsToLines = {
	[20]	= GameData.CareerLine.IRON_BREAKER,
	[100]	= GameData.CareerLine.SWORDMASTER,
	[64]	= GameData.CareerLine.CHOSEN,
	[24]	= GameData.CareerLine.BLACK_ORC,
	[60]	= GameData.CareerLine.WITCH_HUNTER,
	[102]	= GameData.CareerLine.WHITE_LION,
	[65]	= GameData.CareerLine.MARAUDER,
	[105]	= GameData.CareerLine.WITCH_ELF,
	[62]	= GameData.CareerLine.BRIGHT_WIZARD,
	[67]	= GameData.CareerLine.MAGUS,
	[107]	= GameData.CareerLine.SORCERER,
	[23]	= GameData.CareerLine.ENGINEER,
	[101]	= GameData.CareerLine.SHADOW_WARRIOR,
	[27]	= GameData.CareerLine.SQUIG_HERDER,
	[63]	= GameData.CareerLine.WARRIOR_PRIEST,
	[106]	= GameData.CareerLine.DISCIPLE,
	[103]	= GameData.CareerLine.ARCHMAGE,
	[26]	= GameData.CareerLine.SHAMAN,
	[22]	= GameData.CareerLine.RUNE_PRIEST,
	[66]	= GameData.CareerLine.ZEALOT,
	[104]	= GameData.CareerLine.BLACKGUARD,
	[61]	= GameData.CareerLine.KNIGHT,
	[25]	= GameData.CareerLine.CHOPPA,
	[21]	= GameData.CareerLine.SLAYER,
}

local LosCheckAbiliyId = {
	[GameData.CareerLine.SHAMAN]			= {healID = 1898, ressID = 1908}, -- Gork'll Fix It, Gedup!
	[GameData.CareerLine.RUNE_PRIEST]		= {healID = 1587, ressID = 1598}, -- Grungni's Gift, Rune of Life
	[GameData.CareerLine.DISCIPLE]			= {healID = 9548, ressID = 9558}, -- Restore Essence, Stand, Coward!
	[GameData.CareerLine.ARCHMAGE]			= {healID = 9236, ressID = 9246}, -- Healing Energy, Gift of Life
	[GameData.CareerLine.WARRIOR_PRIEST]	= {healID = 8238, ressID = 8248}, -- Divine Aid, Breath of Sigmar
	[GameData.CareerLine.ZEALOT]			= {healID = 8569, ressID = 8555}, -- Flash Of Chaos, Tzeentch Shall Remake You
}

local PartyTargetEvent = {
	[1] = SystemData.Events.TARGET_GROUP_MEMBER_1,
	[2] = SystemData.Events.TARGET_GROUP_MEMBER_2,
	[3] = SystemData.Events.TARGET_GROUP_MEMBER_3,
	[4] = SystemData.Events.TARGET_GROUP_MEMBER_4,
	[5] = SystemData.Events.TARGET_GROUP_MEMBER_5,
	[6] = SystemData.Events.TARGET_GROUP_MEMBER_6,
}

-- Effect id allowlists used to filter dead targets.
-- Pending resurrection effects should contain the buff/effect id shown on a corpse that
-- already has a rez offer. Use /wt buffs while targeting that corpse to discover the id.
local REZ_PENDING_EFFECT_IDS = {
	[1598] = true, -- Rune of Life
	[1908] = true, -- Gedup!
	[8248] = true, -- Breath of Sigmar
	[8555] = true, -- Tzeentch Shall Remake You
	[9246] = true, -- Gift of Life
	[9558] = true, -- Stand, Coward!
}
-- Unresurrectable corpse effects.
local REZ_BLOCK_EFFECT_IDS = {
	[9700] = true, -- Purgatory (Witch Hunter)
	[9701] = true, -- Shadow of Death (Witch Elf)
	[8567] = true, -- Mark of Remaking (Zealot self-rez)
	[1608] = true, -- Oath Rune of Sanctuary (Rune Priest self-rez)
}

local REZ_BLOCK_EFFECT_DURATIONS = {
	[9700] = DEFAULT_REZ_BLOCK_DURATION,
	[9701] = DEFAULT_REZ_BLOCK_DURATION,
}

-- Boss anti-res debuff ("Terror"); all known variants share ability icon 2572.
local TERROR_EFFECT_ICON = 2572
local TERROR_EFFECT_IDS = {
	[5968] = true,
	[5969] = true,
	[5970] = true,
	[13795] = true,
	[23001] = true,
	[23895] = true,
	[23896] = true,
	[23897] = true,
	[27008] = true,
}

local function normalizePriorityRank(rank)
	rank = tonumber(rank) or 5
	if rank < 1 then return 1 end
	if rank > 5 then return 5 end
	return mathFloor(rank)
end

local function getPlayerPriorityRank(player)
	if not player or not WarTriage.Settings then
		return 5
	end

	local settings = WarTriage.Settings
	if player.name == WarTriage.Player.name then
		return normalizePriorityRank(settings.prioSelf)
	end

	if player.archeType == HEALER then
		return normalizePriorityRank(settings.prioHealer)
	elseif player.archeType == RANGED_DPS then
		return normalizePriorityRank(settings.prioRangedDps)
	elseif player.archeType == MELEE_DPS then
		return normalizePriorityRank(settings.prioMeleeDps)
	elseif player.archeType == TANK then
		return normalizePriorityRank(settings.prioTank)
	end

	return 5
end

local function getSelectionRouteName(player)
	if not player then return "unknown" end
	if player.name == WarTriage.Player.name then
		return "self"
	end
	if player.archeType == HEALER then
		return "healer"
	elseif player.archeType == RANGED_DPS then
		return "ranged-dps"
	elseif player.archeType == MELEE_DPS then
		return "melee-dps"
	elseif player.archeType == TANK then
		return "tank"
	end
	return "unknown"
end

local function getBuffRemainingSeconds(buff, fallbackSeconds)
	if not buff then return fallbackSeconds end

	local directFields = {
		"timeRemaining",
		"remainingTime",
		"timeLeft",
		"duration",
		"buffDuration",
		"durationSeconds",
	}

	for _, fieldName in ipairs(directFields) do
		local value = tonumber(buff[fieldName])
		if value and value > 0 then
			return value
		end
	end

	local duration = tonumber(buff.duration)
	if duration and duration > 0 then
		local elapsed = tonumber(buff.passedTime) or tonumber(buff.elapsedTime) or tonumber(buff.timePassed)
		if elapsed and elapsed >= 0 then
			local remaining = duration - elapsed
			if remaining > 0 then
				return remaining
			end
		end
	end

	return fallbackSeconds
end

local function getFriendlyTargetBuffs()
	return GetBuffs(GameData.BuffTargetType.TARGET_FRIENDLY) or {}
end

local function isNameOnSocialList(playerName, socialList)
	local function normalizeWName(value)
		if value == nil then return nil end
		local normalized = value
		local pos = normalized:find(L"^", 1, true)
		if pos then
			normalized = normalized:sub(1, pos - 1)
		end
		return normalized
	end

	if not playerName or playerName == L"" then
		return false
	end

	if type(socialList) ~= "table" then
		return false
	end

	local normalizedPlayerName = normalizeWName(playerName)
	for _, entry in ipairs(socialList) do
		local ignoredName = normalizeWName(entry and entry.name)
		if ignoredName and ignoredName ~= L"" then
			if WStringsCompareIgnoreGrammer and WStringsCompareIgnoreGrammer(normalizedPlayerName, ignoredName) == 0 then
				return true
			end
			if ignoredName == normalizedPlayerName then
				return true
			end
		end
	end

	return false
end

local function getFriendlyTargetRezState()
	local rezPending = false
	local rezBlocked = false
	local pendingDuration
	local blockedDuration
	local buffs = getFriendlyTargetBuffs()

	for _, buff in pairs(buffs) do
		local abilityId = buff.abilityId
		if REZ_PENDING_EFFECT_IDS[abilityId] then
			rezPending = true
			pendingDuration = getBuffRemainingSeconds(buff, pendingDuration)
		elseif REZ_BLOCK_EFFECT_IDS[abilityId] then
			rezBlocked = true
			blockedDuration = getBuffRemainingSeconds(buff, REZ_BLOCK_EFFECT_DURATIONS[abilityId])
		end
	end

	return {
		pending = rezPending,
		pendingDuration = pendingDuration,
		blocked = rezBlocked,
		blockedDuration = blockedDuration,
	}
end

-- Minimal cooldown probe using a hidden hotbar slot
local TEST_BARSLOT = 118
local function IsActionOnCooldown(actionId)
	if not actionId or actionId == 0 then return false end
	SetHotbarData(TEST_BARSLOT, GameData.PlayerActions.DO_ABILITY, actionId)
	local cd = GetHotbarCooldown(TEST_BARSLOT)
	return cd and cd > 0.1
end

local function fixString (str)
	if (str == nil) then return nil end
	local str = str
	local pos = str:find (L"^", 1, true)
	if (pos) then str = str:sub (1, pos - 1) end
	return str
end

local function hasBuff(target, id)
    local buffData = GetBuffs(target)
    if (buffData == nil)
    then
        return false
    end

    for _, b in pairs( buffData )
    do
        if (b.abilityId == id)
        then
            return true
        end
    end
    return false
end

local function hasTerrorDebuff(target)
	local buffData = GetBuffs(target)
	if buffData == nil then
		return false
	end

	for _, b in pairs(buffData) do
		if TERROR_EFFECT_IDS[b.abilityId] or b.iconNum == TERROR_EFFECT_ICON then
			return true
		end
	end
	return false
end

local clampHealthPercent

clampHealthPercent = function(health)
	health = tonumber(health) or 100
	if health < 0 then return 0 end
	if health > 100 then return 100 end
	return health
end

local function toWString(value)
	if value == nil then return L"" end
	if type(value) == "string" then
		return towstring(value)
	end
	return value
end

local function isTraceLoggingEnabled()
	return WarTriage and WarTriage.Settings and WarTriage.Settings.traceLogging
end

local function appendTrace(eventName, message)
	if not isTraceLoggingEnabled() then return end

	local entries = WarTriage.TraceState.entries
	local entry = {
		time = currentTime,
		event = toWString(eventName),
		message = toWString(message),
	}
	entries[#entries + 1] = entry

	if #entries > TRACE_LOG_LIMIT then
		table.remove(entries, 1)
	end
end

local function appendTraceUnique(stateKey, signature, eventName, message)
	if not isTraceLoggingEnabled() then return end
	if WarTriage.TraceState[stateKey] == signature then
		return
	end

	WarTriage.TraceState[stateKey] = signature
	appendTrace(eventName, message)
end

local function formatCandidateTrace(player)
	if not player or not player.name or player.name == L"" then
		return L"-"
	end

	local result = player.name .. L" @ " .. towstring(clampHealthPercent(player.health)) .. L"%"
	if player.distance ~= nil then
		result = result .. L", " .. towstring(player.distance) .. L"ft"
	end
	return result
end

local function getTraceContextSuffix()
	local mode = "solo"
	if GameData.Player.isInScenario or GameData.Player.isInSiege then
		mode = "scenario"
	elseif IsWarBandActive and IsWarBandActive() then
		mode = "warband"
	elseif GameData.Player.isGrouped then
		mode = "party"
	end

	return L" [mode="
		.. towstring(mode)
		.. L", ownPartyOnly="
		.. towstring(WarTriage.Settings and WarTriage.Settings.ownPartyOnly and 1 or 0)
		.. L", autoOwnParty="
		.. towstring(WarTriage.Settings and WarTriage.Settings.autoTargetOwnParty and 1 or 0)
		.. L"]"
end

local function formatTraceName(name)
	if not name or name == L"" then
		return L"-"
	end
	return name
end

local function traceSelectionDecision(routeName, player)
	local routeW = toWString(routeName or "unknown")
	local playerName = player and player.name or L""
	local playerHealth = player and clampHealthPercent(player.health) or 100
	local signature = routeW .. L"|" .. formatTraceName(playerName) .. L"|" .. towstring(playerHealth)
	appendTraceUnique(
		"lastDecisionSignature",
		signature,
		"selection-route",
		L"route="
		.. routeW
		.. L"; choice="
		.. formatCandidateTrace(player)
		.. L"; friendlyTarget="
		.. formatCandidateTrace(WarTriage.CurrentFriendlyTarget)
		.. L"; macroTarget="
		.. formatTraceName(WarTriage.PlayerTarget)
		.. getTraceContextSuffix()
	)
end

local function traceMacroAction(actionName, player, reason)
	local actionW = toWString(actionName or "unknown")
	local reasonW = toWString(reason or "")
	local playerName = player and player.name or L""
	local playerHealth = player and clampHealthPercent(player.health) or 100
	local signature = actionW .. L"|" .. formatTraceName(playerName) .. L"|" .. towstring(playerHealth) .. L"|" .. reasonW
	appendTraceUnique(
		"lastMacroActionSignature",
		signature,
		"macro-action",
		L"action="
		.. actionW
		.. L"; player="
		.. formatCandidateTrace(player)
		.. L"; reason="
		.. reasonW
		.. L"; pending="
		.. formatTraceName(WarTriage.AutoTargetState and WarTriage.AutoTargetState.pendingName)
		.. getTraceContextSuffix()
	)
end

local function getLocalPlayerHealthPercent(contextLabel)
	local hitPoints = GameData.Player.hitPoints or {}
	local current = tonumber(hitPoints.current) or 0
	local maximum = tonumber(hitPoints.maximum) or 0
	if maximum <= 0 then
		appendTrace("local-health-invalid", toWString(contextLabel) .. L" saw local max HP <= 0; using 100% fallback.")
		return 100
	end

	return clampHealthPercent(mathFloor(100 * current / maximum))
end

local function formatVersion(value)
	return string.format("%.2f", tonumber(value) or VERSION)
end

local function formatCheckboxIcon(enabled)
	if enabled then
		return L"<icon57>"
	end
	return L"<icon58>"
end

local function setTooltipLabelText(windowName, suffix, text)
	LabelSetText(windowName .. suffix, text or L"")
end

local function clearWarTriageAbilityTooltipRequirements(windowName)
	local maxRequirements = GameData.ABILITY_REQUIREMENT_COUNT or 5
	for requirementIndex = 1, maxRequirements do
		local requirementLabel = windowName .. "Requirements" .. requirementIndex
		if DoesWindowExist(requirementLabel) then
			LabelSetText(requirementLabel, L"")
		end
	end
end

local function getWarTriageMacroTooltipStatus()
	if not WarTriage.Settings or not WarTriage.Settings.enabled then
		return L"Disabled"
	end
	if not WarTriage.Settings.isHealer then
		return L"Dormant"
	end
	if WarTriage.MacroButtonState and WarTriage.MacroButtonState.playerName ~= L"" then
		return L"Ready"
	end
	return L"No Target"
end

local function getWarTriageMacroTooltipDescription()
	if not WarTriage.Settings or not WarTriage.Settings.enabled then
		return L"Addon disabled. The macro is inactive and the button is gray because clicking it would do nothing."
	end
	if not WarTriage.Settings.isHealer then
		return L"Current career is not a healer. WarTriage stays dormant and the button remains gray until it can actually target a player."
	end
	if WarTriage.MacroButtonState and WarTriage.MacroButtonState.playerName ~= L"" then
		return L"Click the macro to target the queued ally. Glow indicates a usable queued target."
	end
	return L"No valid player target is currently queued on the macro. The button is gray until WarTriage finds one."
end

local function getWarTriageMacroTooltipQueuedLine()
	local macroName = WarTriage.MacroButtonState and WarTriage.MacroButtonState.playerName
	if macroName == nil or macroName == L"" then
		return L"Healing assist macro"
	end

	for _, player in ipairs(WarTriage.Players or {}) do
		if player.name == macroName then
			if player.health == 0 then
				return L"Queued rez: " .. macroName
			end
			return L"Queued heal: " .. macroName .. L" @ " .. towstring(clampHealthPercent(player.health)) .. L"%"
		end
	end

	return L"Queued: " .. macroName
end

local function getWarTriageMacroTooltipPrioritySummary()
	return towstring("Hurt < "
		.. tostring(tonumber(WarTriage.Settings.hurtThreshold) or 100)
		.. "%, rez safety "
		.. tostring(tonumber(WarTriage.Settings.rezSafetyThreshold) or DEFAULT_REZ_SAFETY_THRESHOLD)
		.. "%, crossover "
		.. tostring(tonumber(WarTriage.Settings.rankCrossover) or DEFAULT_RANK_CROSSOVER))
end

local function getWarTriageMacroTooltipRankSummary()
	return towstring("Ranks S/H/R/M/T "
		.. tostring(normalizePriorityRank(WarTriage.Settings.prioSelf)) .. "/"
		.. tostring(normalizePriorityRank(WarTriage.Settings.prioHealer)) .. "/"
		.. tostring(normalizePriorityRank(WarTriage.Settings.prioRangedDps)) .. "/"
		.. tostring(normalizePriorityRank(WarTriage.Settings.prioMeleeDps)) .. "/"
		.. tostring(normalizePriorityRank(WarTriage.Settings.prioTank)))
end

local function getWarTriageMacroTooltipSettingsLineOne()
	return formatCheckboxIcon(WarTriage.Settings.enabled) .. L" Enabled"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.losCheck) .. L" LOS Check"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.rangeCheck) .. L" Range Check"
		.. L"\n"
		.. formatCheckboxIcon(WarTriage.Settings.ownPartyOnly) .. L" Own Party Only"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.ignoreDead) .. L" Ignore Dead"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.ignoreIgnoredPlayers) .. L" Skip Ignored Players"
end

local function getWarTriageMacroTooltipSettingsLineTwo()
	return formatCheckboxIcon(WarTriage.Settings.favorFriends) .. L" Favor Friends (25% HP Bias)"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.glowEffects) .. L" Glow Effects"
		.. L"\n"
		.. formatCheckboxIcon(WarTriage.Settings.autoTargetOwnParty) .. L" Auto-Target Self / Own Party"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.manualOverride)
		.. L" Manual Target Lock (" .. towstring(tonumber(WarTriage.Settings.manualOverrideDuration) or 0) .. L"s)"
end

local function getWarTriageMacroTooltipFooter()
	return L"Ctrl+click macro button: enable / disable WarTriage."
		.. L"\nUse /wt to change settings."
end

local function getWarTriageMacroTooltipFallbackActionText()
	return formatCheckboxIcon(WarTriage.Settings.ignoreIgnoredPlayers) .. L" Skip Ignored Players"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.favorFriends) .. L" Favor Friends"
		.. L"\n"
		.. formatCheckboxIcon(WarTriage.Settings.glowEffects) .. L" Glow Effects"
		.. L"   "
		.. formatCheckboxIcon(WarTriage.Settings.autoTargetOwnParty) .. L" Auto-Target Party"
		.. L"\n"
		.. formatCheckboxIcon(WarTriage.Settings.manualOverride)
		.. L" Manual Lock (" .. towstring(tonumber(WarTriage.Settings.manualOverrideDuration) or 0) .. L"s)"
		.. L"\n"
		.. getWarTriageMacroTooltipFooter()
end

local function setDefaultTooltipRowColor(row, column, colorDef)
	if not colorDef or type(Tooltips.SetTooltipColorDef) ~= "function" then
		return
	end
	Tooltips.SetTooltipColorDef(row, column, colorDef)
end

local function clearDefaultTooltipRows()
	if not Tooltips or type(Tooltips.SetTooltipText) ~= "function" then
		return
	end

	local numRows = Tooltips.NUM_ROWS or 17
	local numColumns = Tooltips.NUM_COLUMNS or 3
	for rowIndex = 1, numRows do
		for columnIndex = 1, numColumns do
			Tooltips.SetTooltipText(rowIndex, columnIndex, L"")
		end
	end

	if type(Tooltips.SetTooltipActionText) == "function" then
		Tooltips.SetTooltipActionText(L"")
	end
end

local function setDefaultTooltipFooter()
	if type(Tooltips.SetTooltipActionText) ~= "function" then
		return
	end

	Tooltips.SetTooltipActionText(getWarTriageMacroTooltipFooter())

	local extraColor = Tooltips.COLOR_EXTRA_TEXT_DEFAULT or { r = 175, g = 175, b = 175 }
	if DoesWindowExist("DefaultTooltipActionText") then
		LabelSetTextColor("DefaultTooltipActionText", extraColor.r, extraColor.g, extraColor.b)
	end
end

local TOOLTIP_MIN_WIDTH = 390
local TOOLTIP_BOTTOM_PADDING = 16

local function finalizeDefaultTooltipWithPadding()
	Tooltips.Finalize()

	if not DoesWindowExist("DefaultTooltip") then
		return
	end

	local width, height = WindowGetDimensions("DefaultTooltip")
	WindowSetDimensions("DefaultTooltip", math.max(width, TOOLTIP_MIN_WIDTH), height + TOOLTIP_BOTTOM_PADDING)
end

local function createWarTriageRichMacroTooltip(mouseoverWindow, anchor)
	if not Tooltips
		or type(Tooltips.CreateTextOnlyTooltip) ~= "function"
		or type(Tooltips.SetTooltipText) ~= "function"
		or type(Tooltips.Finalize) ~= "function"
		or type(Tooltips.AnchorTooltip) ~= "function"
	then
		return false
	end

	local headingColor = Tooltips.COLOR_HEADING or { r = 255, g = 204, b = 102 }
	local bodyColor = Tooltips.COLOR_BODY or { r = 255, g = 255, b = 255 }

	Tooltips.CreateTextOnlyTooltip(mouseoverWindow, nil)
	clearDefaultTooltipRows()

	Tooltips.SetTooltipText(1, Tooltips.COLUMN_LEFT or 1, L"WarTriage")
	setDefaultTooltipRowColor(1, Tooltips.COLUMN_LEFT or 1, headingColor)
	Tooltips.SetTooltipText(1, Tooltips.COLUMN_RIGHT_RIGHT_ALIGN or 2, getWarTriageMacroTooltipStatus())
	setDefaultTooltipRowColor(1, Tooltips.COLUMN_RIGHT_RIGHT_ALIGN or 2, headingColor)

	Tooltips.SetTooltipText(2, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipQueuedLine())
	setDefaultTooltipRowColor(2, Tooltips.COLUMN_LEFT or 1, bodyColor)
	Tooltips.SetTooltipText(2, Tooltips.COLUMN_RIGHT_RIGHT_ALIGN or 2, towstring("v" .. formatVersion(WarTriage.Settings.version)))
	setDefaultTooltipRowColor(2, Tooltips.COLUMN_RIGHT_RIGHT_ALIGN or 2, bodyColor)

	Tooltips.SetTooltipText(3, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipDescription())
	setDefaultTooltipRowColor(3, Tooltips.COLUMN_LEFT or 1, headingColor)

	Tooltips.SetTooltipText(4, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipPrioritySummary())
	setDefaultTooltipRowColor(4, Tooltips.COLUMN_LEFT or 1, bodyColor)

	Tooltips.SetTooltipText(5, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipRankSummary())
	setDefaultTooltipRowColor(5, Tooltips.COLUMN_LEFT or 1, bodyColor)

	Tooltips.SetTooltipText(6, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipSettingsLineOne())
	setDefaultTooltipRowColor(6, Tooltips.COLUMN_LEFT or 1, bodyColor)

	Tooltips.SetTooltipText(7, Tooltips.COLUMN_LEFT or 1, getWarTriageMacroTooltipSettingsLineTwo())
	setDefaultTooltipRowColor(7, Tooltips.COLUMN_LEFT or 1, bodyColor)

	setDefaultTooltipFooter()
	finalizeDefaultTooltipWithPadding()
	Tooltips.AnchorTooltip(anchor)
	return true
end

local function createWarTriageFallbackAbilityMacroTooltip(mouseoverWindow, anchor)
	if not Tooltips
		or type(Tooltips.CreateCustomTooltip) ~= "function"
		or type(Tooltips.AnchorTooltip) ~= "function"
		or type(Tooltips.SetExtraText) ~= "function"
	then
		return false
	end

	local windowName = "AbilityTooltip"
	setTooltipLabelText(windowName, "Name", L"WarTriage")
	setTooltipLabelText(windowName, "SpecLine", getWarTriageMacroTooltipQueuedLine())
	setTooltipLabelText(windowName, "Type", getWarTriageMacroTooltipStatus())
	setTooltipLabelText(windowName, "Cost", L"")
	setTooltipLabelText(windowName, "CastTime", L"")
	setTooltipLabelText(windowName, "Level", L"")
	setTooltipLabelText(windowName, "Range", L"")
	setTooltipLabelText(windowName, "Cooldown", L"")
	setTooltipLabelText(windowName, "Desc", getWarTriageMacroTooltipDescription())

	clearWarTriageAbilityTooltipRequirements(windowName)
	setTooltipLabelText(windowName, "Requirements1", formatCheckboxIcon(WarTriage.Settings.enabled) .. L" Enabled")
	setTooltipLabelText(windowName, "Requirements2", formatCheckboxIcon(WarTriage.Settings.losCheck) .. L" LOS Check")
	setTooltipLabelText(windowName, "Requirements3", formatCheckboxIcon(WarTriage.Settings.rangeCheck) .. L" Range Check")
	setTooltipLabelText(windowName, "Requirements4", formatCheckboxIcon(WarTriage.Settings.ownPartyOnly) .. L" Own Party Only")
	setTooltipLabelText(windowName, "Requirements5", formatCheckboxIcon(WarTriage.Settings.ignoreDead) .. L" Ignore Dead")
	Tooltips.SetExtraText(windowName, "ActionText", "ActionTextLine", getWarTriageMacroTooltipFallbackActionText(), nil)

	Tooltips.CreateCustomTooltip(mouseoverWindow, windowName)
	Tooltips.AnchorTooltip(anchor, false, true)
	return true
end

local function createWarTriageMacroTooltip(mouseoverWindow, anchor)
	if createWarTriageRichMacroTooltip(mouseoverWindow, anchor) then
		return true
	end
	return createWarTriageFallbackAbilityMacroTooltip(mouseoverWindow, anchor)
end

local function installMacroTooltipHook()
	if macroTooltipHookInstalled then return end
	if not Tooltips or type(Tooltips.CreateMacroTooltip) ~= "function" then return end

	local originalCreateMacroTooltip = Tooltips.CreateMacroTooltip
	Tooltips.CreateMacroTooltip = function(macroData, mouseoverWindow, anchor, extraText)
		if macroData and macroData.name == towstring(WARTRIAGE_MACRO_NAME) then
			if createWarTriageMacroTooltip(mouseoverWindow, anchor) then
				return
			end
		end
		return originalCreateMacroTooltip(macroData, mouseoverWindow, anchor, extraText)
	end

	macroTooltipHookInstalled = true
end

local function getChatPrefixWString(includeSpace)
	local r, g, b = WARTRIAGE_CHAT_PREFIX_COLOR[1], WARTRIAGE_CHAT_PREFIX_COLOR[2], WARTRIAGE_CHAT_PREFIX_COLOR[3]
	local coloredPartRaw = string.format("<LINK data=\"0\" color=\"%d,%d,%d\" text=\"%s\">", r, g, b, WARTRIAGE_CHAT_PREFIX_TEXT)
	local prefix = L"[" .. towstring(coloredPartRaw) .. L"]"
	if includeSpace then
		prefix = prefix .. L" "
	end
	return prefix
end

local function getButtonGlowFrame(button)
	if not button then return nil end
	if button.m_WarTriageGlowFrame then
		return button.m_WarTriageGlowFrame
	end

	local glowFrame = button.m_Windows and button.m_Windows[6]
	if not glowFrame and button.GetName then
		local glowWindowName = button:GetName() .. "OverlayGlow"
		if DoesWindowExist(glowWindowName) then
			glowFrame = AnimatedImage:CreateFrameForExistingWindow(glowWindowName)
		end
	end

	button.m_WarTriageGlowFrame = glowFrame
	return glowFrame
end

local function getButtonBaseIconFrame(button)
	if not button or not button.m_Windows then return nil end
	return button.m_Windows[0]
end

local function getButtonStatusOverlayFrame(button)
	if not button or not button.m_Windows then return nil end
	return button.m_Windows[7]
end

local function setMacroButtonEnabledOverlay(button, enabled)
	local overlay = getButtonStatusOverlayFrame(button)
	if not overlay then return end

	overlay:Show(true)
	if enabled then
		overlay:SetText(L"<icon00057>")
	else
		overlay:SetText(L"<icon00058>")
	end
end

local function setMacroButtonVisualDisabled(button, disabled)
	if not button then return end

	local iconFrame = getButtonBaseIconFrame(button)
	local tint = disabled and WARTRIAGE_DISABLED_TINT or WARTRIAGE_ENABLED_TINT
	if iconFrame then
		iconFrame:SetTintColor(tint[1], tint[2], tint[3])
	end

	if disabled then
		local glowFrame = getButtonGlowFrame(button)
		if glowFrame then
			glowFrame:StopAnimation(true)
		end
		if button.m_Name then
			WindowSetGameActionData(button.m_Name.."Action", 0, 0, L"")
		end
	end
end

----------------------------------------------------------------
-- WarTriage
----------------------------------------------------------------
WarTriage = {}
WarTriage.Player = {}
WarTriage.Players = {}
WarTriage.PlayerDistances = {}
WarTriage.RezEffectCache = {}
WarTriage.PlayerHealthHistory = {}
WarTriage.OwnPartyTargetEvents = {}
WarTriage.AutoTargetState = {
	pendingName = L"",
	nextAllowedTime = 0,
}
WarTriage.RefreshState = {
	playersDirty = true,
	transientDirty = true,
	targetDirty = true,
	nextPlayersSnapshotTime = 0,
	nextTransientRefreshTime = 0,
	nextTargetRefreshTime = 0,
}
WarTriage.MacroWarningState = {
	missing = false,
	unplaced = false,
	repaired = false,
	full = false,
}
WarTriage.TraceState = {
	entries = {},
	lastDecisionSignature = nil,
	lastMacroActionSignature = nil,
}
WarTriage.MacroButtonState = {
	playerName = L"",
	hasTarget = false,
	glowLevel = 0,
}
WarTriage.PlayerTarget = L""
WarTriage.CurrentFriendlyTarget = {
	name = L"",
	health = 100,
	isExplicit = false,
}
WarTriage.ManualOverrideTarget = {
	name = L"",
	health = 100,
	timeLeft = 0,
}
WarTriage.LastSuggestedTarget = L""
WarTriage.PreviousFriendlyTarget = L""

local function mergeSettings(defaults, current)
	local merged = {}
	current = type(current) == "table" and current or {}

	for key, defaultValue in pairs(defaults) do
		local currentValue = current[key]
		if type(defaultValue) == "table" then
			merged[key] = mergeSettings(defaultValue, currentValue)
		elseif currentValue == nil then
			merged[key] = defaultValue
		else
			merged[key] = currentValue
		end
	end

	return merged
end

local function migrateSettings(settings)
	settings = type(settings) == "table" and settings or {}
	local oldVersion = tonumber(settings.version) or 0

	if settings.prioSelf == nil or oldVersion < 3.0 then
		settings.hurtThreshold = settings.hurtThreshold or settings.playerTargetPct or 100
		settings.rankCrossover = settings.rankCrossover or DEFAULT_RANK_CROSSOVER
		settings.prioSelf = settings.prioSelf or 1
		settings.prioHealer = settings.prioHealer or 2
		settings.prioRangedDps = settings.prioRangedDps or 3
		settings.prioMeleeDps = settings.prioMeleeDps or 4
		settings.prioTank = settings.prioTank or 5
	end

	if settings.rezSafetyThreshold == nil then
		settings.rezSafetyThreshold = DEFAULT_REZ_SAFETY_THRESHOLD
	end

	return settings
end

local function normalizeSettings(settings)
	settings.hurtThreshold = clampHealthPercent(settings.hurtThreshold or 100)
	settings.rezSafetyThreshold = clampHealthPercent(settings.rezSafetyThreshold or DEFAULT_REZ_SAFETY_THRESHOLD)

	settings.rankCrossover = tonumber(settings.rankCrossover) or DEFAULT_RANK_CROSSOVER
	if settings.rankCrossover < MIN_RANK_CROSSOVER then
		settings.rankCrossover = MIN_RANK_CROSSOVER
	elseif settings.rankCrossover > MAX_RANK_CROSSOVER then
		settings.rankCrossover = MAX_RANK_CROSSOVER
	end

	settings.prioSelf = normalizePriorityRank(settings.prioSelf)
	settings.prioHealer = normalizePriorityRank(settings.prioHealer)
	settings.prioRangedDps = normalizePriorityRank(settings.prioRangedDps)
	settings.prioMeleeDps = normalizePriorityRank(settings.prioMeleeDps)
	settings.prioTank = normalizePriorityRank(settings.prioTank)

	settings.manualOverrideDuration = tonumber(settings.manualOverrideDuration) or 4
	if settings.manualOverrideDuration < 0 then
		settings.manualOverrideDuration = 0
	end

	settings.version = VERSION
	settings.traceLogging = false
	return settings
end

local function initializeSettings(currentSettings)
	local settings = mergeSettings(WarTriage.DefaultSettings, migrateSettings(currentSettings))
	return normalizeSettings(settings)
end

local function isAddonActive()
	return WarTriage.Settings and WarTriage.Settings.enabled and WarTriage.Settings.isHealer
end

local function resetRuntimeState()
	WarTriage.Players = {}
	WarTriage.PlayerDistances = {}
	WarTriage.RezEffectCache = {}
	WarTriage.PlayerHealthHistory = {}
	WarTriage.OwnPartyTargetEvents = {}
	WarTriage.PlayerTarget = L""
	WarTriage.CurrentFriendlyTarget.name = L""
	WarTriage.CurrentFriendlyTarget.health = 100
	WarTriage.CurrentFriendlyTarget.isExplicit = false
	WarTriage.ManualOverrideTarget.name = L""
	WarTriage.ManualOverrideTarget.health = 100
	WarTriage.ManualOverrideTarget.timeLeft = 0
	WarTriage.LastSuggestedTarget = L""
	WarTriage.PreviousFriendlyTarget = L""
	WarTriage.AutoTargetState.pendingName = L""
	WarTriage.AutoTargetState.nextAllowedTime = 0
	WarTriage.RefreshState.playersDirty = true
	WarTriage.RefreshState.transientDirty = true
	WarTriage.RefreshState.targetDirty = true
	WarTriage.RefreshState.nextPlayersSnapshotTime = 0
	WarTriage.RefreshState.nextTransientRefreshTime = 0
	WarTriage.RefreshState.nextTargetRefreshTime = 0
	timeLeft = 0
	macroWatchdogTimeLeft = 0
	WarTriage.TraceState.lastDecisionSignature = nil
	WarTriage.TraceState.lastMacroActionSignature = nil
	WarTriage.MacroButtonState.playerName = L""
	WarTriage.MacroButtonState.hasTarget = false
	WarTriage.MacroButtonState.glowLevel = 0
	if WarTriage.RefreshMacroButtonAppearance then
		WarTriage.RefreshMacroButtonAppearance()
	end
end

local function markPlayersDirty()
	WarTriage.RefreshState.playersDirty = true
	WarTriage.RefreshState.transientDirty = true
end

local function markTargetDirty()
	WarTriage.RefreshState.targetDirty = true
	WarTriage.RefreshState.transientDirty = true
end

local function markAllDirty()
	markPlayersDirty()
	markTargetDirty()
end

local function sortTrackedPlayers(players)
	local sortFunc = function (k1, k2)
		if k1.health < k2.health then
			return true
		elseif k1.health == k2.health and k1.distance < k2.distance then
			return true
		end
		return false
	end
	tableSort(players, sortFunc)
end

local function getPlayerHealthHistory(name)
	if not name or name == L"" then return nil end
	local history = WarTriage.PlayerHealthHistory[name]
	if history then
		return history
	end

	history = {
		health = nil,
		lastUpdateTime = currentTime,
		lastSeenTime = currentTime,
		damageRate = 0,
		recentlyRezzedUntil = 0,
	}
	WarTriage.PlayerHealthHistory[name] = history
	return history
end

local function updatePlayerHealthHistory(player)
	if not player or not player.name or player.name == L"" then return end

	local history = getPlayerHealthHistory(player.name)
	local now = currentTime
	local lastHealth = history.health
	local dt = now - (history.lastUpdateTime or now)

	if lastHealth ~= nil and dt > 0 then
		if lastHealth <= 0 and player.health > 0 then
			history.recentlyRezzedUntil = now + RECENT_REZ_GRACE_PERIOD
		end

		if player.health < lastHealth then
			local damageRate = (lastHealth - player.health) / dt
			local previousRate = history.damageRate or 0
			history.damageRate = mathMax(damageRate, (previousRate * 0.4) + (damageRate * 0.6))
		elseif player.health > lastHealth then
			local healRate = (player.health - lastHealth) / dt
			local previousRate = history.damageRate or 0
			history.damageRate = mathMax(0, previousRate - healRate)
		end
	end

	history.health = player.health
	history.lastUpdateTime = now
	history.lastSeenTime = now
end

local function decayPlayerHealthHistory(elapsed)
	if elapsed <= 0 then return end

	local decayFactor = mathExp(-DAMAGE_RATE_DECAY_PER_SECOND * elapsed)
	for _, history in pairs(WarTriage.PlayerHealthHistory) do
		if history.damageRate and history.damageRate > 0 then
			history.damageRate = history.damageRate * decayFactor
			if history.damageRate < 0.05 then
				history.damageRate = 0
			end
		end
	end
end

local function cleanupPlayerHealthHistory(activePlayers)
	local activeNames = nil
	if activePlayers then
		activeNames = {}
		for _, player in ipairs(activePlayers) do
			activeNames[player.name] = true
		end
	end

	for name, history in pairs(WarTriage.PlayerHealthHistory) do
		local staleTime = currentTime - (history.lastSeenTime or 0)
		local missingFromSnapshot = activeNames and not activeNames[name]
		if staleTime > HEALTH_HISTORY_STALE_SECONDS or (missingFromSnapshot and staleTime > TIME_DELAY) then
			WarTriage.PlayerHealthHistory[name] = nil
		end
	end
end

local function getPlayerDangerScore(player)
	if not player then return -1 end

	local score = 100 - clampHealthPercent(player.health)
	local history = WarTriage.PlayerHealthHistory[player.name]
	if not history then
		return score
	end

	score = score + mathMin(MAX_DAMAGE_URGENCY_BONUS, (history.damageRate or 0) * DAMAGE_URGENCY_SCALE)
	if history.recentlyRezzedUntil and history.recentlyRezzedUntil > currentTime then
		score = score - RECENT_REZ_URGENCY_PENALTY
	end

	return score
end

local function getPlayerSelectionScore(player, effectiveHealth)
	if not player then return -1 end

	local score = getPlayerDangerScore(player)
	if effectiveHealth ~= nil then
		score = score + (clampHealthPercent(player.health) - clampHealthPercent(effectiveHealth))
	end

	local rank = getPlayerPriorityRank(player)
	local crossover = tonumber(WarTriage.Settings.rankCrossover) or DEFAULT_RANK_CROSSOVER
	return score - (rank - 1) * crossover
end

-- Higher-priority roles (lower rank number) raise the HP floor that blocks rez selection.
-- Incoming damage lowers that floor; high-priority roles treat damage as more urgent.
local function getRezSafetyBlockHealth(player)
	if not player or not WarTriage.Settings then
		return DEFAULT_REZ_SAFETY_THRESHOLD
	end

	local rank = getPlayerPriorityRank(player)
	local crossover = tonumber(WarTriage.Settings.rankCrossover) or DEFAULT_RANK_CROSSOVER
	local baseThreshold = clampHealthPercent(WarTriage.Settings.rezSafetyThreshold or DEFAULT_REZ_SAFETY_THRESHOLD)
	local rankBonus = (5 - rank) * (crossover / REZ_SAFETY_RANK_SCALE)

	local history = WarTriage.PlayerHealthHistory[player.name]
	local damageRate = history and history.damageRate or 0
	local urgencyRankScale = 1 + (5 - rank) * REZ_SAFETY_URGENCY_RANK_FACTOR
	local urgencyPenalty = mathMin(
		REZ_SAFETY_MAX_URGENCY,
		damageRate * REZ_SAFETY_DAMAGE_SCALE * urgencyRankScale
	)

	return clampHealthPercent(baseThreshold + rankBonus - urgencyPenalty)
end

local function livingPlayerBlocksRez(player, effectiveHealth)
	if not player or player.health <= 0 then
		return false
	end

	effectiveHealth = clampHealthPercent(effectiveHealth or player.health)
	return effectiveHealth < getRezSafetyBlockHealth(player)
end

local function isScannableLivingPlayer(player)
	return player
		and player.health > 0
		and player.hasLOS
		and player.distance < MAX_HEAL_DISTANCE
end

local function getSelectionHealthWithFriendBias(player, friendsList)
	local health = clampHealthPercent(player and player.health or 100)
	if not player or not WarTriage.Settings or not WarTriage.Settings.favorFriends then
		return health
	end

	if player.name == WarTriage.Player.name then
		return health
	end

	if isNameOnSocialList(player.name, friendsList) and health < 100 then
		return clampHealthPercent(health * (1 - (FRIEND_HP_BIAS / 100)))
	end

	return health
end

local function refreshFriendlyTargetState()
	WarTriage.PlayerTarget = WarTriage.GetFriendlyTarget()
	WarTriage.RefreshState.targetDirty = false
	WarTriage.RefreshState.nextTargetRefreshTime = currentTime + TARGET_REFRESH_INTERVAL
end

function WarTriage.Initialize()
	WarTriage.Settings = initializeSettings(WarTriage.Settings)
	installMacroTooltipHook()
	installActionButtonHooks()

	LibSlash.RegisterSlashCmd("wartriage", function(input) WarTriage_Config.Slash(input) end)
	LibSlash.RegisterSlashCmd("wt", function(input) WarTriage_Config.Slash(input) end)
	
	WarTriage.CheckCareer()
	WarTriage.Player.name = fixString(LOCAL_PLAYER_NAME)
	WarTriage.Print("v" .. formatVersion(WarTriage.Settings.version) .. " loaded. /wt opens config. /wt help shows commands.")
	
	if WarTriage.Settings.isHealer then
		if not WarTriage.UpdateMacro(WARTRIAGE_MACRO_NAME, WARTRIAGE_MACRO_TEXT, WARTRIAGE_MACRO_ICON) then
			if not WarTriage.MacroWarningState.full then
				WarTriage.Print("<icon20087> Failed to create macro!")
			end
		end
		WarTriage.RegisterHotbarEventHandler()
	else
		WarTriage.UnregisterHotbarEventHandler()
	end

	WarTriage.RegisterEventHandlers(WarTriage.Settings.enabled)
	if isAddonActive() then
		markAllDirty()
	else
		resetRuntimeState()
	end
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.Print(message)
	EA_ChatWindow.Print(
		getChatPrefixWString(true) .. toWString(message),
		SystemData.SystemLogFilters.GENERAL
	)
end

function WarTriage.ClearTraceLog()
	WarTriage.TraceState.entries = {}
	WarTriage.TraceState.lastDecisionSignature = nil
	WarTriage.TraceState.lastMacroActionSignature = nil
	WarTriage.Print("Trace history cleared.")
end

function WarTriage.DumpTraceLog()
	local entries = WarTriage.TraceState.entries
	if #entries == 0 then
		WarTriage.Print("Trace history is empty.")
		return
	end

	WarTriage.Print("Trace history (" .. tostring(#entries) .. " entries, showing last " .. tostring(TRACE_DUMP_TO_CHAT_LIMIT) .. "):")
	local startIndex = math.max(1, #entries - TRACE_DUMP_TO_CHAT_LIMIT + 1)
	for i = startIndex, #entries do
		local entry = entries[i]
		WarTriage.Print(
			"["
			.. tostring(string.format("%.1f", entry.time or 0))
			.. "] "
			.. tostring(entry.event or "")
			.. ": "
			.. tostring(entry.message or "")
		)
	end
end

function WarTriage.SetTraceLoggingEnabled(enabled)
	enabled = enabled == true
	WarTriage.Settings.traceLogging = enabled
	WarTriage.TraceState.lastDecisionSignature = nil
	WarTriage.TraceState.lastMacroActionSignature = nil
	if enabled then
		WarTriage.Print("Trace logging enabled (in-memory only; use /wt trace dump).")
	else
		WarTriage.Print("Trace logging disabled.")
	end
end

function WarTriage.PrintSlashHelp()
	WarTriage.Print("Commands:")
	WarTriage.Print("/wt or /wartriage - open config window")
	WarTriage.Print("/wt help - show this help")
	WarTriage.Print("/wt settings - print current settings")
	WarTriage.Print("/wt buffs - print effects on current friendly target")
	WarTriage.Print("/wt toggle - enable or disable WarTriage")
	WarTriage.Print("/wt trace on|off|status|dump|clear - in-memory debug trace (no log file)")
end

function WarTriage.OnShutdown()
	WarTriage.UnregisterHotbarEventHandler()
	WarTriage.RegisterEventHandlers(false)
end

function WarTriage.RegisterEventHandlers(enabled)
	if not loadingEndEventRegistered and enabled then
		RegisterEventHandler(SystemData.Events.LOADING_END, "WarTriage.LOADING_END")
		loadingEndEventRegistered = true
	elseif loadingEndEventRegistered and not enabled then
		UnregisterEventHandler(SystemData.Events.LOADING_END, "WarTriage.LOADING_END")
		loadingEndEventRegistered = false
	end

	local shouldRegisterActiveEvents = enabled and isAddonActive()
	if not activeEventsRegistered and shouldRegisterActiveEvents then
		RegisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "WarTriage.PLAYER_TARGET_UPDATED")
		RegisterEventHandler(SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED, "WarTriage.PLAYER_CUR_HIT_POINTS_UPDATED")
		RegisterEventHandler(SystemData.Events.GROUP_UPDATED, "WarTriage.GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "WarTriage.GROUP_STATUS_UPDATED")
		RegisterEventHandler(SystemData.Events.SCENARIO_GROUP_UPDATED, "WarTriage.SCENARIO_GROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "WarTriage.SCENARIO_PLAYER_HITS_UPDATED")
		RegisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED, "WarTriage.BATTLEGROUP_UPDATED")
		RegisterEventHandler(SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "WarTriage.BATTLEGROUP_MEMBER_UPDATED")
		activeEventsRegistered = true
		markAllDirty()
	elseif activeEventsRegistered and not shouldRegisterActiveEvents then
		UnregisterEventHandler(SystemData.Events.PLAYER_TARGET_UPDATED, "WarTriage.PLAYER_TARGET_UPDATED")
		UnregisterEventHandler(SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED, "WarTriage.PLAYER_CUR_HIT_POINTS_UPDATED")
		UnregisterEventHandler(SystemData.Events.GROUP_UPDATED, "WarTriage.GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.GROUP_STATUS_UPDATED, "WarTriage.GROUP_STATUS_UPDATED")
		UnregisterEventHandler(SystemData.Events.SCENARIO_GROUP_UPDATED, "WarTriage.SCENARIO_GROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "WarTriage.SCENARIO_PLAYER_HITS_UPDATED")
		UnregisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED, "WarTriage.BATTLEGROUP_UPDATED")
		UnregisterEventHandler(SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "WarTriage.BATTLEGROUP_MEMBER_UPDATED")
		activeEventsRegistered = false
		resetRuntimeState()
	end
end

WarTriage.DefaultSettings = {
		version = VERSION,
		enabled = true,
		ignoreDead = false,
		glowEffects = true,
		hurtThreshold = 100,
		rezSafetyThreshold = DEFAULT_REZ_SAFETY_THRESHOLD,
		rankCrossover = DEFAULT_RANK_CROSSOVER,
		prioSelf = 1,
		prioHealer = 2,
		prioRangedDps = 3,
		prioMeleeDps = 4,
		prioTank = 5,
		isHealer = false,
		macroCreated = false,
		losCheck = true,
		rangeCheck = true,
		ownPartyOnly = false,
		ignoreIgnoredPlayers = false,
		favorFriends = false,
		manualOverride = true,
		manualOverrideDuration = 4,
		autoTargetOwnParty = false,
		traceLogging = false,
}

WarTriage.DefaultSettings = DataUtils.CopyTable(WarTriage.DefaultSettings)

local function clearManualOverride(reason)
	if WarTriage.ManualOverrideTarget.name ~= L"" then
		appendTraceUnique(
			"lastManualOverrideSignature",
			L"clear|" .. WarTriage.ManualOverrideTarget.name .. L"|" .. toWString(reason or "unknown"),
			"manual-lock",
			L"clear=" .. WarTriage.ManualOverrideTarget.name .. L"; reason=" .. toWString(reason or "unknown") .. getTraceContextSuffix()
		)
	end
	WarTriage.ManualOverrideTarget.name = L""
	WarTriage.ManualOverrideTarget.health = 100
	WarTriage.ManualOverrideTarget.timeLeft = 0
end

local function startManualOverride(name, health)
	local duration = tonumber(WarTriage.Settings.manualOverrideDuration) or 0
	if not WarTriage.Settings.manualOverride or duration <= 0 then
		return
	end
	WarTriage.ManualOverrideTarget.name = name
	WarTriage.ManualOverrideTarget.health = clampHealthPercent(health)
	WarTriage.ManualOverrideTarget.timeLeft = duration
	WarTriage.AutoTargetState.pendingName = L""
	WarTriage.AutoTargetState.nextAllowedTime = 0
	if WarTriage.SetMacroTarget then
		WarTriage.SetMacroTarget(WARTRIAGE_MACRO_NAME, L"", 0)
	end
	appendTraceUnique(
		"lastManualOverrideSignature",
		L"start|" .. name .. L"|" .. towstring(clampHealthPercent(health)),
		"manual-lock",
		L"lock=" .. name .. L" @ " .. towstring(clampHealthPercent(health)) .. L"%; duration=" .. towstring(duration) .. L"s" .. getTraceContextSuffix()
	)
end

local function isManualOverrideActive()
	return WarTriage.ManualOverrideTarget.timeLeft > 0
		and WarTriage.ManualOverrideTarget.name ~= L""
end

local function updateManualOverrideTimer(elapsed)
	if WarTriage.ManualOverrideTarget.timeLeft > 0 then
		WarTriage.ManualOverrideTarget.timeLeft = WarTriage.ManualOverrideTarget.timeLeft - elapsed
		if WarTriage.ManualOverrideTarget.timeLeft <= 0 then
			clearManualOverride("expired")
		end
	end
end

local function clearRezEffectCache(name)
	if name and name ~= L"" then
		WarTriage.RezEffectCache[name] = nil
	end
end

local function cleanupRezEffectCache()
	for name, cache in pairs(WarTriage.RezEffectCache) do
		local pendingActive = cache.pendingUntil and cache.pendingUntil > currentTime
		local blockedActive = cache.blockedUntil and cache.blockedUntil > currentTime
		if not pendingActive and not blockedActive then
			WarTriage.RezEffectCache[name] = nil
		end
	end
end

local function updateRezEffectCache(name, health, rezState)
	if not name or name == L"" then return end
	if health > 0 then
		clearRezEffectCache(name)
		return
	end

	if not rezState or (not rezState.pending and not rezState.blocked) then
		return
	end

	local cache = WarTriage.RezEffectCache[name] or {}
	if rezState.pending then
		local pendingDuration = rezState.pendingDuration or TIME_DELAY
		cache.pendingUntil = math.max(cache.pendingUntil or 0, currentTime + pendingDuration)
	end
	if rezState.blocked then
		local blockedDuration = rezState.blockedDuration or TIME_DELAY
		cache.blockedUntil = math.max(cache.blockedUntil or 0, currentTime + blockedDuration)
	end
	WarTriage.RezEffectCache[name] = cache
end

local function applyCachedRezEffectState(player)
	if player.health > 0 then
		clearRezEffectCache(player.name)
		player.rezPending = false
		player.rezBlocked = false
		return
	end

	local cache = WarTriage.RezEffectCache[player.name]
	if not cache then
		player.rezPending = false
		player.rezBlocked = false
		return
	end

	player.rezPending = cache.pendingUntil and cache.pendingUntil > currentTime or false
	player.rezBlocked = cache.blockedUntil and cache.blockedUntil > currentTime or false

	if not player.rezPending and not player.rezBlocked then
		clearRezEffectCache(player.name)
	end
end

local function detectManualTargetOverride()
	local currentTarget = WarTriage.CurrentFriendlyTarget
	if not WarTriage.Settings.manualOverride then
		clearManualOverride("disabled")
		WarTriage.PreviousFriendlyTarget = currentTarget.name
		return
	end

	if currentTarget.isExplicit
	and currentTarget.name ~= L""
	and currentTarget.name ~= WarTriage.PreviousFriendlyTarget
	and currentTarget.name ~= WarTriage.LastSuggestedTarget
	then
		startManualOverride(currentTarget.name, currentTarget.health)
	end

	WarTriage.PreviousFriendlyTarget = currentTarget.name
end

function WarTriage.OnUpdate(elapsed)
	if not isAddonActive() then
		return
	end

	currentTime = currentTime + elapsed
	cleanupRezEffectCache()
	decayPlayerHealthHistory(elapsed)
	cleanupPlayerHealthHistory()
	updateManualOverrideTimer(elapsed)
	macroWatchdogTimeLeft = macroWatchdogTimeLeft - elapsed
	if macroWatchdogTimeLeft <= 0 then
		macroWatchdogTimeLeft = MACRO_WATCHDOG_INTERVAL
		if WarTriage.Settings.enabled and WarTriage.Settings.isHealer then
			ensureMacroAvailable(WARTRIAGE_MACRO_NAME, WARTRIAGE_MACRO_TEXT, WARTRIAGE_MACRO_ICON)
		end
	end
    timeLeft = timeLeft - elapsed
	if timeLeft > 0 then
        return
    end
    timeLeft = TIME_DELAY

	if WarTriage.Settings.enabled and WarTriage.Settings.isHealer then
		if WarTriage.RefreshState.targetDirty or currentTime >= WarTriage.RefreshState.nextTargetRefreshTime then
			refreshFriendlyTargetState()
		end

		if WarTriage.RefreshState.playersDirty or #WarTriage.Players == 0 or currentTime >= WarTriage.RefreshState.nextPlayersSnapshotTime then
			WarTriage.RefreshPlayersSnapshot()
		end

		if WarTriage.RefreshState.transientDirty or currentTime >= WarTriage.RefreshState.nextTransientRefreshTime then
			WarTriage.RefreshPlayersTransientState()
		end

		detectManualTargetOverride()
		if isManualOverrideActive() then
			traceMacroAction(
				"pause-manual-lock",
				{
					name = WarTriage.ManualOverrideTarget.name,
					health = WarTriage.ManualOverrideTarget.health,
					distance = 0,
				},
				"manual-lock"
			)
			return
		end

		WarTriage.TargetPlayer(WarTriage.GetHurtPlayer())
	end
end

function WarTriage.CheckCareer()
	local career = GameData.Player and GameData.Player.career or {}
	local careerLine = career.line or CareerIDsToLines[career.id]
	WarTriage.Settings.isHealer = ArcheType[careerLine] == HEALER
	return WarTriage.Settings.isHealer
end

function WarTriage.Enable()
	if WarTriage.Settings.enabled then
		WarTriage.RefreshMacroButtonAppearance()
		return
	end

	WarTriage.Settings.enabled = true
	WarTriage.RegisterEventHandlers(true)
	if isAddonActive() then
		markAllDirty()
	end
	WarTriage.Print(L"--- <icon57> Enabled")
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.Disable()
	if not WarTriage.Settings.enabled then
		WarTriage.RefreshMacroButtonAppearance()
		return
	end

	WarTriage.Settings.enabled = false
	WarTriage.RegisterEventHandlers(false)
	WarTriage.Print(L"--- <icon58> Enabled")
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.ToggleEnabled()
	if WarTriage.Settings.enabled then
		WarTriage.Disable()
	else
		WarTriage.Enable()
	end
end

function WarTriage.RegisterHotbarEventHandler()
	if hotbarEventRegistered or not WarTriage.Settings.isHealer then
		return
	end

	RegisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "WarTriage.PLAYER_HOT_BAR_UPDATED")
	hotbarEventRegistered = true
end

function WarTriage.UnregisterHotbarEventHandler()
	if not hotbarEventRegistered then
		return
	end

	UnregisterEventHandler(SystemData.Events.PLAYER_HOT_BAR_UPDATED, "WarTriage.PLAYER_HOT_BAR_UPDATED")
	hotbarEventRegistered = false
end

function WarTriage.PLAYER_HOT_BAR_UPDATED()
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.PrintSettings()
	WarTriage.Print("<icon20087> v" .. formatVersion(WarTriage.Settings.version) .. " settings: /wt")
	if WarTriage.Settings.enabled then
		WarTriage.Print(L"--- <icon57> Enabled (Ctrl+click macro to toggle)")
	else
		WarTriage.Print(L"--- <icon58> Enabled (Ctrl+click macro to toggle)")
	end

	if WarTriage.Settings.losCheck then
		WarTriage.Print(L"--- <icon57> Check LOS")
	else
		WarTriage.Print(L"--- <icon58> Check LOS")
	end

	if WarTriage.Settings.rangeCheck then
		WarTriage.Print(L"--- <icon57> Check Range")
	else
		WarTriage.Print(L"--- <icon58> Check Range")
	end

	if WarTriage.Settings.ownPartyOnly then
		WarTriage.Print(L"--- <icon57> Own Party Only")
	else
		WarTriage.Print(L"--- <icon58> Own Party Only")
	end

	if WarTriage.Settings.ignoreDead then
		WarTriage.Print(L"--- <icon57> Ignore Dead")
	else
		WarTriage.Print(L"--- <icon58> Ignore Dead")
	end

	if WarTriage.Settings.ignoreIgnoredPlayers then
		WarTriage.Print(L"--- <icon57> Skip Ignored Players")
	else
		WarTriage.Print(L"--- <icon58> Skip Ignored Players")
	end

	if WarTriage.Settings.favorFriends then
		WarTriage.Print(L"--- <icon57> Favor Friends (25% HP Bias)")
	else
		WarTriage.Print(L"--- <icon58> Favor Friends (25% HP Bias)")
	end

	if WarTriage.Settings.glowEffects then
		WarTriage.Print(L"--- <icon57> Glow Effects")
	else
		WarTriage.Print(L"--- <icon58> Glow Effects")
	end

	if WarTriage.Settings.manualOverride then
		WarTriage.Print("--- <icon57> Manual Lock: " .. tostring(WarTriage.Settings.manualOverrideDuration) .. "s")
	else
		WarTriage.Print(L"--- <icon58> Manual Lock")
	end

	if WarTriage.Settings.autoTargetOwnParty then
		WarTriage.Print(L"--- <icon57> Auto-Target Self / Own Party")
	else
		WarTriage.Print(L"--- <icon58> Auto-Target Self / Own Party")
	end

	WarTriage.Print("--- Hurt threshold: " .. tostring(WarTriage.Settings.hurtThreshold) .. "%")
	WarTriage.Print("--- Rez safety threshold: " .. tostring(WarTriage.Settings.rezSafetyThreshold) .. "%")
	WarTriage.Print("--- Rank crossover: " .. tostring(WarTriage.Settings.rankCrossover))
	WarTriage.Print("--- Priority ranks (1 = heal first when similarly hurt):")
	WarTriage.Print("------ Self: " .. tostring(WarTriage.Settings.prioSelf))
	WarTriage.Print("------ Healer: " .. tostring(WarTriage.Settings.prioHealer))
	WarTriage.Print("------ Ranged DPS: " .. tostring(WarTriage.Settings.prioRangedDps))
	WarTriage.Print("------ Melee DPS: " .. tostring(WarTriage.Settings.prioMeleeDps))
	WarTriage.Print("------ Tank: " .. tostring(WarTriage.Settings.prioTank))

end

-- Debug: Print effect IDs on current friendly target and on self
function WarTriage.PrintTargetEffects()
	local function sayW(str)
		WarTriage.Print(str)
	end
	local function dumpBuffs(title, targetType)
		sayW(title)
		local buffs = GetBuffs(targetType)
		if not buffs or next(buffs) == nil then
			sayW("  (none)")
			return
		end
		for _, b in pairs(buffs) do
			local id = b.abilityId or 0
			local name = b.name or L""
			local remaining = getBuffRemainingSeconds(b)
			local suffix = ""
			if remaining then
				suffix = " (" .. string.format("%.1fs", remaining) .. " remaining)"
			end
			WarTriage.Print(towstring("  * [" .. tostring(id) .. "] ") .. name .. towstring(suffix))
		end
	end

	dumpBuffs("Friendly Target Effects:", GameData.BuffTargetType.TARGET_FRIENDLY)
	dumpBuffs("Self Effects:", GameData.BuffTargetType.SELF)
end

function WarTriage.GetFriendlyTarget()
	TargetInfo:UpdateFromClient()
	local target = TargetInfo.m_Units[TargetInfo.FRIENDLY_TARGET]
	if target and not target.isNPC and target.name ~= L"" then
		WarTriage.CurrentFriendlyTarget.name = fixString(target.name)
		WarTriage.CurrentFriendlyTarget.health = clampHealthPercent(target.healthPercent)
		WarTriage.CurrentFriendlyTarget.isExplicit = true
		return WarTriage.CurrentFriendlyTarget.name
	elseif target and target.entityid == 0 then -- Treat no target as self target
		WarTriage.CurrentFriendlyTarget.name = fixString(LOCAL_PLAYER_NAME)
		WarTriage.CurrentFriendlyTarget.health = getLocalPlayerHealthPercent("friendly-target-fallback")
		WarTriage.CurrentFriendlyTarget.isExplicit = false
		return fixString(LOCAL_PLAYER_NAME)
	else
		WarTriage.CurrentFriendlyTarget.name = L""
		WarTriage.CurrentFriendlyTarget.health = 0
		WarTriage.CurrentFriendlyTarget.isExplicit = false
		return L""
	end
end

-- Event handlers
function WarTriage.LOADING_END()
	installMacroTooltipHook()
	installActionButtonHooks()
	WarTriage.CheckCareer()
	if WarTriage.Settings.isHealer then
		WarTriage.RegisterHotbarEventHandler()
	else
		WarTriage.UnregisterHotbarEventHandler()
	end
	WarTriage.RegisterEventHandlers(WarTriage.Settings.enabled)
	if isAddonActive() then
		markAllDirty()
	else
		resetRuntimeState()
	end
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.PLAYER_TARGET_UPDATED()
	refreshFriendlyTargetState()
	if WarTriage.CurrentFriendlyTarget.name == WarTriage.AutoTargetState.pendingName then
		WarTriage.AutoTargetState.pendingName = L""
		WarTriage.AutoTargetState.nextAllowedTime = 0
	end
	detectManualTargetOverride()
	WarTriage.RefreshState.transientDirty = true
end

function WarTriage.PLAYER_CUR_HIT_POINTS_UPDATED()
	markPlayersDirty()
end

function WarTriage.GROUP_UPDATED()
	markPlayersDirty()
end

function WarTriage.GROUP_STATUS_UPDATED()
	markPlayersDirty()
end

function WarTriage.SCENARIO_GROUP_UPDATED()
	markPlayersDirty()
end

function WarTriage.SCENARIO_PLAYER_HITS_UPDATED()
	markPlayersDirty()
end

function WarTriage.BATTLEGROUP_UPDATED()
	markPlayersDirty()
end

function WarTriage.BATTLEGROUP_MEMBER_UPDATED()
	markPlayersDirty()
end

-- Creates or updates the WarTriage Macro
function WarTriage.UpdateMacro(macroName, macroText, macroIcon)
	local macros = GetMacrosData()
	local macroSlot = nil
	
	-- Check for existing macro or free macro slot
	for i = 1, #macros do
		-- Macro exists?
		if macros[i].name == towstring(macroName) then
			macroSlot = i
			break
		-- Find first free slot
		elseif macros[i].iconNum == 0 and macroSlot == nil then
			macroSlot = i
		end
	end

	-- Update Macro
	if macroSlot ~= nil then 
		SetMacroData(towstring(macroName), towstring(macroText), macroIcon, macroSlot)
		WarTriage.Settings.macroCreated = true
		WarTriage.MacroWarningState.full = false
		return true
	else
		WarTriage.Settings.macroCreated = false
		if not WarTriage.MacroWarningState.full then
			WarTriage.Print("<icon20087> Could not create macro because all macro slots are full.")
			WarTriage.MacroWarningState.full = true
		end
		return false
	end
end

local function getOwnPartyTargetEvents()
	local ownPartyTargetEvents = {
		[fixString(LOCAL_PLAYER_NAME)] = SystemData.Events.TARGET_SELF,
	}

	if IsWarBandActive and IsWarBandActive() and PartyUtils.IsPlayerInWarband and PartyUtils.GetWarbandParty then
		local partyIndex = PartyUtils.IsPlayerInWarband(fixString(LOCAL_PLAYER_NAME))
		local warbandParty = partyIndex and PartyUtils.GetWarbandParty(partyIndex)
		local partyPlayers = warbandParty and warbandParty.players or {}
		for index, member in ipairs(partyPlayers) do
			local memberName = fixString(member and member.name)
			if memberName and memberName ~= L"" and PartyTargetEvent[index] then
				if memberName == fixString(LOCAL_PLAYER_NAME) then
					ownPartyTargetEvents[memberName] = SystemData.Events.TARGET_SELF
				else
					ownPartyTargetEvents[memberName] = PartyTargetEvent[index]
				end
			end
		end
	else
		local partyData = PartyUtils.GetPartyData and PartyUtils.GetPartyData() or {}
		for index, member in ipairs(partyData) do
			local memberName = fixString(member and member.name)
			if memberName and memberName ~= L"" and PartyTargetEvent[index] then
				ownPartyTargetEvents[memberName] = PartyTargetEvent[index]
			end
		end
	end

	return ownPartyTargetEvents
end

local function getOwnPartyMembers()
	local ownPartyTargetEvents = getOwnPartyTargetEvents()
	local ownPartyMembers = {
		[fixString(LOCAL_PLAYER_NAME)] = true,
	}
	for memberName in pairs(ownPartyTargetEvents) do
		if memberName and memberName ~= L"" then
			ownPartyMembers[memberName] = true
		end
	end
	return ownPartyMembers, ownPartyTargetEvents
end

local function shouldIgnoreHealthMerge(name, sourceName)
	return name == WarTriage.Player.name and sourceName == "scenario"
end

local function pushFriendlyPlayer(playersByName, ownPartyMembers, ownPartyTargetEvents, name, health, archeType, sourceName)
	name = fixString(name)
	if not name or name == L"" then return end

	local inMyParty = ownPartyMembers[name] == true
	local targetEvent = ownPartyTargetEvents[name]
	local player = playersByName[name]
	if not player then
		playersByName[name] = {
			name = name,
			health = clampHealthPercent(health),
			archeType = archeType,
			inMyParty = inMyParty,
			targetEvent = targetEvent,
			lastSource = sourceName,
		}
		if name == WarTriage.Player.name and sourceName ~= "self" then
			appendTrace(
				"self-from-source",
				toWString(sourceName or "unknown") .. L" inserted self at " .. towstring(clampHealthPercent(health)) .. L"%." .. getTraceContextSuffix()
			)
		end
		return
	end

	local normalizedHealth = clampHealthPercent(health)
	if normalizedHealth < player.health then
		if name == WarTriage.Player.name then
			appendTrace(
				"self-health-lowered",
				toWString(sourceName or "unknown")
				.. L" lowered self from "
				.. towstring(player.health)
				.. L"% to "
				.. towstring(normalizedHealth)
				.. L"%."
				.. getTraceContextSuffix()
			)
		end
		if not shouldIgnoreHealthMerge(name, sourceName) then
			player.health = normalizedHealth
			player.lastSource = sourceName
		end
	end
	if not player.archeType and archeType then
		player.archeType = archeType
	end
	if inMyParty then
		player.inMyParty = true
	end
	if targetEvent then
		player.targetEvent = targetEvent
	end
end

-- Get all players in party, warband or scenario using stock client APIs.
function WarTriage.BuildFriendlyPlayersSnapshot()
	local players = {}
	local playersByName = {}
	local ownPartyMembers, ownPartyTargetEvents = getOwnPartyMembers()
	WarTriage.OwnPartyTargetEvents = ownPartyTargetEvents

	WarTriage.Player.name = fixString(LOCAL_PLAYER_NAME)
	WarTriage.Player.health = getLocalPlayerHealthPercent("snapshot")
	WarTriage.Player.archeType = ArcheType[GameData.Player.career.line]
	WarTriage.Player.inMyParty = true
	WarTriage.Player.targetEvent = ownPartyTargetEvents[WarTriage.Player.name]
	pushFriendlyPlayer(playersByName, ownPartyMembers, ownPartyTargetEvents, WarTriage.Player.name, WarTriage.Player.health, WarTriage.Player.archeType, "self")

	if (GameData.Player.isInScenario or GameData.Player.isInSiege) and GameData.GetScenarioPlayerGroups then
		local scenarioPlayers = GameData.GetScenarioPlayerGroups() or {}
		for _, playerData in ipairs(scenarioPlayers) do
			pushFriendlyPlayer(
				playersByName,
				ownPartyMembers,
				ownPartyTargetEvents,
				playerData.name,
				playerData.health,
				ArcheType[CareerIDsToLines[playerData.careerId]],
				"scenario"
			)
		end
	elseif IsWarBandActive and IsWarBandActive() then
		local warbandData = PartyUtils.GetWarbandData() or {}
		for _, groupData in ipairs(warbandData) do
			for _, playerData in ipairs(groupData.players or {}) do
				pushFriendlyPlayer(
					playersByName,
					ownPartyMembers,
					ownPartyTargetEvents,
					playerData.name,
					playerData.healthPercent,
					ArcheType[playerData.careerLine],
					"warband"
				)
			end
		end
	else
		local partyData = PartyUtils.GetPartyData() or {}
		for _, playerData in ipairs(partyData) do
			pushFriendlyPlayer(
				playersByName,
				ownPartyMembers,
				ownPartyTargetEvents,
				playerData.name,
				playerData.healthPercent,
				ArcheType[playerData.careerLine],
				"party"
			)
		end
	end

	local mergedSelf = playersByName[WarTriage.Player.name]
	if mergedSelf and mergedSelf.health ~= WarTriage.Player.health then
		appendTrace(
			"self-health-mismatch",
			L"Snapshot direct self HP is "
			.. towstring(WarTriage.Player.health)
			.. L"%, but merged self HP is "
			.. towstring(mergedSelf.health)
			.. L"% from "
			.. toWString(mergedSelf.lastSource or "unknown")
			.. L"."
			.. getTraceContextSuffix()
		)
	end

	for _, player in pairs(playersByName) do
		updatePlayerHealthHistory(player)
		players[#players + 1] = player
	end
	cleanupPlayerHealthHistory(players)

	return players
end

function WarTriage.RefreshPlayersSnapshot()
	WarTriage.Players = WarTriage.BuildFriendlyPlayersSnapshot()
	WarTriage.RefreshState.playersDirty = false
	WarTriage.RefreshState.transientDirty = true
	WarTriage.RefreshState.nextPlayersSnapshotTime = currentTime + SNAPSHOT_FALLBACK_INTERVAL
	return WarTriage.Players
end

function WarTriage.RefreshPlayersTransientState()
	local players = WarTriage.Players or {}
	if #players == 0 then
		WarTriage.PlayerDistances = {}
		WarTriage.RefreshState.transientDirty = false
		WarTriage.RefreshState.nextTransientRefreshTime = currentTime + TRANSIENT_REFRESH_INTERVAL
		return players
	end

	players = WarTriage.SetPlayersDistance(players)
	players = WarTriage.SetPlayersLOS(players)
	sortTrackedPlayers(players)
	WarTriage.Players = players
	WarTriage.RefreshState.transientDirty = false
	WarTriage.RefreshState.nextTransientRefreshTime = currentTime + TRANSIENT_REFRESH_INTERVAL
	return players
end

function WarTriage.GetFriendlyPlayers()
	local players = WarTriage.BuildFriendlyPlayersSnapshot()
	players = WarTriage.SetPlayersDistance(players)
	players = WarTriage.SetPlayersLOS(players)
	sortTrackedPlayers(players)

	return players
end

-- Set the distance so we don't target a player that is out of range
function WarTriage.SetPlayersDistance(players)
	local defaultDistance = 999999
	local players = players
	local playerDistances = {}
	
	-- build table of player distances
	for i = 1, MAX_MAP_POINTS do
		local mpd = GetMapPointData("EA_Window_OverheadMapMapDisplay", i)
		if mpd and MapPointTypeFilter[mpd.pointType] and mpd.name then
			local dist = mpd.distance or defaultDistance
			playerDistances[fixString(mpd.name)] = mathFloor(dist * DISTANCE_FIX_COEFFICIENT)
		end
	end
	
	-- look up and set distances
	for i = 1, #players do
		if WarTriage.Settings.rangeCheck then
			players[i].distance = playerDistances[players[i].name] or defaultDistance
		else
			players[i].distance = 0
		end
	end

	WarTriage.PlayerDistances = playerDistances

	return players	
end

-- Limited LOS check.
-- If a targeted player is out of LOS it will not be selected on the next macro click (but maybe on the click after)
function WarTriage.SetPlayersLOS(players)
	local players = players
	local checkAbilityID = LosCheckAbiliyId[GameData.Player.career.line]

	local target = WarTriage.PlayerTarget
	
	if target == L"" then
		target = WarTriage.Player.name -- no friendly target, target is self.
	end
	
	for i = 1, #players do
		if target == players[i].name and WarTriage.Settings.losCheck then
			if players[i].health > 0 then
				players[i].hasLOS = IsTargetValid(checkAbilityID.healID)
			else
				players[i].hasLOS = IsAbilityEnabled(checkAbilityID.ressID) and IsTargetValid(checkAbilityID.ressID)
			end
		else
			players[i].hasLOS = true -- assume we have LOS until we target the player and know for certain.
		end

		if target == players[i].name and players[i].health == 0 then
			updateRezEffectCache(players[i].name, players[i].health, getFriendlyTargetRezState())
		end

		applyCachedRezEffectState(players[i])
	end
	return players
end

local function isBetterSelectionCandidate(candidate, current, candidateEffectiveHealth, currentEffectiveHealth)
	if not candidate then return false end
	if not current then return true end

	local candidateScore = getPlayerSelectionScore(candidate, candidateEffectiveHealth)
	local currentScore = getPlayerSelectionScore(current, currentEffectiveHealth)
	if candidateScore > currentScore then
		return true
	elseif candidateScore == currentScore and candidate.health < current.health then
		return true
	elseif candidateScore == currentScore and candidate.health == current.health and candidate.distance < current.distance then
		return true
	end
	return false
end

local function isValidLivingTarget(player, effectiveHealth)
	effectiveHealth = clampHealthPercent(effectiveHealth or player.health)
	local hurtThreshold = clampHealthPercent(WarTriage.Settings.hurtThreshold or 100)

	return player.hasLOS
		and player.distance < MAX_HEAL_DISTANCE
		and effectiveHealth > 0
		and effectiveHealth < hurtThreshold
end

local function isValidDeadTarget(player, terrorActive, resOnCooldown)
	if WarTriage.Settings.ignoreDead or terrorActive then
		return false
	end

	if not player.hasLOS or player.distance >= MAX_RESS_DISTANCE or player.health > 0 then
		return false
	end

	if resOnCooldown or player.rezPending or player.rezBlocked then
		return false
	end

	return true
end

-- Main function to select which player will be targeted when clicking the macro
function WarTriage.GetHurtPlayer()
	local players = WarTriage.Players
	local emptyPlayer = {
		name = L"",
		health = 100,
		distance = 999999,
		inMyParty = false
	}

	local bestLiving = nil
	local bestLivingHealth = nil
	local bestDead = nil
	local bestDeadHealth = nil
	local rezSafetyBlocked = false
	local ignoreList = nil
	local friendsList = nil
	if WarTriage.Settings.ignoreIgnoredPlayers then
		ignoreList = GetIgnoreList()
	end
	if WarTriage.Settings.favorFriends then
		friendsList = GetFriendsList()
	end
    
	-- Check resurrection cooldown via hidden hotbar slot
	local resOnCooldown = false
	local terrorActive = hasTerrorDebuff(GameData.BuffTargetType.SELF)
	local checkAbilityID = LosCheckAbiliyId[GameData.Player.career.line]
	if checkAbilityID and checkAbilityID.ressID then
		resOnCooldown = IsActionOnCooldown(checkAbilityID.ressID)
	end
	
	for i = 1, #players do
		local player = players[i]
		local effectiveHealth = getSelectionHealthWithFriendBias(player, friendsList)
		if not (WarTriage.Settings.ownPartyOnly and not player.inMyParty) then
			if player.name ~= WarTriage.Player.name and isNameOnSocialList(player.name, ignoreList) then
				-- Explicitly skipped by user preference to avoid auto-selecting ignored players.
			elseif isValidDeadTarget(player, terrorActive, resOnCooldown) then
				if isBetterSelectionCandidate(player, bestDead, 0, bestDeadHealth) then
					bestDead = player
					bestDeadHealth = 0
				end
			elseif isValidLivingTarget(player, effectiveHealth) then
				if isBetterSelectionCandidate(player, bestLiving, effectiveHealth, bestLivingHealth) then
					bestLiving = player
					bestLivingHealth = effectiveHealth
				end
			end

			if isScannableLivingPlayer(player) and livingPlayerBlocksRez(player, effectiveHealth) then
				rezSafetyBlocked = true
			end
		end
	end -- end for i = 1, #players do

	if bestLiving then
		traceSelectionDecision(getSelectionRouteName(bestLiving), bestLiving)
		return bestLiving
	end
	if bestDead and not rezSafetyBlocked then
		traceSelectionDecision("dead", bestDead)
		return bestDead
	end
	if bestDead and rezSafetyBlocked then
		traceSelectionDecision("rez-blocked", emptyPlayer)
		return emptyPlayer
	end

	traceSelectionDecision("none", emptyPlayer)

	return emptyPlayer
end

function WarTriage.TargetPlayer(player)
	if player.name ~= L"" then
		WarTriage.LastSuggestedTarget = player.name
	end
	if player.name ~= L"" -- we have a hurt player
	and player.name ~= WarTriage.PlayerTarget -- and it's not already targeted
	then
		if WarTriage.TryAutoTargetOwnParty(player) then
			traceMacroAction("clear-for-auto-target", player, "party-event")
			WarTriage.SetMacroTarget(WARTRIAGE_MACRO_NAME, L"", 0)
		else
			traceMacroAction("set-explicit-target", player, "macro-target")
			WarTriage.SetMacroTarget(WARTRIAGE_MACRO_NAME, player.name, 4 - mathFloor(player.health / 25))
		end
	else
		if player.name == L"" then
			WarTriage.LastSuggestedTarget = L""
			WarTriage.AutoTargetState.pendingName = L""
		end
		traceMacroAction("clear-target", player, player.name == L"" and "no-target" or "already-targeted")
		WarTriage.SetMacroTarget(WARTRIAGE_MACRO_NAME, L"", 0)
	end
end

function WarTriage.TryAutoTargetOwnParty(player)
	if not WarTriage.Settings.autoTargetOwnParty or not player or player.name == L"" then
		return false
	end

	local targetEvent = player.targetEvent or WarTriage.OwnPartyTargetEvents[player.name]
	if not targetEvent then
		return false
	end

	if WarTriage.AutoTargetState.pendingName == player.name and currentTime < WarTriage.AutoTargetState.nextAllowedTime then
		return true
	end

	BroadcastEvent(targetEvent)
	WarTriage.AutoTargetState.pendingName = player.name
	WarTriage.AutoTargetState.nextAllowedTime = currentTime + PARTY_AUTO_TARGET_THROTTLE
	return true
end

-- Macro functions to actually make clicking the macro target a player
function WarTriage.GetMacroSlots(macroId)
	local macroSlots = {}
	for i = 1, #ActionBars.m_Bars do
	   for j = 1, #ActionBars.m_Bars[i].m_Buttons do
		  if ActionBars.m_Bars[i].m_Buttons[j].m_ActionType == GameData.PlayerActions.DO_MACRO then
			 if ActionBars.m_Bars[i].m_Buttons[j].m_ActionId == macroId then
				macroSlots[#macroSlots + 1] = ActionBars.m_Bars[i].m_Buttons[j].m_HotBarSlot
			 end
		  end
	   end
	end
	return macroSlots
end

function WarTriage.GetMacroId(macroName)
	local macros = GetMacrosData()
	macroName = towstring(macroName)
	for i = 1, #macros do
		if macros[i].name == macroName then
			return i
		end
	end
	return nil
end

local function getMacroData(macroName)
	local macros = GetMacrosData()
	local expectedName = towstring(macroName)
	for i = 1, #macros do
		if macros[i].name == expectedName then
			return i, macros[i]
		end
	end
	return nil, nil
end

local function isExpectedMacroText(macroData, expectedText)
	local macroText = macroData.text or macroData.macroText or macroData.body or macroData.command
	if macroText == nil then
		return true
	end
	return macroText == towstring(expectedText)
end

local function isExpectedMacroData(macroData, expectedName, expectedText, expectedIcon)
	return macroData ~= nil
		and macroData.name == towstring(expectedName)
		and macroData.iconNum == expectedIcon
		and isExpectedMacroText(macroData, expectedText)
end

local function repairMacro(macroName, macroText, macroIcon, reason)
	if not WarTriage.UpdateMacro(macroName, macroText, macroIcon) then
		if not WarTriage.MacroWarningState.missing and not WarTriage.MacroWarningState.full then
			WarTriage.Print("<icon20087> Could not find or recreate macro.")
			WarTriage.MacroWarningState.missing = true
		end
		return nil
	end

	local macroId = WarTriage.GetMacroId(macroName)
	if reason == "missing" then
		if not WarTriage.MacroWarningState.missing then
			WarTriage.Print("<icon20087> Macro was missing and has been recreated. Re-add it to your hotbar if needed.")
			WarTriage.MacroWarningState.missing = true
		end
	else
		WarTriage.MacroWarningState.missing = false
		if not WarTriage.MacroWarningState.repaired then
			WarTriage.Print("<icon20087> Macro definition was repaired.")
			WarTriage.MacroWarningState.repaired = true
		end
	end

	return macroId
end

ensureMacroAvailable = function(macroName, macroText, macroIcon)
	local macroId, macroData = getMacroData(macroName)
	if isExpectedMacroData(macroData, macroName, macroText, macroIcon) then
		WarTriage.MacroWarningState.missing = false
		WarTriage.MacroWarningState.repaired = false
		return macroId
	end

	if macroId then
		return repairMacro(macroName, macroText, macroIcon, "invalid")
	end

	return repairMacro(macroName, macroText, macroIcon, "missing")
end

function WarTriage.RefreshMacroButtonAppearance()
	if not ActionBars or not ActionBars.m_Bars or not WarTriage.GetMacroId then
		return
	end

	local macroId = WarTriage.GetMacroId(WARTRIAGE_MACRO_NAME)
	if not macroId then
		return
	end

	local addonActive = isAddonActive()
	local settingsEnabled = WarTriage.Settings and WarTriage.Settings.enabled
	local hasTarget = addonActive and WarTriage.MacroButtonState.hasTarget
	local glowLevel = hasTarget and (WarTriage.MacroButtonState.glowLevel or 0) or 0
	local macroSlots = WarTriage.GetMacroSlots(macroId)

	for i = 1, #macroSlots do
		local hbar, buttonid = ActionBars:BarAndButtonIdFromSlot(macroSlots[i])
		local macroButton = hbar and hbar.m_Buttons and hbar.m_Buttons[buttonid]
		if macroButton then
			setMacroButtonEnabledOverlay(macroButton, settingsEnabled)
			setMacroButtonVisualDisabled(macroButton, not addonActive or not WarTriage.MacroButtonState.hasTarget)

			local effectiveGlowLevel = 0
			if hasTarget and WarTriage.Settings.glowEffects then
				effectiveGlowLevel = mathMax(1, glowLevel)
			end
			WarTriage.SetButtonGlow(macroButton, effectiveGlowLevel)

			if hasTarget and macroButton.m_Name then
				WindowSetGameActionData(
					macroButton.m_Name .. "Action",
					GameData.PlayerActions.SET_TARGET,
					0,
					towstring(WarTriage.MacroButtonState.playerName)
				)
			end
		end
	end
end

function WarTriage.SetMacroTarget(macroName, playerName, glowLevel)
	local macroId = ensureMacroAvailable(macroName, WARTRIAGE_MACRO_TEXT, WARTRIAGE_MACRO_ICON)
	if not macroId then return end

	local hasTarget = playerName ~= nil and playerName ~= L""
	WarTriage.MacroButtonState.playerName = hasTarget and playerName or L""
	WarTriage.MacroButtonState.hasTarget = hasTarget
	WarTriage.MacroButtonState.glowLevel = hasTarget and (glowLevel or 0) or 0

	local macroSlots = WarTriage.GetMacroSlots(macroId)
	if #macroSlots == 0 then
		if not WarTriage.MacroWarningState.unplaced then
			WarTriage.Print("<icon20087> Macro is not on any action bar. Drag it to a hotbar slot to use it.")
			WarTriage.MacroWarningState.unplaced = true
		end
		return
	end

	WarTriage.MacroWarningState.unplaced = false
	WarTriage.RefreshMacroButtonAppearance()
end

function WarTriage.SetButtonGlow(button, glowLevel)
	local glowFrame = getButtonGlowFrame(button)
	if not glowFrame then return end

	if not isAddonActive() or not WarTriage.Settings.glowEffects or glowLevel == 0 then
		glowFrame:StopAnimation (true)
	elseif WarTriage.Settings.glowEffects and glowLevel > 0 and glowLevel < 5 then
		glowFrame:StopAnimation (true)
		glowFrame:SetAnimationTexture ("anim_fury_" .. glowLevel)
		glowFrame:StartAnimation (0, true, false, 0)
	end
end

local function isWarTriageMacroButton(button)
	if not button or button.m_ActionType ~= GameData.PlayerActions.DO_MACRO then
		return false
	end

	local macroId = WarTriage.GetMacroId and WarTriage.GetMacroId(WARTRIAGE_MACRO_NAME)
	return macroId ~= nil and button.m_ActionId == macroId
end

function installActionButtonHooks()
	if actionButtonHooksInstalled or not ActionButton then
		return
	end

	local orgActionButtonOnLButtonDown = ActionButton.OnLButtonDown
	function ActionButton.OnLButtonDown(self, flags, x, y)
		if isWarTriageMacroButton(self) and flags == SystemData.ButtonFlags.CONTROL then
			WarTriage.ToggleEnabled()
		end
		orgActionButtonOnLButtonDown(self, flags, x, y)
	end

	local orgActionButtonUpdateInventory = ActionButton.UpdateInventory
	function ActionButton.UpdateInventory(self)
		if isWarTriageMacroButton(self) then
			WarTriage.RefreshMacroButtonAppearance()
			return
		end
		orgActionButtonUpdateInventory(self)
	end

	local orgActionButtonUpdateBurning = ActionButton.UpdateBurning
	function ActionButton.UpdateBurning(self, previousResource, currentResource)
		if isWarTriageMacroButton(self) then
			return
		end
		orgActionButtonUpdateBurning(self, previousResource, currentResource)
	end

	actionButtonHooksInstalled = true
end
