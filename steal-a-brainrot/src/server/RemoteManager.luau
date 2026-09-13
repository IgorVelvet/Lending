--!strict
--[[
	RemoteManager (ModuleScript)
	Расположение: ServerScriptService.Server.RemoteManager

	Создаёт ReplicatedStorage.Remotes и все RemoteEvent/RemoteFunction по именам из RemoteNames.
	Даёт хелперы для привязки обработчиков с автоматическим rate-limit и защитой от ошибок (§9, §10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))
local Config = require(Modules:WaitForChild("Config"))
local RateLimiter = require(script.Parent.RateLimiter)

local RemoteManager = {}

local folder: Folder
local functions: { [string]: RemoteFunction } = {}
local events: { [string]: RemoteEvent } = {}

function RemoteManager.Init(_)
	folder = Instance.new("Folder")
	folder.Name = RemoteNames.Folder

	for _, name in RemoteNames.Functions do
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = folder
		functions[name] = rf
	end

	for _, name in RemoteNames.Events do
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = folder
		events[name] = re
	end

	folder.Parent = ReplicatedStorage
end

-- Возвращает лимит для ключа из конфига (или дефолтный).
local function limitFor(key: string): number
	return Config.RateLimits[key] or Config.RateLimits.Default
end

--[[
	Привязать обработчик RemoteFunction.
	handler(player, ...) -> любые значения. Оборачивается в pcall и rate-limit.
	При превышении лимита возвращает (false, "rate") без вызова handler.
]]
function RemoteManager.OnFunction(_, name: string, handler: (Player, ...any) -> ...any)
	local rf = functions[name]
	assert(rf, "Unknown RemoteFunction: " .. name)
	rf.OnServerInvoke = function(player: Player, ...): ...any
		if not RateLimiter:Allow(player, name, limitFor(name)) then
			return false, "rate"
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(("[RemoteFunction %s] error: %s"):format(name, tostring(results[2])))
			return false, "error"
		end
		return table.unpack(results, 2, results.n)
	end
end

--[[
	Привязать обработчик RemoteEvent (client->server).
]]
function RemoteManager.OnEvent(_, name: string, handler: (Player, ...any) -> ())
	local re = events[name]
	assert(re, "Unknown RemoteEvent: " .. name)
	re.OnServerEvent:Connect(function(player: Player, ...)
		if not RateLimiter:Allow(player, name, limitFor(name)) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[RemoteEvent %s] error: %s"):format(name, tostring(err)))
		end
	end)
end

-- Отправить событие одному игроку (server->client).
function RemoteManager.FireClient(_, name: string, player: Player, ...: any)
	local re = events[name]
	if re then
		re:FireClient(player, ...)
	end
end

-- Отправить событие всем.
function RemoteManager.FireAll(_, name: string, ...: any)
	local re = events[name]
	if re then
		re:FireAllClients(...)
	end
end

return RemoteManager
