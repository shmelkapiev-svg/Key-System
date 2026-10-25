--[[
    Config v1.2.lua
    New loader/config file. This does NOT replace any existing version.
    Edit these settings, then run this file.
    The settings table remains compatible with the audited key-system script.

    Do not put Luarmor API keys, tokens, or other secrets here.
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

    -- Leave empty to use the built-in labels for Language.
    -- Optional overrides: GetKey = "...", CheckKey = "...", Discord = "..."
    Buttons = {},

    -- Links
    AdRewardsUrl = "", -- paste your real Luarmor Ad Rewards URL here
    DiscordUrl = "", -- paste your real Discord invite here
    ShowDiscordButton = true,

    -- Luarmor
    ScriptId = "YOUR_LUARMOR_SCRIPT_ID", -- replace with your actual Luarmor Script ID

    -- Behaviour
    DetailedErrors = false,
    CheckTimeout = 20, -- seconds; accepted range in this build is 5..120
}

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/shmelkapiev-svg/Key-System/refs/heads/main/System/Kmv1.2.lua"
))()
