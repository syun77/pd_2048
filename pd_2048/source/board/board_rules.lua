import "game_config"

local Config <const> = GameConfig
local BoardRules = {}

function BoardRules.isCenter(x, y)
    return x == Config.CENTER and y == Config.CENTER
end

function BoardRules.isPlayable(x, y)
    return x >= 1 and x <= Config.BOARD_SIZE and y >= 1 and y <= Config.BOARD_SIZE
        and not BoardRules.isCenter(x, y)
end

function BoardRules.isOccupied(board, x, y)
    return board ~= nil and BoardRules.isPlayable(x, y) and board:get(x, y) ~= 0
end

function BoardRules.findDropCell(board, column)
    if board == nil then return nil end
    for y = 1, Config.BOARD_SIZE do
        if BoardRules.isCenter(column, y) or board:get(column, y) ~= 0 then return nil end
        local supported = BoardRules.isOccupied(board, column, y + 1)
            or (column == Config.CENTER and y == Config.CENTER - 1)
            or BoardRules.isOccupied(board, column - 1, y)
            or BoardRules.isOccupied(board, column + 1, y)
        if supported then return column, y end
    end
    return nil
end

function BoardRules.canDropInAnyColumn(board)
    for x = 1, Config.BOARD_SIZE do
        if BoardRules.findDropCell(board, x) ~= nil then return true end
    end
    return false
end

_G.BoardRules = BoardRules
return BoardRules
