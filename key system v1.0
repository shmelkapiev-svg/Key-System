--[[
    KeySystem.lua  (Script 1 - main key checker)
    Key GUI + Luarmor key check. Mobile-friendly, dark theme.

    Reads settings from getgenv().KeySystemConfig (see Config.lua).
    Every setting has a default, so this file also runs on its own.

    Flow:  GUI -> Luarmor check_key -> only on "KEY_VALID" -> script_key + load_script()
    Nothing is loaded if the check fails, errors, or times out.
]]

--------------------------------------------------------------------
-- Defaults (overridden by getgenv().KeySystemConfig)
--------------------------------------------------------------------
local DEFAULTS = {
	Title = "Key System",
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
	Buttons = {
		GetKey = "Get Key",
		CheckKey = "Check Key",
		Discord = "Copy Discord",
	},
	DiscordUrl = "https://discord.gg/example",
	ShowDiscordButton = true,
	AdRewardsUrl = "Example", -- paste your Luarmor Ad Rewards link here (via config)
	ScriptId = "YOUR_LUARMOR_SCRIPT_ID",
	DetailedErrors = false,
	CheckTimeout = 20, -- seconds before a check counts as a network failure
}

local LIBRARY_URL = "https://sdkapi-public.luarmor.net/library.lua" -- official Luarmor key check library

--------------------------------------------------------------------
-- Environment / config
--------------------------------------------------------------------
local env = (getgenv and getgenv()) or _G

local function merge(base, over)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if type(over) == "table" then
		for k, v in pairs(over) do
			if type(v) == "table" and type(base[k]) == "table" then
				out[k] = merge(base[k], v)
			else
				out[k] = v
			end
		end
	end
	return out
end

local cfg = merge(DEFAULTS, env.KeySystemConfig)
local T = cfg.Theme

--------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------
local STRINGS = {
	en = {
		ready = "Enter your key and press Check Key.",
		placeholder = "Paste your key here",
		enterKey = "Enter your key first.",
		checking = "Checking key...",
		valid = "Key accepted. Loading...",
		validExpires = "Key accepted. Time left: %s. Loading...",
		lifetime = "lifetime",
		days = "%d day(s)",
		hours = "%d hour(s)",
		KEY_EXPIRED = "Your key has expired. Get a new one.",
		KEY_BANNED = "This key has been blacklisted.",
		KEY_HWID_LOCKED = "This key is linked to another device. Reset your HWID.",
		KEY_INCORRECT = "Incorrect key. Check it and try again.",
		KEY_INVALID = "Invalid key format. Check that you copied the whole key.",
		SCRIPT_ID_INCORRECT = "Script ID not found. Contact the developer.",
		SCRIPT_ID_INVALID = "Script ID is invalid. Contact the developer.",
		INVALID_EXECUTOR = "This executor is not supported.",
		SECURITY_ERROR = "Security check failed. Try again.",
		TIME_ERROR = "Request timed out or device time is wrong. Try again.",
		UNKNOWN_ERROR = "Service error. Try again later.",
		unexpected = "Unexpected response from the service. Try again.",
		network = "Could not reach the service. Try again.",
		keyLinkCopied = "Key link copied. Open it in your browser.",
		keyLinkMissing = "Key link is not configured yet.",
		noClipboard = "Clipboard unavailable. Copy manually: %s",
		discordCopied = "Discord link copied.",
		loadFailed = "Failed to load the script. Try again.",
	},
	ru = {
		ready = "Введите ключ и нажмите Check Key.",
		placeholder = "Вставьте ключ сюда",
		enterKey = "Сначала введите ключ.",
		checking = "Проверка ключа...",
		valid = "Ключ принят. Загрузка...",
		validExpires = "Ключ принят. Осталось: %s. Загрузка...",
		lifetime = "навсегда",
		days = "%d дн.",
		hours = "%d ч.",
		KEY_EXPIRED = "Срок действия ключа закончился. Получите новый.",
		KEY_BANNED = "Этот ключ заблокирован.",
		KEY_HWID_LOCKED = "Ключ привязан к другому устройству. Сбросьте HWID.",
		KEY_INCORRECT = "Неверный ключ. Проверьте и попробуйте снова.",
		KEY_INVALID = "Неверный формат ключа. Проверьте, что скопирован весь ключ.",
		SCRIPT_ID_INCORRECT = "Script ID не найден. Свяжитесь с разработчиком.",
		SCRIPT_ID_INVALID = "Script ID недействителен. Свяжитесь с разработчиком.",
		INVALID_EXECUTOR = "Этот executor не поддерживается.",
		SECURITY_ERROR = "Проверка безопасности не пройдена. Повторите.",
		TIME_ERROR = "Время ожидания истекло или время на устройстве неверно. Повторите.",
		UNKNOWN_ERROR = "Ошибка сервиса. Попробуйте позже.",
		unexpected = "Неожиданный ответ сервиса. Повторите.",
		network = "Не удалось связаться с сервисом. Попробуйте ещё раз.",
		keyLinkCopied = "Ссылка на ключ скопирована. Откройте её в браузере.",
		keyLinkMissing = "Ссылка на получение ключа ещё не настроена.",
		noClipboard = "Буфер обмена недоступен. Скопируйте вручную: %s",
		discordCopied = "Ссылка на Discord скопирована.",
		loadFailed = "Не удалось загрузить скрипт. Повторите.",
	},
}
local S = STRINGS[cfg.Language] or STRINGS.en

