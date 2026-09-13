--!strict
--[[
	Server bootstrap (Script)
	Расположение: ServerScriptService.Server  (этот файл делает контейнер Script'ом)

	Точка входа сервера. Собирает контекст (ctx) со ссылками на все менеджеры и
	инициализирует их в порядке зависимостей. Менеджеры общаются только через ctx —
	это исключает циклические require (§9).

	Дочерние ModuleScript'ы этого скрипта:
		RateLimiter, RemoteManager, DataManager, PlotManager, GamepassManager,
		UpgradeManager, EconomyManager, DefenseManager, ShopManager, StealManager
]]

local RateLimiter = require(script.RateLimiter)
local RemoteManager = require(script.RemoteManager)
local DataManager = require(script.DataManager)
local PlotManager = require(script.PlotManager)
local GamepassManager = require(script.GamepassManager)
local UpgradeManager = require(script.UpgradeManager)
local EconomyManager = require(script.EconomyManager)
local DefenseManager = require(script.DefenseManager)
local ShopManager = require(script.ShopManager)
local StealManager = require(script.StealManager)

-- Общий контекст. Заполняется полностью ДО вызова Init, чтобы обработчики,
-- захватывающие ctx, видели все менеджеры.
local ctx = {
	RateLimiter = RateLimiter,
	Remotes = RemoteManager,
	Data = DataManager,
	Plots = PlotManager,
	Gamepass = GamepassManager,
	Upgrades = UpgradeManager,
	Economy = EconomyManager,
	Defense = DefenseManager,
	Shop = ShopManager,
	Steal = StealManager,
}

-- Порядок: сначала remote-объекты и карта, затем логика, DataManager — последним
-- (он грузит игроков и выдаёт плоты, для чего всё остальное должно быть готово).
RemoteManager:Init(ctx)
PlotManager:Init(ctx)
GamepassManager:Init(ctx)
UpgradeManager:Init(ctx)
EconomyManager:Init(ctx)
DefenseManager:Init(ctx)
ShopManager:Init(ctx)
StealManager:Init(ctx)
DataManager:Init(ctx)

print("[StealABrainrot] Server initialized.")
