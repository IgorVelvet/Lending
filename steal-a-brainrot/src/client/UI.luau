--!strict
--[[
	UI (ModuleScript)
	Расположение: StarterPlayer.StarterPlayerScripts.Client.UI

	Весь интерфейс строится кодом (без ручной сборки в StarterGui) — экраны §11:
	HUD, магазин-каталог с замками, инвентарь/расстановка, апгрейды, защита, геймпассы,
	прогресс кражи + маркер «несу добычу», уведомления, «твою базу грабят».

	Модуль только рисует и зовёт коллбэки (ui.On*). Логику/remote'ы держит контроллер.
	Шрифты — встроенные бесплатные (Gotham). Отступы заголовков единые (см. HEADER_PAD).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local UI = {}
UI.__index = UI

-- Единые отступы (§ дизайн-правила пользователя): одинаковые до/после заголовков.
local HEADER_PAD = 12
local PANEL_BG = Color3.fromRGB(28, 30, 38)
local PANEL_BG2 = Color3.fromRGB(38, 41, 52)
local ACCENT = Color3.fromRGB(90, 170, 255)
local TEXT = Color3.fromRGB(235, 238, 245)
local SUBTEXT = Color3.fromRGB(160, 166, 180)
local GOOD = Color3.fromRGB(90, 210, 130)
local BAD = Color3.fromRGB(235, 90, 90)

local function create(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	return inst
end

local function corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function pad(px: number): UIPadding
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function rarityColor(rarity: string): Color3
	local r = Config.Rarities[rarity]
	return r and r.color or Color3.fromRGB(160, 160, 160)
end

local function money(n: number): string
	return "$" .. tostring(math.floor(n))
end

-- Клиентская оценка дохода/сек (только для отображения; истина — на сервере).
local function estimateIncome(profile: any): number
	local raw = 0
	local slots = profile.Slots or Config.StartingSlots
	for _, e in profile.Brainrots do
		if e.podium and e.podium <= slots then
			local def = Config.BrainrotById[e.id]
			if def then
				raw += def.income
			end
		end
	end
	local mult = Config.Upgrades.IncomeMult.levels[profile.Upgrades.IncomeMult].value
	local passMult = 1
	if profile.Passes.DoubleIncome then
		passMult *= Config.Gamepasses.DoubleIncome.multiplier
	end
	if profile.Passes.VIP then
		passMult *= (1 + Config.Gamepasses.VIP.incomeBonus)
	end
	return raw * mult * passMult
end

-- ─────────────────────────────────────────────────────────────────────────
function UI.new()
	local self = setmetatable({}, UI)
	self.profile = nil :: any

	-- Коллбэки (устанавливает контроллер).
	self.OnCollect = function() end
	self.OnBuy = function(_id: string) end
	self.OnBuyUpgrade = function(_kind: string) end
	self.OnBuySlot = function() end
	self.OnBuyDefense = function() end
	self.OnPlace = function(_uid: string, _podium: number) end
	self.OnRemove = function(_podium: number) end
	self.OnBuyPass = function(_key: string) end
	self.OnStealPressed = function() end
	self.OnStealReleased = function() end

	local gui = create("ScreenGui", {
		Name = "StealABrainrotUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	self:_buildHUD()
	self:_buildSideBar()
	self:_buildShop()
	self:_buildInventory()
	self:_buildUpgrades()
	self:_buildDefense()
	self:_buildPasses()
	self:_buildSteal()
	self:_buildToasts()
	self:_buildRobAlert()

	return self
end

-- ─── HUD (§11) ─────────────────────────────────────────────────────────────
function UI._buildHUD(self: any)
	local bar = create("Frame", {
		Name = "HUD",
		Size = UDim2.new(0, 360, 0, 64),
		Position = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.1,
		Parent = self.gui,
	}, { corner(12), pad(10) })

	self.cashLabel = create("TextLabel", {
		Size = UDim2.new(0.55, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEXT,
		Text = "$0",
		Parent = bar,
	})
	self.incomeLabel = create("TextLabel", {
		Size = UDim2.new(0.55, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SUBTEXT,
		Text = "+$0/сек",
		Parent = bar,
	})

	local collectBtn = create("TextButton", {
		Name = "Collect",
		Size = UDim2.new(0.42, 0, 1, 0),
		Position = UDim2.new(0.58, 0, 0, 0),
		BackgroundColor3 = GOOD,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(20, 30, 22),
		Text = "СОБРАТЬ КАССУ",
		AutoButtonColor = true,
		Parent = bar,
	}, { corner(10) })
	self.collectBtn = collectBtn
	collectBtn.MouseButton1Click:Connect(function()
		self.OnCollect()
	end)
end

-- ─── Боковая панель кнопок ────────────────────────────────────────────────
function UI._buildSideBar(self: any)
	local bar = create("Frame", {
		Name = "SideBar",
		Size = UDim2.new(0, 130, 0, 300),
		Position = UDim2.new(0, 16, 0.5, -150),
		BackgroundTransparency = 1,
		Parent = self.gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local defs = {
		{ key = "Shop", text = "🛒 Магазин" },
		{ key = "Inventory", text = "📦 Инвентарь" },
		{ key = "Upgrades", text = "⬆️ Апгрейды" },
		{ key = "Defense", text = "🛡️ Защита" },
		{ key = "Passes", text = "⭐ Пассы" },
	}
	self.panels = {}
	for i, d in defs do
		local btn = create("TextButton", {
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = i,
			BackgroundColor3 = PANEL_BG,
			BackgroundTransparency = 0.05,
			Font = Enum.Font.GothamMedium,
			TextSize = 15,
			TextColor3 = TEXT,
			Text = d.text,
			Parent = bar,
		}, { corner(10) })
		btn.MouseButton1Click:Connect(function()
			self:TogglePanel(d.key)
		end)
	end
end

function UI.TogglePanel(self: any, key: string)
	for name, panel in self.panels do
		panel.Visible = (name == key) and not panel.Visible or false
	end
end

-- Общая обёртка панели с заголовком и кнопкой закрытия.
function UI._panel(self: any, key: string, title: string): (Frame, Frame)
	local panel = create("Frame", {
		Name = key,
		Size = UDim2.new(0, 440, 0, 480),
		Position = UDim2.new(0.5, -220, 0.5, -240),
		BackgroundColor3 = PANEL_BG,
		Visible = false,
		Parent = self.gui,
	}, { corner(14) })

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 44 + HEADER_PAD * 2),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { pad(HEADER_PAD) })
	create("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEXT,
		Text = title,
		Parent = header,
	})
	local close = create("TextButton", {
		Size = UDim2.new(0, 32, 0, 32),
		Position = UDim2.new(1, -40, 0, 6),
		BackgroundColor3 = BAD,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = TEXT,
		Text = "✕",
		Parent = header,
	}, { corner(8) })
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	local body = create("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, -24, 1, -(44 + HEADER_PAD * 2) - 12),
		Position = UDim2.new(0, 12, 0, 44 + HEADER_PAD * 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	self.panels[key] = panel
	return panel, body
end

-- ─── Магазин (§11) ─────────────────────────────────────────────────────────
function UI._buildShop(self: any)
	local _, body = self:_panel("Shop", "Магазин брейнротов")
	self.shopRows = {}
	for i, def in Config.Brainrots do
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = PANEL_BG2,
			LayoutOrder = i,
			Parent = body,
		}, { corner(10), pad(8) })

		create("Frame", {
			Size = UDim2.new(0, 6, 1, 0),
			BackgroundColor3 = rarityColor(def.rarity),
			Parent = row,
		}, { corner(3) })

		create("TextLabel", {
			Size = UDim2.new(0.55, 0, 0.5, 0),
			Position = UDim2.new(0, 14, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = TEXT,
			Text = def.name,
			Parent = row,
		})
		create("TextLabel", {
			Size = UDim2.new(0.55, 0, 0.5, 0),
			Position = UDim2.new(0, 14, 0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(def.rarity),
			Text = ("%s · +$%s/сек"):format(def.rarity, tostring(def.income)),
			Parent = row,
		})

		local buyBtn = create("TextButton", {
			Size = UDim2.new(0, 110, 0, 40),
			Position = UDim2.new(1, -110, 0.5, -20),
			BackgroundColor3 = ACCENT,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(15, 20, 30),
			Text = money(def.price),
			Parent = row,
		}, { corner(8) })

		local lockLabel = create("TextLabel", {
			Size = UDim2.new(0, 110, 0, 40),
			Position = UDim2.new(1, -110, 0.5, -20),
			BackgroundColor3 = Color3.fromRGB(60, 62, 72),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = SUBTEXT,
			Text = "🔒",
			Visible = false,
			Parent = row,
		}, { corner(8) })

		buyBtn.MouseButton1Click:Connect(function()
			self.OnBuy(def.id)
		end)
		self.shopRows[def.id] = { buy = buyBtn, lock = lockLabel, def = def }
	end
end

-- ─── Инвентарь / расстановка (§11) ─────────────────────────────────────────
function UI._buildInventory(self: any)
	local _, body = self:_panel("Inventory", "Инвентарь и подиумы")
	self.invBody = body
end

function UI.RefreshInventory(self: any)
	local body = self.invBody
	local profile = self.profile
	if not body or not profile then
		return
	end
	for _, c in body:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local slots = profile.Slots or Config.StartingSlots

	-- Занятые подиумы.
	local placed: { [number]: any } = {}
	local inInventory = {}
	for _, e in profile.Brainrots do
		if e.podium then
			placed[e.podium] = e
		else
			table.insert(inInventory, e)
		end
	end

	local order = 0
	local function addRow(text: string, sub: string, btnText: string, color: Color3, cb: () -> ())
		order += 1
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = PANEL_BG2,
			LayoutOrder = order,
			Parent = body,
		}, { corner(10), pad(8) })
		create("TextLabel", {
			Size = UDim2.new(0.6, 0, 0.55, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = TEXT,
			Text = text,
			Parent = row,
		})
		create("TextLabel", {
			Size = UDim2.new(0.6, 0, 0.45, 0),
			Position = UDim2.new(0, 0, 0.55, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = SUBTEXT,
			Text = sub,
			Parent = row,
		})
		local btn = create("TextButton", {
			Size = UDim2.new(0, 96, 0, 38),
			Position = UDim2.new(1, -96, 0.5, -19),
			BackgroundColor3 = color,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(15, 20, 30),
			Text = btnText,
			Parent = row,
		}, { corner(8) })
		btn.MouseButton1Click:Connect(cb)
	end

	for i = 1, slots do
		local e = placed[i]
		if e then
			local def = Config.BrainrotById[e.id]
			addRow(
				("Подиум %d: %s"):format(i, def and def.name or "?"),
				def and (def.rarity .. " · +$" .. def.income .. "/сек") or "",
				"Снять",
				Color3.fromRGB(230, 170, 80),
				function()
					self.OnRemove(i)
				end
			)
		else
			addRow(("Подиум %d: пусто"):format(i), "Свободно", "—", Color3.fromRGB(70, 72, 82), function() end)
		end
	end

	for _, e in inInventory do
		local def = Config.BrainrotById[e.id]
		-- Первый свободный подиум для постановки.
		local target: number? = nil
		for i = 1, slots do
			if not placed[i] then
				target = i
				break
			end
		end
		addRow(
			("В инвентаре: %s"):format(def and def.name or "?"),
			def and (def.rarity .. " · +$" .. def.income .. "/сек") or "",
			target and ("→ #" .. target) or "нет слота",
			target and GOOD or Color3.fromRGB(70, 72, 82),
			function()
				if target then
					placed[target] = e
					self.OnPlace(e.uid, target)
				end
			end
		)
	end
end

-- ─── Апгрейды (§11) ────────────────────────────────────────────────────────
function UI._buildUpgrades(self: any)
	local _, body = self:_panel("Upgrades", "Апгрейды")
	self.upgRows = {}

	local kinds = {
		{ key = "IncomeMult", title = "Множитель дохода" },
		{ key = "WalkSpeed", title = "Скорость бега" },
		{ key = "CollectSpeed", title = "Кап кассы (сбор)" },
	}
	local order = 0
	for _, k in kinds do
		order += 1
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = PANEL_BG2,
			LayoutOrder = order,
			Parent = body,
		}, { corner(10), pad(8) })
		local title = create("TextLabel", {
			Size = UDim2.new(0.6, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = TEXT,
			Text = k.title,
			Parent = row,
		})
		local sub = create("TextLabel", {
			Size = UDim2.new(0.6, 0, 0.5, 0),
			Position = UDim2.new(0, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = SUBTEXT,
			Text = "",
			Parent = row,
		})
		local btn = create("TextButton", {
			Size = UDim2.new(0, 120, 0, 40),
			Position = UDim2.new(1, -120, 0.5, -20),
			BackgroundColor3 = ACCENT,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(15, 20, 30),
			Text = "—",
			Parent = row,
		}, { corner(8) })
		btn.MouseButton1Click:Connect(function()
			self.OnBuyUpgrade(k.key)
		end)
		self.upgRows[k.key] = { title = title, sub = sub, btn = btn }
	end

	-- Докупка слота.
	order += 1
	local slotRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = PANEL_BG2,
		LayoutOrder = order,
		Parent = body,
	}, { corner(10), pad(8) })
	create("TextLabel", {
		Size = UDim2.new(0.6, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEXT,
		Text = "Слот подиума",
		Parent = slotRow,
	})
	self.slotSub = create("TextLabel", {
		Size = UDim2.new(0.6, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SUBTEXT,
		Text = "",
		Parent = slotRow,
	})
	self.slotBtn = create("TextButton", {
		Size = UDim2.new(0, 120, 0, 40),
		Position = UDim2.new(1, -120, 0.5, -20),
		BackgroundColor3 = GOOD,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(15, 20, 30),
		Text = "—",
		Parent = slotRow,
	}, { corner(8) })
	self.slotBtn.MouseButton1Click:Connect(function()
		self.OnBuySlot()
	end)
end

function UI.RefreshUpgrades(self: any)
	local profile = self.profile
	if not profile then
		return
	end
	for kind, row in self.upgRows do
		local def = Config.Upgrades[kind]
		local level = profile.Upgrades[kind]
		local nextDef = def.levels[level + 1]
		row.sub.Text = ("Ур. %d → знач. %s"):format(level, tostring(def.levels[level].value))
		if nextDef then
			row.btn.Text = money(nextDef.cost)
			row.btn.BackgroundColor3 = profile.Cash >= nextDef.cost and ACCENT or Color3.fromRGB(70, 72, 82)
			row.btn.Active = true
		else
			row.btn.Text = "MAX"
			row.btn.BackgroundColor3 = Color3.fromRGB(70, 72, 82)
		end
	end

	local slots = profile.Slots or Config.StartingSlots
	if slots >= Config.MaxSlots then
		self.slotSub.Text = ("Слотов: %d (макс)"):format(slots)
		self.slotBtn.Text = "MAX"
		self.slotBtn.BackgroundColor3 = Color3.fromRGB(70, 72, 82)
	else
		local extra = slots - Config.StartingSlots
		local cost = math.floor(Config.SlotBaseCost * (Config.SlotCostGrowth ^ math.max(0, extra)))
		self.slotSub.Text = ("Слотов: %d / %d"):format(slots, Config.MaxSlots)
		self.slotBtn.Text = money(cost)
		self.slotBtn.BackgroundColor3 = profile.Cash >= cost and GOOD or Color3.fromRGB(70, 72, 82)
	end
end

-- ─── Защита (§11) ──────────────────────────────────────────────────────────
function UI._buildDefense(self: any)
	local _, body = self:_panel("Defense", "Защита базы")
	self.defBody = body
	self.defInfo = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = PANEL_BG2,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = TEXT,
		TextWrapped = true,
		Text = "",
		LayoutOrder = 1,
		Parent = body,
	}, { corner(10), pad(8) })
	self.defBtn = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = ACCENT,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(15, 20, 30),
		Text = "—",
		LayoutOrder = 2,
		Parent = body,
	}, { corner(10) })
	self.defBtn.MouseButton1Click:Connect(function()
		self.OnBuyDefense()
	end)
end

function UI.RefreshDefense(self: any)
	local profile = self.profile
	if not profile then
		return
	end
	local level = profile.DefenseLevel
	local cur = Config.Defense.levels[level]
	local nextDef = Config.Defense.levels[level + 1]
	self.defInfo.Text = ("Уровень защиты: %d\nЗабор: %s · Кулдаун: %dс · Оглушалка: %s"):format(
		level,
		cur.fenceHeight > 0 and (cur.fenceHeight .. " studs") or "нет",
		cur.robCooldown,
		cur.stunner and "да" or "нет"
	)
	if nextDef then
		self.defBtn.Text = "Улучшить — " .. money(nextDef.cost)
		self.defBtn.BackgroundColor3 = profile.Cash >= nextDef.cost and ACCENT or Color3.fromRGB(70, 72, 82)
	else
		self.defBtn.Text = "MAX"
		self.defBtn.BackgroundColor3 = Color3.fromRGB(70, 72, 82)
	end
end

-- ─── Геймпассы (§11) ───────────────────────────────────────────────────────
function UI._buildPasses(self: any)
	local _, body = self:_panel("Passes", "Геймпассы")
	self.passRows = {}
	local defs = {
		{ key = "VIP", title = "VIP", desc = "+25% дохода, метка, косметика" },
		{ key = "DoubleIncome", title = "×2 доход", desc = "Перманентный множитель дохода" },
		{ key = "AutoCollect", title = "Авто-сбор", desc = "Касса капает сразу в баланс" },
	}
	for i, d in defs do
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = PANEL_BG2,
			LayoutOrder = i,
			Parent = body,
		}, { corner(10), pad(8) })
		create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = TEXT,
			Text = d.title,
			Parent = row,
		})
		create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.5, 0),
			Position = UDim2.new(0, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextColor3 = SUBTEXT,
			Text = d.desc,
			Parent = row,
		})
		local btn = create("TextButton", {
			Size = UDim2.new(0, 110, 0, 44),
			Position = UDim2.new(1, -110, 0.5, -22),
			BackgroundColor3 = Color3.fromRGB(240, 190, 60),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(30, 24, 10),
			Text = "Купить",
			Parent = row,
		}, { corner(8) })
		btn.MouseButton1Click:Connect(function()
			self.OnBuyPass(d.key)
		end)
		self.passRows[d.key] = { btn = btn }
	end
