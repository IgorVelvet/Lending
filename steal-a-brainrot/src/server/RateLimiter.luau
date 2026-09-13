--!strict
--[[
	RateLimiter (ModuleScript)
	Расположение: ServerScriptService.Server.RateLimiter

	Токен-бакет на игрока и на ключ (имя remote). Защита от спама вызовов (§10).
	Использование: if not RateLimiter:Allow(player, "BuyBrainrot", limitPerSec) then return end
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- Хранилище: [player] = { [key] = { tokens=number, last=number, cap=number } }
local buckets: { [Player]: { [string]: { tokens: number, last: number, cap: number } } } = {}

-- Разрешён ли вызов. limitPerSec — и cap, и скорость восстановления (1 сек = полный бак).
function RateLimiter.Allow(_, player: Player, key: string, limitPerSec: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local b = playerBuckets[key]
	if not b then
		b = { tokens = limitPerSec, last = now, cap = limitPerSec }
		playerBuckets[key] = b
	end

	-- Восстановление токенов пропорционально прошедшему времени.
	local elapsed = now - b.last
	b.last = now
	b.tokens = math.min(b.cap, b.tokens + elapsed * limitPerSec)

	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.Clear(_, player: Player)
	buckets[player] = nil
end

return RateLimiter
