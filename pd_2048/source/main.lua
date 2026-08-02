import "CoreLibs/graphics"
import "array2d"
import "game_context"
import "game_config"
import "game_state"
import "board/board_transform"
import "tile_generator"
import "undo_history"
import "board/board_rules"
import "cursor_controller"
import "input/input_command"
import "input/auto_player"
import "render/game_renderer"
import "render/overlay_renderer"
import "turn_resolver"
import "scene/scene_manager"
import "scene/scene_context"
import "scene/scene_title"
import "scene/scene_game_normal"
import "scene/scene_game_over"

local pd <const> = playdate
local gfx <const> = pd.graphics
local gameContext <const> = GameContext.getInstance()
local sound <const> = gameContext.sound
local Config <const> = GameConfig
local cursorController <const> = CursorController.new()
local autoPlayer <const> = AutoPlayer.new()
local autoPlayEnabled = false

local DEFAULT_REFRESH_RATE <const> = Config.DEFAULT_REFRESH_RATE -- ディスプレイの更新レート (FPS。フレーム毎秒).
local CURSOR_KEY_REPEAT_INITIAL_DELAY_MS <const> = Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS -- 左右キーを押し続けたとき、最初にリピートするまでの待ち時間.
local CURSOR_KEY_REPEAT_INTERVAL_MS <const> = Config.CURSOR_KEY_REPEAT_INTERVAL_MS -- 左右キーを押し続けたときのリピート間隔.
local BOARD_SIZE <const> = Config.BOARD_SIZE
local CENTER <const> = Config.CENTER
-- 落下対象を除いたブロックを表示するため、表示数より1つ多く保持する.
local NEXT_QUEUE_COUNT <const> = Config.NEXT_QUEUE_COUNT
local MAX_REWIND_USES <const> = Config.MAX_REWIND_USES
local REWIND_HOLD_DURATION_MS <const> = Config.REWIND_HOLD_DURATION_MS
-- コンボ表示時間.
local COMBO_SCORE_COEFFICIENT <const> = Config.COMBO_SCORE_COEFFICIENT
local COMBO_SCORE_EXPONENT <const> = Config.COMBO_SCORE_EXPONENT
local SCORE_MULTIPLIER <const> = Config.SCORE_MULTIPLIER
-- 方向定数.
local DIRECTION_DOWN <const> = Config.DIRECTION.DOWN
local DIRECTION_LEFT <const> = Config.DIRECTION.LEFT
local DIRECTION_RIGHT <const> = Config.DIRECTION.RIGHT
local DIRECTION_UP <const> = Config.DIRECTION.UP
local Scene <const> = Config.SCENE
local GamePhase <const> = Config.GAME_PHASE
local GameResult <const> = Config.GAME_RESULT
local PREVIEW_ROTATION_MAX_DEGREES <const> = Config.PREVIEW_ROTATION_MAX_DEGREES
local PREVIEW_ROTATION_EVALUATION_MULTIPLIER <const> = Config.PREVIEW_ROTATION_EVALUATION_MULTIPLIER
local PREVIEW_IMPULSE_ROTATION_DEGREES <const> = Config.PREVIEW_IMPULSE_ROTATION_DEGREES
-- 回転方向の評価値.
local ROTATION_EVALUATION_POSITION_RIGHT <const> = Config.ROTATION_EVALUATION_POSITION_RIGHT -- 右側の位置を評価する値.
local ROTATION_EVALUATION_POSITION_LEFT <const> = Config.ROTATION_EVALUATION_POSITION_LEFT -- 左側の位置を評価する値.
local ROTATION_EVALUATION_POSITION_CENTER <const> = Config.ROTATION_EVALUATION_POSITION_CENTER -- 中央の位置を評価する値.
local ROTATION_EVALUATION_DROP_POSITION_WEIGHT <const> = Config.ROTATION_EVALUATION_DROP_POSITION_WEIGHT -- 落下位置の評価値の重み.
local ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT <const> = Config.ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT -- 消えたブロックの評価値の重み.
local ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT <const> = Config.ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT -- マージされたブロックの評価値の重み.
local ROTATION_EVALUATION_MERGE_DIRECTION_LEFT <const> = Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT -- マージ方向の評価値 (左方向).
local ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT <const> = Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT -- マージ方向の評価値 (右方向).
local ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT <const> = Config.ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT -- マージ方向が上下の場合の評価値の重み.
local state = GameState.new()
local finishHoldAnimation

