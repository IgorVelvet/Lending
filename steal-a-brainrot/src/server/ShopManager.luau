--!strict
--[[
	ShopManager (ModuleScript)
	Расположение: ServerScriptService.Server.ShopManager

	Магазин-каталог с анлоками редкостей по прогрессу (§4.3), покупка брейнрота,
	расстановка/снятие юнитов с подиумов (инвентарь). Валидация на сервере (§10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))

local ShopManager = {}
local ctx: any

local function rarityUnlocked(profile: any, rarity: string): boolean
	return profile.TotalEarned >= (Config.RarityUnlockAtTotalEarned[rarity] or 0)
end

-- Найти запись брейнрота по uid.
local function findEntry(profile: any, uid: string)
	for _, entry in profile.Brainrots do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

local function podiumOccupied(profile: any, index: number): boolean
	for _, entry in profile.Brainrots do
		if entry.podium == index then
			return true
		end
	end
	return false
end

-- ─── Покупка ──────────────────────────────────────────────────────────────

function ShopManager.Buy(_, player: Player, id: string): (boolean, string?)
	local profile = ctx.Data:Get(player)
	if not profile then
		return false, "no_profile"
	end
	local def = Config.BrainrotById[id]
	if not def then
		return false, "bad_id"
	end
	if not rarityUnlocked(profile, def.rarity) then
		return false, "locked"
	end
	if profile.Cash < def.price then
		return false, "cash"
	end

	profile.Cash -= def.price
	local uid = ctx.Data:NextUid(player)
	local podium = ctx.Plots:FirstFreePodium(player) -- авто-постановка на свободный подиум
	table.insert(profile.Brainrots, { uid = uid, id = id, podium = podium })

	ctx.Plots:Render(player)
	ctx.Data:Push(player)
	ctx.Data:Save(player)

	if not podium then
		ctx.Remotes:FireClient(RemoteNames.Events.Notification, player, {
			text = "Куплено. Нет свободного подиума — в инвентаре. Докупи слот или сними другого.",
			kind = "info",
		})
	end
	return true
end

-- ─── Расстановка ──────────────────────────────────────────────────────────

function ShopManager.Place(_, player: Player, uid: string, podiumIndex: number): (boolean, string?)
	local profile = ctx.Data:Get(player)
	if not profile then
		return false, "no_profile"
	end
	if type(uid) ~= "string" or type(podiumIndex) ~= "number" then
		return false, "bad_args"
	end
	local slots = ctx.Upgrades:GetSlotCount(player)
	if podiumIndex < 1 or podiumIndex > slots then
		return false, "bad_slot"
	end
	local entry = findEntry(profile, uid)
	if not entry then
		return false, "not_owned"
	end
	if podiumOccupied(profile, podiumIndex) then
		return false, "occupied"
	end
	entry.podium = podiumIndex
	ctx.Plots:Render(player)
	ctx.Data:Push(player)
	ctx.Data:Save(player)
	return true
end

function ShopManager.Remove(_, player: Player, podiumIndex: number): (boolean, string?)
	local profile = ctx.Data:Get(player)
	if not profile then
		return false, "no_profile"
	end
	if type(podiumIndex) ~= "number" then
		return false, "bad_args"
	end
	for _, entry in profile.Brainrots do
		if entry.podium == podiumIndex then
			entry.podium = nil
			ctx.Plots:Render(player)
			ctx.Data:Push(player)
			ctx.Data:Save(player)
			return true
		end
	end
	return false, "empty"
end

-- ─── Каталог ──────────────────────────────────────────────────────────────

function ShopManager.GetCatalog(_, player: Player)
	local profile = ctx.Data:Get(player)
	local list = {}
	for _, def in Config.Brainrots do
		table.insert(list, {
			id = def.id,
			name = def.name,
			rarity = def.rarity,
			price = def.price,
			income = def.income,
			unlocked = profile ~= nil and rarityUnlocked(profile, def.rarity),
			unlockAt = Config.RarityUnlockAtTotalEarned[def.rarity] or 0,
		})
	end
	return list
end

function ShopManager.Init(_, context)
	ctx = context

	ctx.Remotes:OnFunction(RemoteNames.Functions.BuyBrainrot, function(player, id)
		if type(id) ~= "string" then
			return false, "bad_id"
		end
		return ShopManager:Buy(player, id)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.PlaceBrainrot, function(player, uid, podiumIndex)
		return ShopManager:Place(player, uid, podiumIndex)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.RemoveBrainrot, function(player, podiumIndex)
		return ShopManager:Remove(player, podiumIndex)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.GetCatalog, function(player)
		return true, ShopManager:GetCatalog(player)
	end)
	ctx.Remotes:OnFunction(RemoteNames.Functions.RefreshPasses, function(player)
		ctx.Gamepass:Refresh(player)
		return true
	end)
end

return ShopManager
