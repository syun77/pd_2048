import "array2d"
import "game_config"
import "game_state"
import "game/merge_resolver"
import "game/game_session"
import "game/level_progress"
import "game/statistics_store"
import "game/undo_controller"
import "board/board_transform"
import "board/board_rules"
import "tile_generator"
import "practice_stage_loader"
import "cursor_controller"
import "input/input_command"
import "input/auto_player"
import "input/replay_controller"
import "game/game_random"

local pd <const> = playdate
local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE
local GameResult <const> = Config.GAME_RESULT

---@class GameController ゲームコントローラー.
---@field state GameState ゲーム状態.
---@field sound Sound サウンド管理.
---@field cursorController CursorController
---@field autoPlayer AutoPlayer 自動プレイ.
---@field autoPlayEnabled boolean 自動プレイが有効か.
---@field practiceStage any
---@field session GameSession ゲームセッション.
---@field undoController UndoController UNDO管理.
---@field randomGenerator GameRandom ランダムジェネレーター.
---@field replayController ReplayController リプレイ管理.
local GameController = {}
GameController.__index = GameController

function GameController.new(dependencies)
    local self = setmetatable({}, GameController)
    self.state = GameState.new()
    self.sound = dependencies.sound
    self.cursorController = CursorController.new()
    self.autoPlayer = AutoPlayer.new()
    self.autoPlayEnabled = false
    self.randomGenerator = GameRandom.new(1)
    self.replayController = ReplayController.new(pd)
    self.replayMode = false
    self.replayData = nil
    self.replayIndex = 1
    self.replayEventStartedAt = nil
    self.replayExecuting = false
    self.replayRemainingHolds = 0
    self.replaySaved = false
    self.suspendRestoreData = nil
    self.suspendRestoreActive = false
    self.titleNotice = nil
    self.practiceStage = nil
    self.statisticsRunStarted = false
    self.statisticsRunEligible = true
    self.statisticsResultRecorded = false
    self.statisticsLastTickMs = nil
    self.statisticsDirty = false
    self.statisticsNormalHighestTileAtStart = 0
    self.statisticsNormalMaxComboAtStart = 0
    self.statisticsNormalHighScoreAtStart = 0
    self.statisticsNormalBestLevelAtStart = 1
    self.session = GameSession.new(self.state)
    self.undoController = UndoController.new({
        state = self.state,
        session = self.session,
        sound = self.sound,
        setMessage = function(text, duration)
            self:setMessage(text, duration)
        end,
        randomGenerator = self.randomGenerator,
    })
    self:loadHighScore()
    return self
end

function GameController:createReplaySeed()
    local seconds = 0
    local ok, value = pcall(pd.getSecondsSinceEpoch)
    if ok and type(value) == "number" then seconds = value end
    local now = pd.getCurrentTimeMilliseconds()
    return (seconds * 1000 + now) % 2147483646 + 1
end

function GameController:isReplayMode()
    return self.replayMode
end

function GameController:isReplayPaused()
    return self.state.replayPaused
end

function GameController:isSuspendRestoring()
    return self.suspendRestoreActive
end

function GameController:hasSuspendData()
    return ReplayController.hasSuspend(pd)
end

function GameController:discardSuspendData()
    ReplayController.deleteSuspend(pd)
end

function GameController:consumeTitleNotice()
    local notice = self.titleNotice
    self.titleNotice = nil
    return notice
end

function GameController:listReplays()
    return ReplayController.loadAll(pd)
end

function GameController:toggleReplayFavorite(id)
    return ReplayController.toggleFavorite(pd, id)
end

function GameController:startReplay(id)
    local data = ReplayController.load(pd, id)
    if data == nil or data.mode ~= Config.GAME_MODE.NORMAL then return false end
    self:start(Config.GAME_MODE.NORMAL, nil,
        { replayData = data, seed = data.seed })
    return true
end

function GameController:restartReplay()
    local data = self.replayData
    if data == nil or data.mode ~= Config.GAME_MODE.NORMAL then return false end
    self:start(Config.GAME_MODE.NORMAL, nil,
        { replayData = data, seed = data.seed })
    return true
end

-- NORMALの中断データを読み込み、復元処理を開始する関数.
---@return boolean 開始できたかどうか
function GameController:startSuspendRestore()
    local data = ReplayController.loadSuspend(pd)
    if data == nil then return false end
    self.suspendRestoreData = data
    self.suspendRestoreActive = true
    self.sound.effectsSuppressed = true
    self:start(Config.GAME_MODE.NORMAL, nil, {
        replayData = data,
        seed = data.seed,
        restoring = true,
    })
    self.state.levelRecordEligible = data.levelRecordEligible ~= false
    local statisticsRun = type(data.statisticsRun) == "table"
        and data.statisticsRun or {}
    self.statisticsRunEligible = statisticsRun.eligible ~= false
        and data.levelRecordEligible ~= false
    self.statisticsRunStarted = statisticsRun.started == true
        or data.statisticsRunStarted == true
    if statisticsRun.started == nil and data.statisticsRunStarted == nil then
        for _, event in ipairs(data.events or {}) do
            if event.drop == true then self.statisticsRunStarted = true break end
        end
    end
    if type(statisticsRun.normalHighScoreAtStart) == "number" then
        self.statisticsNormalHighScoreAtStart = statisticsRun.normalHighScoreAtStart
    end
    if type(statisticsRun.normalBestLevelAtStart) == "number" then
        self.statisticsNormalBestLevelAtStart = statisticsRun.normalBestLevelAtStart
    end
    if type(statisticsRun.normalHighestTileAtStart) == "number" then
        self.statisticsNormalHighestTileAtStart = statisticsRun.normalHighestTileAtStart
    end
    if type(statisticsRun.normalMaxComboAtStart) == "number" then
        self.statisticsNormalMaxComboAtStart = statisticsRun.normalMaxComboAtStart
    end
    return true
end

function GameController:setAutoPlayEnabled(value)
    if value and self.statisticsRunEligible then
        self.statisticsRunEligible = false
        if self.statisticsRunStarted then
            StatisticsStore.removePlay(self.state.statistics, self.state.mode)
            self.statisticsRunStarted = false
        end
        if self.state.mode == Config.GAME_MODE.NORMAL then
            self.state.normalHighScore = self.statisticsNormalHighScoreAtStart
            self.state.highScore = math.max(self.state.score,
                self.statisticsNormalHighScoreAtStart)
            self.state.normalBestLevel = self.statisticsNormalBestLevelAtStart
            self.state.statistics.normal.highScore =
                self.statisticsNormalHighScoreAtStart
            self.state.statistics.normal.bestLevel =
                self.statisticsNormalBestLevelAtStart
            self.state.statistics.normal.highestTile =
                self.statisticsNormalHighestTileAtStart
            self.state.statistics.normal.maxCombo =
                self.statisticsNormalMaxComboAtStart
            pd.datastore.write(self.state.normalHighScore, "highScore")
            pd.datastore.write(self.state.normalBestLevel, "normalBestLevel")
        end
        self.statisticsDirty = true
    end
    self.autoPlayEnabled = value
    self.autoPlayer:reset()
    if value and self.state.mode == Config.GAME_MODE.NORMAL then
        self.state.levelRecordEligible = false
    end
end

function GameController:isAutoPlayEnabled()
    return self.autoPlayEnabled
