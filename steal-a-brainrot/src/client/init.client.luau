--!strict
--[[
	Client controller (LocalScript)
	Расположение: StarterPlayer.StarterPlayerScripts.Client  (этот файл делает контейнер LocalScript'ом)

	Ввод (ПК + мобилки), отправка запросов на сервер, клиентские эффекты (§9).
	Никакой экономической логики — только запросы и отрисовка. Истина на сервере (§10).

	Дочерний ModuleScript: UI
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"))
local RemoteNames = require(Modules:WaitForChild("RemoteNames"))
local UI = require(script:WaitForChild("UI"))

local player = Players.LocalPlayer

-- ─── Remote-объекты ────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild(RemoteNames.Folder)
local function fn(name: string): RemoteFunction
	return remotesFolder:WaitForChild(name) :: RemoteFunction
end
local function ev(name: string): RemoteEvent
	return remotesFolder:WaitForChild(name) :: RemoteEvent
end

local ui = UI.new()

-- ─── Коллбэки UI → сервер ──────────────────────────────────────────────────
ui.OnCollect = function()
	fn(RemoteNames.Functions.CollectCash):InvokeServer()
end

ui.OnBuy = function(id: string)
	local ok, reason = fn(RemoteNames.Functions.BuyBrainrot):InvokeServer(id)
	if not ok then
		local msg = reason == "cash" and "Не хватает валюты"
			or reason == "locked" and "Редкость ещё не открыта"
			or reason == "rate" and "Слишком часто"
			or "Не удалось купить"
		ui:Toast(msg, "warn")
	end
end

ui.OnBuyUpgrade = function(kind: string)
	local ok, reason = fn(RemoteNames.Functions.BuyUpgrade):InvokeServer(kind)
	if not ok then
		ui:Toast(reason == "cash" and "Не хватает валюты" or "Апгрейд недоступен", "warn")
	end
end

ui.OnBuySlot = function()
	local ok, reason = fn(RemoteNames.Functions.BuySlot):InvokeServer()
	if not ok then
		ui:Toast(reason == "cash" and "Не хватает валюты" or "Слот недоступен", "warn")
	end
end

ui.OnBuyDefense = function()
	local ok, reason = fn(RemoteNames.Functions.BuyDefense):InvokeServer()
	if not ok then
		ui:Toast(reason == "cash" and "Не хватает валюты" or "Защита на максимуме", "warn")
	end
end

ui.OnPlace = function(uid: string, podium: number)
	fn(RemoteNames.Functions.PlaceBrainrot):InvokeServer(uid, podium)
end

ui.OnRemove = function(podium: number)
	fn(RemoteNames.Functions.RemoveBrainrot):InvokeServer(podium)
end

ui.OnBuyPass = function(key: string)
	local passDef = Config.Gamepasses[key]
	if not passDef or passDef.id <= 0 then
		ui:Toast("Геймпасс не настроен (укажи ID в Config).", "warn")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, passDef.id)
end

-- ─── События сервера → UI ──────────────────────────────────────────────────
ev(RemoteNames.Events.ProfileUpdated).OnClientEvent:Connect(function(profile)
	ui:SetProfile(profile)
end)

ev(RemoteNames.Events.Notification).OnClientEvent:Connect(function(data)
	ui:Toast(data.text, data.kind)
end)

ev(RemoteNames.Events.StealProgress).OnClientEvent:Connect(function(data)
	ui:SetStealProgress(data)
end)

ev(RemoteNames.Events.CarryStateChanged).OnClientEvent:Connect(function(data)
	ui:SetCarry(data)
end)

ev(RemoteNames.Events.RobAlert).OnClientEvent:Connect(function(data)
	ui:RobAlert(data.robberName)
end)

ev(RemoteNames.Events.PlotAssigned).OnClientEvent:Connect(function(plotIndex)
	ui:Toast(("База выдана (плот #%d). Ставь брейнротов и защищайся!"):format(plotIndex), "info")
end)

-- Пере-проверка геймпассов после покупки.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_plr, _id, purchased)
	if purchased then
		fn(RemoteNames.Functions.RefreshPasses):InvokeServer()
	end
end)

-- ─── Детект цели кражи и ввод (§5) ─────────────────────────────────────────
-- Ищет ближайший чужой занятый активный подиум в радиусе захвата.
local function findStealTarget(): (number?, number?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil
	end
	local bestDist = Config.Steal.CaptureRadius
	local bestOwner: number? = nil
	local bestPodium: number? = nil

	for _, model in workspace:GetChildren() do
		if model:IsA("Model") and model.Name:match("^Plot_") then
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") and part.Name:match("^Podium_") then
					local ownerId = part:GetAttribute("PlotOwnerUserId")
					local occupant = part:GetAttribute("OccupantUid")
					local active = part:GetAttribute("Active")
					if
						typeof(ownerId) == "number"
						and ownerId ~= 0
						and ownerId ~= player.UserId
						and typeof(occupant) == "string"
						and occupant ~= ""
						and active == true
					then
						local d = (part.Position - hrp.Position).Magnitude
						if d <= bestDist then
							bestDist = d
							bestOwner = ownerId
							bestPodium = part:GetAttribute("PodiumIndex") :: number
						end
					end
				end
			end
		end
	end
	return bestOwner, bestPodium
end

ui.OnStealPressed = function()
	local ownerId, podiumIndex = findStealTarget()
	if ownerId and podiumIndex then
		ev(RemoteNames.Events.StartSteal):FireServer(ownerId, podiumIndex)
	else
		ui:Toast("Рядом нет чужого брейнрота для кражи.", "warn")
	end
end

ui.OnStealReleased = function()
	ev(RemoteNames.Events.StopSteal):FireServer()
end

-- Клавиша E (ПК) / кнопка на экране (мобилки уже привязаны в UI).
ContextActionService:BindAction("StealAction", function(_, state)
	if state == Enum.UserInputState.Begin then
		ui.OnStealPressed()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		ui.OnStealReleased()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.E)

print("[StealABrainrot] Client initialized.")