--------------------------------------------------------------------
-- Services
--------------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local GUI_NAME = "KeySystemGui"

local function copyText(text)
	local fn = setclipboard or toclipboard or (syn and syn.write_clipboard) or (Clipboard and Clipboard.set)
	if not fn then
		return false
	end
	return (pcall(fn, text))
end

local function lighten(c, a)
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c, a)
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function isHttpLink(s)
	return type(s) == "string" and s:match("^https?://") ~= nil
end

local function formatTimeLeft(authExpire)
	if type(authExpire) ~= "number" or authExpire <= 0 then
		return S.lifetime
	end
	local left = authExpire - os.time()
	if left <= 0 then
		return nil
	end
	if left >= 86400 then
		return string.format(S.days, math.floor(left / 86400))
	end
	return string.format(S.hours, math.max(1, math.floor(left / 3600)))
end

--------------------------------------------------------------------
-- LuarmorAdapter: the only place that talks to Luarmor
--------------------------------------------------------------------
local LuarmorAdapter = {}
local apiCache

local function loadApi()
	if apiCache then
		return apiCache
	end
	local ok, api = pcall(function()
		return loadstring(game:HttpGet(LIBRARY_URL))()
	end)
	if ok and type(api) == "table" then
		api.script_id = cfg.ScriptId
		apiCache = api
		return api
	end
	return nil
end

-- Returns: status table {code, message, data?} or nil if the service could not be reached.
function LuarmorAdapter.check(key)
	local api = loadApi()
	if not api then
		return nil
	end

	local result, done = nil, false
	task.spawn(function()
		local ok, res = pcall(api.check_key, key)
		result = ok and res or nil
		done = true
	end)

	local started = os.clock()
	while not done and os.clock() - started < cfg.CheckTimeout do
		task.wait(0.1)
	end

	if type(result) == "table" and type(result.code) == "string" then
		return result
	end
	return nil
end

-- Called only after KEY_VALID.
function LuarmorAdapter.launch(key)
	local api = loadApi()
	if not api then
		return false
	end
	env.script_key = key -- must be set before load_script
	script_key = key
	return (pcall(api.load_script))
end

--------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------
-- Remove a previous instance
for _, parent in ipairs({ (gethui and gethui()) or nil, game:GetService("CoreGui"), Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") }) do
	local old = parent and parent:FindFirstChild(GUI_NAME)
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
	if syn and syn.protect_gui then
		syn.protect_gui(gui)
	end
end)

do
	local candidates = {}
	if gethui then
		local ok, ui = pcall(gethui)
		if ok and ui then
			table.insert(candidates, ui)
		end
	end
	table.insert(candidates, game:GetService("CoreGui"))
	table.insert(candidates, Players.LocalPlayer:WaitForChild("PlayerGui"))
	for _, c in ipairs(candidates) do
		pcall(function()
			gui.Parent = c
		end)
		if gui.Parent == c then
			break
		end
	end
end

local connections = {}
local closed = false

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function closeGui()
	if closed then
		return
	end
	closed = true
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		gui:Destroy()
	end)
end

-- Layout numbers
local WIDTH, TOPBAR, PAD, GAP = 320, 44, 16, 10
local INPUT_H, BTN_H, DISCORD_H, STATUS_H = 44, 44, 38, 58
local height = TOPBAR + PAD + INPUT_H + GAP + BTN_H + GAP + STATUS_H + PAD
if cfg.ShowDiscordButton then
	height = height + DISCORD_H + GAP
end

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(WIDTH, height)
window.BackgroundColor3 = T.Background
window.BorderSizePixel = 0
window.Parent = gui
corner(window, 14)
stroke(window, T.Panel, 1.5)

-- Scale for mobile / small screens
local uiScale = Instance.new("UIScale")
uiScale.Parent = window