-- メニューBGMの再生.
local function playMenuBgm()
    sound:setBgmRandomMode(BGMRandomMode.MENU)
    sound:play_bgm(-1, false)
end

-- メインゲームBGMの再生.
local function playGameBgm()
    sound:setBgmRandomMode(BGMRandomMode.NOMAL)
    sound:play_bgm(-1, false)
end

-- 中央から見たブロックの左右位置を評価する.
-- 右側を正、左側を負、中央を0とする.
local function getPositionEvaluation(x)
    if x > CENTER then
        return ROTATION_EVALUATION_POSITION_RIGHT
    elseif x < CENTER then
        return ROTATION_EVALUATION_POSITION_LEFT
    end
    return ROTATION_EVALUATION_POSITION_CENTER
end

-- マージ方向の評価を返す.
-- 左方向を負、右方向を正とし、上下方向はマージ後の位置を評価する.
local function getMergeDirectionEvaluation(sourceX, targetX)
    if targetX < sourceX then
        return ROTATION_EVALUATION_MERGE_DIRECTION_LEFT
    elseif targetX > sourceX then
        return ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT
    end
    return ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT * getPositionEvaluation(targetX)
end

local function getMergeEvaluation(sourceX, targetX)
    return ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT * getPositionEvaluation(sourceX)
        + ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT * getPositionEvaluation(targetX)
        + getMergeDirectionEvaluation(sourceX, targetX)
end

-- 方向の力を一時的なプレビュー反動として加算する.
local function addPreviewImpulse(direction)
    if direction == ROTATION_EVALUATION_POSITION_CENTER then
        return
    end
    if direction > 0 then
        state.previewImpulseRotationDegrees += PREVIEW_IMPULSE_ROTATION_DEGREES
    else
        state.previewImpulseRotationDegrees -= PREVIEW_IMPULSE_ROTATION_DEGREES
    end
end

local function addRotationEvaluation(value)
	-- 加算倍率を適用.
	value *= PREVIEW_ROTATION_EVALUATION_MULTIPLIER
    state.rotationEvaluation += value
	--print("state.rotationEvaluation"	 .. state.rotationEvaluation)
	-- 傾き制限を適用.
	state.rotationEvaluation = math.max(-PREVIEW_ROTATION_MAX_DEGREES,
		math.min(PREVIEW_ROTATION_MAX_DEGREES, state.rotationEvaluation))
end

local function setMessage(text, duration)
    state.message = text
    state.messageUntil = pd.getCurrentTimeMilliseconds() + duration
end

-- ハイスコアのロード.
local function loadHighScore()
    local ok, value = pcall(pd.datastore.read, "highScore")
    if ok and type(value) == "number" then
        state.highScore = value
    end
end

-- ハイスコアの保存.
local function saveHighScore()
    if state.score > state.highScore then
        state.highScore = state.score
        pd.datastore.write(state.highScore, "highScore")
    end
end

-- 盤面を初期化する.
local function clearBoard()
    state.board = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    state.board:set(CENTER, CENTER, 0)
end

-- 1手前の状態を履歴に保存する。
local function saveUndoState(action)
    UndoHistory.push(state.undoStates, {
        board = state.board, score = state.score, cursorX = state.cursorX,
        holdValue = state.holdValue, holdAvailable = state.holdAvailable,
        lastRandomBlockValue = state.lastRandomBlockValue,
        consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
        nextValues = state.nextValues,
    }, action)
end

-- 直前の手を取り消す。取り消しは最大MAX_UNDO_COUNT手分可能。
local function isRewindAvailable()
    return UndoHistory.canRestore(state.undoStates, state.rewindUsesRemaining)
