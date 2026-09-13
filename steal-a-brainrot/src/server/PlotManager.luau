--!strict
--[[
	PlotManager (ModuleScript)
	Расположение: ServerScriptService.Server.PlotManager

	Строит карту и приватные плоты (§3), выдаёт/освобождает базы, рендерит подиумы,
	кассу, брейнротов-болванок (§4.1). Геометрия создаётся процедурно, чтобы код был
	самодостаточным (без ручной сборки в Studio).

	Атрибуты для клиента (реплицируются, не содержат экономической логики):
		Podium part: PlotOwnerUserId (number), PodiumIndex (number), OccupantUid (string),
		             OccupantName (string), Active (bool)
		Plot model:  OwnerUserId (number)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))

local PlotManager = {}

type Podium = { part: Part, index: number, occupantUid: string?, model: Instance? }
type Plot = {
	index: number,
	model: Model,
	base: Part,
	spawn: Part,
	register: Part,
	podiums: { Podium },
	fenceFolder: Folder,
	owner: Player?,
	robCooldownUntil: number,
}

local ctx: any
local plots: { Plot } = {}
local plotByOwner: { [Player]: Plot } = {}

-- ─── Хелперы построения ────────────────────────────────────────────────────

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function makeLabel(parent: Instance, text: string, color: Color3): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = bb
	return bb
end

-- Локальные смещения подиумов внутри плота (2 ряда по 5).
local PODIUM_OFFSETS: { Vector3 } = {}
do
	local cols = { -16, -8, 0, 8, 16 }
	local rows = { -8, 8 }
	for _, z in rows do
		for _, x in cols do
			table.insert(PODIUM_OFFSETS, Vector3.new(x, 1.5, z))
		end
	end
end

local function buildPlot(index: number): Plot
	local centerX = Config.Plot.Origin.X + index * Config.Plot.Spacing
	local plotCF = CFrame.new(centerX, 0, 0)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("OwnerUserId", 0)

	-- Плита базы.
	local base = makePart({
		Name = "Base",
		Size = Config.Plot.Size,
		Color = Config.Plot.BaseColor,
		Material = Enum.Material.Grass,
		CFrame = plotCF * CFrame.new(0, 0, 0),
	})
	base.Parent = model

	-- Точка спавна владельца (сзади).
	local spawnPart = makePart({
		Name = "SpawnPad",
		Size = Vector3.new(6, 1, 6),
		Color = Color3.fromRGB(90, 110, 90),
		Material = Enum.Material.SmoothPlastic,
		CFrame = plotCF * CFrame.new(0, 1, -18),
	})
	spawnPart.Parent = model

	-- Касса (Register) — тап для сбора (§4.4).
	local register = makePart({
		Name = "Register",
		Size = Vector3.new(6, 5, 4),
		Color = Color3.fromRGB(220, 180, 40),
		Material = Enum.Material.Neon,
		CFrame = plotCF * CFrame.new(0, 3, 18),
	})
	register.Parent = model
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 24
	click.Parent = register
	makeLabel(register, "КАССА: $0", Color3.fromRGB(255, 255, 255))
	register:SetAttribute("PlotIndex", index)

	-- Подиумы.
	local podiums: { Podium } = {}
	for i = 1, Config.MaxSlots do
		local offset = PODIUM_OFFSETS[i]
		local part = makePart({
			Name = "Podium_" .. i,
			Size = Vector3.new(5, 1, 5),
			Color = Color3.fromRGB(120, 120, 130),
			Material = Enum.Material.Metal,
			CFrame = plotCF * CFrame.new(offset),
		})
		part:SetAttribute("PlotOwnerUserId", 0)
		part:SetAttribute("PodiumIndex", i)
		part:SetAttribute("OccupantUid", "")
		part:SetAttribute("OccupantName", "")
		part:SetAttribute("Active", i <= Config.StartingSlots)
		part.Transparency = i <= Config.StartingSlots and 0 or 0.6
		part.Parent = model
		podiums[i] = { part = part, index = i, occupantUid = nil, model = nil }
	end

	local fenceFolder = Instance.new("Folder")
	fenceFolder.Name = "Fences"
	fenceFolder.Parent = model

	model.PrimaryPart = base
	model.Parent = workspace

	return {
		index = index,
		model = model,
		base = base,
		spawn = spawnPart,
		register = register,
		podiums = podiums,
		fenceFolder = fenceFolder,
		owner = nil,
		robCooldownUntil = 0,
	}
end

-- ─── Рендер брейнрота-болванки (§4.1) ──────────────────────────────────────

local function renderBrainrot(plot: Plot, podiumIndex: number, def: any, uid: string)
	local podium = plot.podiums[podiumIndex]
	if podium.model then
		podium.model:Destroy()
		podium.model = nil
	end

	local rarity = Config.Rarities[def.rarity]
	local body = makePart({
		Name = "Brainrot",
		Size = Vector3.new(3, 4, 3),
		Color = rarity.color,
		Material = def.rarity == "Secret" and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		CFrame = podium.part.CFrame * CFrame.new(0, 3, 0),
		Anchored = true,
		CanCollide = false,
	})
	makeLabel(body, ("%s [%s]"):format(def.name, def.rarity), rarity.color)
	body:SetAttribute("Uid", uid)
	body:SetAttribute("BrainrotId", def.id)
	body.Parent = plot.model

	podium.model = body
	podium.occupantUid = uid
	podium.part:SetAttribute("OccupantUid", uid)
	podium.part:SetAttribute("OccupantName", def.name)
end

