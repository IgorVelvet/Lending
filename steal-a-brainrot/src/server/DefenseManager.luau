--!strict
--[[
	DefenseManager (ModuleScript)
	Расположение: ServerScriptService.Server.DefenseManager

	Защита базы (§6): заборы (физически замедляют вход, апгрейдятся по уровням),
	кулдаун неуязвимости после кражи, оглушалка/лазер (сбивает вора, роняя добычу).
	Само оглушение вора в зоне выполняет StealManager (он ведёт список несущих).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))

local DefenseManager = {}
local ctx: any

local function makeWall(cf: CFrame, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Brick
	p.Name = "Fence"
	return p
end

-- Уровневые данные защиты.
function DefenseManager.GetLevelDef(_, player: Player)
	local profile = ctx.Data:Get(player)
	local level = profile and profile.DefenseLevel or 1
	return Config.Defense.levels[level]
end

function DefenseManager.HasStunner(_, player: Player): boolean
	local def = DefenseManager:GetLevelDef(player)
	return def ~= nil and def.stunner == true
end

function DefenseManager.RobCooldownSeconds(_, player: Player): number
	local def = DefenseManager:GetLevelDef(player)
	return def and def.robCooldown or 20
end

-- Построить/перестроить заборы по текущему уровню.
function DefenseManager.Build(_, player: Player)
	local plot = ctx.Plots:GetByOwner(player)
	if not plot then
		return
	end
	DefenseManager:Clear(player)

	local levelDef = DefenseManager:GetLevelDef(player)
	local height = levelDef and levelDef.fenceHeight or 0
	if height <= 0 then
		return
	end

	local color = Color3.fromRGB(120, 80, 60)
	local base = plot.base
	local cf = base.CFrame
	local sx = Config.Plot.Size.X / 2 -- 24
	local sz = Config.Plot.Size.Z / 2 -- 20
	local t = 1 -- толщина стены
	local yc = height / 2 + 0.5
	local folder = plot.fenceFolder

	-- Задняя и боковые стены.
	makeWall(cf * CFrame.new(0, yc, -sz), Vector3.new(Config.Plot.Size.X, height, t), color).Parent = folder
	makeWall(cf * CFrame.new(-sx, yc, 0), Vector3.new(t, height, Config.Plot.Size.Z), color).Parent = folder
	makeWall(cf * CFrame.new(sx, yc, 0), Vector3.new(t, height, Config.Plot.Size.Z), color).Parent = folder

	-- Передняя стена с проёмом-дверью (10 studs) по центру.
	local door = 10
	local seg = (Config.Plot.Size.X - door) / 2
	makeWall(cf * CFrame.new(-(door / 2 + seg / 2), yc, sz), Vector3.new(seg, height, t), color).Parent = folder
	makeWall(cf * CFrame.new((door / 2 + seg / 2), yc, sz), Vector3.new(seg, height, t), color).Parent = folder

	-- Маркер оглушалки (визуал зоны), если есть.
	if levelDef.stunner then
		local ring = Instance.new("Part")
		ring.Name = "StunnerCore"
		ring.Anchored = true
		ring.CanCollide = false
		ring.Shape = Enum.PartType.Ball
		ring.Size = Vector3.new(3, 3, 3)
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(255, 60, 60)
		ring.CFrame = cf * CFrame.new(0, 8, 0)
		ring.Parent = folder
	end
end

function DefenseManager.Clear(_, player: Player)
	local plot = ctx.Plots:GetByOwner(player)
	if not plot then
		return
	end
	plot.fenceFolder:ClearAllChildren()
end

function DefenseManager.Init(_, context)
	ctx = context
end

return DefenseManager
