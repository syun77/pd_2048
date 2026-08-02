import "array2d"
import "game_config"

local Config <const> = GameConfig

local GameState = {}

function GameState.new()
    local self = {
        board = Array2D(Config.BOARD_SIZE, Config.BOARD_SIZE, 0),
        cursorX = Config.CENTER,
        nextValues = {},
        score = 0,
        highScore = 0,
        normalHighScore = 0,
        timeAttackHighScore = 0,
        coreRushBestTimeMs = nil,
        coreRushValue = 0,
        coreRushGainCombo = 0,
        coreRushGainMergeValue = 0,
        coreRushGainTotal = 0,
        coreRushGainUntil = 0,
        coreRushCompleteUntil = 0,
        coreRushVictoryPending = false,
        mode = Config.GAME_MODE.NORMAL,
        elapsedTimeMs = 0,
        remainingTimeMs = nil,
        timerStartedAt = nil,
        timerLastUpdateAt = nil,
        timeoutPending = false,
        holdValue = 0,
        holdAvailable = true,
        lastRandomBlockValue = 0,
        consecutiveRandomBlockCount = 0,
        undoStates = {},
        rewindUsesRemaining = 0,
        combo = 0,
        comboBonusScore = 0,
        comboDisplayFrame = 0,
        comboSoundPlayed = false,
        phase = Config.GAME_PHASE.INPUT,
        result = nil,
        message = "",
        messageUntil = 0,
        animationProgress = 0,
        animationDuration = 0,
        pendingDropX = 0, pendingDropY = 0, pendingDropValue = 0,
        rotationStartBoard = nil, rotationEndBoard = nil, rotationClockwise = false,
        mergeSourceX = 0, mergeSourceY = 0, mergeTargetX = 0, mergeTargetY = 0,
        mergeValue = 0, mergeNextAction = "FINISH",
        activeMergeX = 0, activeMergeY = 0,
        nextAnimationGameOver = false,
        holdAnimationSourceValue = 0, holdAnimationReturnValue = 0,
        rewindHoldAnimationActive = false,
        rotationEvaluation = 0,
        previewImpulseRotationDegrees = 0,
        crisisBgmActive = false,
        rewindHoldStartedAt = nil,
        rewindHoldTriggered = false,
        cursorRepeatDirection = 0,
        cursorRepeatNextAt = nil,
    }
    for i = 1, Config.NEXT_QUEUE_COUNT do
        self.nextValues[i] = 2
    end
    return self
end

function GameState:isAnimating()
    local s = self.phase
    local states = Config.GAME_PHASE
    return s == states.DROPPING or s == states.MERGING or s == states.ROTATING
        or s == states.UNDO_ROTATING or s == states.NEXT_ANIM or s == states.HOLD_ANIM
end

_G.GameState = GameState
return GameState