end

-- 巻き戻しを実行.
local function undoLastTurn()
    if not isRewindAvailable() then
        if state.rewindUsesRemaining <= 0 then
            setMessage("NO REWINDS", 700)
        else
            setMessage("NO UNDO", 700)
        end
        return false
    end

    local restored = UndoHistory.pop(state.undoStates)
    local rewindHoldAnimation = restored.action == "HOLD"
    state.rewindHoldAnimationActive = rewindHoldAnimation
    if rewindHoldAnimation then
        -- HOLD操作後に表示されていたブロックを、復元前のHOLDへ戻す。
        -- 復元前のHOLDブロックは、復元後の現在ブロックへ向かわせる。
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

    state.combo = 0
    state.comboBonusScore = 0
    state.comboDisplayFrame = 0
    state.comboSoundPlayed = false
    state.rotationEvaluation = 0
    state.previewImpulseRotationDegrees = 0
    state.pendingDropValue = 0
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    state.nextAnimationGameOver = false
    state.message = ""
    state.crisisBgmActive = false

	sound:play_se("rewind")
    if restored.hasRotation then
        -- 現在の盤面を逆回転させながら、取り消し前の盤面へ戻す。
        state.board = currentBoard
        state.rotationStartBoard = currentBoard
        state.rotationEndBoard = restored.board
        state.rotationClockwise = not restored.rotationClockwise
        state.animationProgress = 0
        state.animationDuration = 0.38
        sound:play_se("rotate")
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

-- Bボタン長押しによる巻き戻し入力を開始する。
local function beginRewindHold()
    if not isRewindAvailable() then
		-- 巻き戻しはできない.
		if state.rewindUsesRemaining <= 0 then
            setMessage("NO REWINDS", 700)
        else
            setMessage("NO UNDO", 700)
        end
		sound:play_se("error")
        return
    end
    state.rewindHoldStartedAt = pd.getCurrentTimeMilliseconds()
    state.rewindHoldTriggered = false
	sound:play_se("rewind_button")
end

-- Bボタン長押しによる巻き戻し入力を終了する。
local function endRewindHold()
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
end

-- Bボタンの長押し時間を更新し、
-- 1秒 (REWIND_HOLD_DURATION_MS) 到達時にUNDOを実行する。
local function updateRewindHold()
    if not isRewindAvailable() then
        endRewindHold()
        return
    end

    if state.rewindHoldStartedAt == nil or not pd.buttonIsPressed(pd.kButtonB) then
        if state.rewindHoldStartedAt ~= nil then
			-- 長押し完了.
            endRewindHold()
        end
        return
    end

    if not state.rewindHoldTriggered
        and pd.getCurrentTimeMilliseconds() - state.rewindHoldStartedAt >= REWIND_HOLD_DURATION_MS then
        state.rewindHoldTriggered = true
        undoLastTurn()
    end
end

local function getMaxTileValue()
    local maxValue = 0
    state.board:foreach(function(x, y, value)
        if value > maxValue then
            maxValue = value
        end
    end)
    return maxValue
end

-- ランダムでブロックを抽選する.
local function randomBlockValue()
    local randomState = {
        lastValue = state.lastRandomBlockValue,
        consecutiveCount = state.consecutiveRandomBlockCount,
    }
    local value = TileGenerator.next(state.board, randomState, getMaxTileValue)
    state.lastRandomBlockValue = randomState.lastValue
    state.consecutiveRandomBlockCount = randomState.consecutiveCount
    return value
end

-- 落下可能なセルを見つける.
local function findDropCell(x)
    return BoardRules.findDropCell(state.board, x)
end

-- 現在のカーソル位置からブロックを落とせるかどうかを判定する.
local function isDropAvailable()
    return findDropCell(state.cursorX) ~= nil
end

-- スコアを加算.
local function addScore(value)
    state.score += value * SCORE_MULTIPLIER
    if state.score > state.highScore then
        state.highScore = state.score -- ハイスコア更新.
    end
end