end

-- ゲーム状態の取得.
---@return GameState ゲーム状態.
function GameController:getState()
    return self.state
end

function GameController:isTimeAttack()
    return self.state.mode == Config.GAME_MODE.TIME_ATTACK
        or self.state.mode == Config.GAME_MODE.TIME_ATTACK_256
        or self.state.mode == Config.GAME_MODE.TIME_ATTACK_512
end

function GameController:isCoreRush()
    return self.state.mode == Config.GAME_MODE.CORE_RUSH
end

function GameController:isGameOver()
    return self.state.result ~= nil
end

function GameController:setMessage(text, duration)
    self.state.message = text
    self.state.messageUntil = pd.getCurrentTimeMilliseconds() + duration
end

function GameController:loadHighScore()
    local ok, value = pcall(pd.datastore.read, "highScore")
    if ok and type(value) == "number" then
        self.state.normalHighScore = value
    end
    local okLevel, levelValue = pcall(pd.datastore.read, "normalBestLevel")
    if okLevel and type(levelValue) == "number" then
        self.state.normalBestLevel = math.max(1, math.floor(levelValue))
    end
    local okTimeAttack, timeAttackValue = pcall(pd.datastore.read, "timeAttackBestTimeMs")
    if okTimeAttack and type(timeAttackValue) == "number" then
        self.state.timeAttackBestTimeMs = timeAttackValue
    end
    local okCoreRush, coreRushValue = pcall(pd.datastore.read, "coreRushBestTimeMs")
    if okCoreRush and type(coreRushValue) == "number" then
        self.state.coreRushBestTimeMs = coreRushValue
    end
    local okPractice, practiceValue = pcall(pd.datastore.read, "practiceClearedStages")
    if okPractice and type(practiceValue) == "table" then
        self.state.practiceClearedStages = practiceValue
    end
    self.state.statistics = StatisticsStore.load(pd, {
        normalHighScore = self.state.normalHighScore,
        normalBestLevel = self.state.normalBestLevel,
        coreRushBestTimeMs = self.state.coreRushBestTimeMs,
    })
    self.state.normalHighScore = self.state.statistics.normal.highScore
    self.state.normalBestLevel = self.state.statistics.normal.bestLevel
    self.state.coreRushBestTimeMs =
        self.state.statistics.timeAttack.coreRush.bestTimeMs
    self.state.highScore = self.state.normalHighScore
end

function GameController:flushStatistics()
    if not self.statisticsDirty or self.state.statistics == nil then return true end
    local ok = StatisticsStore.save(pd, self.state.statistics)
    if ok then self.statisticsDirty = false end
    return ok
end

function GameController:updateStatisticsPlayTime(now)
    local previous = self.statisticsLastTickMs
    self.statisticsLastTickMs = now
    if previous == nil then return end
    local delta = now - previous
    if delta < 0 or delta > 250 then return end
    local state = self.state
    if state.startReadyUntil ~= 0 or state.result ~= nil or self.replayMode
        or self.suspendRestoreActive or self.autoPlayEnabled then return end
    state.statistics.totalPlayTimeMs += delta
    self.statisticsDirty = true
end

function GameController:recordStatisticsPlay()
    if self.statisticsRunStarted or not self.statisticsRunEligible
        or self.replayMode or self.autoPlayEnabled then return end
    if StatisticsStore.recordPlay(self.state.statistics, self.state.mode) then
        self.statisticsRunStarted = true
        self.statisticsDirty = true
    end
end

function GameController:recordStatisticsResult()
    if self.statisticsResultRecorded then return end
    self.statisticsResultRecorded = true
    local state = self.state
    if self.replayMode or not self.statisticsRunEligible
        or not self.statisticsRunStarted then return end
    if state.mode == Config.GAME_MODE.NORMAL
        and state.result == GameResult.GAME_OVER then
        StatisticsStore.recordNormalCompletion(
            state.statistics, state.level, state.score)
        self.statisticsDirty = true
    elseif state.result == GameResult.VICTORY
        and StatisticsStore.recordTimedClear(
            state.statistics, state.mode, state.elapsedTimeMs) then
        self.statisticsDirty = true
    end
    self:flushStatistics()
end

function GameController:getPracticeStageId(stage)
    if stage ~= nil and stage.id ~= nil then return tostring(stage.id) end
    if stage ~= nil and stage.fileName ~= nil then return tostring(stage.fileName) end
    return self.state.practiceScenarioId
end

function GameController:isPracticeStageCleared(stage)
    local stageId = self:getPracticeStageId(stage)
    return stageId ~= nil and self.state.practiceClearedStages[stageId] == true
end

function GameController:savePracticeClearedStages()
    if self.replayMode then return end
    pd.datastore.write(self.state.practiceClearedStages, "practiceClearedStages")
end

function GameController:markPracticeStageCleared()
    if self.replayMode then return end
    local stageId = self:getPracticeStageId(self.practiceStage)
    if stageId == nil or self.state.practiceClearedStages[stageId] == true then
        return
    end
    self.state.practiceClearedStages[stageId] = true
    self:savePracticeClearedStages()
end

function GameController:saveCurrentModeHighScore()
    if self.replayMode then return end
    local state = self.state
    if state.mode == Config.GAME_MODE.NORMAL and self.statisticsRunEligible
        and state.score > state.normalHighScore then
        state.normalHighScore = state.score
        state.statistics.normal.highScore = state.score
        self.statisticsDirty = true
        pd.datastore.write(state.normalHighScore, "highScore")
    end
end

-- レベルアップの進行を適用する.
---@param levelUp boolean レベルアップしたかどうか.
---@param previousLevel integer? 前のレベル.
function GameController:applyLevelProgress(levelUp, previousLevel)
    if not levelUp then
		return -- レベルアップしていないので何もしない.
	end
    local state = self.state
    if state.levelUpDisplayFrame >= Config.LEVEL_UP_DISPLAY_FRAMES then
        state.levelUpFrom = previousLevel or math.max(1, state.level - 1)
    end
    state.levelUpTo = state.level
    state.levelUpDisplayFrame = 0 -- レベルアップ演出の表示開始.

	-- レベルアップSEを再生.
	self.sound:play_se("levelup")

    if state.levelRecordEligible and state.level > state.normalBestLevel then
		-- 最高レベルの記録更新.
        state.normalBestLevel = state.level
        state.statistics.normal.bestLevel = state.level
        self.statisticsDirty = true
        state.levelNewBest = true
        pd.datastore.write(state.normalBestLevel, "normalBestLevel")
    end
end

-- タイムアタックでの最短クリア時間を保存する.
function GameController:saveTimeAttackBestTime()
    if self.replayMode then return end
    local state = self.state
    if not self.statisticsRunEligible or not self:isTimeAttack()
        or state.result ~= GameResult.VICTORY then return end
    self:recordStatisticsResult()
end

function GameController:saveCoreRushBestTime()
    if self.replayMode then return end
    local state = self.state
    if not self.statisticsRunEligible or not self:isCoreRush()
        or state.result ~= GameResult.VICTORY then return end
    if state.coreRushBestTimeMs == nil or state.elapsedTimeMs < state.coreRushBestTimeMs then
        state.coreRushBestTimeMs = state.elapsedTimeMs
        pd.datastore.write(state.coreRushBestTimeMs, "coreRushBestTimeMs")
    end
    self:recordStatisticsResult()
