---@class GameRandom ブロック生成専用の決定的乱数生成器。BGMなどの演出が使用する math.random から乱数系列を分離する。
---@field state integer 現在の乱数生成器の状態
local GameRandom = {}
GameRandom.__index = GameRandom

local MODULUS <const> = 2147483647
local MULTIPLIER <const> = 48271

local function normalizeSeed(seed)
    local value = math.floor(tonumber(seed) or 1) % MODULUS
    if value <= 0 then value = 1 end
    return value
end

function GameRandom.new(seed)
    return setmetatable({ state = normalizeSeed(seed) }, GameRandom)
end

function GameRandom:setSeed(seed)
    self.state = normalizeSeed(seed)
end

function GameRandom:getState()
    return self.state
end

function GameRandom:setState(state)
    self.state = normalizeSeed(state)
end

function GameRandom:nextFloat()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return (self.state - 1) / (MODULUS - 1)
end

function GameRandom:nextInt(minimum, maximum)
    assert(maximum >= minimum, "Invalid random integer range")
    local count = maximum - minimum + 1
    return minimum + math.floor(self:nextFloat() * count)
end

_G.GameRandom = GameRandom
return GameRandom