-- 中心軸を空けておく.
local function applyGravity()
    -- 中心軸は見えない固定ブロックとして常に空けておく。
    state.board:set(CENTER, CENTER, 0)
end

-- マージ後もブロックが接続されたままかどうかを判定する.
local function mergeKeepsBlockConnected(sourceX, sourceY, targetX, targetY)
	-- soruceは targetにマージする.
	-- 合成したブロック上下左右に隣接するブロックがあれば接続されたとみなす.
    local neighborX = targetX - 1
    if BoardRules.isPlayable(neighborX, targetY) and neighborX ~= sourceX
        and BoardRules.isOccupied(state.board, neighborX, targetY) then
        return true
    end
    neighborX = targetX + 1
    if BoardRules.isPlayable(neighborX, targetY) and neighborX ~= sourceX
        and BoardRules.isOccupied(state.board, neighborX, targetY) then
        return true
    end
    local neighborY = targetY - 1
    if BoardRules.isPlayable(targetX, neighborY) and neighborY ~= sourceY
        and BoardRules.isOccupied(state.board, targetX, neighborY) then
        return true
    end
    neighborY = targetY + 1
    if BoardRules.isPlayable(targetX, neighborY) and neighborY ~= sourceY
        and BoardRules.isOccupied(state.board, targetX, neighborY) then
        return true
    end
    return false
end

-- 指定したブロックのマージ先を見つける.
local function findMergeForBlock(sourceX, sourceY, activeValue)
	-- 方向の優先順位は「下・左・右・上」の順で、最初に見つかったマージ可能なブロックの位置を返す.
    local fallbackSourceX = 0
    local fallbackSourceY = 0
    local fallbackTargetX = 0
    local fallbackTargetY = 0

    for direction = DIRECTION_DOWN, DIRECTION_UP do
        local dx = 0
        local dy = 0
        if direction == DIRECTION_DOWN then
            dy = 1       -- down
        elseif direction == DIRECTION_LEFT then
            dx = -1      -- left
        elseif direction == DIRECTION_RIGHT then
            dx = 1       -- right
        elseif direction == DIRECTION_UP then
            dy = -1      -- up
        end
        local neighborX = sourceX + dx
        local neighborY = sourceY + dy
        if activeValue ~= 0 and BoardRules.isPlayable(neighborX, neighborY)
            and state.board:get(neighborX, neighborY) == activeValue then
            if mergeKeepsBlockConnected(sourceX, sourceY, neighborX, neighborY) then
                return sourceX, sourceY, neighborX, neighborY
            end
            if fallbackSourceX == 0 then
                fallbackSourceX = sourceX
                fallbackSourceY = sourceY
                fallbackTargetX = neighborX
                fallbackTargetY = neighborY
            end
        end
    end

    if fallbackSourceX ~= 0 then
        return fallbackSourceX, fallbackSourceY, fallbackTargetX, fallbackTargetY
    end
    return nil
end

-- アクティブなブロックのマージ先を見つける.
local function findMergeForActiveBlock()
	-- Activeブロックは新たに追加されたブロックまたは前回のマージで残ったブロック.
    return findMergeForBlock(state.activeMergeX, state.activeMergeY,
        state.board:get(state.activeMergeX, state.activeMergeY))
end

-- 自動プレイ用に、各列へ落とした場合の候補を作る。
-- マージ判定は通常プレイと同じ findMergeForBlock を使用する。
local function getAutoPlayCandidates(activeValue)
    local candidates = {}
    for column = 1, BOARD_SIZE do
        local x, y = findDropCell(column)
        if x ~= nil then
            local sourceX, sourceY, targetX, targetY =
                findMergeForBlock(x, y, activeValue)
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

local function canDropInAnyColumn()
    return BoardRules.canDropInAnyColumn(state.board)
end

