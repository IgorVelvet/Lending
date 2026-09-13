--!strict
--[[
	StealManager (ModuleScript)
	Расположение: ServerScriptService.Server.StealManager

	Механика кражи (§5). Всё серверно: сервер проверяет дистанцию, время удержания,
	свободный слот вора, право владения. Клиент только рисует прогресс (§5, §10).

	Этапы: захват по таймеру у чужого занятого подиума → перенос (медленно, уязвим) →
	сдача на свой свободный подиум. Оглушение в зоне защиты роняет добычу (§6).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))

local StealManager = {}
local ctx: any

type Capture = { targetUserId: number, podiumIndex: number, uid: string, startClock: number }
type Carry = { ownerUserId: number, uid: string, id: string }

local captures: { [Player]: Capture } = {}
local carrying: { [Player]: Carry } = {}
local stunnedUntil: { [Player]: number } = {}

-- ─── Утилиты ──────────────────────────────────────────────────────────────

local function getHRP(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart or nil
end

local function dist(a: Vector3, b: Vector3): number
	return (a - b).Magnitude
end

local function findEntry(profile: any, uid: string)
	for _, entry in profile.Brainrots do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

function StealManager.IsCarrying(_, player: Player): boolean
	return carrying[player] ~= nil
end

local function setProgress(player: Player, active: boolean, progress: number, targetName: string?)
	ctx.Remotes:FireClient(RemoteNames.Events.StealProgress, player, {
		active = active,
		progress = progress,
		targetName = targetName or "",
	})
end

local function setCarryState(player: Player, carryData: Carry?)
	local name = ""
	if carryData then
		local def = Config.BrainrotById[carryData.id]
		name = def and def.name or "?"
	end
	ctx.Remotes:FireClient(RemoteNames.Events.CarryStateChanged, player, {
		carrying = carryData ~= nil,
		brainrotName = name,
	})
end

-- ─── Старт/стоп захвата (client->server) ──────────────────────────────────

function StealManager.Start(_, robber: Player, targetUserId: number, podiumIndex: number)
	if type(targetUserId) ~= "number" or type(podiumIndex) ~= "number" then
		return
	end
	if carrying[robber] or captures[robber] then
		return
	end
	if stunnedUntil[robber] and os.clock() < stunnedUntil[robber] then
		return
	end
	if robber.UserId == targetUserId then
		return -- нельзя красть у себя
	end

	local targetPlot = ctx.Plots:GetByOwnerUserId(targetUserId)
	if not targetPlot or not targetPlot.owner then
		return
	end
	if ctx.Plots:IsOnRobCooldown(targetPlot) then
		ctx.Remotes:FireClient(RemoteNames.Events.Notification, robber, {
			text = "База под защитой (кулдаун). Попробуй позже.",
			kind = "warn",
		})
		return
	end

	local targetProfile = ctx.Data:Get(targetPlot.owner)
	if not targetProfile then
		return
	end
	local podium = targetPlot.podiums[podiumIndex]
	if not podium or not podium.occupantUid then
		return -- подиум пуст
	end
	-- Вору нужен свободный слот (§5, §10).
	if not ctx.Plots:FirstFreePodium(robber) then
		ctx.Remotes:FireClient(RemoteNames.Events.Notification, robber, {
			text = "Нет свободного подиума под добычу.",
			kind = "warn",
		})
		return
	end

	-- Дистанция.
	local hrp = getHRP(robber)
	if not hrp or dist(hrp.Position, podium.part.Position) > Config.Steal.CaptureRadius then
		return
	end

	captures[robber] = {
		targetUserId = targetUserId,
		podiumIndex = podiumIndex,
		uid = podium.occupantUid,
		startClock = os.clock(),
	}
end

function StealManager.Stop(_, robber: Player)
	-- Отменяет только незавершённый захват. Уже поднятую добычу отпускание кнопки
	-- НЕ роняет (§5): её роняет лишь оглушение защитой или выход из игры, а доносится
	-- она авто-сдачей на своём подиуме.
	if captures[robber] then
		captures[robber] = nil
		setProgress(robber, false, 0)
	end
end

-- ─── Завершение захвата ────────────────────────────────────────────────────

local function completeCapture(robber: Player, cap: Capture)
	local targetPlot = ctx.Plots:GetByOwnerUserId(cap.targetUserId)
	if not targetPlot or not targetPlot.owner then
		return
	end
	local owner = targetPlot.owner
	local ownerProfile = ctx.Data:Get(owner)
	if not ownerProfile then
		return
	end
	local entry = findEntry(ownerProfile, cap.uid)
	if not entry or entry.podium ~= cap.podiumIndex then
		return -- уже украли/сняли
	end

	-- Снимаем у владельца.
	local id = entry.id
	for i, e in ownerProfile.Brainrots do
		if e.uid == cap.uid then
			table.remove(ownerProfile.Brainrots, i)
			break
		end
	end
	ctx.Plots:Render(owner)
	ctx.Data:Push(owner)
	ctx.Data:Save(owner)

	-- Кулдаун неуязвимости базы после кражи (§6).
	ctx.Plots:SetRobCooldown(targetPlot, ctx.Defense:RobCooldownSeconds(owner))

	-- Вор берёт добычу.
	carrying[robber] = { ownerUserId = cap.targetUserId, uid = cap.uid, id = id }
	setCarryState(robber, carrying[robber])
	setProgress(robber, false, 0)
	ctx.Upgrades:ApplyWalkSpeed(robber) -- применит замедление переноса

	-- Уведомление владельцу (§6).
	ctx.Remotes:FireClient(RemoteNames.Events.RobAlert, owner, { robberName = robber.Name })
	ctx.Remotes:FireClient(RemoteNames.Events.Notification, owner, {
		text = ("%s ворует твоего брейнрота! Беги защищать."):format(robber.Name),
		kind = "alert",
	})
end

-- ─── Сдача добычи на свою базу ─────────────────────────────────────────────

local function deposit(robber: Player, carry: Carry)
	local profile = ctx.Data:Get(robber)
	if not profile then
		return
	end
	local podiumIndex = ctx.Plots:FirstFreePodium(robber)
	if not podiumIndex then
		return -- некуда, продолжает нести
	end
	local uid = ctx.Data:NextUid(robber)
	table.insert(profile.Brainrots, { uid = uid, id = carry.id, podium = podiumIndex })

	carrying[robber] = nil
	setCarryState(robber, nil)
	ctx.Upgrades:ApplyWalkSpeed(robber)
	ctx.Plots:Render(robber)
	ctx.Data:Push(robber)
	ctx.Data:Save(robber)

	local def = Config.BrainrotById[carry.id]
	ctx.Remotes:FireClient(RemoteNames.Events.Notification, robber, {
		text = ("Добыча доставлена: %s!"):format(def and def.name or "?"),
		kind = "success",
	})
end

-- ─── Дроп добычи (оглушён/отменил/вышел) ───────────────────────────────────

function StealManager.Drop(_, robber: Player)
	local carry = carrying[robber]
	if not carry then
		return
	end
	carrying[robber] = nil
	setCarryState(robber, nil)
	if robber.Parent then
		ctx.Upgrades:ApplyWalkSpeed(robber)
		ctx.Remotes:FireClient(RemoteNames.Events.Notification, robber, {
			text = "Ты выронил добычу!",
			kind = "warn",
		})
	end

	-- Через таймаут возвращаем владельцу (§5), если он ещё в сессии.
	task.delay(Config.Steal.DropReturnSeconds, function()
		for _, p in Players:GetPlayers() do
			if p.UserId == carry.ownerUserId then
				local profile = ctx.Data:Get(p)
				if profile then
					local podium = ctx.Plots:FirstFreePodium(p)
					local uid = ctx.Data:NextUid(p)
					table.insert(profile.Brainrots, { uid = uid, id = carry.id, podium = podium })
					ctx.Plots:Render(p)
					ctx.Data:Push(p)
					ctx.Data:Save(p)
					ctx.Remotes:FireClient(RemoteNames.Events.Notification, p, {
						text = "Украденный брейнрот вернулся к тебе.",
						kind = "info",
					})
				end
				return
			end
		end
		-- Владелец офлайн → добыча теряется (база освобождена, возвращать некуда).
	end)
end

-- ─── Оглушение вора в зоне защиты (§6) ─────────────────────────────────────

local function stun(robber: Player)
	stunnedUntil[robber] = os.clock() + Config.Defense.StunDuration
	StealManager:Drop(robber)
	local char = robber.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
	ctx.Remotes:FireClient(RemoteNames.Events.Notification, robber, {
		text = "Тебя оглушила защита базы!",
		kind = "alert",
	})
	task.delay(Config.Defense.StunDuration, function()
		stunnedUntil[robber] = nil
		if robber.Parent then
			ctx.Upgrades:ApplyWalkSpeed(robber)
			local h = robber.Character and robber.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h.JumpPower = 50
				h.JumpHeight = 7.2
			end
		end
	end)
end

-- ─── Главный цикл ──────────────────────────────────────────────────────────

local function tick()
	-- Захваты.
	for robber, cap in captures do
		if not robber.Parent then
			captures[robber] = nil
			continue
		end
		local targetPlot = ctx.Plots:GetByOwnerUserId(cap.targetUserId)
		local hrp = getHRP(robber)
		local podium = targetPlot and targetPlot.podiums[cap.podiumIndex]
		local valid = targetPlot ~= nil
			and targetPlot.owner ~= nil
			and podium ~= nil
			and podium.occupantUid == cap.uid
			and hrp ~= nil
			and dist(hrp.Position, podium.part.Position) <= Config.Steal.CaptureRadius
			and not carrying[robber]
			and ctx.Plots:FirstFreePodium(robber) ~= nil
			and not ctx.Plots:IsOnRobCooldown(targetPlot)

		if not valid then
			captures[robber] = nil
			setProgress(robber, false, 0)
			continue
		end

		local progress = (os.clock() - cap.startClock) / Config.Steal.CaptureSeconds
		if progress >= 1 then
			captures[robber] = nil
			completeCapture(robber, cap)
		else
			local ownerName = targetPlot.owner and targetPlot.owner.Name or ""
			setProgress(robber, true, progress, ownerName)
		end
	end

	-- Несущие: оглушение в чужих зонах + сдача на свою базу.
	for robber, carry in carrying do
		if not robber.Parent then
			carrying[robber] = nil
			continue
		end
		local hrp = getHRP(robber)
		if not hrp then
			continue
		end

		-- Оглушалки чужих баз.
		local stunned = false
		for _, plot in ctx.Plots:All() do
			if plot.owner and plot.owner ~= robber and ctx.Defense:HasStunner(plot.owner) then
				if dist(hrp.Position, plot.base.Position) <= Config.Defense.StunnerRadius then
					stun(robber)
					stunned = true
					break
				end
			end
		end
		if stunned then
			continue
		end

		-- Сдача на свой свободный подиум.
		local myPlot = ctx.Plots:GetByOwner(robber)
		if myPlot then
			local freeIdx = ctx.Plots:FirstFreePodium(robber)
			if freeIdx then
				local podPos = ctx.Plots:GetPodiumPosition(myPlot, freeIdx)
				if dist(hrp.Position, podPos) <= Config.Steal.DepositRadius then
					deposit(robber, carry)
				end
			end
		end
	end
end

function StealManager.Init(_, context)
	ctx = context

	ctx.Remotes:OnEvent(RemoteNames.Events.StartSteal, function(player, targetUserId, podiumIndex)
		StealManager:Start(player, targetUserId, podiumIndex)
	end)
	ctx.Remotes:OnEvent(RemoteNames.Events.StopSteal, function(player)
		StealManager:Stop(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		captures[player] = nil
		if carrying[player] then
			StealManager:Drop(player)
		end
		stunnedUntil[player] = nil
	end)

	RunService.Heartbeat:Connect(tick)
end

return StealManager