local function clearPodium(plot: Plot, podiumIndex: number)
	local podium = plot.podiums[podiumIndex]
	if podium.model then
		podium.model:Destroy()
		podium.model = nil
	end
	podium.occupantUid = nil
	podium.part:SetAttribute("OccupantUid", "")
	podium.part:SetAttribute("OccupantName", "")
end

-- Полный ре-рендер базы из профиля (после выдачи плота, кражи, покупки).
function PlotManager.Render(_, player: Player)
	local plot = plotByOwner[player]
	local profile = ctx.Data:Get(player)
	if not plot or not profile then
		return
	end

	-- Активность слотов по числу купленных слотов.
	local slots = PlotManager:GetSlotCount(player)
	for i = 1, Config.MaxSlots do
		local podium = plot.podiums[i]
		local active = i <= slots
		podium.part:SetAttribute("Active", active)
		podium.part.Transparency = active and 0 or 0.6
	end

	-- Очистить всё, затем разложить занятые.
	for i = 1, Config.MaxSlots do
		clearPodium(plot, i)
	end
	for _, entry in profile.Brainrots do
		if entry.podium then
			local def = Config.BrainrotById[entry.id]
			if def and entry.podium >= 1 and entry.podium <= slots then
				renderBrainrot(plot, entry.podium, def, entry.uid)
			end
		end
	end
end

-- ─── API ────────────────────────────────────────────────────────────────

function PlotManager.Init(_, context)
	ctx = context
	for i = 0, Config.MaxPlayers - 1 do
		plots[i + 1] = buildPlot(i)
	end

	-- Тап по кассе → сбор (§4.4). Валидируется на сервере в EconomyManager.
	for _, plot in plots do
		local click = plot.register:FindFirstChildOfClass("ClickDetector")
		if click then
			click.MouseClick:Connect(function(player: Player)
				if plot.owner == player then
					ctx.Economy:Collect(player)
				end
			end)
		end
	end
end

function PlotManager.Assign(_, player: Player): Plot?
	if plotByOwner[player] then
		return plotByOwner[player]
	end
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plot.robCooldownUntil = 0
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			for i = 1, Config.MaxSlots do
				plot.podiums[i].part:SetAttribute("PlotOwnerUserId", player.UserId)
			end
			plotByOwner[player] = plot

			-- Заборы по уровню защиты.
			if ctx.Defense then
				ctx.Defense:Build(player)
			end
			-- Рендер брейнротов.
			PlotManager:Render(player)
			-- Спавн игрока на своей базе.
			task.spawn(function()
				PlotManager:TeleportToBase(player)
			end)
			-- Сообщить клиенту индекс плота.
			ctx.Remotes:FireClient(RemoteNames.Events.PlotAssigned, player, plot.index)
			return plot
		end
	end
	warn("[PlotManager] нет свободных плотов для " .. player.Name)
	return nil
end

function PlotManager.Free(_, player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end
	for i = 1, Config.MaxSlots do
		clearPodium(plot, i)
		plot.podiums[i].part:SetAttribute("PlotOwnerUserId", 0)
	end
	if ctx.Defense then
		ctx.Defense:Clear(player)
	end
	plot.model:SetAttribute("OwnerUserId", 0)
	plot.owner = nil
	plot.robCooldownUntil = 0
	plotByOwner[player] = nil
end

function PlotManager.TeleportToBase(_, player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		(hrp :: BasePart).CFrame = plot.spawn.CFrame * CFrame.new(0, 4, 0)
	end
end

-- ─── Геттеры для других менеджеров ────────────────────────────────────────

function PlotManager.GetByOwner(_, player: Player): Plot?
	return plotByOwner[player]
end

function PlotManager.GetByOwnerUserId(_, userId: number): Plot?
	for _, plot in plots do
		if plot.owner and plot.owner.UserId == userId then
			return plot
		end
	end
	return nil
end

function PlotManager.GetPodiumPosition(_, plot: Plot, index: number): Vector3
	return plot.podiums[index].part.Position
end

-- Число активных слотов игрока (стартовые + докупленные считает UpgradeManager,
-- но здесь читаем прямо из профиля-агрегата через ctx.Upgrades).
function PlotManager.GetSlotCount(_, player: Player): number
	if ctx.Upgrades then
		return ctx.Upgrades:GetSlotCount(player)
	end
	return Config.StartingSlots
end

-- Индекс первого свободного активного подиума (или nil).
function PlotManager.FirstFreePodium(_, player: Player): number?
	local plot = plotByOwner[player]
	local profile = ctx.Data:Get(player)
	if not plot or not profile then
		return nil
	end
	local slots = PlotManager:GetSlotCount(player)
	local used: { [number]: boolean } = {}
	for _, e in profile.Brainrots do
		if e.podium then
			used[e.podium] = true
		end
	end
	for i = 1, slots do
		if not used[i] then
			return i
		end
	end
	return nil
end

function PlotManager.GetRegisterLabel(_, plot: Plot): TextLabel?
	local bb = plot.register:FindFirstChildOfClass("BillboardGui")
	return bb and bb:FindFirstChildOfClass("TextLabel") or nil
end

function PlotManager.UpdateRegister(_, player: Player, bank: number)
	local plot = plotByOwner[player]
	if not plot then
		return
	end
	local label = PlotManager:GetRegisterLabel(plot)
	if label then
		label.Text = ("КАССА: $%d"):format(math.floor(bank))
	end
end

function PlotManager.SetRobCooldown(_, plot: Plot, seconds: number)
	plot.robCooldownUntil = os.clock() + seconds
end

function PlotManager.IsOnRobCooldown(_, plot: Plot): boolean
	return os.clock() < plot.robCooldownUntil
end

function PlotManager.All(_): { Plot }
	return plots
end

return PlotManager
