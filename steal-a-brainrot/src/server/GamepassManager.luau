--!strict
--[[
	GamepassManager (ModuleScript)
	Расположение: ServerScriptService.Server.GamepassManager

	Проверка владения геймпассами на сервере через MarketplaceService (§7, §10).
	ID пассов заданы в Config.Gamepasses (по умолчанию 0 = пасс отключён/не настроен).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))

local GamepassManager = {}
local ctx: any

-- Безопасная проверка владения (с pcall — сеть может упасть).
local function owns(userId: number, passId: number): boolean
	if passId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok and result == true
end

-- Пере-проверить все пассы игрока и записать в профиль.
function GamepassManager.Refresh(_, player: Player)
	local profile = ctx.Data:Get(player)
	if not profile then
		return
	end
	profile.Passes.VIP = owns(player.UserId, Config.Gamepasses.VIP.id)
	profile.Passes.DoubleIncome = owns(player.UserId, Config.Gamepasses.DoubleIncome.id)
	profile.Passes.AutoCollect = owns(player.UserId, Config.Gamepasses.AutoCollect.id)
	ctx.Data:Push(player)
end

-- Множитель дохода от пассов: ×2 (если есть) * (1 + VIP-бонус).
function GamepassManager.IncomeMultiplier(_, player: Player): number
	local profile = ctx.Data:Get(player)
	if not profile then
		return 1
	end
	local mult = 1
	if profile.Passes.DoubleIncome then
		mult *= Config.Gamepasses.DoubleIncome.multiplier
	end
	if profile.Passes.VIP then
		mult *= (1 + Config.Gamepasses.VIP.incomeBonus)
	end
	return mult
end

function GamepassManager.HasAutoCollect(_, player: Player): boolean
	local profile = ctx.Data:Get(player)
	return profile ~= nil and profile.Passes.AutoCollect == true
end

function GamepassManager.Init(_, context)
	ctx = context

	-- При заходе: дождаться загрузки профиля и проверить пассы.
	local function onAdded(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 30
			while not ctx.Data:IsLoaded(player) and os.clock() < deadline do
				task.wait(0.5)
			end
			if ctx.Data:IsLoaded(player) then
				GamepassManager:Refresh(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, p in Players:GetPlayers() do
		onAdded(p)
	end

	-- Мгновенное обновление после покупки.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and ctx.Data:IsLoaded(player) then
			GamepassManager:Refresh(player)
		end
	end)
end

return GamepassManager