end

function GameController:clearBoard()
    local state = self.state
    state.board = Array2D(Config.BOARD_SIZE, Config.BOARD_SIZE, 0)
    state.board:set(Config.CENTER, Config.CENTER, 0)
end

function GameController:addPreviewImpulse(direction)
    if direction == Config.ROTATION_EVALUATION_POSITION_CENTER then return end
    if direction > 0 then
        self.state.previewImpulseRotationDegrees += Config.PREVIEW_IMPULSE_ROTATION_DEGREES
    else
        self.state.previewImpulseRotationDegrees -= Config.PREVIEW_IMPULSE_ROTATION_DEGREES
    end
end

function GameController:addRotationEvaluation(value)
    local state = self.state
    value *= Config.PREVIEW_ROTATION_EVALUATION_MULTIPLIER
    state.rotationEvaluation += value
    state.rotationEvaluation = math.max(-Config.PREVIEW_ROTATION_MAX_DEGREES,
        math.min(Config.PREVIEW_ROTATION_MAX_DEGREES, state.rotationEvaluation))
end

function GameController:beginRewindHold()
    local state = self.state
    if not self.undoController:isAvailable() then
        if state.rewindUsesRemaining <= 0 then
            self:setMessage("NO REWINDS", 700)
        else
            self:setMessage("NO UNDO", 700)
        end
        self.sound:play_se("error")
        return
    end
    state.rewindHoldStartedAt = pd.getCurrentTimeMilliseconds()
    state.rewindHoldTriggered = false
    self.sound:play_se("rewind_button")
end

function GameController:endRewindHold()
    self.state.rewindHoldStartedAt = nil
    self.state.rewindHoldTriggered = false
end

function GameController:updateRewindHold()
    local state = self.state
    if not self.undoController:isAvailable() then
        self:endRewindHold()
        return
    end
    if state.rewindHoldStartedAt == nil or not pd.buttonIsPressed(pd.kButtonB) then
        if state.rewindHoldStartedAt ~= nil then self:endRewindHold() end
        return
    end
    if not state.rewindHoldTriggered
        and pd.getCurrentTimeMilliseconds() - state.rewindHoldStartedAt
            >= Config.REWIND_HOLD_DURATION_MS then
        state.rewindHoldTriggered = true
        self:executeCommand(InputCommand.REWIND)
    end
end

-- ドロップ可能なセルを見つける.
-- 指定された列にブロックをドロップできるかどうかを判定する.
---@param column integer ドロップする列のインデックス (1始まり)
---@return integer?, integer? ドロップ可能なセルの座標 (column, row) または nil
function GameController:findDropCell(column)
    return BoardRules.findDropCell(self.state.board, column, self.state.mode)
end

-- ドロップ可能かどうかを判定する.
---@return false|true ドロップ可能かどうか
function GameController:isDropAvailable()
    return self:findDropCell(self.state.cursorX) ~= nil
end

-- 指定された座標にブロックをドロップできるかどうかを判定する.
---@param sourceX integer マージ対象のブロックのX座標
---@param sourceY integer マージ対象のブロックのY座標
---@param activeValue integer マージ対象のブロックの値
---@return integer? sourceX マージ元のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? sourceY マージ元のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetX マージ先のブロックのX座標（マージ可能なブロックが見つからない場合はnil）
---@return integer? targetY マージ先のブロックのY座標（マージ可能なブロックが見つからない場合はnil）
function GameController:findMergeForBlock(sourceX, sourceY, activeValue)
    return MergeResolver.find(self.state.board, sourceX, sourceY, activeValue, self.state.mode)
end

-- UNDOが利用可能かどうかを判定する.
---@return boolean UNDOが利用可能かどうか
function GameController:isRewindAvailable()
    return self.undoController:isAvailable()
end

-- 重力の適用.
function GameController:applyGravity()
    self.state.board:set(Config.CENTER, Config.CENTER, 0)
end

function GameController:canDropInAnyColumn()
    return BoardRules.canDropInAnyColumn(self.state.board, self.state.mode)
end

function GameController:advanceNextQueue()
    local state = self.state
    for i = 1, Config.NEXT_QUEUE_COUNT - 1 do
        state.nextValues[i] = state.nextValues[i + 1]
    end
    if state.mode == Config.GAME_MODE.PRACTICE then
        state.nextValues[Config.NEXT_QUEUE_COUNT] = self:getPracticeNextValue()
    else
        state.nextValues[Config.NEXT_QUEUE_COUNT] = TileGenerator.nextForState(
            state.board, state, self.randomGenerator)
    end
end

function GameController:promoteHoldIfNextEmpty()
    local state = self.state
    if state.nextValues[1] ~= 0 or state.holdValue == 0 then return end
    local promotedValue = state.holdValue
    state.nextValues[1] = promotedValue
    state.holdValue = 0
    return promotedValue
end

function GameController:updateHoldAvailability()
    local state = self.state
    state.holdAvailable = state.nextValues[2] ~= 0 or state.holdValue ~= 0
end

function GameController:getPracticeNextValue()
    local state = self.state
    local values = state.practiceNextValues
    if #values == 0 then
        return state.practiceTurnLimit > 0 and 0 or 2
    end
    if state.practiceTurnLimit > 0
        and state.practiceSpawnCount >= state.practiceTurnLimit then
        return 0
    end

    local value
    if state.practiceNextPolicy == "STATIC" then
        value = values[1]
    else
        value = values[state.practiceNextIndex]
    end
    if state.practiceNextPolicy == "FIXED" then
        if value == nil then
            state.practiceNextExhausted = true
            return 0
        end
        state.practiceNextIndex += 1
    elseif state.practiceNextPolicy ~= "STATIC" then
        state.practiceNextIndex += 1
        if state.practiceNextIndex > #values then
            state.practiceNextIndex = 1
        end
    end
    state.practiceSpawnCount += 1
    return value
end

function GameController:finishTurn()
    local state = self.state
    self:applyLevelProgress(LevelProgress.recordCombo(state))
    if state.timeAttackVictoryPending then
        self:beginVictory()
        return
    end
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    state.holdAvailable = true
    self:advanceNextQueue()
    self:updatePracticeObjective()
    local promotedValue = self:promoteHoldIfNextEmpty()
    self:updateHoldAvailability()
    if state.nextValues[1] == 0 then
        if state.practiceVictoryPending then
            self:beginPracticeVictory()
        else
            self:beginGameOver()
        end
        return
    end
    state.nextAnimationGameOver = state.nextValues[1] == 0
        or not self:canDropInAnyColumn()
    state.animationProgress = 0
    state.animationDuration = 0.30
    if promotedValue ~= nil then
        state.holdAnimationSourceValue = 0
        state.holdAnimationReturnValue = promotedValue
        state.holdAnimationNextValue = 0
        state.nextAnimationGameOver = false
        state.phase = GamePhase.HOLD_ANIM
    else
        state.phase = GamePhase.NEXT_ANIM
    end
end

-- Practiceモードでの最大タイル値を取得する.
---@return integer 最大タイル値
function GameController:getPracticeMaxTileValue()
    local maxValue = 0
    self.state.board:foreach(function(_, _, value)
        if value > maxValue then maxValue = value end
    end)
    if self.state.holdValue > maxValue then maxValue = self.state.holdValue end
    return maxValue
