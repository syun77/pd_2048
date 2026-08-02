import "game_config"
import "undo_history"

local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE
local UndoController = {}
UndoController.__index = UndoController

function UndoController.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        session = dependencies.session,
        sound = dependencies.sound,
        setMessage = dependencies.setMessage,
    }, UndoController)
end

function UndoController:save(action)
    local state = self.state
    UndoHistory.push(state.undoStates, {
        board = state.board, score = state.score, cursorX = state.cursorX,
        holdValue = state.holdValue, holdAvailable = state.holdAvailable,
        lastRandomBlockValue = state.lastRandomBlockValue,
        consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
        nextValues = state.nextValues,
    }, action)
end

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
    state.cursorX = restored.cursorX
    state.holdValue = restored.holdValue
    state.holdAvailable = restored.holdAvailable
    state.lastRandomBlockValue = restored.lastRandomBlockValue or 0
    state.consecutiveRandomBlockCount = restored.consecutiveRandomBlockCount or 0
    state.nextValues = restored.nextValues

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
