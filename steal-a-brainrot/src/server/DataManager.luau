--!strict
--[[
	DataManager (ModuleScript)
	Расположение: ServerScriptService.Server.DataManager

	Профили игроков в DataStore с session-lock (защита от дюпа при переходах между
	серверами) — аккуратная обёртка над DataStoreService с блокировками (§8, §10).

	Схема профиля (§9):
	{
		Cash, TotalEarned, Bank,
		Brainrots = { {uid, id, podium=number?}, ... },  -- podium=nil → в инвентаре
		Upgrades  = { IncomeMult, WalkSpeed, CollectSpeed },  -- номера уровней
		DefenseLevel = number,
		Passes = { VIP, DoubleIncome, AutoCollect },
		NextUid = number,
	}
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))

local DataManager = {}

export type Profile = {
	Cash: number,
	TotalEarned: number,
	Bank: number,
	Brainrots: { { uid: string, id: string, podium: number? } },
	Upgrades: { IncomeMult: number, WalkSpeed: number, CollectSpeed: number },
	Slots: number,
	DefenseLevel: number,
	Passes: { VIP: boolean, DoubleIncome: boolean, AutoCollect: boolean },
	NextUid: number,
}

local ctx: any
local store = DataStoreService:GetDataStore(Config.DataStore.Name)
local JOB_ID = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.time()))

-- Загруженные профили в этой сессии.
local profiles: { [Player]: Profile } = {}
-- Игроки, для которых загрузка ещё идёт / провалилась.
local loading: { [Player]: boolean } = {}
-- Профили с несохранёнными изменениями (дебаунс записей в DataStore).
local dirty: { [Player]: boolean } = {}

local function defaultProfile(): Profile
	return {
		Cash = Config.StartingCash,
		TotalEarned = 0,
		Bank = 0,
		Brainrots = {},
		Upgrades = { IncomeMult = 1, WalkSpeed = 1, CollectSpeed = 1 },
		Slots = Config.StartingSlots,
		DefenseLevel = 1,
		Passes = { VIP = false, DoubleIncome = false, AutoCollect = false },
		NextUid = 1,
	}
end

-- Гарантирует наличие всех полей (миграция при добавлении новых полей в конфиг).
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if type(data) ~= "table" then
		return base
	end
	for key, value in base :: any do
		if data[key] == nil then
			data[key] = value
		end
	end
	-- Вложенные таблицы уровней/пассов.
	for key, value in base.Upgrades do
		if data.Upgrades[key] == nil then
			data.Upgrades[key] = value
		end
	end
	for key, value in base.Passes do
		if data.Passes[key] == nil then
			data.Passes[key] = value
		end
	end
	return data :: Profile
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- ─── Session lock через UpdateAsync ───────────────────────────────────────
-- Запись в DataStore: { lock = { jobId, ts } | nil, data = Profile }

-- Пытается захватить лок и вернуть данные. Возвращает (ok, dataOrReason).
local function tryAcquire(player: Player): (boolean, any)
	local key = keyFor(player)
	local acquired = false
	local resultData: any = nil

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			old = old or { lock = nil, data = nil }
			local lock = old.lock
			local now = os.time()

			-- Лок занят другим сервером и ещё свежий → отказ (не трогаем запись).
			if lock and lock.jobId ~= JOB_ID and (now - lock.ts) < Config.DataStore.SessionLockStale then
				acquired = false
				return nil -- отмена записи
			end

			-- Свободно или протух или наш → захватываем.
			old.lock = { jobId = JOB_ID, ts = now }
			acquired = true
			resultData = old.data
			return old
		end)
	end)

	if not ok then
		return false, err
	end
	if not acquired then
		return false, "locked"
	end
	return true, resultData
end

-- Обновляет timestamp лока (heartbeat), чтобы он не «протух» в долгой сессии.
local function refreshLock(player: Player)
	local key = keyFor(player)
	pcall(function()
		store:UpdateAsync(key, function(old)
			if not old then
				return nil
			end
			if old.lock and old.lock.jobId == JOB_ID then
				old.lock.ts = os.time()
				return old
			end
			return nil
		end)
	end)
end