end

function GameController:isPracticeObjectiveMet(objective)
    local state = self.state
    local target = objective.value or 0
    if objective.type == "TILE_VALUE" then
        return self:getPracticeMaxTileValue() >= target
    elseif objective.type == "COMBO" then
        return state.combo >= target
    elseif objective.type == "SCORE" then
        return state.score >= target
    elseif objective.type == "MERGE_COUNT" then
        return state.practiceMergeCount >= target
    end
    return false
end

function GameController:updatePracticeObjective()
    local state = self.state
    if state.mode ~= Config.GAME_MODE.PRACTICE or state.practiceVictoryPending then
        return
    end

    local objectives = state.practiceObjectives
    if #objectives == 0 then return end

    local achievedCount = 0
    for _, objective in ipairs(objectives) do
        if self:isPracticeObjectiveMet(objective) then achievedCount += 1 end
    end

    local achieved = state.practiceObjectiveMode == "ALL"
        and achievedCount == #objectives
        or state.practiceObjectiveMode ~= "ALL" and achievedCount > 0
    if achieved then state.practiceVictoryPending = true end
end

function GameController:formatPracticeObjective(objective)
    if objective.type == "TILE_VALUE" then
        return "MAKE " .. tostring(objective.value)
    elseif objective.type == "COMBO" then
        return tostring(objective.value) .. " COMBO"
    elseif objective.type == "SCORE" then
        return "SCORE " .. tostring(objective.value)
    elseif objective.type == "MERGE_COUNT" then
        return "MERGE " .. tostring(objective.value)
    end
    return "PRACTICE"
end

function GameController:beginPracticeVictory()
    local state = self.state
    self:markPracticeStageCleared()
    state.practiceCompleteUntil = pd.getCurrentTimeMilliseconds()
        + Config.CORE_RUSH_COMPLETE_DISPLAY_MS
    state.timerStartedAt = nil
    state.timerLastUpdateAt = nil
    state.phase = GamePhase.INPUT
    self.sound:play_se("complete")
    self.sound:stop_bgm(1.0)
end

function GameController:beginGameOver()
    local state = self.state
    self:saveCurrentModeHighScore()
    state.result = GameResult.GAME_OVER
    self:recordStatisticsResult()
    state.phase = GamePhase.INPUT
    self.sound:play_se("gameover")
    self.sound:stop_bgm(1.0)
end

function GameController:beginTimeUp()
    local state = self.state
    state.remainingTimeMs = 0
    state.timeoutPending = false
    state.result = GameResult.TIME_UP
    self:recordStatisticsResult()
    state.phase = GamePhase.INPUT
    self:saveCurrentModeHighScore()
    self.sound:play_se("gameover")
    self.sound:stop_bgm(1.0)
end

-- CORE RUSHモードでのクリア処理を開始する.
function GameController:beginVictory()
    local state = self.state
    state.coreRushCompleteUntil = pd.getCurrentTimeMilliseconds()
        + Config.CORE_RUSH_COMPLETE_DISPLAY_MS
    state.timerStartedAt = nil
    state.timerLastUpdateAt = nil
    state.phase = GamePhase.INPUT
    self.sound:play_se("complete")
    self.sound:stop_bgm(1.0)
end

-- CORE RUSHモードでのスコア加算.
function GameController:addCoreRushValue(mergeValue)
    if not self:isCoreRush() then return false end
    local state = self.state
    local gain = mergeValue * state.combo
    state.coreRushValue += gain
    state.coreRushGainCombo = state.combo
    state.coreRushGainMergeValue = mergeValue
    state.coreRushGainTotal = gain
    state.coreRushGainUntil = pd.getCurrentTimeMilliseconds()
        + Config.CORE_RUSH_GAIN_DISPLAY_MS
    if state.coreRushValue > 2048 then
        state.coreRushVictoryPending = true
    end
    return false
end

-- 時間切れ警告音を再生するタイミングか判定する.
function GameController:shouldPlayTimeAttackWarning(
    prevRemainingTimeMs, currentRemainingTimeMs)
    local prevSec = math.floor(prevRemainingTimeMs / 1000)
    local currentSec = math.floor(currentRemainingTimeMs / 1000)
    local prevMs = prevRemainingTimeMs % 1000
    local currentMs = currentRemainingTimeMs % 1000

    if prevSec ~= currentSec then
		-- 9秒以下のときは再生.
        return currentSec <= 9
    end

	-- 5秒以下は、0.5秒ごとに再生.
    return currentSec < 5
        and currentMs < 500
        and prevMs >= 500
end

-- タイムアタックモードでの制限時間の更新.
function GameController:updateTimeAttackTimer()
    local state = self.state
    if (not self:isTimeAttack() and not self:isCoreRush()) or state.result ~= nil
        or state.timerStartedAt == nil then
		-- タイムアタックモードでなければ何もしない.
        return
    end

	-- 現在時間.
    local now = pd.getCurrentTimeMilliseconds()
    if state.timerLastUpdateAt == nil then state.timerLastUpdateAt = now end
    if state.phase == GamePhase.PAUSED then
		-- ポーズ中は更新しない.
        state.timerLastUpdateAt = now
        return
    end

	-- 経過時間を加算.
    state.elapsedTimeMs += math.max(0, now - state.timerLastUpdateAt)
    state.timerLastUpdateAt = now
end

function GameController:finishNextAnimation()
    if self.state.timeAttackVictoryPending or self.state.coreRushVictoryPending then
        self:beginVictory()
    elseif self.state.practiceVictoryPending then
        self:beginPracticeVictory()
    elseif self.state.nextAnimationGameOver then
        self:beginGameOver()
    else
        self.state.phase = GamePhase.INPUT
    end
end

-- 回転の開始.
function GameController:startRotation()
    local state = self.state
    if state.rotationEvaluation == 0 then
        self:finishTurn()
        return
    end

    state.rotationClockwise = state.rotationEvaluation > 0
    self.undoController:recordRotation(state.rotationClockwise)
    state.rotationStartBoard = state.board
    state.rotationEndBoard = BoardTransform.rotate(
        state.rotationStartBoard, state.rotationClockwise,
        function(x, y) return BoardRules.isPlayable(x, y, state.mode) end)

    local oldActiveX, oldActiveY = state.activeMergeX, state.activeMergeY
    if state.rotationClockwise then
        state.activeMergeX = Config.BOARD_SIZE + 1 - oldActiveY
        state.activeMergeY = oldActiveX
    else
        state.activeMergeX = oldActiveY
        state.activeMergeY = Config.BOARD_SIZE + 1 - oldActiveX
    end

    state.animationProgress = 0
    state.animationDuration = 0.38
    self.sound:play_se("rotate")
    state.phase = GamePhase.ROTATING
end

-- コンボ音の再生.
function GameController:playComboSoundIfNeeded()
    local state = self.state
    if state.combo < 2 or state.comboSoundPlayed then
		return -- 再生不要.
	end
    state.comboSoundPlayed = true
    state.comboDisplayFrame = 0
    if state.combo < 3 then
		-- 2 COMBO.
        self.sound:play_se("combo1")
    elseif state.combo < 5 then
		-- 3～4 COMBO.
        self.sound:play_se("combo2")
    else
		-- 5 COMBO以上.
        self.sound:play_se("combo3")
    end