-- 外周の各辺について、準危険状態と危険状態を判定する.
local function getDangerEdges()
    local bottomCount = 0
    for x = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, x, BOARD_SIZE) then
            bottomCount += 1
        end
    end

    local leftCount = 0
    local rightCount = 0
    for y = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, 1, y) then
            leftCount += 1
        end
        if BoardRules.isOccupied(state.board, BOARD_SIZE, y) then
            rightCount += 1
        end
    end

    return bottomCount >= 4, bottomCount == BOARD_SIZE,
        leftCount >= 4, leftCount == BOARD_SIZE,
        rightCount >= 4, rightCount == BOARD_SIZE
end

-- 次の手番のブロックを配り、先読みキューを更新する.
-- 落下開始時ではなく、マージ・回転まで完了した手番の切り替え時に行う.
local function advanceNextQueue()
    for i = 1, NEXT_QUEUE_COUNT - 1 do
        state.nextValues[i] = state.nextValues[i + 1]
    end
    state.nextValues[NEXT_QUEUE_COUNT] = randomBlockValue()
end

local function finishTurn()
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    -- ブロックを落として手が完了したので、次の手でHOLD可能にする.
    state.holdAvailable = true
    advanceNextQueue()
    state.nextAnimationGameOver = not canDropInAnyColumn()
    state.animationProgress = 0
    state.animationDuration = 0.30
    state.phase = GamePhase.NEXT_ANIM
end

-- ゲームオーバー開始.
local function beginGameOver()
	saveHighScore()
	state.result = GameResult.GAME_OVER
	state.phase = GamePhase.INPUT
	sound:play_se("gameover")
	sound:stop_bgm(1.0)
end

local function finishNextAnimation()
    if state.nextAnimationGameOver then
		-- ゲームオーバー開始.
		beginGameOver()
    else
        state.phase = GamePhase.INPUT
    end
end

-- 回転開始.
local function startRotation()
    if state.rotationEvaluation == 0 then
        finishTurn()
        return
    end

    state.rotationClockwise = state.rotationEvaluation > 0
    local latestUndoState = state.undoStates[#state.undoStates]
    if latestUndoState ~= nil then
        latestUndoState.hasRotation = true
        latestUndoState.rotationClockwise = state.rotationClockwise
    end
    state.rotationStartBoard = state.board
    state.rotationEndBoard = BoardTransform.rotate(
        state.rotationStartBoard, state.rotationClockwise, BoardRules.isPlayable)

    local oldActiveX = state.activeMergeX
    local oldActiveY = state.activeMergeY
    if state.rotationClockwise then
        state.activeMergeX = BOARD_SIZE + 1 - oldActiveY
        state.activeMergeY = oldActiveX
    else
        state.activeMergeX = oldActiveY
        state.activeMergeY = BOARD_SIZE + 1 - oldActiveX
    end

    state.animationProgress = 0
    state.animationDuration = 0.38
    sound:play_se("rotate")
    state.phase = GamePhase.ROTATING
end

-- 連鎖が確定した時点でコンボSEを再生する.
local function playComboSoundIfNeeded()
    if state.combo < 2 or state.comboSoundPlayed then
        return
    end

    state.comboSoundPlayed = true
    state.comboDisplayFrame = 0
    if state.combo < 3 then
        sound:play_se("combo1")
    elseif state.combo < 5 then
        sound:play_se("combo2")
    else
        sound:play_se("combo3")
    end
end

local function startResolve(nextAction)
    applyGravity()
    local x1, y1, x2, y2 = findMergeForActiveBlock()
    if x1 == nil then
        if nextAction == "ROTATE" then
            -- これ以上マージが発生しないことが確定した直後に再生する.
            -- 回転アニメーション開始より前になる.
            playComboSoundIfNeeded()
            startRotation()
        else
            -- 回転後に初めてコンボが成立した場合はこちらで再生する.
            playComboSoundIfNeeded()
            finishTurn()
        end
        return
    end

	-- マージ開始.
    state.mergeSourceX = x1
    state.mergeSourceY = y1
    state.mergeTargetX = x2
    state.mergeTargetY = y2
    state.mergeValue = state.board:get(x1, y1) * 2
    state.mergeNextAction = nextAction
    state.animationProgress = 0
    state.animationDuration = 0.22
	sound:play_se("merge")
    state.phase = GamePhase.MERGING
end

local function finishMerge()
    state.combo += 1
    local v = getMergeEvaluation(state.mergeSourceX, state.mergeTargetX)
    addRotationEvaluation(v)
    if state.mergeTargetX < state.mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_LEFT)
    elseif state.mergeTargetX > state.mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT)
    end
    state.board:set(state.mergeSourceX, state.mergeSourceY, 0)
    state.board:set(state.mergeTargetX, state.mergeTargetY, state.mergeValue)
    addScore(state.mergeValue)

    -- 1コンボ目は通常のマージ得点のみとし、2コンボ目以降に差分ボーナスを加算する.
    -- 累積値は係数 * (コンボ回数 ^ 指数 - 1)になる.
    state.comboBonusScore = 0
    if state.combo >= 2 then
        local currentComboScore = COMBO_SCORE_COEFFICIENT * (state.combo ^ COMBO_SCORE_EXPONENT)
        local previousComboScore = COMBO_SCORE_COEFFICIENT * ((state.combo - 1) ^ COMBO_SCORE_EXPONENT)
        state.comboBonusScore = math.floor(currentComboScore - previousComboScore)
        addScore(state.comboBonusScore)
    end

    state.activeMergeX = state.mergeTargetX
    state.activeMergeY = state.mergeTargetY
    startResolve(state.mergeNextAction)
