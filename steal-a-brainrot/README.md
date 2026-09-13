# Кради брейнрота (клон Steal a Brainrot)

Тайкун-игра для Roblox: пассивный доход с брейнротов на подиумах + воровство чужих
юнитов прямо с баз. Код на Luau, серверная валидация всей экономики, кросс-платформа
(ПК + мобилки) с первой версии.

> Модели брейнротов на старте — процедурные болванки (примитивы с табличкой имени и
> цветом по редкости). Замена на готовые модели — отдельная задача (см. «Замена моделей»).

---

## Что внутри

```
steal-a-brainrot/
├── default.project.json        # Rojo: раскладка по сервисам Roblox
└── src/
    ├── shared/                 → ReplicatedStorage.Modules  (ModuleScript'ы-конфиги)
    │   ├── Config.luau         # весь баланс: редкости, каталог, цены, апгрейды, кап и т.д.
    │   └── RemoteNames.luau    # согласованные имена remote-объектов
    ├── server/                 → ServerScriptService.Server  (Script + дочерние ModuleScript'ы)
    │   ├── init.server.luau    # bootstrap: собирает ctx и инициализирует менеджеры
    │   ├── RateLimiter.luau    # токен-бакет против спама remote (§10)
    │   ├── RemoteManager.luau  # создаёт Remotes, привязка обработчиков + rate-limit
    │   ├── DataManager.luau    # DataStore + session-lock + автосейв (§8)
    │   ├── PlotManager.luau    # карта, плоты, подиумы, касса, рендер болванок (§3)
    │   ├── GamepassManager.luau# проверка геймпассов через MarketplaceService (§7)
    │   ├── EconomyManager.luau # общий тик дохода, кап, сбор кассы (§4)
    │   ├── UpgradeManager.luau # апгрейды, слоты, покупка защиты (§7)
    │   ├── DefenseManager.luau # заборы, кулдаун, оглушалка (§6)
    │   ├── ShopManager.luau    # каталог, покупка, расстановка по подиумам (§4.3)
    │   └── StealManager.luau   # захват, перенос, сдача, дроп, оглушение (§5)
    └── client/                 → StarterPlayer.StarterPlayerScripts.Client  (LocalScript + UI)
        ├── init.client.luau    # ввод, remote-вызовы, детект цели кражи (§9)
        └── UI.luau             # все экраны интерфейса кодом (§11)
```

Соответствие сервисам задаёт `default.project.json`:

| Файл/папка на диске | Место в Roblox |
|---|---|
| `src/shared/*` | `ReplicatedStorage.Modules.*` (ModuleScript) |
| `src/server/init.server.luau` | `ServerScriptService.Server` (Script) |
| `src/server/*.luau` (кроме init) | дочерние ModuleScript'ы `ServerScriptService.Server` |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` (LocalScript) |
| `src/client/UI.luau` | дочерний ModuleScript `...Client.UI` |

Расширения Rojo: `.server.luau` → `Script`, `.client.luau` → `LocalScript`,
`.luau` → `ModuleScript`, `init.*` → сам контейнер становится этим классом.

---

## Сборка через Rojo (рекомендуется)