end

-- マージの解決を開始する.
function GameController:startResolve(nextAction)
    local state = self.state
    self:applyGravity()
    local x1, y1, x2, y2 = MergeResolver.findForActive(
        state.board, state.activeMergeX, state.activeMergeY, state.mode)
    if x1 == nil then
        self:playComboSoundIfNeeded()
        if nextAction == "ROTATE" then self:startRotation()
        else self:finishTurn() end
        return
    end

    state.mergeSourceX, state.mergeSourceY = x1, y1
    state.mergeTargetX, state.mergeTargetY = x2, y2
    state.mergeValue = state.board:get(x1, y1) * 2
    state.mergeNextAction = nextAction
    state.animationProgress = 0
    state.animationDuration = 0.22
    self.sound:play_se("merge")
    state.phase = GamePhase.MERGING
end

-- マージの完了処理.
function GameController:finishMerge()
    local state = self.state
    local evaluation = MergeResolver.getEvaluation(
        state.mergeSourceX, state.mergeTargetX)
    self:addRotationEvaluation(evaluation)
    if state.mergeTargetX < state.mergeSourceX then
        self:addPreviewImpulse(Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT)
    elseif state.mergeTargetX > state.mergeSourceX then
        self:addPreviewImpulse(Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT)
    end
    state.board:set(state.mergeSourceX, state.mergeSourceY, 0)
    state.board:set(state.mergeTargetX, state.mergeTargetY, state.mergeValue)
    local timeAttackTarget = Config.TIME_ATTACK_TARGET_VALUE
    if state.mode == Config.GAME_MODE.TIME_ATTACK_256 then
        timeAttackTarget = Config.TIME_ATTACK_256_TARGET_VALUE
    elseif state.mode == Config.GAME_MODE.TIME_ATTACK_512 then
        timeAttackTarget = Config.TIME_ATTACK_512_TARGET_VALUE
    end
    if self:isTimeAttack() and state.mergeValue >= timeAttackTarget then
        state.timeAttackVictoryPending = true
    end
    self.session:recordMerge(state.mergeValue)
    if state.mode == Config.GAME_MODE.NORMAL and self.statisticsRunEligible
        and not self.replayMode and not self.autoPlayEnabled then
        local normal = state.statistics.normal
        if state.mergeValue > normal.highestTile then
            normal.highestTile = state.mergeValue
            self.statisticsDirty = true
        end
        if state.combo > normal.maxCombo then
            normal.maxCombo = state.combo
            self.statisticsDirty = true
        end
    end
    self:applyLevelProgress(LevelProgress.recordMerge(state, state.mergeValue))
    state.practiceMergeCount += 1
    state.activeMergeX, state.activeMergeY = state.mergeTargetX, state.mergeTargetY
    self:addCoreRushValue(state.mergeValue)
    self:updatePracticeObjective()
    self:startResolve(state.mergeNextAction)
end

function GameController:finishDrop()
    local state = self.state
    state.board:set(state.pendingDropX, state.pendingDropY, state.pendingDropValue)
    self:applyLevelProgress(LevelProgress.recordDrop(state))
    state.pendingDropValue = 0
    state.activeMergeX, state.activeMergeY = state.pendingDropX, state.pendingDropY
    self:addRotationEvaluation(Config.ROTATION_EVALUATION_DROP_POSITION_WEIGHT
        * MergeResolver.getPositionEvaluation(state.pendingDropX))
    self:addPreviewImpulse(MergeResolver.getPositionEvaluation(state.pendingDropX))
    self:startResolve("ROTATE")
    if state.phase ~= GamePhase.MERGING then self.sound:play_se("fixed") end
end

function GameController:advanceAnimation()
    local state = self.state
    state.previewImpulseRotationDegrees *= Config.PREVIEW_IMPULSE_DECAY
    state.animationProgress += 1
        / (state.animationDuration * Config.DEFAULT_REFRESH_RATE)
    if state.animationProgress < 1 then return end
    state.animationProgress = 1

    if state.phase == GamePhase.DROPPING then
        self:finishDrop()
    elseif state.phase == GamePhase.MERGING then
        self:finishMerge()
    elseif state.phase == GamePhase.ROTATING then
        state.board = state.rotationEndBoard
        state.phase = GamePhase.ROTATING
        self:startResolve("FINISH")
    elseif state.phase == GamePhase.UNDO_ROTATING then
        state.board = state.rotationEndBoard
        state.rotationStartBoard = nil
        state.rotationEndBoard = nil
        state.phase = GamePhase.INPUT
    elseif state.phase == GamePhase.NEXT_ANIM then
        self:finishNextAnimation()
    elseif state.phase == GamePhase.HOLD_ANIM then
        self:finishHoldAnimation()
    end
end

-- ゲーム開始時に初期ブロックを生成する.
function GameController:spawnInitialBlocks()
    local state = self.state
    if not self:isCoreRush() then
        local initialValue = 8
        if state.mode == Config.GAME_MODE.TIME_ATTACK_256 then
            initialValue = 128
        elseif state.mode == Config.GAME_MODE.TIME_ATTACK_512 then
            initialValue = 256
        end
        state.board:set(Config.CENTER - 1, Config.CENTER, initialValue)
        state.board:set(Config.CENTER + 1, Config.CENTER, initialValue)
    end
end

-- Practiceモードのシナリオを適用する.
function GameController:applyPracticeScenario(scenario)
    local state = self.state
    state.practiceScenarioId = scenario.id
    state.practiceDescriptionText = PracticeStageLoader.descriptionForSystemLanguage(
        scenario)
    state.practiceTurnLimit = math.max(0, scenario.turnLimit or 0)
    state.practiceNextValues = {}
    state.practiceNextIndex = 1
    state.practiceSpawnCount = 0
    state.practiceNextPolicy = scenario.nextPolicy or "LOOP"
    state.practiceNextExhausted = false
    state.practiceObjectiveMode = scenario.objectiveMode or "ANY"
    state.practiceObjectives = {}
    for i, objective in ipairs(scenario.objectives or {}) do
        state.practiceObjectives[i] = objective
    end

    for _, block in ipairs(scenario.initialBoard or {}) do
        assert(block.x >= 1 and block.x <= Config.BOARD_SIZE,
            "Practice block x is out of range")
        assert(block.y >= 1 and block.y <= Config.BOARD_SIZE,
            "Practice block y is out of range")
        assert(not BoardRules.isCenter(block.x, block.y),
            "Practice block cannot occupy the center cell")
        assert(block.value > 0, "Practice block value must be positive")
        assert(state.board:get(block.x, block.y) == 0,
            "Practice scenario contains duplicate board coordinates")
        state.board:set(block.x, block.y, block.value)
    end

    assert(scenario.nextValues ~= nil and #scenario.nextValues > 0,
        "Practice scenario must define nextValues")
    for i, value in ipairs(scenario.nextValues) do
        assert(value > 0, "Practice next value must be positive")
        state.practiceNextValues[i] = value
    end
end

