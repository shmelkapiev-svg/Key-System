--[[
    key system v1.2.lua  (main key checker, audited)
    Key GUI + official Luarmor key check library. Mobile-friendly, dark theme.

    Reads settings from getgenv().KeySystemConfig (see Config.lua). Every setting
    has a default, so this file also runs on its own. Invalid settings fall back
    to defaults and are reported through warn(); the user's table is never modified.

    Flow:  GUI -> api.check_key(key) -> ONLY on status.code == "KEY_VALID"
           -> script_key = key -> api.load_script()

    Documented SDK contract (docs.luarmor.net, "Key Check Library"):
      api = loadstring(game:HttpGet("https://sdkapi-public.luarmor.net/library.lua"))()
      api.script_id = "<script id>"                 -- set first
      status = api.check_key("<32-char key>")       -- {code:string, message:string, data?:table}
      status.data (KEY_VALID only): auth_expire (number; 0 or -1 = lifetime), note, total_executions
      script_key = "<key>"                          -- global, MUST be set before load_script
      api.load_script()                             -- return value is NOT documented

    Request lifecycle (state machine):
      idle -> checking -> launching -> (closed | launch_failed)
      checking -> idle (any failed check) ; any state -> closed (X button / re-run)
]]

--------------------------------------------------------------------
-- Constants and defaults
--------------------------------------------------------------------
local LIBRARY_URL = "https://sdkapi-public.luarmor.net/library.lua" -- official Luarmor key check library
local GUI_NAME = "KeySystemGui"
local REGISTRY_KEY = "__KeySystemInstance" -- lets a re-run close the previous instance cleanly
local LOG_PREFIX = "[KeySystem] "

-- Implementation choices (NOT Luarmor-documented limits):
local TIMEOUT_MIN, TIMEOUT_MAX = 5, 120 -- seconds allowed for CheckTimeout
local MAX_KEY_LENGTH = 128 -- documented keys are 32 chars; longer input is rejected locally as KEY_INVALID

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
	Buttons = {}, -- empty on purpose: localized defaults come from STRINGS[lang].buttons
	DiscordUrl = "https://discord.gg/example",
	ShowDiscordButton = true,
	AdRewardsUrl = "Example", -- paste your Luarmor Ad Rewards link here (via Config.lua)
	ScriptId = "YOUR_LUARMOR_SCRIPT_ID",
	DetailedErrors = false,
	CheckTimeout = 20, -- seconds before a check is reported as timed out
}

--------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------
local function resolveEnv()
	if type(getgenv) == "function" then
		local ok, e = pcall(getgenv)
		if ok and type(e) == "table" then
			return e
		end
	end
	return _G
end
local env = resolveEnv()

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	pcall(warn, LOG_PREFIX .. table.concat(parts, " "))
end

-- Never let a key reach logs: replace every plain occurrence.
local function redact(text, key)
	text = tostring(text)
	if type(key) ~= "string" or key == "" then
		return text
	end
	local out, from = text, 1
	while true do
		local i, j = out:find(key, from, true)
		if not i then
			break
		end
		out = out:sub(1, i - 1) .. "<key>" .. out:sub(j + 1)
		from = i + 5
	end
	return out
end

local function trim(s)
	return (s:match("^%s*(.-)%s*$"))
end

local function isFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function nonEmptyString(v)
	return type(v) == "string" and trim(v) ~= ""
end

-- Same recursive merge as before (partial nested overrides such as Theme are preserved).
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

