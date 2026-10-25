--[[
    Config.lua  (Script 2 - config + loader)
    Edit the values below, then run this script.
    It sets getgenv().KeySystemConfig and loads KeySystem.lua (Script 1).

    No secrets here: never put your Luarmor API key or ad-provider tokens in this file.
]]

getgenv().KeySystemConfig = {
	-- Look
	Title = "My Script | Key System",
	Language = "en", -- "en" | "ru"
	Accent = Color3.fromRGB(88, 130, 255),
	Theme = {
		Background = Color3.fromRGB(14, 14, 16),
		Panel = Color3.fromRGB(24, 24, 28),
		Input = Color3.fromRGB(32, 32, 38),
		Text = Color3.fromRGB(235, 235, 240),
		Muted = Color3.fromRGB(140, 140, 150),
		Success = Color3.fromRGB(80, 200, 120),
		Error = Color3.fromRGB(235, 80, 80),
		AccentText = Color3.fromRGB(255, 255, 255),
	},

	-- Button labels
	Buttons = {
		GetKey = "Get Key",
		CheckKey = "Check Key",
		Discord = "Copy Discord",
	},

	-- Links
	AdRewardsUrl = "Example", -- <- paste your Luarmor Ad Rewards link (https://ads.luarmor.net/...)
	DiscordUrl = "https://discord.gg/example",
	ShowDiscordButton = true,

	-- Luarmor
	ScriptId = "YOUR_LUARMOR_SCRIPT_ID", -- <- your script ID (not a secret)

	-- Behaviour
	DetailedErrors = false, -- true = append the Luarmor status code to error messages
}

-- Load the key checker (Script 1). Replace the URL with where you host KeySystem.lua
-- (e.g. a GitHub raw link).
loadstring(game:HttpGet("https://raw.githubusercontent.com/shmelkapiev-svg/Key-System/refs/heads/main/key%20system%20v1.0.lua?token=GHSAT0AAAAAAEMWG63HHKPYIO5OOOZFZ4QC2W5XSMA"))()