-- ゲームの開始.
function GameController:start(mode, practiceStage, options)
    options = options or {}
    self:flushStatistics()
    local state = self.state
    self.replayMode = options.replayData ~= nil
    self.replayData = options.replayData
    self.replayIndex = 1
    self.replayEventStartedAt = nil
    self.replayExecuting = false
    self.replayRemainingHolds = 0
    self.replaySaved = false
    self.suspendRestoreActive = options.restoring == true
    if not self.suspendRestoreActive then self.suspendRestoreData = nil end
    state.replayActive = self.replayMode
    state.replayPaused = false
    state.replayPauseStartedAt = nil
    state.suspendRestoreActive = self.suspendRestoreActive
    local seed = options.seed or self:createReplaySeed()
    self.randomGenerator:setSeed(seed)
    state.mode = mode or Config.GAME_MODE.NORMAL
    self.statisticsRunStarted = false
    self.statisticsRunEligible = not self.autoPlayEnabled and not self.replayMode
    self.statisticsResultRecorded = false
    self.statisticsLastTickMs = nil
    self.statisticsNormalHighestTileAtStart = state.statistics.normal.highestTile
    self.statisticsNormalMaxComboAtStart = state.statistics.normal.maxCombo
    self.statisticsNormalHighScoreAtStart = state.statistics.normal.highScore
    self.statisticsNormalBestLevelAtStart = state.statistics.normal.bestLevel
    if state.mode == Config.GAME_MODE.NORMAL and not self.replayMode
        and not self.suspendRestoreActive then
        ReplayController.deleteSuspend(pd)
    end
    if practiceStage ~= nil then self.practiceStage = practiceStage end
    self:clearBoard()
    state.result = nil
    state.score = 0
    LevelProgress.reset(state, not self.autoPlayEnabled and not self.replayMode)
    state.coreRushValue = 0
    state.coreRushGainCombo = 0
    state.coreRushGainMergeValue = 0
    state.coreRushGainTotal = 0
    state.coreRushGainUntil = 0
    state.coreRushCompleteUntil = 0
    state.coreRushVictoryPending = false
    state.timeAttackVictoryPending = false
    state.highScore = state.normalHighScore
    state.elapsedTimeMs = 0
    state.remainingTimeMs = nil
    state.timerStartedAt = nil
    state.timerLastUpdateAt = nil
    state.timeoutPending = false
    state.practiceTurnLimit = 0
    state.practiceTurnCount = 0
    state.holdValue = 0
    state.holdAvailable = true
    state.lastRandomBlockValue = 0
    state.consecutiveRandomBlockCount = 0
    state.undoStates = {}
    state.rewindUsesRemaining = Config.MAX_REWIND_USES
    self.session:resetCombo()
    state.cursorX = Config.CENTER
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
    state.animationProgress = 0
    state.animationDuration = 0
    state.pendingDropX, state.pendingDropY, state.pendingDropValue = 0, 0, 0
    state.rotationStartBoard, state.rotationEndBoard = nil, nil
    state.rotationClockwise = false
    state.mergeSourceX, state.mergeSourceY = 0, 0
    state.mergeTargetX, state.mergeTargetY = 0, 0
    state.mergeValue = 0
    state.mergeNextAction = "FINISH"
    state.activeMergeX, state.activeMergeY = 0, 0
    state.nextAnimationGameOver = false
    state.holdAnimationSourceValue, state.holdAnimationReturnValue = 0, 0
    state.holdAnimationNextValue = 0
    state.rotationEvaluation = 0
    state.nextValues = {}
    state.practiceScenarioId = nil
    state.practiceNextValues = {}
    state.practiceNextIndex = 1
    state.practiceNextPolicy = nil
    state.practiceNextExhausted = false
    state.practiceObjectives = {}
    state.practiceObjectiveMode = "ANY"
    state.practiceMergeCount = 0
    state.practiceVictoryPending = false
    state.practiceCompleteUntil = 0
    state.practiceObjectiveText = ""
    state.practiceDescriptionText = ""
    self.autoPlayer:reset()
    state.previewImpulseRotationDegrees = 0
    if state.mode == Config.GAME_MODE.PRACTICE then
        if self.practiceStage == nil then
            local stages = PracticeStageLoader.loadAll()
            self.practiceStage = stages[1]
        end
        assert(self.practiceStage ~= nil, "No practice stages found")
        self:applyPracticeScenario(self.practiceStage)
        for i = 1, Config.NEXT_QUEUE_COUNT do
            state.nextValues[i] = self:getPracticeNextValue()
        end
    else
        self:spawnInitialBlocks()
        for i = 1, Config.NEXT_QUEUE_COUNT do
            state.nextValues[i] = TileGenerator.nextForState(
                state.board, state, self.randomGenerator)
        end
    end
    if not self.replayMode and state.mode == Config.GAME_MODE.NORMAL then
        self.replayController:start(state.mode, nil, seed)
    elseif not self.replayMode then
        self.replayController:cancelRecording()
    end
    self:updateHoldAvailability()
    if state.mode == Config.GAME_MODE.PRACTICE
        and #state.practiceObjectives > 0 then
        state.practiceObjectiveText = self:formatPracticeObjective(
            state.practiceObjectives[1])
    end
    state.phase = GamePhase.INPUT
	-- "GET READY" 表示開始.
    state.startReadyUntil = self.suspendRestoreActive
        and 0 or pd.getCurrentTimeMilliseconds() + 1000
    state.message = ""
    state.crisisBgmActive = false
	-- BGM再生開始.
    if not self.suspendRestoreActive then
	    self.sound:playGameBgm()
	    -- 開始SEの再生
	    self.sound:play_se("start")
    end
end

function GameController:holdCurrentBlock()
    local state = self.state
    local currentValue = state.nextValues[1]
    if currentValue == 0 then
        self:beginGameOver()
        return false
    end
    if not state.holdAvailable then
		-- HOLDできない.
		self:setMessage("CAN'T HOLD", 700)
		self.sound:play_se("error")
        return false
    end
    state.holdAnimationSourceValue = currentValue
    state.holdAnimationReturnValue = state.holdValue
    state.holdAnimationNextValue = 0
    if state.holdValue == 0 then
        state.holdValue = currentValue
        self:updatePracticeObjective()
        self:advanceNextQueue()
        self:promoteHoldIfNextEmpty()
        -- 空HOLDでは、繰り上がったNEXTを選択列の落下開始位置へ移動する。
        state.holdAnimationNextValue = state.nextValues[1]
    else
        state.holdValue, state.nextValues[1] = currentValue, state.holdValue
        self:updatePracticeObjective()
    end
    -- HOLDはDROP前の待機中であれば何度でも使用できる。
    -- UNDOはDROP開始時のスナップショットへ戻すため、HOLD単体は履歴に残さない。
    self:updateHoldAvailability()
    self.sound:play_se("hold")
    state.animationProgress = 0
    state.animationDuration = 0.30
    state.phase = GamePhase.HOLD_ANIM
    if not self.replayMode then
        self.replayController:noteHold()
        self.replayController:pauseDecision(pd.getCurrentTimeMilliseconds())
    end
    return true
end

function GameController:finishHoldAnimation()
    local state = self.state
    self:promoteHoldIfNextEmpty()
    state.holdAnimationSourceValue = 0
    state.holdAnimationReturnValue = 0
    state.holdAnimationNextValue = 0
    if state.practiceVictoryPending then
        if not self.replayMode then
            self.replayController:recordTurn(
                pd.getCurrentTimeMilliseconds(), state.cursorX, false)
        end
        self:beginPracticeVictory()
    elseif state.nextValues[1] == 0 or not self:canDropInAnyColumn() then
        if not self.replayMode then
            self.replayController:recordTurn(
                pd.getCurrentTimeMilliseconds(), state.cursorX, false)
        end
        self:beginGameOver()
    else state.phase = GamePhase.INPUT end