--------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------
local STRINGS = {
	en = {
		buttons = { GetKey = "Get Key", CheckKey = "Check Key", Discord = "Copy Discord" },
		ready = "Enter your key and press %s.",
		placeholder = "Paste your key here",
		enterKey = "Enter your key first.",
		checking = "Checking key...",
		valid = "Key accepted. Loading...",
		validExpires = "Key accepted. Time left: %s. Loading...",
		lifetime = "lifetime",
		lessThanMinute = "less than a minute",
		units = {
			days = { "%d day", "%d days" },
			hours = { "%d hour", "%d hours" },
			minutes = { "%d minute", "%d minutes" },
		},
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
		unknownStatus = "Verification failed. Try again later.",
		unexpected = "Unexpected response from the service. Try again.",
		network = "Could not reach the service. Try again.",
		timeout = "The service did not respond in time. Try again.",
		sdkBroken = "The key service library could not be loaded correctly. Try again later.",
		checkFailed = "The key check failed unexpectedly. Try again.",
		stillBusy = "The previous check is still running. Please wait a moment.",
		cfgScriptId = "Configuration error: set a valid ScriptId in Config.lua.",
		keyLinkCopied = "Key link copied. Open it in your browser.",
		keyLinkMissing = "Key link is not configured (AdRewardsUrl in Config.lua).",
		discordMissing = "Discord link is not configured (DiscordUrl in Config.lua).",
		noClipboard = "Clipboard unavailable. Copy manually: %s",
		discordCopied = "Discord link copied.",
		loadFailed = "Failed to load the script. Re-run the loader to try again.",
	},
	ru = {
		buttons = { GetKey = "Получить ключ", CheckKey = "Проверить ключ", Discord = "Копировать Discord" },
		ready = "Введите ключ и нажмите «%s».",
		placeholder = "Вставьте ключ сюда",
		enterKey = "Сначала введите ключ.",
		checking = "Проверка ключа...",
		valid = "Ключ принят. Загрузка...",
		validExpires = "Ключ принят. Осталось: %s. Загрузка...",
		lifetime = "навсегда",
		lessThanMinute = "меньше минуты",
		units = {
			days = { "%d день", "%d дня", "%d дней" },
			hours = { "%d час", "%d часа", "%d часов" },
			minutes = { "%d минута", "%d минуты", "%d минут" },
		},
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
		unknownStatus = "Проверка не пройдена. Попробуйте позже.",
		unexpected = "Неожиданный ответ сервиса. Повторите.",
		network = "Не удалось связаться с сервисом. Попробуйте ещё раз.",
		timeout = "Сервис не ответил вовремя. Повторите попытку.",
		sdkBroken = "Не удалось корректно загрузить библиотеку проверки ключей. Попробуйте позже.",
		checkFailed = "Проверка ключа завершилась неожиданной ошибкой. Повторите.",
		stillBusy = "Предыдущая проверка ещё выполняется. Подождите немного.",
		cfgScriptId = "Ошибка конфигурации: укажите корректный ScriptId в Config.lua.",
		keyLinkCopied = "Ссылка на ключ скопирована. Откройте её в браузере.",
		keyLinkMissing = "Ссылка на ключ не настроена (AdRewardsUrl в Config.lua).",
		discordMissing = "Ссылка на Discord не настроена (DiscordUrl в Config.lua).",
		noClipboard = "Буфер обмена недоступен. Скопируйте вручную: %s",
		discordCopied = "Ссылка на Discord скопирована.",
		loadFailed = "Не удалось загрузить скрипт. Перезапустите загрузчик.",
	},
}

-- Plural form index per language (en: 1 = one, 2 = other; ru: 1 = one, 2 = few, 3 = many)
local PLURAL = {
	en = function(n)
		return n == 1 and 1 or 2
	end,
	ru = function(n)
		local m10, m100 = n % 10, n % 100
		if m10 == 1 and m100 ~= 11 then
			return 1
		elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
			return 2
		end
		return 3
	end,
}

--------------------------------------------------------------------
-- URL validation (pure string checks - no network requests)
--------------------------------------------------------------------
-- Returns normalized url, lowercase host, path+query (or nil if it is not a plain https URL).
local function parseHttpsUrl(s)
	if type(s) ~= "string" then
		return nil
	end
	s = trim(s)
	if s == "" or #s > 512 or s:find("[%s%c]") then
		return nil
	end
	local rest = s:match("^[Hh][Tt][Tt][Pp][Ss]://(.+)$")
	if not rest then
		return nil
	end
	local host, path = rest:match("^([^/?#]*)(.*)$")
	if host == "" or host:find("[@:%[%]]") then -- no userinfo, port or IPv6 literals
		return nil
	end
	return s, host:lower(), path
end

-- Luarmor Ad Rewards links are documented as "ads.luarmor.net/get_key..." links.
-- Only the host is enforced; the exact path format is not specified in the docs.
local function isLuarmorAdUrl(s)
	local url, host, path = parseHttpsUrl(s)
	if url and host == "ads.luarmor.net" and #path > 1 and path:sub(1, 1) == "/" then
		return url
	end
	return nil