end

function UI.RefreshPasses(self: any)
	local profile = self.profile
	if not profile then
		return
	end
	for key, row in self.passRows do
		if profile.Passes[key] then
			row.btn.Text = "✓ Есть"
			row.btn.BackgroundColor3 = GOOD
			row.btn.Active = false
		else
			row.btn.Text = "Купить"
			row.btn.BackgroundColor3 = Color3.fromRGB(240, 190, 60)
			row.btn.Active = true
		end
	end
end

-- ─── Кража: прогресс-бар, кнопка, маркер переноса (§11) ────────────────────
function UI._buildSteal(self: any)
	-- Кнопка кражи (видна на тач-устройствах; на ПК — клавиша E, см. контроллер).
	local btn = create("TextButton", {
		Name = "StealButton",
		Size = UDim2.new(0, 150, 0, 60),
		Position = UDim2.new(0.5, -75, 1, -110),
		BackgroundColor3 = BAD,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = TEXT,
		Text = "КРАСТЬ (E)",
		Visible = UserInputService.TouchEnabled,
		Parent = self.gui,
	}, { corner(12) })
	self.stealBtn = btn
	btn.MouseButton1Down:Connect(function()
		self.OnStealPressed()
	end)
	btn.MouseButton1Up:Connect(function()
		self.OnStealReleased()
	end)

	-- Прогресс-бар захвата.
	local barBg = create("Frame", {
		Name = "StealProgress",
		Size = UDim2.new(0, 300, 0, 26),
		Position = UDim2.new(0.5, -150, 1, -150),
		BackgroundColor3 = Color3.fromRGB(20, 22, 28),
		Visible = false,
		Parent = self.gui,
	}, { corner(8) })
	self.stealFill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = BAD,
		Parent = barBg,
	}, { corner(8) })
	self.stealText = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = TEXT,
		Text = "",
		Parent = barBg,
	})
	self.stealBar = barBg

	-- Маркер «несу добычу».
	self.carryMarker = create("TextLabel", {
		Name = "CarryMarker",
		Size = UDim2.new(0, 300, 0, 40),
		Position = UDim2.new(0.5, -150, 0, 90),
		BackgroundColor3 = Color3.fromRGB(200, 120, 40),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(30, 20, 10),
		Text = "",
		Visible = false,
		Parent = self.gui,
	}, { corner(10) })
