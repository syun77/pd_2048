import "game_config"
import "game/undo_snapshot"
import "undo_history"

local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE
---@class UndoController ゲームのUNDO管理クラス.
---@field state GameState ゲーム状態.
---@field session GameSession ゲームセッション.
---@field sound Sound サウンド管理.
---@field setMessage fun(message: string, durationMs: integer) メッセージを表示する関数.
---@field randomGenerator GameRandom ランダムジェネレーター.
local UndoController = {}
UndoController.__index = UndoController

-- コンストラクタ.
---@return UndoController
function UndoController.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        session = dependencies.session,
        sound = dependencies.sound,
        setMessage = dependencies.setMessage,
        randomGenerator = dependencies.randomGenerator,
    }, UndoController)
end

function UndoController:save()
    local state = self.state
    local snapshot = UndoSnapshot.capture(state, self.randomGenerator:getState())
    UndoHistory.push(state.undoStates, snapshot)
end

-- 最新のUNDO履歴に回転情報を記録する.
---@param clockwise boolean 回転方向が時計回りかどうか
function UndoController:recordRotation(clockwise)
    local snapshot = UndoHistory.peek(self.state.undoStates)
    if snapshot ~= nil then snapshot.turn.rotationClockwise = clockwise end
end

-- UNDOが可能かどうかを判定する.
---@return boolean UNDOが可能かどうか
function UndoController:isAvailable()
    local state = self.state
    return UndoHistory.canRestore(state.undoStates, state.rewindUsesRemaining)
end

-- UNDOを実行する.
---@return boolean UNDOが成功したかどうか
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
    ---@cast restored UndoSnapshot
    state.rewindUsesRemaining -= 1
    local currentBoard = state.board
    UndoSnapshot.apply(restored, state, self.randomGenerator)
    state.coreRushGainCombo = 0
    state.coreRushGainMergeValue = 0
    state.coreRushGainTotal = 0
    state.coreRushGainUntil = 0
    state.levelUpFrom = 0
    state.levelUpTo = 0
    state.levelUpDisplayFrame = Config.LEVEL_UP_DISPLAY_FRAMES
    state.practiceVictoryPending = false
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
    local rotationClockwise = restored.turn.rotationClockwise
    if rotationClockwise ~= nil then
        state.board = currentBoard
        state.rotationStartBoard = currentBoard
        state.rotationEndBoard = restored.state.board
        state.rotationClockwise = not rotationClockwise
        state.animationProgress = 0
        state.animationDuration = 0.38
        self.sound:play_se("rotate")
        state.phase = GamePhase.UNDO_ROTATING
    else
        state.holdAnimationSourceValue = 0
        state.holdAnimationReturnValue = 0
        state.phase = GamePhase.INPUT
    end
    return true
end

_G.UndoController = UndoController
return UndoController
