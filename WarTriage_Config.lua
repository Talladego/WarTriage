LibConfig = LibStub("LibConfig")

WarTriage_Config = {}

local GUI
local CONFIG_WINDOW_WIDTH = 860
local CONFIG_WINDOW_HEIGHT = 620
local CONFIG_WINDOW_TITLE = "<icon20087> WarTriage v"

local MIN_RANK_CROSSOVER = 5
local MAX_RANK_CROSSOVER = 30
local DEFAULT_RANK_CROSSOVER = 15
local DEFAULT_REZ_SAFETY_THRESHOLD = 90

-- LibConfig.MinMax errors on nil from tonumber(""); keep last/default instead.
local function clampConfigNumber(minVal, maxVal, fallback)
	return function(value)
		local number = tonumber(value)
		if number == nil then
			return fallback
		end
		if number < minVal then
			return minVal
		end
		if number > maxVal then
			return maxVal
		end
		return number
	end
end

local function trimInput(input)
	if input == nil then return "" end
	local normalized = tostring(input)
	normalized = string.gsub(normalized, "^%s+", "")
	normalized = string.gsub(normalized, "%s+$", "")
	return normalized
end

local function getInfoTabText()
	return table.concat({
		"WarTriage helps healers decide who to target next, reducing target switching without replacing judgement.",
		"",
		"It creates a macro for your hotbar. Clicking it targets the player most in need of heals.",
		"Auto-Target Self / Own Party optionally uses direct target events for yourself and party members, which can remove the need for the macro during normal party play.",
		"",
		"The macro icon glows when a new player needs attention. Lower health produces a stronger glow level.",
		"Ctrl+click the WarTriage macro on your hotbar to enable or disable the addon.",
		"",
		"Only players within healing range are considered, and a limited line-of-sight check is performed.",
		"Direct auto-targeting does not apply to non-party warband or scenario players; those still use the macro path.",
		"",
		"The Settings tab enables or disables features. The Priorities tab sets role ranks (1 = heal first when similarly hurt), hurt threshold, rez safety threshold, and rank crossover."
	}, "\n")
end

local function resizeConfigWindow(gui, width, height)
	gui.width = width
	gui.height = height
	gui.window:Resize(width, height)
	gui.window.titleText:Resize(width)

	if gui.window.tabDownButton then
		gui.window.tabDownButton:AnchorTo(gui.window, "bottomleft", "bottomleft", 20, -70)
	end
end

local function copySettingsTable(source, destination)
	for key in pairs(destination) do
		if source[key] == nil then
			destination[key] = nil
		end
	end

	for key, value in pairs(source) do
		if type(value) == "table" then
			local target = destination[key]
			if type(target) ~= "table" then
				target = {}
				destination[key] = target
			end
			copySettingsTable(value, target)
		else
			destination[key] = value
		end
	end
end

function WarTriage_Config.ResetToDefaults()
	if not WarTriage.Settings then
		WarTriage.Settings = {}
	end

	copySettingsTable(WarTriage.DefaultSettings, WarTriage.Settings)
	WarTriage.CheckCareer()
	WarTriage.RegisterEventHandlers(WarTriage.Settings.enabled)
	WarTriage.RefreshMacroButtonAppearance()

	if WarTriage.RefreshState then
		WarTriage.RefreshState.playersDirty = true
		WarTriage.RefreshState.transientDirty = true
		WarTriage.RefreshState.targetDirty = true
		WarTriage.RefreshState.nextPlayersSnapshotTime = 0
		WarTriage.RefreshState.nextTransientRefreshTime = 0
		WarTriage.RefreshState.nextTargetRefreshTime = 0
	end

	if GUI then
		GUI:Reset()
	end

	WarTriage.Print("Settings reset to defaults.")
end

local function priorityRankFromCombo(value)
	if type(value) == "wstring" then
		value = tonumber(WStringToString(value))
	else
		value = tonumber(value)
	end
	return math.min(math.max(value or 1, 1), 5)
end

local function addPriorityRankCombo(labelText, settingsKey)
	local element = GUI("combobox", labelText, settingsKey, priorityRankFromCombo)
	element.label:Font("font_default_text_small")
	element.label:Align("left")
	element.combo:AnchorTo(element.label, "right", "right")
	for rank = 1, 5 do
		element.combo:Add(rank)
	end
	return element
end

