--!strict
--[[
	Config (ModuleScript)
	Расположение: ReplicatedStorage.Modules.Config

	Единый источник баланса игры. Все числа — стартовые, правятся здесь.
	Модуль читают и сервер, и клиент (клиент — только для отрисовки, не для логики).
]]

local Config = {}

-- ─────────────────────────────────────────────────────────────────────────
-- РЕДКОСТИ (§4.2)
-- incomeMult / priceMult — относительные множители от базовой единицы (Common = ×1).
-- color — цвет болванки и рамок в UI.
-- ─────────────────────────────────────────────────────────────────────────
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

Config.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" } :: { Rarity }

Config.Rarities = {
	Common = { color = Color3.fromRGB(160, 160, 160), incomeMult = 1, priceMult = 1 },
	Rare = { color = Color3.fromRGB(60, 120, 240), incomeMult = 3, priceMult = 4 },
	Epic = { color = Color3.fromRGB(150, 70, 230), incomeMult = 8, priceMult = 12 },
	Legendary = { color = Color3.fromRGB(240, 190, 40), incomeMult = 20, priceMult = 35 },
	Mythic = { color = Color3.fromRGB(230, 50, 50), incomeMult = 50, priceMult = 100 },
	Secret = { color = Color3.fromRGB(20, 20, 20), incomeMult = 150, priceMult = 400 },
}

-- Базовая единица (Common). Итог = base * rarityMult, но в каталоге значения заданы явно
-- для читаемого баланса. Эти константы — ориентир при добавлении новых юнитов.
Config.BaseUnitPrice = 50
Config.BaseUnitIncome = 1 -- в секунду

-- Порог суммарного заработка (TotalEarned) для разблокировки редкости в магазине (§4.3).
Config.RarityUnlockAtTotalEarned = {
	Common = 0,
	Rare = 500,
	Epic = 5000,
	Legendary = 50000,
	Mythic = 500000,
	Secret = 5000000,
}

-- ─────────────────────────────────────────────────────────────────────────
-- КАТАЛОГ БРЕЙНРОТОВ (§4.1, §4.3)
-- Фиксированный список. price / income заданы явно, следуют пропорциям редкости.
-- model = nil → используется процедурная болванка (§4.1). Позже сюда кладут имя модели из Assets.
-- ─────────────────────────────────────────────────────────────────────────
export type BrainrotDef = {
	id: string,
	name: string,
	rarity: Rarity,
	price: number,
	income: number, -- в секунду
	model: string?,
}

Config.Brainrots = {
	-- Common (×1 / ×1)
	{ id = "cmn_tung", name = "Tung Tung", rarity = "Common", price = 50, income = 1 },
	{ id = "cmn_skibi", name = "Skibi Toilet", rarity = "Common", price = 80, income = 1.5 },
	-- Rare (×3 / ×4)
	{ id = "rar_bombardino", name = "Bombardino", rarity = "Rare", price = 200, income = 3 },
	{ id = "rar_trippi", name = "Trippi Troppi", rarity = "Rare", price = 320, income = 4.5 },
	-- Epic (×8 / ×12)
	{ id = "epc_tralalero", name = "Tralalero", rarity = "Epic", price = 600, income = 8 },
	{ id = "epc_lirili", name = "Lirili Larila", rarity = "Epic", price = 900, income = 12 },
	-- Legendary (×20 / ×35)
	{ id = "lgd_bruritos", name = "Bruritos", rarity = "Legendary", price = 1750, income = 20 },
	{ id = "lgd_glorbo", name = "Glorbo", rarity = "Legendary", price = 2600, income = 30 },
	-- Mythic (×50 / ×100)
	{ id = "myt_chimpanzini", name = "Chimpanzini", rarity = "Mythic", price = 5000, income = 50 },
	{ id = "myt_bananita", name = "Ballerina Bananita", rarity = "Mythic", price = 8000, income = 80 },
	-- Secret (×150 / ×400)
	{ id = "scr_garamararam", name = "Garamararam", rarity = "Secret", price = 20000, income = 150 },
	{ id = "scr_orcalero", name = "Orcalero Orcala", rarity = "Secret", price = 45000, income = 320 },
} :: { BrainrotDef }

-- Быстрый доступ по id (заполняется ниже).
Config.BrainrotById = {} :: { [string]: BrainrotDef }
for _, def in Config.Brainrots do
	Config.BrainrotById[def.id] = def
end

-- ─────────────────────────────────────────────────────────────────────────
-- ЭКОНОМИКА (§4.4)
-- ─────────────────────────────────────────────────────────────────────────
Config.StartingCash = 100
Config.IncomeTickInterval = 1 -- сек; один общий серверный тик на всех (§9)
Config.AccumulationCapSeconds = 30 * 60 -- кап кассы = 30 минут дохода

-- ─────────────────────────────────────────────────────────────────────────
-- ПОДИУМЫ И СЛОТЫ (§7)
-- ─────────────────────────────────────────────────────────────────────────
Config.StartingSlots = 3
Config.MaxSlots = 10
-- Цена докупки слота: base * growth^(куплено сверх стартовых).
Config.SlotBaseCost = 500
Config.SlotCostGrowth = 2.2

