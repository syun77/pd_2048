import "game_config"

local Config <const> = GameConfig
local TileGenerator = {}

function TileGenerator.next(board, randomState, getMaxTileValue)
    local maxValue = getMaxTileValue(board)
    local maxQuarter = math.floor(maxValue / 4)
    local suppressedValue = nil
    if randomState.consecutiveCount >= 3 then suppressedValue = randomState.lastValue end
    local selectedValue

    if maxValue >= 16 then
        local totalWeight = 0
        local value = 2
        while value <= maxQuarter do
            local weight = value == maxQuarter and 0.5 / value or 1 / value
            if value ~= suppressedValue then totalWeight += weight end
            value *= 2
        end
        local roll, cumulativeWeight = math.random() * totalWeight, 0
        value = 2
        while value <= maxQuarter do
            local weight = value == maxQuarter and 0.5 / value or 1 / value
            if value ~= suppressedValue then
                cumulativeWeight += weight
                if roll < cumulativeWeight then selectedValue = value; break end
            end
            value *= 2
        end
        if selectedValue == nil then
            value = 2
            while value <= maxQuarter do
                if value ~= suppressedValue then selectedValue = value; break end
                value *= 2
            end
        end
    else
        selectedValue = math.random(1, 10) == 10 and 4 or 2
        if selectedValue == suppressedValue then selectedValue = selectedValue == 2 and 4 or 2 end
    end

    if selectedValue == randomState.lastValue then
        randomState.consecutiveCount += 1
    else
        randomState.lastValue = selectedValue
        randomState.consecutiveCount = 1
    end
    return selectedValue
end

_G.TileGenerator = TileGenerator
return TileGenerator
