--!strict
--[[
	RemoteNames (ModuleScript)
	Расположение: ReplicatedStorage.Modules.RemoteNames

	Согласованные имена Remote-объектов между сервером и клиентом (§9, §13).
	Сами объекты создаёт сервер в ReplicatedStorage.Remotes при старте (см. RemoteManager).
	Клиент только берёт их по этим именам.
]]

local RemoteNames = {}

-- Папка, в которой лежат все remote-объекты.
RemoteNames.Folder = "Remotes"

-- RemoteFunction: клиент запрашивает — сервер отвечает (ok:boolean, payload/reason).
RemoteNames.Functions = {
	BuyBrainrot = "BuyBrainrot", -- (id) -> ok, reason
	CollectCash = "CollectCash", -- () -> ok, collectedAmount
	BuyUpgrade = "BuyUpgrade", -- (kind) -> ok, reason
	BuySlot = "BuySlot", -- () -> ok, reason
	BuyDefense = "BuyDefense", -- () -> ok, reason
	PlaceBrainrot = "PlaceBrainrot", -- (brainrotUid, podiumIndex) -> ok, reason
	RemoveBrainrot = "RemoveBrainrot", -- (podiumIndex) -> ok  (снять юнит с подиума в инвентарь)
	GetCatalog = "GetCatalog", -- () -> catalog snapshot (с флагами unlocked)
	RefreshPasses = "RefreshPasses", -- () -> passes table (пере-проверка владения геймпассами)
}

-- RemoteEvent: односторонние сообщения.
RemoteNames.Events = {
	ProfileUpdated = "ProfileUpdated", -- server->client: снимок профиля игрока (только его данные)
	Notification = "Notification", -- server->client: {text, kind}
	StealProgress = "StealProgress", -- server->client: {active, progress 0..1, targetName}
	CarryStateChanged = "CarryStateChanged", -- server->client: {carrying, brainrotName}
	StartSteal = "StartSteal", -- client->server: (targetUserId, podiumIndex)
	StopSteal = "StopSteal", -- client->server: ()
	RobAlert = "RobAlert", -- server->client(владельцу): {robberName}
	PlotAssigned = "PlotAssigned", -- server->client: (plotIndex) — какой плот выдан
}

return RemoteNames
