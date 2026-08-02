import "board/board_transform"
import "game_config"

local Config <const> = GameConfig
local UndoHistory = {}

function UndoHistory.push(history, state, action)
    local snapshot = {
        board = BoardTransform.copy(state.board), score = state.score,
        coreRushValue = state.coreRushValue,
        cursorX = state.cursorX, holdValue = state.holdValue,
        holdAvailable = state.holdAvailable,
        lastRandomBlockValue = state.lastRandomBlockValue,
        consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
        hasRotation = false, rotationClockwise = false, action = action, nextValues = {},
    }
    for i = 1, Config.NEXT_QUEUE_COUNT do snapshot.nextValues[i] = state.nextValues[i] end
    table.insert(history, snapshot)
    if #history > Config.MAX_UNDO_COUNT then table.remove(history, 1) end
end

function UndoHistory.canRestore(history, rewindUsesRemaining)
    return rewindUsesRemaining > 0 and #history > 0
end

function UndoHistory.pop(history)
    return table.remove(history)
end

_G.UndoHistory = UndoHistory
return UndoHistory