end

function GameController:beginDrop()
    local state = self.state
    if state.nextValues[1] == 0 then
        self:beginGameOver()
        return false
    end
    if not self:isDropAvailable() then
        self:setMessage("NO SPACE", 700)
        self.sound:play_se("error")
        return false
    end
    self:recordStatisticsPlay()
    local x, y = self:findDropCell(state.cursorX)
    if not self.replayMode then
        self.replayController:recordTurn(
            pd.getCurrentTimeMilliseconds(), state.cursorX, true)
    end
    self.undoController:save()
    if state.mode == Config.GAME_MODE.PRACTICE then
        state.practiceTurnCount += 1
    end
    self.session:resetCombo()
    state.pendingDropX, state.pendingDropY = x, y
    state.pendingDropValue = state.nextValues[1]
    state.rotationEvaluation = 0
    state.animationProgress = 0
    state.animationDuration = math.max(0.18, (y + 1) * 0.07)
    self.sound:play_se("fall")
    state.phase = GamePhase.DROPPING
    return true
end

function GameController:moveCursor(delta)
    local state = self.state
    local previous = state.cursorX
    state.cursorX = math.max(1, math.min(Config.BOARD_SIZE, state.cursorX + delta))
    if previous ~= state.cursorX then self.sound:play_se("pi") end
end

function GameController:executeCommand(command)
    if command == InputCommand.HOLD then return self:holdCurrentBlock()
    elseif command == InputCommand.MOVE_LEFT then
        self:moveCursor(-1)
        return true
    elseif command == InputCommand.MOVE_RIGHT then
        self:moveCursor(1)
        return true
    elseif command == InputCommand.DROP then return self:beginDrop()
    elseif command == InputCommand.REWIND then
        local restored = self.undoController:restore()
        if restored and not self.replayMode then
            self.replayController:recordRewind(pd.getCurrentTimeMilliseconds())
        end
        return restored
    end
    return false
end

-- カーソルキーのリピート状態をリセットする.
function GameController:resetCursorKeyRepeat()
    CursorController.reset(self.cursorController)
    self.state.cursorRepeatDirection = Config.DIRECTION.NONE
    self.state.cursorRepeatNextAt = nil
end

-- カーソルキーのリピート状態を更新する.
function GameController:updateCursorKeyRepeat()
    local state = self.state
    CursorController.update(self.cursorController, pd,
        pd.getCurrentTimeMilliseconds(), function(delta)
            self:executeCommand(delta < 0
                and InputCommand.MOVE_LEFT or InputCommand.MOVE_RIGHT)
        end)
    state.cursorRepeatDirection = self.cursorController.direction
    state.cursorRepeatNextAt = self.cursorController.nextAt
end

function GameController:completeReplayEvent()
    self.replayIndex += 1
    self.replayEventStartedAt = nil
    self.replayExecuting = false
    self.replayRemainingHolds = 0
end

-- リプレイ再生の一時停止を切り替える.
-- 再開時は停止時間を待ち時間と開始演出の基準時刻から除外する.
function GameController:toggleReplayPause(now)
    local state = self.state
    if not self.replayMode or self.suspendRestoreActive or state.result ~= nil then
        return
    end

    if not state.replayPaused then
        state.replayPaused = true
        state.replayPauseStartedAt = now
        return
    end

    local pausedDuration = math.max(0, now - (state.replayPauseStartedAt or now))
    if self.replayEventStartedAt ~= nil then
        self.replayEventStartedAt += pausedDuration
    end
    if state.startReadyUntil ~= 0 then
        state.startReadyUntil += pausedDuration
    end
    state.replayPaused = false
    state.replayPauseStartedAt = nil
end

-- 受理済みのアニメーションを論理的な安定状態まで完了させる関数.
---@return boolean INPUT状態へ到達したかどうか
function GameController:settleAnimationsForSuspend()
    local previousSuppressed = self.sound.effectsSuppressed
    self.sound.effectsSuppressed = true
    local steps = 0
    while GameState.isAnimating(self.state) and steps < 1000 do
        self.state.animationProgress = 1
        self:advanceAnimation()
        steps += 1
    end
    self.sound.effectsSuppressed = previousSuppressed
    return self.state.phase == GamePhase.INPUT and self.state.result == nil
end

-- 現在のNORMALプレイを中断保存する関数.
---@return boolean 保存に成功したかどうか
function GameController:suspendNormalGame()
    local state = self.state
    if state.mode ~= Config.GAME_MODE.NORMAL or self.replayMode
        or self.suspendRestoreActive then return false end
    if state.result ~= nil then
        ReplayController.deleteSuspend(pd)
        return false
    end
    if not self:settleAnimationsForSuspend() then
        if state.result ~= nil then ReplayController.deleteSuspend(pd) end
        return false
    end
    self:resetCursorKeyRepeat()
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
    self:flushStatistics()
    return self.replayController:saveSuspend(
        state, self.randomGenerator:getState(), {
            started = self.statisticsRunStarted,
            eligible = self.statisticsRunEligible,
            normalHighScoreAtStart = self.statisticsNormalHighScoreAtStart,
            normalBestLevelAtStart = self.statisticsNormalBestLevelAtStart,
            normalHighestTileAtStart = self.statisticsNormalHighestTileAtStart,
            normalMaxComboAtStart = self.statisticsNormalMaxComboAtStart,
        })
end

function GameController:stopReplayWithError()
    self.replayIndex = #(self.replayData.events or {}) + 1
    self.replayEventStartedAt = nil
    self.replayExecuting = false
    self:setMessage("REPLAY DESYNC", 3000)
end

function GameController:updateReplayPlayback(now, ignoreWait)
    local state = self.state
    local events = self.replayData ~= nil and self.replayData.events or {}
    local event = events[self.replayIndex]
    if event == nil then return end

    if self.replayEventStartedAt == nil then
        self.replayEventStartedAt = now
    end
    if not self.replayExecuting then
        if not ignoreWait
            and now - self.replayEventStartedAt < (event.waitMs or 0) then return end
        self.replayExecuting = true
        self.replayRemainingHolds = event.holdApplications or 0
    end

    if event.type == "REWIND" then
        if not self:executeCommand(InputCommand.REWIND) then
            self:stopReplayWithError()
            return
        end
        self:completeReplayEvent()
        return
    end
    if event.type ~= "TURN" and event.type ~= "CHECKPOINT" then
        self:stopReplayWithError()
        return
    end

    local targetColumn = math.max(1, math.min(Config.BOARD_SIZE,
        event.targetColumn or state.cursorX))
    if state.cursorX < targetColumn then
        self:executeCommand(InputCommand.MOVE_RIGHT)
        return
    elseif state.cursorX > targetColumn then
        self:executeCommand(InputCommand.MOVE_LEFT)
        return
    end

    if self.replayRemainingHolds > 0 then
        if not self:executeCommand(InputCommand.HOLD) then
            self:stopReplayWithError()
            return
        end
        self.replayRemainingHolds -= 1
        if self.replayRemainingHolds == 0 and event.drop == false then
            self:completeReplayEvent()
        end
        return
    end

    if event.drop == false then
        self:completeReplayEvent()
        return
    end
    if not self:executeCommand(InputCommand.DROP) then
        self:stopReplayWithError()
        return
    end
    self:completeReplayEvent()
