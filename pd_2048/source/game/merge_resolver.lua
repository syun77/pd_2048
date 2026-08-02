import "game_config"
import "board/board_rules"

local Config <const> = GameConfig
local MergeResolver = {}

function MergeResolver.getPositionEvaluation(x)
    if x > Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_RIGHT end
    if x < Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_LEFT end
    return Config.ROTATION_EVALUATION_POSITION_CENTER
end

function MergeResolver.getDirectionEvaluation(sourceX, targetX)
    if targetX < sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT end
    if targetX > sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT end
    return Config.ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT
        * MergeResolver.getPositionEvaluation(targetX)
end

function MergeResolver.getEvaluation(sourceX, targetX)
    return Config.ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT
        * MergeResolver.getPositionEvaluation(sourceX)
        + Config.ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT
        * MergeResolver.getPositionEvaluation(targetX)
        + MergeResolver.getDirectionEvaluation(sourceX, targetX)
end

function MergeResolver.keepsBlockConnected(board, sourceX, sourceY, targetX, targetY)
    local neighbors = {
        { x = targetX - 1, y = targetY, excludedX = sourceX, excludedY = targetY },
        { x = targetX + 1, y = targetY, excludedX = sourceX, excludedY = targetY },
        { x = targetX, y = targetY - 1, excludedX = targetX, excludedY = sourceY },
        { x = targetX, y = targetY + 1, excludedX = targetX, excludedY = sourceY },
    }
    for _, neighbor in ipairs(neighbors) do
        if BoardRules.isPlayable(neighbor.x, neighbor.y)
            and (neighbor.x ~= neighbor.excludedX or neighbor.y ~= neighbor.excludedY)
            and BoardRules.isOccupied(board, neighbor.x, neighbor.y) then
            return true
        end
    end
    return false
end

function MergeResolver.find(board, sourceX, sourceY, activeValue)
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
        if activeValue ~= 0 and BoardRules.isPlayable(neighborX, neighborY)
            and board:get(neighborX, neighborY) == activeValue then
            if MergeResolver.keepsBlockConnected(
                board, sourceX, sourceY, neighborX, neighborY) then
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

function MergeResolver.findForActive(board, activeX, activeY)
    return MergeResolver.find(board, activeX, activeY, board:get(activeX, activeY))
end

function MergeResolver.getAutoPlayCandidates(board, activeValue)
    local candidates = {}
    for column = 1, Config.BOARD_SIZE do
        local x, y = BoardRules.findDropCell(board, column)
        if x ~= nil then
            local sourceX, sourceY, targetX, targetY =
                MergeResolver.find(board, x, y, activeValue)
            table.insert(candidates, {
                column = column,
                merge = sourceX ~= nil,
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
