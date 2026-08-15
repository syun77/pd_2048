import "game_config"
import "undo_history"

local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE
---@class UndoController ゲームのUNDO管理クラス.
---@field state GameState ゲーム状態.
---@field session GameSession ゲームセッション.
---@field sound Sound サウンド管理.
---@field setMessage fun(message: string, durationMs: integer) メッセージを表示する関数.
local UndoController = {}
UndoController.__index = UndoController

function UndoController.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        session = dependencies.session,
        sound = dependencies.sound,
        setMessage = dependencies.setMessage,
        randomGenerator = dependencies.randomGenerator,
    }, UndoController)
end

function UndoController:save(action)
    local state = self.state
    UndoHistory.push(state.undoStates, {
        board = state.board, score = state.score, cursorX = state.cursorX,
        holdValue = state.holdValue, holdAvailable = state.holdAvailable,
        lastRandomBlockValue = state.lastRandomBlockValue,
        consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
        practiceNextIndex = state.practiceNextIndex,
        practiceSpawnCount = state.practiceSpawnCount,
        practiceTurnCount = state.practiceTurnCount,
        practiceMergeCount = state.practiceMergeCount,
        level = state.level,
        levelXp = state.levelXp,
        levelDropCount = state.levelDropCount,
        levelCreatedMilestones = state.levelCreatedMilestones,
        levelXpBySource = state.levelXpBySource,
        nextValues = state.nextValues,
        randomGeneratorState = self.randomGenerator:getState(),
    }, action)
end

-- UNDOが可能かどうかを判定する.
---@return boolean UNDOが可能かどうか
function UndoController:isAvailable()
    local state = self.state
    return UndoHistory.canRestore(state.undoStates, state.rewindUsesRemaining)
end

function UndoController:restore()
    local state = self.state
    if not self:isAvailable() then
        if state.rewindUsesRemaining <= 0 then
            self.setMessage("NO REWINDS", 700)
        else
            self.setMessage("NO UNDO", 700)
        end
        return false
    end

    local restored = UndoHistory.pop(state.undoStates)
    local rewindHoldAnimation = restored.action == "HOLD"
    state.rewindHoldAnimationActive = rewindHoldAnimation
    if rewindHoldAnimation then
        state.holdAnimationSourceValue = state.nextValues[1]
        state.holdAnimationReturnValue = state.holdValue
    end

    state.rewindUsesRemaining -= 1
    local currentBoard = state.board
    state.board = restored.board
    state.score = restored.score
    state.coreRushValue = restored.coreRushValue or 0
    state.coreRushGainCombo = 0
    state.coreRushGainMergeValue = 0
    state.coreRushGainTotal = 0
    state.coreRushGainUntil = 0
    state.cursorX = restored.cursorX
    state.holdValue = restored.holdValue
    state.holdAvailable = restored.holdAvailable
    state.lastRandomBlockValue = restored.lastRandomBlockValue or 0
    state.consecutiveRandomBlockCount = restored.consecutiveRandomBlockCount or 0
    state.practiceNextIndex = restored.practiceNextIndex or 1
    state.practiceSpawnCount = restored.practiceSpawnCount or 0
    state.practiceTurnCount = restored.practiceTurnCount or 0
    state.practiceNextExhausted = restored.practiceNextExhausted or false
    state.practiceMergeCount = restored.practiceMergeCount or 0
    state.level = restored.level or 1
    state.levelXp = restored.levelXp or 0
    state.levelDropCount = restored.levelDropCount or 0
    state.levelCreatedMilestones = restored.levelCreatedMilestones or {}
    state.levelXpBySource = restored.levelXpBySource
        or { drop = 0, merge = 0, firstTile = 0, combo = 0 }
    state.levelUpFrom = 0
    state.levelUpTo = 0
    state.levelUpDisplayFrame = Config.LEVEL_UP_DISPLAY_FRAMES
    state.practiceVictoryPending = false
    state.nextValues = restored.nextValues
    if restored.randomGeneratorState ~= nil then
        self.randomGenerator:setState(restored.randomGeneratorState)
    end
    state.holdAnimationNextValue = 0

    self.session:resetCombo()
    state.rotationEvaluation = 0
    state.previewImpulseRotationDegrees = 0
    state.pendingDropValue = 0
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    state.nextAnimationGameOver = false
    state.message = ""
    state.crisisBgmActive = false

    self.sound:play_se("rewind")
    if restored.hasRotation then
        state.board = currentBoard
        state.rotationStartBoard = currentBoard
        state.rotationEndBoard = restored.board
        state.rotationClockwise = not restored.rotationClockwise
        state.animationProgress = 0
        state.animationDuration = 0.38
        self.sound:play_se("rotate")
        state.phase = GamePhase.UNDO_ROTATING
    elseif rewindHoldAnimation then
        state.animationProgress = 0
        state.animationDuration = 0.30
        state.phase = GamePhase.HOLD_ANIM
    else
        state.holdAnimationSourceValue = 0
        state.holdAnimationReturnValue = 0
        state.phase = GamePhase.INPUT
    end
    return true
end

_G.UndoController = UndoController
return UndoController