end

function UI.SetStealProgress(self: any, data: any)
	if data.active then
		self.stealBar.Visible = true
		self.stealFill.Size = UDim2.new(math.clamp(data.progress, 0, 1), 0, 1, 0)
		self.stealText.Text = ("Кража у %s… %d%%"):format(data.targetName, math.floor(data.progress * 100))
	else
		self.stealBar.Visible = false
	end
end

function UI.SetCarry(self: any, data: any)
	if data.carrying then
		self.carryMarker.Visible = true
		self.carryMarker.Text = ("НЕСУ: %s — беги на свою базу!"):format(data.brainrotName)
	else
		self.carryMarker.Visible = false
	end
end

-- ─── Уведомления-тосты (§11) ───────────────────────────────────────────────
function UI._buildToasts(self: any)
	self.toastHolder = create("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 300, 1, -40),
		Position = UDim2.new(1, -316, 0, 20),
		BackgroundTransparency = 1,
		Parent = self.gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Top,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function UI.Toast(self: any, text: string, kind: string?)
	local color = ACCENT
	if kind == "success" then
		color = GOOD
	elseif kind == "warn" then
		color = Color3.fromRGB(235, 180, 70)
	elseif kind == "alert" then
		color = BAD
	end
	local t = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.05,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Parent = self.toastHolder,
	}, { corner(10), pad(10), create("UIStroke", { Color = color, Thickness = 2 }) })
	task.delay(4, function()
		t:Destroy()
	end)