local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vs = cam.ViewportSize
	uiScale.Scale = math.clamp(math.min(vs.X / (WIDTH + 40), vs.Y / (height + 40)), 0.55, 1.25)
end
updateScale()
if workspace.CurrentCamera then
	connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateScale)
end

-- Top bar
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, TOPBAR)
topBar.BackgroundColor3 = T.Panel
topBar.BorderSizePixel = 0
topBar.Parent = window
corner(topBar, 14)

local topFix = Instance.new("Frame") -- squares off the bottom corners of the top bar
topFix.Size = UDim2.new(1, 0, 0, 14)
topFix.Position = UDim2.new(0, 0, 1, -14)
topFix.BackgroundColor3 = T.Panel
topFix.BorderSizePixel = 0
topFix.Parent = topBar

local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(0, 4, 0, 18)
accentLine.Position = UDim2.new(0, PAD, 0.5, -9)
accentLine.BackgroundColor3 = cfg.Accent
accentLine.BorderSizePixel = 0
accentLine.Parent = topBar
corner(accentLine, 2)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, PAD + 14, 0, 0)
title.Size = UDim2.new(1, -(PAD + 14 + TOPBAR), 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = T.Text
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Text = tostring(cfg.Title)
title.Parent = topBar

-- Button factory with hover / press states
local function makeButton(parent, text, color, textColor)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = textColor
	b.Text = text
	b.Parent = parent
	corner(b, 10)

	local disabled, hovering = false, false
	local function paint(c)
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = c }):Play()
	end

	connect(b.MouseEnter, function()
		hovering = true
		if not disabled then
			paint(lighten(color, 0.12))
		end
	end)
	connect(b.MouseLeave, function()
		hovering = false
		if not disabled then
			paint(color)
		end
	end)
	connect(b.MouseButton1Down, function()
		if not disabled then
			paint(darken(color, 0.2))
		end
	end)
	connect(b.MouseButton1Up, function()
		if not disabled then
			paint(hovering and lighten(color, 0.12) or color)
		end
	end)

	local obj = { Instance = b }
	function obj.SetDisabled(state)
		disabled = state
		b.Active = not state
		paint(state and darken(color, 0.45) or color)
		b.TextTransparency = state and 0.5 or 0
	end
	function obj.IsDisabled()
		return disabled
	end
	function obj.OnClick(fn)
		connect(b.Activated, function()
			if not disabled then
				fn()
			end
		end)
	end
	return obj
end

local closeBtn = makeButton(topBar, "×", T.Panel, T.Muted)
closeBtn.Instance.Size = UDim2.fromOffset(34, 34)
closeBtn.Instance.Position = UDim2.new(1, -(34 + 6), 0.5, -17)
closeBtn.Instance.TextSize = 24
closeBtn.OnClick(closeGui)

-- Body
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, PAD, 0, TOPBAR + PAD)
body.Size = UDim2.new(1, -PAD * 2, 1, -(TOPBAR + PAD * 2))
body.Parent = window

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, GAP)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

-- Key input
local inputFrame = Instance.new("Frame")
inputFrame.LayoutOrder = 1
inputFrame.Size = UDim2.new(1, 0, 0, INPUT_H)
inputFrame.BackgroundColor3 = T.Input
inputFrame.BorderSizePixel = 0
inputFrame.Parent = body
corner(inputFrame, 10)
local inputStroke = stroke(inputFrame, T.Panel, 1.5)

local keyBox = Instance.new("TextBox")
keyBox.BackgroundTransparency = 1
keyBox.Size = UDim2.new(1, -24, 1, 0)
keyBox.Position = UDim2.new(0, 12, 0, 0)
keyBox.Font = Enum.Font.GothamMedium
keyBox.TextSize = 15
keyBox.TextColor3 = T.Text
keyBox.PlaceholderText = S.placeholder
keyBox.PlaceholderColor3 = T.Muted
keyBox.Text = ""
keyBox.ClearTextOnFocus = false
keyBox.TextXAlignment = Enum.TextXAlignment.Left
keyBox.ClipsDescendants = true
keyBox.Parent = inputFrame

connect(keyBox.Focused, function()
	inputStroke.Color = cfg.Accent
end)
connect(keyBox.FocusLost, function()
	inputStroke.Color = T.Panel
end)

-- Get Key / Check Key row
local row = Instance.new("Frame")
row.LayoutOrder = 2
row.BackgroundTransparency = 1
row.Size = UDim2.new(1, 0, 0, BTN_H)
row.Parent = body

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, GAP)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = row