-- ─────────────────────────────────────────────────────────────────────────
-- АПГРЕЙДЫ ЗА ВАЛЮТУ (§7)
-- Каждый уровень: множитель эффекта + цена. Уровень 0 = стартовое состояние.
-- ─────────────────────────────────────────────────────────────────────────
Config.Upgrades = {
	-- Множитель дохода базы.
	IncomeMult = {
		levels = {
			{ value = 1.0, cost = 0 }, -- lvl 0 (стартовый)
			{ value = 1.25, cost = 1000 },
			{ value = 1.6, cost = 5000 },
			{ value = 2.0, cost = 20000 },
			{ value = 2.75, cost = 80000 },
			{ value = 4.0, cost = 300000 },
		},
	},
	-- Скорость бега (WalkSpeed).
	WalkSpeed = {
		levels = {
			{ value = 16, cost = 0 },
			{ value = 20, cost = 750 },
			{ value = 24, cost = 4000 },
			{ value = 28, cost = 15000 },
		},
	},
	-- Скорость сбора: множитель к сумме, забираемой за один тап кассы (мгновенный сбор всё равно весь,
	-- но апгрейд повышает кап-бонус — эффективный кап = base * value).
	CollectSpeed = {
		levels = {
			{ value = 1.0, cost = 0 },
			{ value = 1.3, cost = 2000 },
			{ value = 1.7, cost = 10000 },
		},
	},
}

-- ─────────────────────────────────────────────────────────────────────────
-- ЗАЩИТА БАЗЫ (§6)
-- Уровни защиты: высота/прочность забора, кулдаун неуязвимости, наличие оглушалки.
-- ─────────────────────────────────────────────────────────────────────────
Config.Defense = {
	levels = {
		{ fenceHeight = 0, robCooldown = 20, stunner = false, cost = 0 }, -- lvl 0
		{ fenceHeight = 4, robCooldown = 25, stunner = false, cost = 1500 }, -- забор
		{ fenceHeight = 7, robCooldown = 30, stunner = false, cost = 8000 }, -- высокий забор
		{ fenceHeight = 7, robCooldown = 35, stunner = true, cost = 40000 }, -- + оглушалка/лазер
	},
	-- Оглушалка: радиус зоны и длительность оглушения вора.
	StunnerRadius = 18,
	StunDuration = 3,
}

-- ─────────────────────────────────────────────────────────────────────────
-- МЕХАНИКА КРАЖИ (§5)
-- ─────────────────────────────────────────────────────────────────────────
Config.Steal = {
	CaptureSeconds = 4, -- удержание рядом для захвата
	CaptureRadius = 12, -- макс. дистанция до подиума во время захвата (studs)
	CarrySpeedMultiplier = 0.6, -- замедление во время переноса добычи
	DropReturnSeconds = 8, -- через сколько упавшая добыча вернётся владельцу
	DepositRadius = 14, -- дистанция до своего свободного подиума для авто-сдачи
}

-- ─────────────────────────────────────────────────────────────────────────
-- ГЕЙМПАССЫ (§7). ID — заглушки, заменить на реальные из Roblox Creator Dashboard.
-- ─────────────────────────────────────────────────────────────────────────
Config.Gamepasses = {
	VIP = { id = 0, incomeBonus = 0.25, label = "VIP" }, -- +25% дохода + метка/косметика
	DoubleIncome = { id = 0, multiplier = 2, label = "×2 доход" },
	AutoCollect = { id = 0, label = "Авто-сбор" }, -- касса капает сразу в баланс
}

-- ─────────────────────────────────────────────────────────────────────────
-- КАРТА / ПЛОТЫ (§3)
-- ─────────────────────────────────────────────────────────────────────────
Config.MaxPlayers = 8
Config.Plot = {
	Size = Vector3.new(48, 1, 40), -- размер плиты базы
	Spacing = 64, -- расстояние между базами по оси X
	Origin = Vector3.new(0, 0.5, 0), -- центр первой базы
	BaseColor = Color3.fromRGB(70, 90, 70),
}

-- ─────────────────────────────────────────────────────────────────────────
-- АНТИЧИТ / RATE-LIMIT (§10)
-- Макс. вызовов конкретного remote в секунду на игрока.
-- ─────────────────────────────────────────────────────────────────────────
Config.RateLimits = {
	Default = 10,
	BuyBrainrot = 4,
	BuyUpgrade = 4,
	CollectCash = 6,
	StartSteal = 3,
	PlaceBrainrot = 6,
}

-- ─────────────────────────────────────────────────────────────────────────
-- DATASTORE (§8)
-- ─────────────────────────────────────────────────────────────────────────
Config.DataStore = {
	Name = "PlayerProfiles_v1",
	AutosaveInterval = 120, -- автосейв каждые N секунд
	SessionLockStale = 60, -- лок считается «протухшим» через N секунд без обновления
	LockRefreshInterval = 30, -- обновление heartbeat лока
	MaxLoadRetries = 5,
}

return Config