end

-- 中断イベントを高速適用し、通常プレイへ引き継ぐ関数.
---@return table? シーン遷移要求
function GameController:updateSuspendRestore()
    local state = self.state
    local data = self.suspendRestoreData
    if data == nil then
        self.suspendRestoreActive = false
        state.suspendRestoreActive = false
        state.replayActive = false
        self.replayMode = false
        self.sound.effectsSuppressed = false
        self.titleNotice = "SUSPEND DATA ERROR"
        return { scene = Config.SCENE.TITLE }
    end

    for _ = 1, Config.SUSPEND_RESTORE_STEPS_PER_FRAME do
        if state.result ~= nil then break end
        if GameState.isAnimating(state) then
            state.animationProgress = 1
            self:advanceAnimation()
        elseif self.replayIndex <= #(data.events or {}) then
            self:updateReplayPlayback(pd.getCurrentTimeMilliseconds(), true)
        else
            local checksum = ReplayController.suspendChecksum(
                state, self.randomGenerator:getState())
            if checksum ~= data.checkpointChecksum then break end

            self.replayMode = false
            self.replayData = nil
            self.replayIndex = 1
            self.replayEventStartedAt = nil
            self.replayExecuting = false
            self.replayRemainingHolds = 0
            self.suspendRestoreActive = false
            self.suspendRestoreData = nil
            state.replayActive = false
            state.suspendRestoreActive = false
            state.levelRecordEligible = data.levelRecordEligible ~= false
            self.replayController:resume(data)
            ReplayController.deleteSuspend(pd)
            self.sound.effectsSuppressed = false
            self.sound:playGameBgm()
            self:setMessage("GAME RESUMED", 1000)
            return nil
        end
    end

    local exhausted = self.replayIndex > #(data.events or {})
        and not GameState.isAnimating(state)
    if state.result ~= nil or exhausted then
        self.replayController:cancelRecording()
        self.replayMode = false
        self.replayData = nil
        self.suspendRestoreActive = false
        self.suspendRestoreData = nil
        state.replayActive = false
        state.suspendRestoreActive = false
        self.sound.effectsSuppressed = false
        self.titleNotice = "SUSPEND DATA ERROR"
        return { scene = Config.SCENE.TITLE }
    end
    return nil
end

function GameController:finishReplayRecordingIfNeeded()
    if self.replaySaved or self.state.result == nil then return end
    self.replaySaved = true
    if self.replayMode then
        local checksum = ReplayController.checksum(
            self.state, self.randomGenerator:getState())
        if self.replayData.finalChecksum ~= nil
            and checksum ~= self.replayData.finalChecksum then
            self:setMessage("REPLAY DESYNC", 3000)
        end
        return
    end
    if self.state.mode == Config.GAME_MODE.NORMAL then
        ReplayController.deleteSuspend(pd)
    end
    if not self.replayController:finish(
        self.state, self.randomGenerator:getState()) then
        self:setMessage("REPLAY NOT SAVED", 3000)
    end
end

-- 更新.
function GameController:update()
    local state = self.state
    if self.suspendRestoreActive then return self:updateSuspendRestore() end
    local now = pd.getCurrentTimeMilliseconds()
    if self.replayMode and state.result == nil
        and (pd.buttonJustPressed(pd.kButtonA)
            or pd.buttonJustPressed(pd.kButtonB)) then
        self:toggleReplayPause(now)
        return nil
    end
    if state.replayPaused then return nil end
    self:updateStatisticsPlayTime(now)
    if state.levelUpDisplayFrame < Config.LEVEL_UP_DISPLAY_FRAMES then
        state.levelUpDisplayFrame += 1
    end
    if state.startReadyUntil ~= 0 then
        if now < state.startReadyUntil then return nil end
        state.startReadyUntil = 0
        if self:isTimeAttack() or self:isCoreRush() then
            state.timerStartedAt = now
            state.timerLastUpdateAt = now
        end
        return nil
    end
    self:updateTimeAttackTimer()

    if state.coreRushCompleteUntil ~= 0 then
        if pd.getCurrentTimeMilliseconds() >= state.coreRushCompleteUntil then
            state.coreRushCompleteUntil = 0
            state.result = GameResult.VICTORY
            if self:isCoreRush() then self:saveCoreRushBestTime()
            elseif self:isTimeAttack() then self:saveTimeAttackBestTime() end
            self:finishReplayRecordingIfNeeded()
            return { scene = Config.SCENE.GAME_OVER }
        end
        return nil
    end

    if state.practiceCompleteUntil ~= 0 then
        if pd.getCurrentTimeMilliseconds() >= state.practiceCompleteUntil then
            state.practiceCompleteUntil = 0
            state.result = GameResult.VICTORY
            self:finishReplayRecordingIfNeeded()
            return { scene = Config.SCENE.GAME_OVER }
        end
        return nil
    end

    if state.phase ~= GamePhase.INPUT then self:resetCursorKeyRepeat() end

    if state.phase == GamePhase.INPUT and state.result == nil and not self.replayMode then
        self.replayController:beginDecision(
            pd.getCurrentTimeMilliseconds(), state.holdValue == 0)
    end

    if state.phase == GamePhase.INPUT then
        if self.replayMode then
            self:updateReplayPlayback(pd.getCurrentTimeMilliseconds())
        elseif self.autoPlayEnabled then
            local command = self.autoPlayer:poll(nil, {
                phase = state.phase,
                cursorX = state.cursorX,
                nextValue = state.nextValues[1],
                holdValue = state.holdValue,
                holdAvailable = state.holdAvailable,
                mode = state.mode,
                getCandidates = function(activeValue)
                    return MergeResolver.getAutoPlayCandidates(
                        state.board, activeValue, state.mode)
                end,
            })
            self:executeCommand(command)
        else
            self:updateRewindHold()
            if pd.buttonJustPressed(pd.kButtonA) then
                self:executeCommand(InputCommand.HOLD)
            elseif pd.buttonJustPressed(pd.kButtonLeft)
                or pd.buttonJustPressed(pd.kButtonRight) then
                self:updateCursorKeyRepeat()
            elseif pd.buttonJustPressed(pd.kButtonDown) then
                self:executeCommand(InputCommand.DROP)
            elseif pd.buttonJustPressed(pd.kButtonB) then self:beginRewindHold()
            elseif state.cursorRepeatDirection ~= 0 then
                self:updateCursorKeyRepeat()
            end
        end
    elseif state.phase == GamePhase.PAUSED
        and pd.buttonJustPressed(pd.kButtonB) then
        state.phase = GamePhase.INPUT
    end

    if state.phase == GamePhase.DROPPING or state.phase == GamePhase.MERGING
        or state.phase == GamePhase.ROTATING
        or state.phase == GamePhase.UNDO_ROTATING
        or state.phase == GamePhase.NEXT_ANIM
        or state.phase == GamePhase.HOLD_ANIM then
        self:advanceAnimation()
    end

    if state.result ~= nil then
        self:finishReplayRecordingIfNeeded()
        return { scene = Config.SCENE.GAME_OVER }
    end
    return nil
end

_G.GameController = GameController
return GameController