-- Сохраняет данные. release=true → снимает лок.
local function commit(player: Player, release: boolean): boolean
	local key = keyFor(player)
	local data = profiles[player]
	if not data then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			old = old or {}
			-- Пишем только если лок наш (иначе не перетираем чужую сессию).
			if old.lock and old.lock.jobId ~= JOB_ID and (os.time() - old.lock.ts) < Config.DataStore.SessionLockStale then
				return nil
			end
			old.data = data
			old.lock = release and nil or { jobId = JOB_ID, ts = os.time() }
			return old
		end)
	end)
	if ok then
		dirty[player] = nil -- изменения записаны
	else
		warn(("[DataManager] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

-- ─── Публичный API ────────────────────────────────────────────────────────

function DataManager.Init(_, context)
	ctx = context

	Players.PlayerAdded:Connect(function(player)
		DataManager:Load(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		DataManager:Release(player)
	end)
	-- Игроки, успевшие зайти до подключения обработчика (актуально для Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			DataManager:Load(player)
		end)
	end

	-- Автосейв всех загруженных профилей.
	task.spawn(function()
		while true do
			task.wait(Config.DataStore.AutosaveInterval)
			for player in profiles do
				commit(player, false)
			end
		end
	end)

	-- Флаш «грязных» профилей: покупки/апгрейды помечают профиль грязным, а пишутся
	-- дебаунсом (не чаще раза в DirtyFlushInterval на ключ) — против троттлинга DataStore.
	task.spawn(function()
		while true do
			task.wait(Config.DataStore.DirtyFlushInterval)
			for player in dirty do
				if profiles[player] then
					commit(player, false) -- очистит флаг при успехе
				else
					dirty[player] = nil
				end
			end
		end
	end)

	-- Heartbeat локов.
	task.spawn(function()
		while true do
			task.wait(Config.DataStore.LockRefreshInterval)
			for player in profiles do
				refreshLock(player)
			end
		end
	end)

	-- Финальный сейв всех при закрытии сервера.
	game:BindToClose(function()
		for player in profiles do
			commit(player, true)
		end
		if not RunService:IsStudio() then
			task.wait(2)
		end
	end)
end

function DataManager.Load(_, player: Player)
	loading[player] = true

	for attempt = 1, Config.DataStore.MaxLoadRetries do
		if not player.Parent then
			loading[player] = nil
			return
		end
		local ok, data = tryAcquire(player)
		if ok then
			profiles[player] = reconcile(data)
			loading[player] = nil
			DataManager:Push(player)
			-- Плот и рендер поднимает PlotManager после загрузки.
			if ctx.Plots then
				ctx.Plots:Assign(player)
			end
			return
		end

		if data == "locked" then
			-- Возможно, старая сессия ещё держит лок; ждём и пробуем снова.
			warn(("[DataManager] %s profile locked, retry %d"):format(player.Name, attempt))
			task.wait(6)
		else
			warn(("[DataManager] load error %s: %s"):format(player.Name, tostring(data)))
			task.wait(4)
		end
	end

	-- Не смогли захватить лок — кикаем, чтобы не потерять/задублировать данные.
	loading[player] = nil
	if player.Parent then
		player:Kick("Не удалось загрузить профиль (данные заняты другой сессией). Зайдите снова.")
	end
end

function DataManager.Release(_, player: Player)
	if ctx.Plots then
		ctx.Plots:Free(player)
	end
	if profiles[player] then
		commit(player, true)
		profiles[player] = nil
	end
	loading[player] = nil
	dirty[player] = nil
	if ctx.RateLimiter then
		ctx.RateLimiter:Clear(player)
	end
end

function DataManager.Get(_, player: Player): Profile?
	return profiles[player]
end

function DataManager.IsLoaded(_, player: Player): boolean
	return profiles[player] ~= nil
end

-- Немедленный сейв (для критичных событий — кража/потеря брейнрота — §8).
function DataManager.Save(_, player: Player)
	commit(player, false)
end

-- Пометить профиль изменённым: запись отложится до ближайшего флаша (дебаунс).
-- Использовать для частых некритичных действий (покупки, апгрейды, расстановка).
function DataManager.MarkDirty(_, player: Player)
	if profiles[player] then
		dirty[player] = true
	end
end

-- Отправляет клиенту снимок ЕГО профиля (не чужие данные — §10).
function DataManager.Push(_, player: Player)
	local p = profiles[player]
	if not p or not ctx.Remotes then
		return
	end
	ctx.Remotes:FireClient(RemoteNames.Events.ProfileUpdated, player, {
		Cash = p.Cash,
		TotalEarned = p.TotalEarned,
		Bank = p.Bank,
		Brainrots = p.Brainrots,
		Upgrades = p.Upgrades,
		Slots = p.Slots,
		DefenseLevel = p.DefenseLevel,
		Passes = p.Passes,
	})
end

-- Генерирует новый уникальный uid брейнрота внутри профиля.
function DataManager.NextUid(_, player: Player): string
	local p = profiles[player]
	assert(p, "profile not loaded")
	local uid = "b" .. tostring(p.NextUid)
	p.NextUid += 1
	return uid
end

return DataManager