1. Установи [Rojo](https://rojo.space) (плагин в Studio + CLI).
2. В терминале из папки `steal-a-brainrot/`:
   ```
   rojo serve
   ```
3. В Studio: плагин Rojo → **Connect**. Дерево из `default.project.json` зальётся в место.
4. Включи **API Services** для DataStore: Game Settings → Security →
   *Enable Studio Access to API Services* (иначе сохранение не работает в Studio).
5. Нажми **Play**. Плот выдаётся автоматически, HUD появляется, доход капает.

Один раз опубликуй место (**File → Publish to Roblox**), чтобы DataStore работал
и в реальной игре (в неопубликованном месте DataStore недоступен).

---

## Ручная сборка в Studio (без Rojo)

По этапам §12 ТЗ. Классы и места — из таблицы выше.

1. **ReplicatedStorage** → создай `Folder` с именем `Modules`. Внутрь два `ModuleScript`:
   `Config` и `RemoteNames`. Вставь содержимое одноимённых файлов.
2. **ServerScriptService** → создай `Script` с именем `Server`, вставь `init.server.luau`.
   Внутрь этого Script'а добавь `ModuleScript`'ы: `RateLimiter`, `RemoteManager`,
   `DataManager`, `PlotManager`, `GamepassManager`, `EconomyManager`, `UpgradeManager`,
   `DefenseManager`, `ShopManager`, `StealManager` — по одному на файл.
3. **StarterPlayer → StarterPlayerScripts** → создай `LocalScript` с именем `Client`,
   вставь `init.client.luau`. Внутрь добавь `ModuleScript` `UI` (файл `UI.luau`).
4. Папку `Remotes` в ReplicatedStorage создавать **не нужно** — её и все RemoteEvent/
   RemoteFunction сервер создаёт сам при старте (RemoteManager).
5. Включи API Services (см. выше), опубликуй место, жми Play.

Порядок соответствует этапам сборки §12: конфиги → плоты → тик дохода/касса →
DataStore → кража → защита → апгрейды → геймпассы → античит (уже встроен) → UI.

---

## Управление

- **ПК:** ходьба — WASD; сбор кассы — кнопка «Собрать» или клик по жёлтой кассе базы;
  кража — подбеги к чужому подиуму с брейнротом и **зажми `E`**, держи, пока идёт
  прогресс-бар; донеси добычу до своего свободного подиума.
- **Мобилки:** джойстик; кнопка **«КРАСТЬ»** внизу экрана (зажать удержанием).
- Панели (магазин, инвентарь, апгрейды, защита, пассы) — кнопки слева.

---

## Настройка баланса

Всё в `src/shared/Config.luau`:

- `Rarities` — цвета и множители дохода/цены 6 редкостей.
- `Brainrots` — каталог (id, имя, редкость, цена, доход/сек).
- `RarityUnlockAtTotalEarned` — по сколько суммарно заработать, чтобы открыть редкость.
- `StartingCash`, `AccumulationCapSeconds` (кап кассы), `IncomeTickInterval`.
- `StartingSlots` (3), `MaxSlots`, `SlotBaseCost`, `SlotCostGrowth`.
- `Upgrades` — уровни и цены множителя дохода, скорости бега, капа сбора.
- `Defense` — уровни заборов, кулдаун неуязвимости, оглушалка (радиус, длительность).
- `Steal` — время захвата (4с), радиусы, замедление переноса, таймаут возврата дропа.
- `Gamepasses` — **впиши сюда реальные ID геймпассов** (по умолчанию 0 = отключены).
- `RateLimits` — лимиты вызовов remote в секунду на игрока (античит).

---

## Настройка геймпассов (§7)

1. В Roblox Creator Dashboard создай геймпассы: VIP, ×2 доход, Авто-сбор.
2. Скопируй их ID в `Config.Gamepasses.<Pass>.id`.
3. Владение проверяется на сервере (`UserOwnsGamePassAsync`), покупка — промпт с клиента.
   Пока `id = 0`, кнопка покупки сообщит, что пасс не настроен.

---

## Античит и безопасность (§10)

Уже реализовано:

- Сервер — единственный источник истины по балансу, владению, доходу.
- На сервере проверяются: дистанция до подиума при захвате, реальное время удержания,
  наличие свободного слота у вора, право владения, достаточность средств при покупке.
- Клиенту уходит только **его** профиль (чужие балансы не реплицируются).
- Rate-limit на все remote-вызовы (`Config.RateLimits`).
- Session-lock в DataStore против дюпа при переходах между серверами.

---

## Замена моделей брейнротов

Сейчас юнит рисуется как Part с табличкой имени (см. `renderBrainrot` в `PlotManager`).
Чтобы поставить готовую модель:

1. Положи `Model` в `ReplicatedStorage.Modules` (или отдельную папку `Assets`).
2. В `Config.Brainrots` у нужного юнита укажи `model = "ИмяМодели"`.
3. В `PlotManager.renderBrainrot` добавь ветку: если `def.model` задан — клонировать
   модель из Assets и ставить на подиум вместо процедурной болванки.

---

## Известные упрощения версии

- Модели — болванки (по ТЗ).
- Если владелец вышел, пока его добычу несли и уронили — брейнрот теряется (базы
  офлайн-игроков не существует, возвращать некуда; см. §3 «офлайн не грабят»).
- Оглушалка срабатывает по радиусу от центра базы (не лучём-рейкастом) — достаточно
  для v1, апгрейдится до луча позже.
