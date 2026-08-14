import "game_config"

local Config <const> = GameConfig
local BoardRules = {}

-- 指定された座標がボードの中央かどうかを判定する.
---@param x integer X座標 (1始まり)
---@param y integer Y座標 (1始まり)
---@return boolean 中央セルかどうか
function BoardRules.isCenter(x, y)
    return x == Config.CENTER and y == Config.CENTER
end

-- 指定された座標がボード上で有効な位置かどうかを判定する.
---@param x integer X座標 (1始まり)
---@param y integer Y座標 (1始まり)
---@param mode GAME_MODE? ゲームモード
---@return boolean 有効な位置かどうか
function BoardRules.isPlayable(x, y, mode)
    return x >= 1 and x <= Config.BOARD_SIZE and y >= 1 and y <= Config.BOARD_SIZE
        and not BoardRules.isCenter(x, y)
end

-- 指定された座標がボード上で有効な位置かつブロックが存在するかどうかを判定する.
---@param board Array2D ボードの状態
---@param x integer X座標 (1始まり)
---@param y integer Y座標 (1始まり)
---@param mode GAME_MODE? ゲームモード
---@return boolean 有効な位置かつブロックが存在するかどうか
function BoardRules.isOccupied(board, x, y, mode)
    return board ~= nil and BoardRules.isPlayable(x, y, mode) and board:get(x, y) ~= 0
end

-- 指定された列にブロックをドロップできるかどうかを判定する.
---@param board Array2D ボードの状態
---@param column integer ドロップする列のインデックス (1始まり)
---@param mode GAME_MODE ゲームモード
---@return integer?, integer? ドロップ可能なセルの座標 (column, row) または nil
function BoardRules.findDropCell(board, column, mode)
    if board == nil then return nil end
    for y = 1, Config.BOARD_SIZE do
        if BoardRules.isCenter(column, y) or board:get(column, y) ~= 0 then return nil end
        local supported = BoardRules.isOccupied(board, column, y + 1, mode)
            or (column == Config.CENTER and y == Config.CENTER - 1)
            or BoardRules.isOccupied(board, column - 1, y, mode)
            or BoardRules.isOccupied(board, column + 1, y, mode)
        if supported then return column, y end
    end
    return nil
end

-- 指定されたボードにおいて、どの列にもブロックをドロップできるかどうかを判定する.
---@param board Array2D ボードの状態
---@param mode GAME_MODE ゲームモード
---@return boolean どの列にもドロップできるかどうか
function BoardRules.canDropInAnyColumn(board, mode)
    for x = 1, Config.BOARD_SIZE do
        if BoardRules.findDropCell(board, x, mode) ~= nil then return true end
    end
    return false
end

_G.BoardRules = BoardRules
return BoardRules