local function createInfoTab()
	GUI:AddTab("Info")

	local infoLayer = GUI.layers[#GUI.layers]
	local infoBox = infoLayer("multitextbox")
	infoBox:AnchorTo(infoLayer, "topleft", "topleft", 10, 10)
	infoBox:Resize(infoLayer.width - 20, infoLayer.height - 20)
	infoBox:SetText(getInfoTabText())
	TextEditBoxSetTextColor(infoBox.name, 230, 230, 230)
	infoBox:IgnoreInput()
end

function WarTriage_Config.Slash(input)
	local trimmedInput = trimInput(input)
	local command = string.lower(trimmedInput)
	if command == "help" then
		WarTriage.PrintSlashHelp()
		return
	elseif command == "settings" or command == "status" or command == "info" then
		WarTriage.PrintSettings()
		return
	elseif command == "toggle" then
		WarTriage.ToggleEnabled()
		return
	elseif command == "buffs" then
		WarTriage.PrintTargetEffects()
		return
	elseif command == "trace" or string.find(command, "^trace%s+") then
		local traceAction = string.lower(trimInput(string.gsub(trimmedInput, "^trace", "", 1)))
		if traceAction == "" or traceAction == "status" then
			if WarTriage.Settings.traceLogging then
				local count = WarTriage.TraceState and WarTriage.TraceState.entries and #WarTriage.TraceState.entries or 0
				WarTriage.Print("Trace logging is enabled (in-memory, " .. tostring(count) .. " entries).")
			else
				WarTriage.Print("Trace logging is disabled.")
			end
		elseif traceAction == "on" then
			WarTriage.SetTraceLoggingEnabled(true)
		elseif traceAction == "off" then
			WarTriage.SetTraceLoggingEnabled(false)
		elseif traceAction == "dump" then
			WarTriage.DumpTraceLog()
		elseif traceAction == "clear" then
			WarTriage.ClearTraceLog()
		else
			WarTriage.Print("Usage: /wt trace on|off|status|dump|clear")
		end
		return
	end

	if (not GUI) then
		-- parameters: title text, settings table, callback-function
		-- note that you need to have a settings table!
		GUI = LibConfig(CONFIG_WINDOW_TITLE .. string.format("%.2f", tonumber(WarTriage.Settings.version) or 0), WarTriage.Settings, true, WarTriage_Config.SettingsChanged)
		resizeConfigWindow(GUI, CONFIG_WINDOW_WIDTH, CONFIG_WINDOW_HEIGHT)

		GUI.window.resetDefaultsButton = GUI.window("button")
		GUI.window.resetDefaultsButton:Resize(140)
		GUI.window.resetDefaultsButton:AnchorTo(GUI.window, "bottomleft", "bottomleft", 20, -12)
		GUI.window.resetDefaultsButton:SetText("Reset Defaults")
		GUI.window.resetDefaultsButton.OnLButtonUp = WarTriage_Config.ResetToDefaults

		createInfoTab()

		GUI:AddTab("Settings")
		local textbox
		GUI("checkbox", "Enabled", "enabled")
		GUI("checkbox", "Check Line-of-Sight", "losCheck")
		GUI("checkbox", "Check Range", "rangeCheck")
		GUI("checkbox", "Own Party Only", "ownPartyOnly")
		GUI("checkbox", "Ignore Dead", "ignoreDead")
		GUI("checkbox", "Skip Ignored Players", "ignoreIgnoredPlayers")
		GUI("checkbox", "Favor Friends (25% HP Bias)", "favorFriends")
		GUI("checkbox", "Glow Effects", "glowEffects")
		GUI("checkbox", "Auto-Target Self / Own Party", "autoTargetOwnParty")
		GUI("checkbox", "Manual Target Lock", "manualOverride")

		local settings = WarTriage.Settings
		textbox = GUI(
			"textbox",
			"Manual lock duration (seconds):",
			"manualOverrideDuration",
			clampConfigNumber(0, 600, tonumber(settings.manualOverrideDuration) or 4)
		)
		textbox.label:Font("font_default_text_small")
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right")
		textbox.edit:Resize(50)

		GUI:AddTab("Priorities")
		textbox = GUI(
			"textbox",
			"Only target players below this health %:",
			"hurtThreshold",
			clampConfigNumber(1, 100, tonumber(settings.hurtThreshold) or 100)
		)
		textbox.label:Font("font_default_text_small")
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right")
		textbox.edit:Resize(50)

		textbox = GUI(
			"textbox",
			"Rez safety threshold (%):",
			"rezSafetyThreshold",
			clampConfigNumber(0, 100, tonumber(settings.rezSafetyThreshold) or DEFAULT_REZ_SAFETY_THRESHOLD)
		)
		textbox.label:Font("font_default_text_small")
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right")
		textbox.edit:Resize(50)

		textbox = GUI(
			"textbox",
			"Rank crossover (urgency points per rank step):",
			"rankCrossover",
			clampConfigNumber(MIN_RANK_CROSSOVER, MAX_RANK_CROSSOVER, tonumber(settings.rankCrossover) or DEFAULT_RANK_CROSSOVER)
		)
		textbox.label:Font("font_default_text_small")
		textbox.label:Align("left")
		textbox.edit:AnchorTo(textbox.label, "right", "right")
		textbox.edit:Resize(50)

		addPriorityRankCombo("Self priority rank (lower = higher):", "prioSelf")
		addPriorityRankCombo("Healer priority rank:", "prioHealer")
		addPriorityRankCombo("Ranged DPS priority rank:", "prioRangedDps")
		addPriorityRankCombo("Melee DPS priority rank:", "prioMeleeDps")
		addPriorityRankCombo("Tank priority rank:", "prioTank")
	end
	GUI:Show()
end

function WarTriage_Config.SettingsChanged()
	GUI:Hide()
	if WarTriage.NormalizeSettings then
		WarTriage.NormalizeSettings()
	end
	WarTriage.CheckCareer()
	WarTriage.RegisterEventHandlers(WarTriage.Settings.enabled)
	if WarTriage.RefreshState then
		WarTriage.RefreshState.playersDirty = true
		WarTriage.RefreshState.transientDirty = true
		WarTriage.RefreshState.targetDirty = true
		WarTriage.RefreshState.nextPlayersSnapshotTime = 0
		WarTriage.RefreshState.nextTransientRefreshTime = 0
		WarTriage.RefreshState.nextTargetRefreshTime = 0
	end
	WarTriage.RefreshMacroButtonAppearance()
	WarTriage.PrintSettings()
end