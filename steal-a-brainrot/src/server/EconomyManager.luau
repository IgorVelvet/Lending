--!strict
--[[
	EconomyManager (ModuleScript)
	Расположение: ServerScriptService.Server.EconomyManager

	Один общий серверный тик дохода на всех (§9). Начисляет доход от брейнротов на
	подиумах в кассу (Bank) с капом накопления, обрабатывает сбор кассы (§4.4).
	Сервер — единственный источник истины по балансу (§10).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))

local EconomyManager = {}
local ctx: any

-- Доход/сек базы игрока: сумма по брейнротам на подиумах * множители.
function EconomyManager.IncomePerSecond(_, player: Player): number
	local profile = ctx.Data:Get(player)
	if not profile then
		return 0
	end
	local slots = ctx.Upgrades:GetSlotCount(player)
	local raw = 0
	for _, entry in profile.Brainrots do
		if entry.podium and entry.podium <= slots then
			local def = Config.BrainrotById[entry.id]
			if def then
				raw += def.income
			end
		end
	end
	local upgradeMult = ctx.Upgrades:GetUpgradeValue(player, "IncomeMult")
	local passMult = ctx.Gamepass:IncomeMultiplier(player)
	return raw * upgradeMult * passMult
end

-- Кап накопления кассы = доход/сек * секунды капа * бонус CollectSpeed.
function EconomyManager.BankCap(_, player: Player): number
	local perSec = EconomyManager:IncomePerSecond(player)
	local collectBonus = ctx.Upgrades:GetUpgradeValue(player, "CollectSpeed")
	return perSec * Config.AccumulationCapSeconds * collectBonus
end

-- Сбор кассы в баланс (§4.4). Возвращает собранную сумму.
function EconomyManager.Collect(_, player: Player): number
	local profile = ctx.Data:Get(player)
	if not profile then
		return 0
	end
	local amount = math.floor(profile.Bank)
	if amount <= 0 then
		return 0
	end
	profile.Bank -= amount
	profile.Cash += amount
	profile.TotalEarned += amount
	ctx.Plots:UpdateRegister(player, profile.Bank)
	ctx.Data:Push(player)
	return amount
end

function EconomyManager.Init(_, context)
	ctx = context

	-- Сбор по remote (тап через ClickDetector идёт через PlotManager → сюда же).
	ctx.Remotes:OnFunction(require(Modules.RemoteNames).Functions.CollectCash, function(player)
		local collected = EconomyManager:Collect(player)
		return true, collected
	end)

	-- Общий тик дохода.
	task.spawn(function()
		while true do
			local dt = task.wait(Config.IncomeTickInterval)
			for _, player in Players:GetPlayers() do
				if ctx.Data:IsLoaded(player) then
					local profile = ctx.Data:Get(player)
					local perSec = EconomyManager:IncomePerSecond(player)
					if perSec > 0 then
						local gained = perSec * dt
						if ctx.Gamepass:HasAutoCollect(player) then
							-- Авто-сбор: сразу в баланс, без капа (§7).
							profile.Cash += gained
							profile.TotalEarned += gained
						else
							local cap = EconomyManager:BankCap(player)
							profile.Bank = math.min(cap, profile.Bank + gained)
							ctx.Plots:UpdateRegister(player, profile.Bank)
						end
					end
					-- Пушим каждый тик, чтобы HUD оставался живым и поздно
					-- подключившийся клиент получил профиль (§11).
					ctx.Data:Push(player)
				end
			end
		end
	end)
end

return EconomyManager