local getBtn = makeButton(row, cfg.Buttons.GetKey, T.Input, T.Text)
getBtn.Instance.LayoutOrder = 1
getBtn.Instance.Size = UDim2.new(0.5, -GAP / 2, 1, 0)

local checkBtn = makeButton(row, cfg.Buttons.CheckKey, cfg.Accent, T.AccentText)
checkBtn.Instance.LayoutOrder = 2
checkBtn.Instance.Size = UDim2.new(0.5, -GAP / 2, 1, 0)

-- Discord button (optional)
local discordBtn
if cfg.ShowDiscordButton then
	discordBtn = makeButton(body, cfg.Buttons.Discord, T.Panel, T.Text)
	discordBtn.Instance.LayoutOrder = 3
	discordBtn.Instance.Size = UDim2.new(1, 0, 0, DISCORD_H)
	discordBtn.Instance.TextSize = 14
end

-- Status indicator
local statusFrame = Instance.new("Frame")
statusFrame.LayoutOrder = 4
statusFrame.Size = UDim2.new(1, 0, 0, STATUS_H)
statusFrame.BackgroundColor3 = T.Panel
statusFrame.BorderSizePixel = 0
statusFrame.Parent = body
corner(statusFrame, 10)

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(10, 10)
dot.Position = UDim2.new(0, 12, 0.5, -5)
dot.BackgroundColor3 = T.Muted
dot.BorderSizePixel = 0
dot.Parent = statusFrame
corner(dot, 5)

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.new(0, 32, 0, 0)
statusLabel.Size = UDim2.new(1, -42, 1, 0)
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 13
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = T.Text
statusLabel.Text = S.ready
statusLabel.Parent = statusFrame

local function setStatus(kind, text)
	local color = ({
		info = T.Muted,
		busy = cfg.Accent,
		success = T.Success,
		error = T.Error,
	})[kind] or T.Muted
	TweenService:Create(dot, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
	statusLabel.Text = text
end

setStatus("info", S.ready)

-- Dragging (mouse + touch), compensates for UIScale
do
	local dragging, dragStart, startPos = false, nil, nil
	connect(topBar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = window.Position
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
				end
			end)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if
			dragging
			and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
		then
			local d = (input.Position - dragStart) / uiScale.Scale
			window.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

--------------------------------------------------------------------
-- Behaviour
--------------------------------------------------------------------
local busy = false

local function setBusy(state)
	busy = state
	checkBtn.SetDisabled(state)
	getBtn.SetDisabled(state)
end

getBtn.OnClick(function()
	if not isHttpLink(cfg.AdRewardsUrl) then
		setStatus("error", S.keyLinkMissing)
		return
	end
	if copyText(cfg.AdRewardsUrl) then
		setStatus("success", S.keyLinkCopied)
	else
		setStatus("info", string.format(S.noClipboard, cfg.AdRewardsUrl))
	end
end)

if discordBtn then
	discordBtn.OnClick(function()
		if copyText(cfg.DiscordUrl) then
			setStatus("success", S.discordCopied)
		else
			setStatus("info", string.format(S.noClipboard, cfg.DiscordUrl))
		end
	end)
end

local function describe(status)
	local text = S[status.code]
	if type(text) ~= "string" or status.code == "KEY_VALID" then
		text = S.unexpected
	end
	if cfg.DetailedErrors then
		text = text .. " [" .. tostring(status.code) .. "]"
	end
	return text
end

local function onCheck()
	if busy or closed then
		return
	end

	local key = (tostring(keyBox.Text):gsub("%s+", ""))
	if key == "" then
		setStatus("error", S.enterKey)
		return
	end

	setBusy(true)
	setStatus("busy", S.checking)

	task.spawn(function()
		local status = LuarmorAdapter.check(key)
		if closed then
			return
		end

		if not status then
			setStatus("error", S.network)
			setBusy(false)
			return
		end

		-- The ONLY path that opens the main script:
		if status.code == "KEY_VALID" then
			local left = type(status.data) == "table" and formatTimeLeft(status.data.auth_expire) or nil
			setStatus("success", left and string.format(S.validExpires, left) or S.valid)
			task.wait(0.6)
			if closed then
				return
			end

			gui.Enabled = false
			if LuarmorAdapter.launch(key) then
				closeGui()
			else
				gui.Enabled = true
				setStatus("error", S.loadFailed)
				setBusy(false)
			end
			return
		end

		setStatus("error", describe(status))
		setBusy(false)
	end)
end

checkBtn.OnClick(onCheck)
connect(keyBox.FocusLost, function(enterPressed)
	if enterPressed then
		onCheck()
	end
end)
