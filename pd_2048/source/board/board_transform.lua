import "array2d"
import "game_config"

local Config <const> = GameConfig
local BoardTransform = {}

function BoardTransform.copy(source)
    local copied = Array2D(Config.BOARD_SIZE, Config.BOARD_SIZE, 0)
    source:foreach(function(x, y, value) copied:set(x, y, value) end)
    return copied
end

function BoardTransform.rotate(source, clockwise, isPlayable)
    local rotated = Array2D(Config.BOARD_SIZE, Config.BOARD_SIZE, 0)
    source:foreach(function(x, y, value)
        if isPlayable(x, y) and value ~= 0 then
            local newX, newY
            if clockwise then
                newX, newY = Config.BOARD_SIZE + 1 - y, x
            else
                newX, newY = y, Config.BOARD_SIZE + 1 - x
            end
            if isPlayable(newX, newY) then rotated:set(newX, newY, value) end
        end
    end)
    return rotated
end

_G.BoardTransform = BoardTransform
return BoardTransform
