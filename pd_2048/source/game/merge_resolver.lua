import "game_config"
import "board/board_rules"

local Config <const> = GameConfig
---@class MergeResolver マージ解決クラス.
local MergeResolver = {}

-- 指定されたX座標に基づいて、回転評価値を取得する.
---@param x integer X座標 (1始まり)
---@return number 回転評価値
function MergeResolver.getPositionEvaluation(x)
    if x > Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_RIGHT end
    if x < Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_LEFT end
    return Config.ROTATION_EVALUATION_POSITION_CENTER
end

-- 指定されたマージ元とマージ先のX座標に基づいて、回転評価値を取得する.
---@param sourceX integer マージ元のX座標 (1始まり)
---@param targetX integer マージ先のX座標 (1始まり)
---@return number 回転評価値
function MergeResolver.getDirectionEvaluation(sourceX, targetX)
    if targetX < sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT end
    if targetX > sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT end
    return Config.ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT
        * MergeResolver.getPositionEvaluation(targetX)
end

-- 指定されたマージ元とマージ先のX座標に基づいて、回転評価値を取得する.
---@param sourceX integer マージ元のX座標 (1始まり)
---@param targetX integer マージ先のX座標 (1始まり)
---@return number 回転評価値
function MergeResolver.getEvaluation(sourceX, targetX)
    return Config.ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT
        * MergeResolver.getPositionEvaluation(sourceX)
        + Config.ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT
        * MergeResolver.getPositionEvaluation(targetX)
        + MergeResolver.getDirectionEvaluation(sourceX, targetX)
end

-- 指定されたマージ元とマージ先の座標に基づいて、回転評価値を取得する.
---@param sourceX integer マージ元のX座標 (1始まり)
---@param sourceY integer マージ元のY座標 (1始まり)
---@param targetX integer マージ先のX座標 (1始まり)
---@param targetY integer マージ先のY座標 (1始まり)
---@param mode GAME_MODE ゲームモード
---@return boolean マージ後にブロックが接続されたままかどうか
function MergeResolver.keepsBlockConnected(board, sourceX, sourceY, targetX, targetY, mode)
    local neighbors = {
        { x = targetX - 1, y = targetY, excludedX = sourceX, excludedY = targetY },
        { x = targetX + 1, y = targetY, excludedX = sourceX, excludedY = targetY },
        { x = targetX, y = targetY - 1, excludedX = targetX, excludedY = sourceY },
        { x = targetX, y = targetY + 1, excludedX = targetX, excludedY = sourceY },
    }
    for _, neighbor in ipairs(neighbors) do
        if BoardRules.isPlayable(neighbor.x, neighbor.y, mode)
            and (neighbor.x ~= neighbor.excludedX or neighbor.y ~= neighbor.excludedY)
            and BoardRules.isOccupied(board, neighbor.x, neighbor.y, mode) then
			-- 隣接するブロックが存在する場合、マージ後も接続されたままになる.
            return true
        end
    end

	-- 隣接するブロックが存在しない場合、マージ後に接続が失われる可能性がある.
    return false
end

-- 指定された位置のブロックに対して、マージ可能な隣接ブロックを探す.
---@param board Array2D ゲーム盤の状態を表す2次元配列
---@param sourceX integer マージ対象のブロックのX座標
---@param sourceY integer マージ対象のブロックのY座標
---@param activeValue integer マージ対象のブロックの値
---@param mode GAME_MODE ゲームモード
---@return integer? sourceX マージ元のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? sourceY マージ元のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetX マージ先のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetY マージ先のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
function MergeResolver.find(board, sourceX, sourceY, activeValue, mode)
    local directions = Config.DIRECTION
    local fallbackSourceX, fallbackSourceY, fallbackTargetX, fallbackTargetY
    local offsets = {
        [directions.DOWN] = { dx = 0, dy = 1 },
        [directions.LEFT] = { dx = -1, dy = 0 },
        [directions.RIGHT] = { dx = 1, dy = 0 },
        [directions.UP] = { dx = 0, dy = -1 },
    }

    for direction = directions.DOWN, directions.UP do
        local offset = offsets[direction]
        local neighborX = sourceX + offset.dx
        local neighborY = sourceY + offset.dy
        if activeValue ~= 0 and BoardRules.isPlayable(neighborX, neighborY, mode)
            and board:get(neighborX, neighborY) == activeValue then
            if MergeResolver.keepsBlockConnected(
                board, sourceX, sourceY, neighborX, neighborY, mode) then
                return sourceX, sourceY, neighborX, neighborY
            end
            if fallbackSourceX == nil then
                fallbackSourceX, fallbackSourceY = sourceX, sourceY
                fallbackTargetX, fallbackTargetY = neighborX, neighborY
            end
        end
    end

    if fallbackSourceX ~= nil then
        return fallbackSourceX, fallbackSourceY, fallbackTargetX, fallbackTargetY
    end
    return nil
end

-- 指定された位置のブロックに対して、マージ可能な隣接ブロックを探す.
---@param board Array2D ゲーム盤の状態を表す2次元配列
---@param activeX integer マージ対象のブロックのX座標
---@param activeY integer マージ対象のブロックのY座標
---@param mode GAME_MODE ゲームモード
---@return integer? sourceX マージ元のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? sourceY マージ元のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetX マージ先のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetY マージ先のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
function MergeResolver.findForActive(board, activeX, activeY, mode)
    return MergeResolver.find(board, activeX, activeY, board:get(activeX, activeY), mode)
end

function MergeResolver.findConnectionValue(board, x, y, activeValue, mode)
    local minimumValue = activeValue * 2
    local connectionValue = nil
    local neighbors = {
        { x = x - 1, y = y }, { x = x + 1, y = y },
        { x = x, y = y - 1 }, { x = x, y = y + 1 },
    }
    for _, neighbor in ipairs(neighbors) do
        if BoardRules.isOccupied(board, neighbor.x, neighbor.y, mode) then
            local value = board:get(neighbor.x, neighbor.y)
            if value >= minimumValue
                and (connectionValue == nil or value < connectionValue) then
                connectionValue = value
            end
        end
    end
    return connectionValue
end

-- 指定された位置のブロックに対して、マージ可能な隣接ブロックを探す.
---@param board Array2D ゲーム盤の状態を表す2次元配列
---@param activeValue integer マージ対象のブロックの値
---@param mode GAME_MODE ゲームモード
---@return table[] candidates マージ可能なブロックの候補リスト
function MergeResolver.getAutoPlayCandidates(board, activeValue, mode)
    local candidates = {}
    for column = 1, Config.BOARD_SIZE do
        local x, y = BoardRules.findDropCell(board, column, mode)
        if x ~= nil then
            local sourceX, sourceY, targetX, targetY =
                MergeResolver.find(board, x, y, activeValue, mode)
            table.insert(candidates, {
                column = column,
                merge = sourceX ~= nil,
                connectionValue = MergeResolver.findConnectionValue(
                    board, x, y, activeValue, mode),
                sourceX = sourceX,
                sourceY = sourceY,
                targetX = targetX,
                targetY = targetY,
            })
        end
    end
    return candidates
end

_G.MergeResolver = MergeResolver
return MergeResolver