end

-- 落下完了.
local function finishDrop()
    state.board:set(state.pendingDropX, state.pendingDropY, state.pendingDropValue)
    state.pendingDropValue = 0
    state.activeMergeX = state.pendingDropX
    state.activeMergeY = state.pendingDropY
    addRotationEvaluation(ROTATION_EVALUATION_DROP_POSITION_WEIGHT
        * getPositionEvaluation(state.pendingDropX)
    )
    addPreviewImpulse(getPositionEvaluation(state.pendingDropX))
    startResolve("ROTATE")
	if state.phase ~= GamePhase.MERGING then
		sound:play_se("fixed")
	end
end

local function advanceAnimation()
    local context = {
        previewImpulseRotationDegrees = state.previewImpulseRotationDegrees,
        animationProgress = state.animationProgress,
        animationDuration = state.animationDuration,
        refreshRate = DEFAULT_REFRESH_RATE,
        phase = state.phase,
        board = state.board,
        rotationEndBoard = state.rotationEndBoard,
        finishDrop = finishDrop,
        finishMerge = finishMerge,
        startResolve = startResolve,
        finishNextAnimation = finishNextAnimation,
        finishHoldAnimation = finishHoldAnimation,
        setPhase = function(value) state.phase = value end,
        setBoard = function(value) state.board = value end,
    }
    TurnResolver.advance(context)
    if not context.completed then
        state.previewImpulseRotationDegrees = context.previewImpulseRotationDegrees
        state.animationProgress = context.animationProgress
        state.board = context.board
        state.rotationEndBoard = context.rotationEndBoard
    elseif context.phase == GamePhase.ROTATING
        or context.phase == GamePhase.UNDO_ROTATING then
        state.board = context.board
        state.rotationEndBoard = context.rotationEndBoard
    end
end

local function spawnInitialBlocks()
    -- Start with one value-8 block immediately to each side of the rotation axis.
    -- Coordinates are 1-based: the axis is (3, 3), so the two cells are
    -- (2, 3) and (4, 3).
    state.board:set(CENTER - 1, CENTER, 8)
    state.board:set(CENTER + 1, CENTER, 8)
end

