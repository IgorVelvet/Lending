--!strict
--[[
	UpgradeManager (ModuleScript)
	Расположение: ServerScriptService.Server.UpgradeManager

	Апгрейды за валюту: множитель дохода, скорость бега/сбора, докупка слотов подиумов,
	уровни защиты (§7). Вся валидация и списание — на сервере (§10).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))

local UpgradeManager = {}
local ctx: any

-- Текущее числовое значение апгрейда игрока.
function UpgradeManager.GetUpgradeValue(_, player: Player, kind: string): number
	local profile = ctx.Data:Get(player)
	local def = Config.Upgrades[kind]
	if not profile or not def then
		return 1
	end
	local level = profile.Upgrades[kind] or 1
	return def.levels[level].value
end

function UpgradeManager.GetSlotCount(_, player: Player): number
	local profile = ctx.Data:Get(player)
	return profile and profile.Slots or Config.StartingSlots
end

-- Целевой WalkSpeed с учётом переноса добычи (§5).
function UpgradeManager.ApplyWalkSpeed(_, player: Player)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local base = UpgradeManager:GetUpgradeValue(player, "WalkSpeed")
	if ctx.Steal and ctx.Steal:IsCarrying(player) then
		base *= Config.Steal.CarrySpeedMultiplier
	end
	humanoid.WalkSpeed = base
end

-- ─── Покупки ──────────────────────────────────────────────────────────────

function UpgradeManager.BuyUpgrade(_, player: Player, kind: string): (boolean, string?)
	local profile = ctx.Data:Get(player)
	local def = Config.Upgrades[kind]
	if not profile or not def then
		return false, "bad_kind"
	end
	local nextLevel = (profile.Upgrades[kind] or 1) + 1
	local levelDef = def.levels[nextLevel]
	if not levelDef then
		return false, "max"
	end
	if profile.Cash < levelDef.cost then
		return false, "cash"
	end
	profile.Cash -= levelDef.cost
	profile.Upgrades[kind] = nextLevel
	if kind == "WalkSpeed" then
		UpgradeManager:ApplyWalkSpeed(player)
	end
	ctx.Data:Push(player)
	ctx.Data:Save(player)
	return true
end

function UpgradeManager.SlotCost(_, currentSlots: number): number
	local extra = currentSlots - Config.StartingSlots
	return math.floor(Config.SlotBaseCost * (Config.SlotCostGrowth ^ math.max(0, extra)))
end

function UpgradeManager.BuySlot(_, player: Player): (boolean, string?)
	local profile = ctx.Data:Get(player)
	if not profile then
		return false, "no_profile"
	end
	if profile.Slots >= Config.MaxSlots then
		return false, "max"
	end
	local cost = UpgradeManager:SlotCost(profile.Slots)
	if profile.Cash < cost then
		return false, "cash"
	end
	profile.Cash -= cost
	profile.Slots += 1
	ctx.Plots:Render(player)
	ctx.Data:Push(player)
	ctx.Data:Save(player)
	return true
end

function UpgradeManager.BuyDefense(_, player: Player): (boolean, string?)
	local profile = ctx.Data:Get(player)
	if not profile then
		return false, "no_profile"
	end
	local nextLevel = profile.DefenseLevel + 1
	local levelDef = Config.Defense.levels[nextLevel]
	if not levelDef then
		return false, "max"
	end
	if profile.Cash < levelDef.cost then
		return false, "cash"
	end
	profile.Cash -= levelDef.cost
	profile.DefenseLevel = nextLevel
	if ctx.Defense then
		ctx.Defense:Build(player)
	end
	ctx.Data:Push(player)
	ctx.Data:Save(player)
	return true
end

function UpgradeManager.Init(_, context)
	ctx = context

	ctx.Remotes:OnFunction(RemoteNames.Functions.BuyUpgrade, function(player, kind)
		if type(kind) ~= "string" then
			return false, "bad_kind"
		end
		return UpgradeManager:BuyUpgrade(player, kind)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.BuySlot, function(player)
		return UpgradeManager:BuySlot(player)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.BuyDefense, function(player)
		return UpgradeManager:BuyDefense(player)
	end)

	-- Применять WalkSpeed при спавне персонажа.
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			UpgradeManager:ApplyWalkSpeed(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return UpgradeManager