end

-- ─── «Твою базу грабят» (§11) ──────────────────────────────────────────────
function UI._buildRobAlert(self: any)
	self.robAlert = create("TextLabel", {
		Name = "RobAlert",
		Size = UDim2.new(0, 460, 0, 54),
		Position = UDim2.new(0.5, -230, 0, 20),
		BackgroundColor3 = BAD,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextColor3 = TEXT,
		Text = "",
		Visible = false,
		Parent = self.gui,
	}, { corner(12) })
end

function UI.RobAlert(self: any, robberName: string)
	self.robAlert.Text = ("⚠ ТВОЮ БАЗУ ГРАБИТ %s!"):format(robberName)
	self.robAlert.Visible = true
	task.delay(5, function()
		self.robAlert.Visible = false
	end)
end

-- ─── Приём профиля: обновить всё ───────────────────────────────────────────
function UI.SetProfile(self: any, profile: any)
	self.profile = profile
	self.cashLabel.Text = money(profile.Cash)
	self.incomeLabel.Text = ("+%s/сек · касса %s"):format(money(estimateIncome(profile)), money(profile.Bank))

	-- Магазин: замки по TotalEarned.
	for _, row in self.shopRows do
		local unlockAt = Config.RarityUnlockAtTotalEarned[row.def.rarity] or 0
		local unlocked = profile.TotalEarned >= unlockAt
		row.buy.Visible = unlocked
		row.lock.Visible = not unlocked
		if unlocked then
			row.buy.BackgroundColor3 = profile.Cash >= row.def.price and ACCENT or Color3.fromRGB(70, 72, 82)
		else
			row.lock.Text = "🔒 " .. money(unlockAt)
		end
	end

	self:RefreshInventory()
	self:RefreshUpgrades()
	self:RefreshDefense()
	self:RefreshPasses()
end

return UI