local function startGame()
    clearBoard()
    state.result = nil
    state.score = 0
    state.holdValue = 0
    state.holdAvailable = true
    state.lastRandomBlockValue = 0
    state.consecutiveRandomBlockCount = 0
    state.undoStates = {}
    state.rewindUsesRemaining = MAX_REWIND_USES
    state.combo = 0
    state.comboBonusScore = 0
    state.comboDisplayFrame = 0
    state.comboSoundPlayed = false
    state.cursorX = CENTER
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
    state.rewindHoldAnimationActive = false
    state.animationProgress = 0
    state.animationDuration = 0
    state.pendingDropX = 0
    state.pendingDropY = 0
    state.pendingDropValue = 0
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    state.rotationClockwise = false
    state.mergeSourceX = 0
    state.mergeSourceY = 0
    state.mergeTargetX = 0
    state.mergeTargetY = 0
    state.mergeValue = 0
    state.mergeNextAction = "FINISH"
    state.activeMergeX = 0
    state.activeMergeY = 0
    state.nextAnimationGameOver = false
    state.holdAnimationSourceValue = 0
    state.holdAnimationReturnValue = 0
    state.rotationEvaluation = 0
    state.nextValues = {}
    autoPlayer:reset()
    for i = 1, NEXT_QUEUE_COUNT do
        state.nextValues[i] = randomBlockValue()
    end
    state.previewImpulseRotationDegrees = 0
    spawnInitialBlocks()
    state.phase = GamePhase.INPUT
    state.message = ""
    state.crisisBgmActive = false
    playGameBgm()
end

-- 現在のブロックをHOLDする。HOLD自体を1手として履歴に保存する.
local function holdCurrentBlock()
    if not state.holdAvailable then
        sound:play_se("error")
        setMessage("HOLD USED", 700)
        return
    end

    saveUndoState("HOLD")

    local currentValue = state.nextValues[1]
    state.holdAnimationSourceValue = currentValue
    state.holdAnimationReturnValue = state.holdValue
    if state.holdValue == 0 then
        -- 初回は現在ブロックをHOLDし、NEXTの先頭を現在ブロックにする.
        state.holdValue = currentValue
        advanceNextQueue()
    else
        -- HOLD済みの場合は現在ブロックと交換する.
        state.holdValue, state.nextValues[1] = currentValue, state.holdValue
    end

    state.holdAvailable = false
    state.rewindHoldAnimationActive = false
    sound:play_se("hold")

    state.animationProgress = 0
    state.animationDuration = 0.30
    state.phase = GamePhase.HOLD_ANIM
end

-- HOLDアニメーションを終了し、HOLDで出現したブロックの配置可能性を確認する.
finishHoldAnimation = function()
    state.holdAnimationSourceValue = 0
    state.holdAnimationReturnValue = 0
    state.rewindHoldAnimationActive = false
    if not canDropInAnyColumn() then
        beginGameOver()
    else
        state.phase = GamePhase.INPUT
    end
end

-- 落下開始.
local function beginDrop()
    if not isDropAvailable() then
        setMessage("NO SPACE", 700)
		sound:play_se("error")
        return
    end

    local x, y = findDropCell(state.cursorX)

    -- 落下開始.
    saveUndoState("DROP")
    state.combo = 0
    state.comboBonusScore = 0
    state.comboDisplayFrame = 0
    state.comboSoundPlayed = false
    state.pendingDropX = x
    state.pendingDropY = y
    state.pendingDropValue = state.nextValues[1]
    state.rotationEvaluation = 0
    state.animationProgress = 0
    state.animationDuration = math.max(0.18, (y + 1) * 0.07)
	sound:play_se("fall")
    state.phase = GamePhase.DROPPING
end

-- カーソルを移動.
local function moveCursor(delta)
	local prev = state.cursorX
    state.cursorX += delta
    if state.cursorX < 1 then
        state.cursorX = 1
    elseif state.cursorX > BOARD_SIZE then
        state.cursorX = BOARD_SIZE
    end

	if prev ~= state.cursorX then
		-- 移動した.
		sound:play_se("pi")
	end
end

-- 左右キーのリピート状態を解除する.
local function resetCursorKeyRepeat()
    CursorController.reset(cursorController)
    state.cursorRepeatDirection = 0
    state.cursorRepeatNextAt = nil
end