end

-- Accepts discord.gg/<code> and discord(app).com/invite/<code>. This checks the SHAPE only;
-- whether the invite is alive is not (and must not be) checked over the network.
local function isDiscordInviteUrl(s)
	local url, host, path = parseHttpsUrl(s)
	if not url then
		return nil
	end
	path = path:match("^([^?#]*)")
	local code
	if host == "discord.gg" or host == "www.discord.gg" then
		code = path:match("^/([%w%-_]+)/?$")
	elseif
		host == "discord.com"
		or host == "www.discord.com"
		or host == "discordapp.com"
		or host == "www.discordapp.com"
	then
		code = path:match("^/invite/([%w%-_]+)/?$")
	end
	if code and #code >= 2 and #code <= 32 then
		return url
	end
	return nil
end

-- Luarmor docs: SCRIPT_ID_INVALID = "too short / too long / contains non-hexadecimal characters".
-- The exact length is not documented (the docs example has 32 hex chars), so only the
-- hex alphabet is enforced here and the SDK has the final say on length.
local function isValidScriptId(s)
	return type(s) == "string" and s:match("^%x+$") ~= nil and #s <= 128
end

--------------------------------------------------------------------
-- Configuration: validate + normalize (never mutates the caller's table)
--------------------------------------------------------------------
local function buildConfig(raw)
	local issues = {}
	local function issue(msg)
		issues[#issues + 1] = msg
	end

	if raw ~= nil and type(raw) ~= "table" then
		issue("KeySystemConfig must be a table (got " .. type(raw) .. "); using defaults")
		raw = nil
	end
	if type(raw) == "table" then
		for k in pairs(raw) do
			if DEFAULTS[k] == nil then
				issue("unknown setting '" .. tostring(k) .. "' ignored")
			end
		end
	end

	local merged = merge(DEFAULTS, raw)
	local cfg = { Theme = {}, Buttons = {} }

	-- Language first: it decides the default button labels
	local lang = DEFAULTS.Language
	if type(merged.Language) == "string" and STRINGS[merged.Language:lower()] then
		lang = merged.Language:lower()
	else
		issue("Language must be \"en\" or \"ru\"; using \"en\"")
		lang = "en"
	end
	cfg.Language = lang

	if nonEmptyString(merged.Title) then
		cfg.Title = trim(merged.Title)
	else
		issue("Title must be a non-empty string; using default")
		cfg.Title = DEFAULTS.Title
	end

	if typeof(merged.Accent) == "Color3" then
		cfg.Accent = merged.Accent
	else
		issue("Accent must be a Color3; using default")
		cfg.Accent = DEFAULTS.Accent
	end

	local themeIn = merged.Theme
	if type(themeIn) ~= "table" then
		issue("Theme must be a table; using default theme")
		themeIn = {}
	end
	for name, default in pairs(DEFAULTS.Theme) do
		local v = themeIn[name]
		if typeof(v) == "Color3" then
			cfg.Theme[name] = v
		else
			if v ~= nil then
				issue("Theme." .. name .. " must be a Color3; using default")
			end
			cfg.Theme[name] = default
		end
	end

	local buttonsIn = merged.Buttons
	if type(buttonsIn) ~= "table" then
		issue("Buttons must be a table; using default labels")
		buttonsIn = {}
	end
	for name, default in pairs(STRINGS[lang].buttons) do
		local v = buttonsIn[name]
		if nonEmptyString(v) then
			cfg.Buttons[name] = trim(v)
		else
			if v ~= nil then
				issue("Buttons." .. name .. " must be a non-empty string; using default")
			end
			cfg.Buttons[name] = default
		end
	end

	if type(merged.ShowDiscordButton) == "boolean" then
		cfg.ShowDiscordButton = merged.ShowDiscordButton
	else
		issue("ShowDiscordButton must be a boolean; using default")
		cfg.ShowDiscordButton = DEFAULTS.ShowDiscordButton
	end

	if type(merged.DetailedErrors) == "boolean" then
		cfg.DetailedErrors = merged.DetailedErrors
	else
		issue("DetailedErrors must be a boolean; using default")
		cfg.DetailedErrors = DEFAULTS.DetailedErrors
	end

	local t = merged.CheckTimeout
	if isFiniteNumber(t) and t >= TIMEOUT_MIN and t <= TIMEOUT_MAX then
		cfg.CheckTimeout = t
	else
		issue("CheckTimeout must be a number between " .. TIMEOUT_MIN .. " and " .. TIMEOUT_MAX .. "; using default")
		cfg.CheckTimeout = DEFAULTS.CheckTimeout
	end

	-- Links: invalid value -> nil (the button then shows a clear "not configured" message)
	cfg.AdRewardsUrl = isLuarmorAdUrl(merged.AdRewardsUrl)
	if not cfg.AdRewardsUrl then
		issue("AdRewardsUrl is not a valid https://ads.luarmor.net/... link (Get Key will report it)")
	end
	cfg.DiscordUrl = isDiscordInviteUrl(merged.DiscordUrl)
	if not cfg.DiscordUrl then
		issue("DiscordUrl is not a valid Discord invite link (the Discord button will report it)")
	end

	-- Required for production: without a valid Script ID the SDK is never called.
	local sid = type(merged.ScriptId) == "string" and trim(merged.ScriptId) or nil
	if sid and isValidScriptId(sid) then
		cfg.ScriptId = sid
	else
		cfg.ScriptId = nil
		cfg.ConfigError = "cfgScriptId"
		issue("ScriptId is missing or not a hexadecimal Luarmor script ID")
	end

	return cfg, issues
end

local cfg, cfgIssues = buildConfig(env.KeySystemConfig)
for _, msg in ipairs(cfgIssues) do
	log("config:", msg)
end
local T = cfg.Theme
local S = STRINGS[cfg.Language]

--------------------------------------------------------------------
-- Services
--------------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

--------------------------------------------------------------------
-- Formatting helpers
--------------------------------------------------------------------
local function formatPlural(unitName, n)
	local forms = S.units[unitName]
	local idx = PLURAL[cfg.Language](n)
	return string.format(forms[idx] or forms[#forms], n)
end

local function formatDuration(seconds)
	if seconds >= 86400 then
		return formatPlural("days", math.floor(seconds / 86400))
	elseif seconds >= 3600 then
		return formatPlural("hours", math.floor(seconds / 3600))
	elseif seconds >= 60 then
		return formatPlural("minutes", math.floor(seconds / 60))
	end
	return S.lessThanMinute
end

-- Informational only; never influences authorization. Returns nil when it cannot be shown reliably.
local function describeExpiry(data, now)
	if type(data) ~= "table" or not isFiniteNumber(now) then
		return nil
	end
	local e = data.auth_expire
	if not isFiniteNumber(e) then
		return nil
	end
	if e == 0 or e == -1 then -- documented lifetime markers
		return S.lifetime
	end
	if e < 0 or e > 2147483647 then -- not a 32-bit Unix timestamp
		return nil
	end
	local left = e - now
	if left <= 0 then -- inconsistent with a valid key (clock skew?): do not show a duration
		return nil
	end
	return formatDuration(left)
end

local function normalizeKey(text)
	-- Least destructive: trim accidental leading/trailing whitespace only.
	-- Internal characters are left untouched (the SDK/server decides validity).
	return trim(tostring(text or ""))
end

--------------------------------------------------------------------
-- Clipboard (executor specific, isolated here)
--------------------------------------------------------------------
-- Returns true only if a clipboard function was called without raising.
-- Returns false, reason otherwise. Content cannot be read back to confirm it.
local function copyText(text)
	local fns = {}
	if type(setclipboard) == "function" then
		fns[#fns + 1] = setclipboard
	end
	if type(toclipboard) == "function" then
		fns[#fns + 1] = toclipboard
	end
	if type(syn) == "table" and type(syn.write_clipboard) == "function" then
		fns[#fns + 1] = syn.write_clipboard
	end
	if type(Clipboard) == "table" and type(Clipboard.set) == "function" then
		fns[#fns + 1] = Clipboard.set
	end
	if #fns == 0 then
		return false, "no clipboard function"
	end
	local lastErr
	for _, fn in ipairs(fns) do
		local ok, err = pcall(fn, text)
		if ok then
			return true
		end
		lastErr = err
	end
	return false, tostring(lastErr)
end

--------------------------------------------------------------------
-- LuarmorAdapter: the only place that talks to the Luarmor SDK
--------------------------------------------------------------------
local LuarmorAdapter = {}
local apiCache
local sdkActive = false -- true while an SDK call is really running (a timeout does not cancel it)
local launchAttempted = false

local STATUS_CODES = {
	KEY_VALID = true,
	KEY_EXPIRED = true,
	KEY_BANNED = true,
	KEY_HWID_LOCKED = true,
	KEY_INCORRECT = true,
	KEY_INVALID = true,
	SCRIPT_ID_INCORRECT = true,
	SCRIPT_ID_INVALID = true,
	INVALID_EXECUTOR = true,
	SECURITY_ERROR = true,
	TIME_ERROR = true,
	UNKNOWN_ERROR = true,
}

-- Returns api | nil, errorKind, detail
-- errorKind: sdk_fetch | sdk_compile | sdk_init | sdk_shape
local function loadApi()
	if apiCache then
		return apiCache
	end
	if type(loadstring) ~= "function" then
		return nil, "sdk_compile", "loadstring is not available in this executor"
	end

	local okGet, src = pcall(function()
		return game:HttpGet(LIBRARY_URL)
	end)
	if not okGet then
		return nil, "sdk_fetch", tostring(src)
	end
	if type(src) ~= "string" or src:match("^%s*$") then
		return nil, "sdk_fetch", "empty response"
	end

	local fn, compileErr = loadstring(src)
	if type(fn) ~= "function" then
		return nil, "sdk_compile", tostring(compileErr)
	end

	local okRun, api = pcall(fn)
	if not okRun then
		return nil, "sdk_init", tostring(api)
	end
	if type(api) ~= "table" then
		return nil, "sdk_shape", "SDK returned " .. type(api) .. " instead of a table"
	end
	for _, method in ipairs({ "check_key", "load_script" }) do
		if type(api[method]) ~= "function" then
			return nil, "sdk_shape", "SDK method '" .. method .. "' is missing"
		end
	end

	-- script_id must be assigned before the SDK is used
	local okId, idErr = pcall(function()
		api.script_id = cfg.ScriptId
	end)
	if not okId then
		return nil, "sdk_shape", "could not assign script_id: " .. tostring(idErr)
	end

	apiCache = api -- cache only a fully initialized, compatible SDK object
	return api
end

-- Only the documented fields are trusted; everything else is dropped.
local function normalizeStatus(res)
	if type(res) ~= "table" then
		return nil
	end
	if type(res.code) ~= "string" or res.code == "" then
		return nil
	end
	return {
		code = res.code,
		message = type(res.message) == "string" and res.message or nil,
		data = type(res.data) == "table" and res.data or nil,
	}
end

function LuarmorAdapter.isBusy()
	return sdkActive
end

-- callback(status, errorKind, detail) is invoked AT MOST ONCE:
--   status    : normalized {code, message?, data?} (success of the transport, not of the key)
--   errorKind : sdk_fetch | sdk_compile | sdk_init | sdk_shape | sdk_error | bad_response | timeout | busy
-- A timeout does NOT cancel the underlying request (Roblox/executors offer no cancellation);
-- a late result is simply dropped and sdkActive stays true until the call really returns.
function LuarmorAdapter.check(key, timeout, callback)
	if sdkActive then
		callback(nil, "busy")
		return
	end
	sdkActive = true

	local finished = false
	local function finish(status, kind, detail)
		if finished then
			return
		end
		finished = true
		local ok, err = pcall(callback, status, kind, detail)
		if not ok then
			log("check callback error:", redact(err, key))
		end
	end

	task.spawn(function()
		local api, kind, detail = loadApi()
		if not api then
			sdkActive = false
			log("SDK load failed [" .. tostring(kind) .. "]:", redact(detail, key))
			finish(nil, kind, detail)
			return
		end

		local ok, res = pcall(api.check_key, key)
		sdkActive = false
		if not ok then
			log("check_key raised:", redact(res, key))
			finish(nil, "sdk_error", tostring(res))
			return
		end

		local status = normalizeStatus(res)
		if not status then
			log("check_key returned a malformed response (" .. type(res) .. ")")
			finish(nil, "bad_response")
			return
		end
		finish(status)
	end)

	task.delay(timeout, function()
		finish(nil, "timeout")
	end)
end

-- Call only after KEY_VALID. Returns "launched" | "failed", detail
-- Contract notes: load_script()'s return value is undocumented. A raised error is a failure.
-- An explicit `false` return is treated as a failure (conservative assumption, not documented).
-- nil / any other return is treated as success because nil is the normal "no value" return.
-- It is attempted at most once per run: after an attempt the protected script may be partially
-- running, so an automatic or repeated launch could duplicate it.
function LuarmorAdapter.launch(key)
	if launchAttempted then
		return "failed", "launch already attempted"
	end
	launchAttempted = true

	local api, kind, detail = loadApi()
	if not api then
		return "failed", tostring(kind) .. ": " .. tostring(detail)
	end

	env.script_key = key -- must be set before load_script
	script_key = key

	local ok, ret = pcall(api.load_script)
	if not ok then
		return "failed", redact(ret, key)
	end
	if ret == false then
		return "failed", "load_script returned false"
	end
	return "launched"
end

--------------------------------------------------------------------
-- GUI containers (executor specific, isolated here)
--------------------------------------------------------------------
-- Returns only valid, distinct Instances (no nil holes).
local function getContainers()
	local list = {}
	local function add(inst)
		if typeof(inst) ~= "Instance" then
			return
		end
		for _, existing in ipairs(list) do
			if existing == inst then
				return
			end
		end
		list[#list + 1] = inst
	end

	if type(gethui) == "function" then
		local ok, ui = pcall(gethui)
		if ok then
			add(ui)
		end
	end
	local okCore, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore then
		add(core)
	end
	local lp = Players.LocalPlayer
	if lp then
		local okPg, pg = pcall(function()
			return lp:FindFirstChildOfClass("PlayerGui")
		end)
		if okPg then
			add(pg)
		end
	end
	return list
end

-- Closes the previous instance (also disconnects its events) and removes leftovers.
local function sweepOldInstances()
	local prev = env[REGISTRY_KEY]
	if type(prev) == "table" and type(prev.Close) == "function" then
		local ok, err = pcall(prev.Close)
		if not ok then
			log("previous instance cleanup failed:", err)
		end
		env[REGISTRY_KEY] = nil
	end

	for _, container in ipairs(getContainers()) do
		local okList, children = pcall(function()
			return container:GetChildren()
		end)
		if okList then
			for _, child in ipairs(children) do
				pcall(function()
					-- only our own windows: right class, right name, and our structure/marker
					if
						child.ClassName == "ScreenGui"
						and child.Name == GUI_NAME
						and (child:GetAttribute("KeySystem") == true or child:FindFirstChild("Window") ~= nil)
					then
						child:Destroy()
					end
				end)
			end
		end
	end
end

--------------------------------------------------------------------
-- GUI construction helpers
--------------------------------------------------------------------
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

--------------------------------------------------------------------
-- GUI + lifecycle
--------------------------------------------------------------------
sweepOldInstances()

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui:SetAttribute("KeySystem", true)

local connections = {}
local closed = false
local state = "idle" -- idle | checking | launching | launch_failed | closed
local requestId = 0 -- bumped on every new check and on close; stale results are ignored
local instance = {}

-- Every event handler runs protected: an error is logged, never thrown into the engine,
-- and nothing runs after the GUI is closed.
local function connect(signal, fn)
	if closed then
		return nil
	end
	local c = signal:Connect(function(...)
		if closed then
			return
		end
		local ok, err = pcall(fn, ...)
		if not ok then
			log("event handler error:", err)
		end
	end)
	connections[#connections + 1] = c
	return c
end

local function closeGui()
	if closed then
		return
	end
	closed = true
	state = "closed"
	requestId = requestId + 1 -- invalidates any in-flight request
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	connections = {}
	pcall(function()
		gui:Destroy()
	end)
	if env[REGISTRY_KEY] == instance then
		env[REGISTRY_KEY] = nil
	end
end
instance.Close = closeGui

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

local uiScale = Instance.new("UIScale")
uiScale.Parent = window

-- Viewport size from the ScreenGui itself (survives camera replacement); camera is only a fallback.
local function getViewport()
	local size = gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		return size
	end
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
		return cam.ViewportSize
	end
	return Vector2.new(WIDTH + 40, height + 40)
end

-- Position is kept as a fraction of the viewport (Scale only), so dragging does not depend on
-- how UIScale treats offsets, and the window can always be clamped back on screen.
local center = { x = 0.5, y = 0.5 }

local function applyPosition()
	local vs = getViewport()
	local s = uiScale.Scale
	local halfW = (WIDTH * s) / (2 * vs.X)
	local halfH = (height * s) / (2 * vs.Y)
	center.x = (halfW <= 0.5) and math.clamp(center.x, halfW, 1 - halfW) or 0.5
	center.y = (halfH <= 0.5) and math.clamp(center.y, halfH, 1 - halfH) or 0.5
	window.Position = UDim2.fromScale(center.x, center.y)
end

local function updateScale()
	local vs = getViewport()
	uiScale.Scale = math.clamp(math.min(vs.X / (WIDTH + 40), vs.Y / (height + 40)), 0.55, 1.25)
	applyPosition()
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
title.Text = cfg.Title
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
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Parent = parent
	corner(b, 10)

	local disabled, hovering = false, false
	local function paint(c)
		if closed then
			return
		end
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
	function obj.SetDisabled(isDisabled)
		if closed then
			return
		end
		disabled = isDisabled
		b.Active = not isDisabled
		paint(isDisabled and darken(color, 0.45) or color)
		b.TextTransparency = isDisabled and 0.5 or 0
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
statusLabel.Text = ""
statusLabel.Parent = statusFrame

local function setStatus(kind, text)
	if closed then
		return
	end
	local color = ({
		info = T.Muted,
		busy = cfg.Accent,
		success = T.Success,
		error = T.Error,
	})[kind] or T.Muted
	TweenService:Create(dot, TweenInfo.new(0.15), { BackgroundColor3 = color }):Play()
	statusLabel.Text = text
end

-- Buttons / input follow the lifecycle state
local function applyState()
	if closed then
		return
	end
	local working = state == "checking" or state == "launching"
	checkBtn.SetDisabled(working or state == "launch_failed")
	getBtn.SetDisabled(working)
	pcall(function()
		keyBox.TextEditable = not working and state ~= "launch_failed"
	end)
end

local function setState(newState)
	if closed then
		return
	end
	state = newState
	applyState()
end

--------------------------------------------------------------------
-- Attach to a container (after construction, so a failure leaves nothing half-built)
--------------------------------------------------------------------
local function attach()
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		end
	end)
	for _, container in ipairs(getContainers()) do
		local ok = pcall(function()
			gui.Parent = container
		end)
		if ok and gui.Parent == container then
			return true
		end
	end
	return false
end

if not attach() then
	log("could not attach the GUI to any container (gethui / CoreGui / PlayerGui); aborting")
	closeGui()
else
	env[REGISTRY_KEY] = instance
end

-- Scale / position follow the viewport (also when the camera is replaced)
if not closed then
	updateScale()
	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateScale)
	pcall(function()
		connect(workspace:GetPropertyChangedSignal("CurrentCamera"), updateScale)
	end)
end

-- Dragging (mouse + touch). Only the input that started the drag is followed.
do
	local dragging, dragInput, dragStart, startX, startY = false, nil, nil, 0, 0
	connect(topBar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = input
			dragStart = input.Position
			startX, startY = center.x, center.y
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1
		local isSameTouch = input.UserInputType == Enum.UserInputType.Touch and input == dragInput
		if isMouseMove or isSameTouch then
			local vs = getViewport()
			local d = input.Position - dragStart
			center.x = startX + d.X / vs.X
			center.y = startY + d.Y / vs.Y
			applyPosition()
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if not dragging then
			return
		end
		-- touch: the same InputObject ends; mouse: any MouseButton1 release ends the drag
		local sameTouch = input == dragInput
		local mouseRelease = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if sameTouch or mouseRelease then
			dragging = false
			dragInput = nil
		end
	end)
end

--------------------------------------------------------------------
-- Behaviour
--------------------------------------------------------------------
local function copyAndReport(url, okMessage)
	local ok, reason = copyText(url)
	if ok then
		setStatus("success", okMessage)
	else
		log("clipboard unavailable:", reason)
		setStatus("info", string.format(S.noClipboard, url)) -- show it so it can be copied by hand
	end
end

getBtn.OnClick(function()
	if not cfg.AdRewardsUrl then
		setStatus("error", S.keyLinkMissing)
		return
	end
	copyAndReport(cfg.AdRewardsUrl, S.keyLinkCopied)
end)

if discordBtn then
	discordBtn.OnClick(function()
		if not cfg.DiscordUrl then
			setStatus("error", S.discordMissing)
			return
		end
		copyAndReport(cfg.DiscordUrl, S.discordCopied)
	end)
end

local ERROR_MESSAGE = {
	sdk_fetch = "network",
	timeout = "timeout",
	sdk_compile = "sdkBroken",
	sdk_init = "sdkBroken",
	sdk_shape = "sdkBroken",
	sdk_error = "checkFailed",
	bad_response = "unexpected",
	busy = "stillBusy",
}

local function withDetail(text, tag)
	if cfg.DetailedErrors and tag then
		return text .. " [" .. tostring(tag) .. "]"
	end
	return text
end

local function describeStatus(status)
	if status.code ~= "KEY_VALID" and STATUS_CODES[status.code] then
		if cfg.DetailedErrors and status.message then
			log("status", status.code, "-", status.message)
		end
		return withDetail(S[status.code], status.code)
	end
	-- Unknown (future) status code: generic message, never treated as success
	return withDetail(S.unknownStatus, status.code)
end

-- KEY_VALID path: the ONLY route that starts the protected script.
local function startLaunch(key, status)
	setState("launching")
	local left = describeExpiry(status.data, os.time())
	setStatus("success", left and string.format(S.validExpires, left) or S.valid)
	task.wait(0.6)
	if closed or state ~= "launching" then
		return
	end

	gui.Enabled = false
	local result, detail = LuarmorAdapter.launch(key)
	if closed then
		return
	end
	if result == "launched" then
		closeGui()
		return
	end

	log("launch failed:", redact(detail, key))
	gui.Enabled = true
	setState("launch_failed") -- terminal: no automatic or repeated launch
	setStatus("error", S.loadFailed)
end

local function onCheck()
	if state ~= "idle" then -- ignores clicks while checking / launching / after a failed launch
		return
	end
	if cfg.ConfigError then
		setStatus("error", S[cfg.ConfigError])
		return
	end

	local key = normalizeKey(keyBox.Text)
	if key == "" then
		setStatus("error", S.enterKey)
		return
	end
	if #key > MAX_KEY_LENGTH then
		setStatus("error", withDetail(S.KEY_INVALID, "KEY_INVALID"))
		return
	end
	if LuarmorAdapter.isBusy() then
		-- an earlier request timed out but is still running inside the SDK; do not stack requests
		setStatus("error", S.stillBusy)
		return
	end

	requestId = requestId + 1
	local myId = requestId
	setState("checking")
	setStatus("busy", S.checking)

	LuarmorAdapter.check(key, cfg.CheckTimeout, function(status, errKind)
		-- Ignore stale results: closed GUI, newer request, or a state that moved on.
		if closed or myId ~= requestId or state ~= "checking" then
			return
		end

		if not status then
			setState("idle")
			setStatus("error", withDetail(S[ERROR_MESSAGE[errKind] or "checkFailed"], errKind))
			return
		end

		if status.code == "KEY_VALID" then
			startLaunch(key, status)
			return
		end

		setState("idle")
		setStatus("error", describeStatus(status))
	end)
end

checkBtn.OnClick(onCheck)
connect(keyBox.FocusLost, function(enterPressed)
	if not closed then
		inputStroke.Color = T.Panel
	end
	if enterPressed then
		onCheck()
	end
end)

-- Initial state
if not closed then
	if cfg.ConfigError then
		setStatus("error", S[cfg.ConfigError])
	else
		setStatus("info", string.format(S.ready, cfg.Buttons.CheckKey))
	end
	applyState()
end
