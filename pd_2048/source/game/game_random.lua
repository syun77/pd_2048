---@class GameRandom ブロック生成専用の決定的乱数生成器。BGMなどの演出が使用する math.random から乱数系列を分離する。
---@field state integer 現在の乱数生成器の状態
local GameRandom = {}
GameRandom.__index = GameRandom

local MODULUS <const> = 2147483647
local MULTIPLIER <const> = 48271

-- 乱数生成器のシード値を正規化する関数.
---@param seed integer シード値
---@return integer 正規化されたシード値
local function normalizeSeed(seed)
    local value = math.floor(tonumber(seed) or 1) % MODULUS
    if value <= 0 then value = 1 end
    return value
end

-- 乱数生成器の新しいインスタンスを作成する関数.
---@param seed integer シード値
---@return GameRandom 乱数生成器の新しいインスタンス
function GameRandom.new(seed)
    return setmetatable({ state = normalizeSeed(seed) }, GameRandom)
end

-- 乱数生成器のシード値を設定する関数.
---@param seed integer シード値
function GameRandom:setSeed(seed)
    self.state = normalizeSeed(seed)
end

-- 乱数生成器の現在の状態を取得する関数.
---@return integer 現在の乱数生成器の状態
function GameRandom:getState()
    return self.state
end

-- 乱数生成器の状態を設定する関数.
---@param state integer 乱数生成器の状態
function GameRandom:setState(state)
    self.state = normalizeSeed(state)
end

-- 0以上1未満の浮動小数点数の乱数を生成する関数.
---@return number 0以上1未満の浮動小数点数の乱数
function GameRandom:nextFloat()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return (self.state - 1) / (MODULUS - 1)
end

-- 指定された範囲の整数の乱数を生成する関数.
---@param minimum integer 最小値 (含む)
---@param maximum integer 最大値 (含む)
---@return integer 指定された範囲の整数の乱数
function GameRandom:nextInt(minimum, maximum)
    assert(maximum >= minimum, "Invalid random integer range")
    local count = maximum - minimum + 1
    return minimum + math.floor(self:nextFloat() * count)
end

_G.GameRandom = GameRandom
return GameRandom