-- 左右キーの押しっぱなしによるカーソル移動を処理する.
local function updateCursorKeyRepeat()
    CursorController.update(cursorController, pd, pd.getCurrentTimeMilliseconds(), moveCursor)
    state.cursorRepeatDirection = cursorController.direction
    state.cursorRepeatNextAt = cursorController.nextAt
end

-- ゲームシーンを1フレーム進める。Sceneからゲーム内部状態を隠す窓口。
local function updateGame()
    if state.phase ~= GamePhase.INPUT then
        resetCursorKeyRepeat()
    end

    if state.phase == GamePhase.INPUT then
        if autoPlayEnabled then
            local command = autoPlayer:poll(nil, {
                phase = state.phase,
                cursorX = state.cursorX,
                nextValue = state.nextValues[1],
                holdValue = state.holdValue,
                holdAvailable = state.holdAvailable,
                getCandidates = getAutoPlayCandidates,
            })
            if command == InputCommand.HOLD then
                holdCurrentBlock()
            elseif command == InputCommand.MOVE_LEFT then
                moveCursor(-1)
            elseif command == InputCommand.MOVE_RIGHT then
                moveCursor(1)
            elseif command == InputCommand.DROP then
                beginDrop()
            end
        else
            updateRewindHold()
            if pd.buttonJustPressed(pd.kButtonA) then
                holdCurrentBlock()
            elseif pd.buttonJustPressed(pd.kButtonLeft)
                or pd.buttonJustPressed(pd.kButtonRight) then
                updateCursorKeyRepeat()
            elseif pd.buttonJustPressed(pd.kButtonDown) then
                beginDrop()
            elseif pd.buttonJustPressed(pd.kButtonB) then
                beginRewindHold()
            elseif state.cursorRepeatDirection ~= 0 then
                updateCursorKeyRepeat()
            end
        end
    elseif state.phase == GamePhase.PAUSED then
        if pd.buttonJustPressed(pd.kButtonB) then
            state.phase = GamePhase.INPUT
        end
    end

    if TurnResolver.isAnimating(state.phase) then
        advanceAnimation()
    end

    if state.result ~= nil then
        return Scene.GAME_OVER
    end
    return nil
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)

local sceneManager

-- Playdateのシステムメニューからゲームを最初からやり直せるようにする.
pd.getSystemMenu():addCheckmarkMenuItem("Auto Play", autoPlayEnabled, function(value)
    autoPlayEnabled = value
    autoPlayer:reset()
end)

pd.getSystemMenu():addMenuItem("Retry", function()
    startGame()
    if sceneManager ~= nil then
        sceneManager:change(Scene.GAME)
    end
end)

local gameRenderer = GameRenderer.new({
    state = state,
    findDropCell = findDropCell,
    findMergeForBlock = findMergeForBlock,
})

local overlayRenderer = OverlayRenderer.new({
    state = state,
    sound = sound,
    getDangerEdges = getDangerEdges,
    isRewindAvailable = isRewindAvailable,
})

local sceneContext = SceneContext.new({
    playDecideSound = function() sound:play_se("decide") end,
    playMenuBgm = playMenuBgm,
    playGameBgm = playGameBgm,
    startGame = startGame,
    updateGame = updateGame,
    drawTitle = function()
        overlayRenderer:drawTitle()
    end,
    drawNormalFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawRewindHint()
        if state.phase == GamePhase.PAUSED then
            overlayRenderer:drawPause()
        else
            overlayRenderer:drawMessage()
        end
    end,
    drawGameOverFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawGameOver()
    end,
})

sceneManager = SceneManager.new(sceneContext)
sceneManager:register(Scene.TITLE, TitleScene.new(sceneContext))
sceneManager:register(Scene.GAME, NormalGameScene.new(sceneContext))
sceneManager:register(Scene.GAME_OVER, GameOverScene.new(sceneContext))
sceneManager:change(Scene.TITLE)

function pd.update()
    gfx.clear(gfx.kColorWhite)
    sceneManager:update()
    sceneManager:draw()
    pd.drawFPS(4, 4)

    if state.phase == GamePhase.UNDO_ROTATING or state.rewindHoldAnimationActive then
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end
