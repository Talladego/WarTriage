<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	<UiMod name="WarTriage" version="2.02" date="2026-07-11" >
		<Author name="Talladego" email="" />
		<Description text="WarTriage" />
		<VersionSettings gameVersion="1.4.8" windowsVersion="1.0" savedVariablesVersion="1.0" />

		<Dependencies>
			<Dependency name="EA_ActionBars" />
			<Dependency name="EASystem_Utils" />
			<Dependency name="EASystem_TargetInfo" />
			<Dependency name="LibSlash" />
		</Dependencies>
			
		<Files>
			<File name="libs\LibStub.lua" />
			<File name="libs\LibGUI.lua" />
			<File name="libs\LibConfig.lua" />		
			<File name="WarTriage.lua" />
			<File name="WarTriage_Config.lua" />
		</Files>

		<SavedVariables>
			<SavedVariable name="WarTriage.Settings" />
		</SavedVariables>

		<OnInitialize>
			<CallFunction name="WarTriage.Initialize" />
		</OnInitialize>

		<OnUpdate>
			<CallFunction name="WarTriage.OnUpdate" />
		</OnUpdate>

		<OnShutdown>
			<CallFunction name="WarTriage.OnShutdown" />
		</OnShutdown>

	</UiMod>
</ModuleFile>
