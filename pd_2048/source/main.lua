import "CoreLibs/graphics"
import "CoreLibs/ui"
import "array2d"
import "game_context"
import "easing"
import "game_config"
import "game_state"
import "board/board_transform"
import "tile_generator"
import "undo_history"
import "board/board_rules"
import "cursor_controller"
import "board/board_renderer"
import "hud_renderer"
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

local DEFAULT_REFRESH_RATE <const> = 30 -- ディスプレイの更新レート (FPS。フレーム毎秒).
local CURSOR_KEY_REPEAT_INITIAL_DELAY_MS <const> = 300 -- 左右キーを押し続けたとき、最初にリピートするまでの待ち時間.
local CURSOR_KEY_REPEAT_INTERVAL_MS <const> = 80 -- 左右キーを押し続けたときのリピート間隔.
local BOARD_SIZE <const> = 5
local CENTER <const> = 3
local CELL_SIZE <const> = 32
local LAYOUT_BOARD_OFFSET_X <const> = 32 -- 盤面の横方向の調整値.
local LAYOUT_NEXT_OFFSET_X <const> = -24 -- NEXTブロックの横方向の調整値.
local BOARD_X <const> = 100 + LAYOUT_BOARD_OFFSET_X
local BOARD_Y <const> = 48
-- 盤面とNEXTの間にある右上の空き領域をHOLD表示に使用する.
local HOLD_BOX_X <const> = 80
local HOLD_LABEL_X <const> = 64
local HOLD_BOX_Y <const> = 48
local NEXT_BOX_X <const> = 343 + LAYOUT_NEXT_OFFSET_X
local NEXT_LABEL_X <const> = 343 + LAYOUT_NEXT_OFFSET_X
local PANEL_OFFSET_X <const> = 0 -- 左側の情報表示の横方向の調整値.
local PANEL_OFFSET_Y <const> = 128 -- 左側の情報表示の縦方向の調整値.
local NEXT_BOX_Y <const> = 48
local NEXT_BOX_WIDTH <const> = 25
local NEXT_BOX_HEIGHT <const> = 20
local NEXT_PREVIEW_COUNT <const> = 3
-- 落下対象を除いたブロックを表示するため、表示数より1つ多く保持する.
local NEXT_QUEUE_COUNT <const> = NEXT_PREVIEW_COUNT + 1
local NEXT_BOX_GAP <const> = 4
local MAX_UNDO_COUNT <const> = 1
local MAX_REWIND_USES <const> = 3
local REWIND_HOLD_DURATION_MS <const> = 800
local REWIND_GAUGE_WIDTH <const> = 116
-- 危険アイコン関連.
local DANGER_ICON_SIZE <const> = 20
local DANGER_ICON_OFFSET <const> = 4 -- 盤面の外周からアイコンまでの距離.
local DANGER_ICON_BOTTOM_X <const> = BOARD_X + (BOARD_SIZE * CELL_SIZE - DANGER_ICON_SIZE) * 0.5
local DANGER_ICON_BOTTOM_Y <const> = BOARD_Y + BOARD_SIZE * CELL_SIZE + DANGER_ICON_OFFSET
local DANGER_ICON_LEFT_X <const> = BOARD_X - DANGER_ICON_SIZE - DANGER_ICON_OFFSET
local DANGER_ICON_LEFT_Y <const> = BOARD_Y + (BOARD_SIZE * CELL_SIZE - DANGER_ICON_SIZE) * 0.5
local DANGER_ICON_RIGHT_X <const> = BOARD_X + BOARD_SIZE * CELL_SIZE + DANGER_ICON_OFFSET
local DANGER_ICON_RIGHT_Y <const> = DANGER_ICON_LEFT_Y
local DANGER_ICON_BLINK_PERIOD <const> = 600
local DANGER_ICON_BLINK_ON_DURATION <const> = 300
-- コンボ表示時間.
local COMBO_BLINK_PERIOD_FRAMES <const> = 3
local COMBO_BLINK_ON_FRAMES <const> = 1
local COMBO_BLINK_DURATION_FRAMES <const> = 20
local COMBO_STEADY_DURATION_FRAMES <const> = 30
local COMBO_SCORE_COEFFICIENT <const> = 2
local COMBO_SCORE_EXPONENT <const> = 1.5
local SCORE_MULTIPLIER <const> = 100
-- 方向定数.
local DIRECTION_DOWN <const> = 1
local DIRECTION_LEFT <const> = 2
local DIRECTION_RIGHT <const> = 3
local DIRECTION_UP <const> = 4
local Scene <const> = Config.SCENE
local GamePhase <const> = Config.GAME_PHASE
local GameResult <const> = Config.GAME_RESULT
-- 傾きをわかりやすく見せるための回転角度の最大値と、1ポイントあたりの回転角度.
local PREVIEW_ROTATION_MAX_DEGREES <const> = 200
local PREVIEW_ROTATION_EVALUATION_MULTIPLIER <const> = 0.1 -- 評価値に対する倍率.
local PREVIEW_ROTATION_DEGREES_PER_POINT <const> = 0.1 -- 最終的な角度に対する倍率.
-- 回転方向の評価値.
local ROTATION_EVALUATION_POSITION_RIGHT <const> = 10 -- 右側の位置を評価する値.
local ROTATION_EVALUATION_POSITION_LEFT <const> = -10 -- 左側の位置を評価する値.
local ROTATION_EVALUATION_POSITION_CENTER <const> = 0 -- 中央の位置を評価する値.
local ROTATION_EVALUATION_DROP_POSITION_WEIGHT <const> = 20 -- 落下位置の評価値の重み.
local ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT <const> = -10 -- 消えたブロックの評価値の重み.
local ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT <const> = 10 -- マージされたブロックの評価値の重み.
local ROTATION_EVALUATION_MERGE_DIRECTION_LEFT <const> = -5 -- マージ方向の評価値 (左方向).
local ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT <const> = 5 -- マージ方向の評価値 (右方向).
local ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT <const> = 10 -- マージ方向が上下の場合の評価値の重み.
-- プレビュー反動の設定.
local PREVIEW_IMPULSE_ROTATION_DEGREES <const> = 5
local PREVIEW_IMPULSE_DECAY <const> = 0.7
-- 回転予測の矢印.
local ROTATION_DIRECTION_ARROW_OFFSET_Y <const> = -CELL_SIZE * 0.4 -- 矢印の中心位置のY座標をずらす値.
local ROTATION_DIRECTION_ARROW_MIN_LENGTH <const> = 12
local ROTATION_DIRECTION_ARROW_MAX_LENGTH <const> = 24
local ROTATION_DIRECTION_ARROW_HEAD_LENGTH <const> = 6
local ROTATION_DIRECTION_ARROW_HEAD_WIDTH <const> = 4
local ROTATION_DIRECTION_ARROW_MAX_EVALUATION <const> =
    PREVIEW_ROTATION_MAX_DEGREES * PREVIEW_ROTATION_DEGREES_PER_POINT

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

local function isCenter(x, y)
    return BoardRules.isCenter(x, y)
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

local function isPlayable(x, y)
    return BoardRules.isPlayable(x, y)
end

local function isOccupied(x, y)
    return BoardRules.isOccupied(state.board, x, y)
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

-- 盤面を値ごと複製する。Array2Dは参照型なので、取り消し用に別の盤面を作る。
local function copyBoard(source)
    return BoardTransform.copy(source)
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

-- 落下可能かどうかを判定する.
local function isSupported(x, y)
    if not isPlayable(x, y) or state.board:get(x, y) ~= 0 then
        return false
    end
    -- 底面だけでは接続とはみなさない。必ず他のブロックに接している必要がある。
    if isOccupied(x, y + 1) then
        return true
    end
    -- 中心軸は見えない固定ブロックとして、その直上を支える。
    if x == CENTER and y == CENTER - 1 then
        return true
    end
    if x > 1 and isOccupied(x - 1, y) then
        return true
    end
    if x < BOARD_SIZE and isOccupied(x + 1, y) then
        return true
    end
    return false
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

-- 重力を適用する.
local function applyGravity()
    -- 中心軸は見えない固定ブロックとして常に空けておく。
    state.board:set(CENTER, CENTER, 0)
end

-- マージ後もブロックが接続されたままかどうかを判定する.
local function mergeKeepsBlockConnected(sourceX, sourceY, targetX, targetY)
	-- soruceは targetにマージする.
	-- 合成したブロック上下左右に隣接するブロックがあれば接続されたとみなす.
    local neighborX = targetX - 1
    if isPlayable(neighborX, targetY) and neighborX ~= sourceX and isOccupied(neighborX, targetY) then
        return true
    end
    neighborX = targetX + 1
    if isPlayable(neighborX, targetY) and neighborX ~= sourceX and isOccupied(neighborX, targetY) then
        return true
    end
    local neighborY = targetY - 1
    if isPlayable(targetX, neighborY) and neighborY ~= sourceY and isOccupied(targetX, neighborY) then
        return true
    end
    neighborY = targetY + 1
    if isPlayable(targetX, neighborY) and neighborY ~= sourceY and isOccupied(targetX, neighborY) then
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
        if activeValue ~= 0 and isPlayable(neighborX, neighborY)
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

local function makeRotatedBoard(source, clockwise)
    return BoardTransform.rotate(source, clockwise, isPlayable)
end

local function canDropInAnyColumn()
    return BoardRules.canDropInAnyColumn(state.board)
end

-- 外周の各辺について、準危険状態と危険状態を判定する.
local function getDangerEdges()
    local bottomCount = 0
    for x = 1, BOARD_SIZE do
        if isOccupied(x, BOARD_SIZE) then
            bottomCount += 1
        end
    end

    local leftCount = 0
    local rightCount = 0
    for y = 1, BOARD_SIZE do
        if isOccupied(1, y) then
            leftCount += 1
        end
        if isOccupied(BOARD_SIZE, y) then
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
    state.rotationEndBoard = makeRotatedBoard(state.rotationStartBoard, state.rotationClockwise)

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

local function drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

-- 危険標識風のアイコンを描画する.
local function drawDangerIcon(x, y, size, blinking)
    if blinking then
        local blinkProgress = pd.getCurrentTimeMilliseconds() % DANGER_ICON_BLINK_PERIOD
        if blinkProgress >= DANGER_ICON_BLINK_ON_DURATION then
            return
        end
        gfx.setImageDrawMode(gfx.kDrawModeXOR)
    end

    local centerX = x + size * 0.5
    local topY = y + 1
    local bottomY = y + size - 1
    local leftX = x + 1
    local rightX = x + size - 1

    gfx.setLineWidth(2)
    gfx.drawLine(centerX, topY, leftX, bottomY)
    gfx.drawLine(leftX, bottomY, rightX, bottomY)
    gfx.drawLine(rightX, bottomY, centerX, topY)

    gfx.drawLine(centerX, y + 6, centerX, y + 12)
    gfx.fillCircleAtPoint(centerX, y + 16, 1)
    gfx.setLineWidth(1)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

local function drawDangerIcons()
    local bottomDanger, bottomCritical,
        leftDanger, leftCritical,
        rightDanger, rightCritical = getDangerEdges()
    local dangerActive = bottomDanger or leftDanger or rightDanger
    if dangerActive and not state.crisisBgmActive then
        sound:setBgmRandomMode(BGMRandomMode.CRISIS)
        state.crisisBgmActive = true
    elseif not dangerActive and state.crisisBgmActive then
		state.crisisBgmActive = false
    end

    if bottomDanger then
        drawDangerIcon(DANGER_ICON_BOTTOM_X, DANGER_ICON_BOTTOM_Y, DANGER_ICON_SIZE, bottomCritical)
    end
    if leftDanger then
        drawDangerIcon(DANGER_ICON_LEFT_X, DANGER_ICON_LEFT_Y, DANGER_ICON_SIZE, leftCritical)
    end
    if rightDanger then
        drawDangerIcon(DANGER_ICON_RIGHT_X, DANGER_ICON_RIGHT_Y, DANGER_ICON_SIZE, rightCritical)
    end
end

-- タイルの描画.
local function drawTileAt(value, px, py)
    BoardRenderer.tile(value, px, py)
end

local function rotatePointAroundBoardCenter(px, py, angle)
    return BoardRenderer.tilePosition(px - CELL_SIZE * 0.5,
        py - CELL_SIZE * 0.5, angle)
end

local function getRotatedTilePosition(px, py, angle)
    return BoardRenderer.tilePosition(px, py, angle)
end

local function drawBoardGrid()
    BoardRenderer.grid()
end

local function drawBoardCells(skipX, skipY, rotationAngle)
    BoardRenderer.cells(state.board, skipX, skipY, rotationAngle)
end

-- 落下するブロックの描画.
local function drawFallingBlock(rotationAngle)
    local startY = BOARD_Y - CELL_SIZE
    local targetY = BOARD_Y + (state.pendingDropY - 1) * CELL_SIZE
    local y = startY + (targetY - startY) * state.animationProgress
    local px, py = getRotatedTilePosition(
        BOARD_X + (state.pendingDropX - 1) * CELL_SIZE, y, rotationAngle)
    drawTileAt(state.pendingDropValue, px, py)
end

-- 落下させたときの着地点を薄いゴースト表示する.
local function drawLandingPreview()
    if not isDropAvailable() then
        return
    end

    local landingX, landingY = findDropCell(state.cursorX)

    local px = BOARD_X + (landingX - 1) * CELL_SIZE
    local py = BOARD_Y + (landingY - 1) * CELL_SIZE

    gfx.setDitherPattern(0.9, gfx.image.kDitherTypeBayer8x8)
    gfx.fillRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
    gfx.setColor(gfx.kColorBlack)
	-- 外枠は表示しない.
    --gfx.drawRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
	-- 数字の描画.
    gfx.drawTextAligned(tostring(state.nextValues[1]),
        px + CELL_SIZE / 2, py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- マージ予測方向の描画.
    local _, _, targetX, targetY = findMergeForBlock(landingX, landingY, state.nextValues[1])
    if targetX ~= nil then
		-- 方向ベクトルを計算.
        local sourceCenterX = BOARD_X + (landingX - 0.5) * CELL_SIZE
        local sourceCenterY = BOARD_Y + (landingY - 0.5) * CELL_SIZE
        local targetCenterX = BOARD_X + (targetX - 0.5) * CELL_SIZE
        local targetCenterY = BOARD_Y + (targetY - 0.5) * CELL_SIZE
        local directionX = targetX - landingX
        local directionY = targetY - landingY
        local arrowStartX = sourceCenterX + (targetCenterX - sourceCenterX) * 0.25
        local arrowStartY = sourceCenterY + (targetCenterY - sourceCenterY) * 0.25
        local arrowTipX = sourceCenterX + (targetCenterX - sourceCenterX) * 0.75
        local arrowTipY = sourceCenterY + (targetCenterY - sourceCenterY) * 0.75
        local arrowBaseX = arrowTipX - directionX * 7
        local arrowBaseY = arrowTipY - directionY * 7
        local perpendicularX = -directionY * 4
        local perpendicularY = directionX * 4

        gfx.setLineWidth(2)
        gfx.drawLine(arrowStartX, arrowStartY, arrowTipX, arrowTipY)
        gfx.setLineWidth(1)
        gfx.drawLine(arrowTipX, arrowTipY,
            arrowBaseX + perpendicularX, arrowBaseY + perpendicularY)
        gfx.drawLine(arrowTipX, arrowTipY,
            arrowBaseX - perpendicularX, arrowBaseY - perpendicularY)
    end
end

local function drawDropPreview()
    local px = BOARD_X + (state.cursorX - 1) * CELL_SIZE
    local py = BOARD_Y - CELL_SIZE

    drawTileAt(state.nextValues[1], px, py)

    -- Blink the outline around the tile to make the active column obvious.
    if (pd.getCurrentTimeMilliseconds() % 600) < 300 then
        gfx.setLineWidth(2)
        gfx.drawRect(px, py, CELL_SIZE, CELL_SIZE)
        gfx.setLineWidth(1)
    end
end

local function easeInOut(value)
    return value * value * (3 - 2 * value)
end

local function getPreviewRotationEvaluation()
    local evaluation = state.rotationEvaluation
    if state.phase == GamePhase.MERGING then
        local mergeEvaluation = getMergeEvaluation(state.mergeSourceX, state.mergeTargetX)
        evaluation += mergeEvaluation * easeInOut(state.animationProgress)
    end

	-- 最終的な倍率を加算した値を返す.
    return evaluation * PREVIEW_ROTATION_DEGREES_PER_POINT
end

local function getPreviewRotationDegrees()
    if state.phase ~= GamePhase.DROPPING and state.phase ~= GamePhase.MERGING then
        return 0
    end

    local previewEvaluation = getPreviewRotationEvaluation()
	-- 反動値を加算.
	previewEvaluation += state.previewImpulseRotationDegrees
	return previewEvaluation
end

-- 傾きプレビューの値をラジアンに変換して返す.
local function getPreviewRotationAngle()
    local degrees = getPreviewRotationDegrees()
    degrees = math.max(-PREVIEW_ROTATION_MAX_DEGREES,
        math.min(PREVIEW_ROTATION_MAX_DEGREES, degrees))
	-- 反動値は傾き制限を考慮しない.
	degrees += state.previewImpulseRotationDegrees
    return math.rad(degrees)
end

local function drawRotatingBoard()
    local progress = Easing.back_out(state.animationProgress)
    local angle = math.pi * 0.5 * progress
    if not state.rotationClockwise then
        angle = -angle
    end

    state.rotationStartBoard:foreach(function(x, y, value)
        if value ~= 0 then
            local px, py = getRotatedTilePosition(
                BOARD_X + (x - 1) * CELL_SIZE,
                BOARD_Y + (y - 1) * CELL_SIZE,
                angle)
            drawTileAt(value, px, py)
        end
    end)
end

-- 回転アニメーション中の回転方向を、中央の回転軸に表示する.
local function drawRotationDirectionArrow()
    if state.phase ~= GamePhase.MERGING and state.phase ~= GamePhase.ROTATING then
		-- マージ中と回転中のみ描画する.
        return
    end

    local evaluation = getPreviewRotationEvaluation()
    if evaluation == 0 then
		-- 回転しないのであれば描画しない.
        return
    end

    local centerX = BOARD_X + (CENTER - 0.5) * CELL_SIZE
    local centerY = BOARD_Y + (CENTER - 0.5) * CELL_SIZE
	centerY += ROTATION_DIRECTION_ARROW_OFFSET_Y -- オフセットを適用.
    local direction = evaluation > 0 and 1 or -1
    local evaluationRatio = math.min(1,
        math.abs(evaluation) / ROTATION_DIRECTION_ARROW_MAX_EVALUATION)
    local arrowLength = ROTATION_DIRECTION_ARROW_MIN_LENGTH
        + (ROTATION_DIRECTION_ARROW_MAX_LENGTH - ROTATION_DIRECTION_ARROW_MIN_LENGTH)
        * evaluationRatio
    local arrowStartX = centerX - direction * arrowLength * 0.5
    local arrowTipX = centerX + direction * arrowLength * 0.5
    local arrowBaseX = arrowTipX - direction * ROTATION_DIRECTION_ARROW_HEAD_LENGTH

    gfx.setLineWidth(2)
    gfx.drawLine(arrowStartX, centerY, arrowTipX, centerY)
    gfx.setLineWidth(1)
    gfx.drawLine(arrowTipX, centerY,
        arrowBaseX, centerY - ROTATION_DIRECTION_ARROW_HEAD_WIDTH)
    gfx.drawLine(arrowTipX, centerY,
        arrowBaseX, centerY + ROTATION_DIRECTION_ARROW_HEAD_WIDTH)
end

local function drawMergeAnimation(rotationAngle)
    drawBoardCells(state.mergeSourceX, state.mergeSourceY, rotationAngle)

    local progress = easeInOut(state.animationProgress)
    local sourcePx = BOARD_X + (state.mergeSourceX - 1) * CELL_SIZE
    local sourcePy = BOARD_Y + (state.mergeSourceY - 1) * CELL_SIZE
    local targetPx = BOARD_X + (state.mergeTargetX - 1) * CELL_SIZE
    local targetPy = BOARD_Y + (state.mergeTargetY - 1) * CELL_SIZE
    local rotatedTargetPx, rotatedTargetPy = getRotatedTilePosition(
        targetPx, targetPy, rotationAngle)
    drawTileAt(state.board:get(state.mergeTargetX, state.mergeTargetY), rotatedTargetPx, rotatedTargetPy)

    local sourceCenterX = sourcePx + CELL_SIZE * 0.5
    local sourceCenterY = sourcePy + CELL_SIZE * 0.5
    local targetCenterX = targetPx + CELL_SIZE * 0.5
    local targetCenterY = targetPy + CELL_SIZE * 0.5
    local currentCenterX = sourceCenterX + (targetCenterX - sourceCenterX) * progress
    local currentCenterY = sourceCenterY + (targetCenterY - sourceCenterY) * progress
    local rotatedSourcePx, rotatedSourcePy = getRotatedTilePosition(
        currentCenterX - CELL_SIZE * 0.5,
        currentCenterY - CELL_SIZE * 0.5,
        rotationAngle)
    drawTileAt(math.floor(state.mergeValue / 2),
        rotatedSourcePx, rotatedSourcePy)
end

local function drawNextAnimation()
    local progress = easeInOut(state.animationProgress)
    local sourceCenterX = NEXT_BOX_X + NEXT_BOX_WIDTH * 0.5
    local sourceCenterY = NEXT_BOX_Y + NEXT_BOX_HEIGHT * 0.5
    local sourceX = sourceCenterX - CELL_SIZE * 0.5
    local sourceY = sourceCenterY - CELL_SIZE * 0.5
    local targetX = BOARD_X + (state.cursorX - 1) * CELL_SIZE
    local targetY = BOARD_Y - CELL_SIZE
    drawTileAt(state.nextValues[1],
        sourceX + (targetX - sourceX) * progress,
        sourceY + (targetY - sourceY) * progress)
end

-- HOLD枠の中央を基準にしたブロックの左上座標を返す.
local function getHoldTilePosition()
    return HOLD_BOX_X + (NEXT_BOX_WIDTH - CELL_SIZE) * 0.5,
        HOLD_BOX_Y + (NEXT_BOX_HEIGHT - CELL_SIZE) * 0.5
end

-- 現在ブロックとHOLDブロックを移動させるアニメーションを描画する.
local function drawHoldAnimation()
    local progress = easeInOut(state.animationProgress)
    local currentX = BOARD_X + (state.cursorX - 1) * CELL_SIZE
    local currentY = BOARD_Y - CELL_SIZE
    local holdX, holdY = getHoldTilePosition()

    if state.holdAnimationSourceValue ~= 0 then
        drawTileAt(state.holdAnimationSourceValue,
            currentX + (holdX - currentX) * progress,
            currentY + (holdY - currentY) * progress)
    end

    if state.holdAnimationReturnValue ~= 0 then
        drawTileAt(state.holdAnimationReturnValue,
            holdX + (currentX - holdX) * progress,
            holdY + (currentY - holdY) * progress)
    end
end

-- 盤面の描画.
local function drawBoard()
    drawBoardGrid()
    local previewRotationAngle = getPreviewRotationAngle()

    if state.phase == GamePhase.ROTATING or state.phase == GamePhase.UNDO_ROTATING then
        drawRotatingBoard()
    elseif state.phase == GamePhase.MERGING then
        drawMergeAnimation(previewRotationAngle)
    else
        drawBoardCells(nil, nil, previewRotationAngle)
    end

    if state.phase == GamePhase.MERGING or state.phase == GamePhase.ROTATING then
        drawRotationDirectionArrow()
    end

    if state.phase == GamePhase.INPUT then
        drawLandingPreview()
    end

    if state.phase == GamePhase.DROPPING then
		-- 落下ブロックの描画.
        drawFallingBlock(previewRotationAngle)
    end

    if state.phase == GamePhase.INPUT then
        drawDropPreview()
    elseif state.phase == GamePhase.NEXT_ANIM then
        drawNextAnimation()
    end

    if state.phase == GamePhase.HOLD_ANIM then
        drawHoldAnimation()
    end
end

-- スコアの描画.
local function drawScore()
    HudRenderer.score(state.score)
end

-- コンボの描画.
local function drawCombo()
    state.comboDisplayFrame += 1
    HudRenderer.combo(state.combo, state.comboDisplayFrame, state.comboBonusScore)
end

-- NEXTブロックの描画.
local function drawNextBlocks()
    HudRenderer.next(state.nextValues, state.phase)
end

-- HOLDブロックの描画。右上の専用領域を使用する.
local function drawHoldBlock()
    HudRenderer.hold(state.holdValue, state.phase)
end

local function drawHeader()
    HudRenderer.header({
        score = state.score, combo = state.combo, comboDisplayFrame = state.comboDisplayFrame,
        comboBonusScore = state.comboBonusScore, holdValue = state.holdValue,
        nextValues = state.nextValues, phase = state.phase,
    })
    state.comboDisplayFrame = state.comboDisplayFrame + 1
    drawDangerIcons()
end

local function drawTitle()
    drawCenteredText("ROTATE 2048", 62)
    drawCenteredText("5 x 5 MERGE PUZZLE", 88)
    drawCenteredText("PRESS A TO START", 132)
    drawCenteredText("LEFT / RIGHT: SELECT   DOWN: DROP", 164)
end

-- 巻き戻し可能であることを表示する.
local function drawRewindHint()
    if state.phase == GamePhase.INPUT and isRewindAvailable() then
		-- 長押し中は表示とゲージをXORで描画する。
        local isHolding = state.rewindHoldStartedAt ~= nil
        local rewindText = "B: REWIND [" .. tostring(state.rewindUsesRemaining) .. "]"
		-- 巻き戻し可能であることを表示.
		gfx.drawText(rewindText, 280, 218)
		-- 枠の描画.
        gfx.drawRoundRect(270, 216, REWIND_GAUGE_WIDTH, 20, 4)
        if isHolding then
            local elapsed = pd.getCurrentTimeMilliseconds() - state.rewindHoldStartedAt
            local progress = math.min(1, Easing.cube_out(elapsed / REWIND_HOLD_DURATION_MS))
            local previousColor = gfx.getColor()
			-- XORで反転描画.
            gfx.setColor(gfx.kColorXOR)
            gfx.fillRoundRect(270, 216, math.floor(REWIND_GAUGE_WIDTH * progress), 20, 4)
            gfx.setColor(previousColor)
        else
        end
    end
end

-- ゲームオーバー表示.
local function drawGameOver()
    gfx.fillRect(122, 86, 156, 68)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    drawCenteredText("GAME OVER", 96)
    drawCenteredText("SCORE " .. tostring(state.score), 116)
    drawCenteredText("A: RETRY", 136)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)

local sceneManager

-- Playdateのシステムメニューからゲームを最初からやり直せるようにする.
pd.getSystemMenu():addMenuItem("Retry", function()
    startGame()
    if sceneManager ~= nil then
        sceneManager:change(Scene.GAME)
    end
end)

local sceneContext = SceneContext.new({
    sound = sound,
    phases = {
        INPUT = GamePhase.INPUT,
        PAUSED = GamePhase.PAUSED,
    },
    getPhase = function() return state.phase end,
    getResult = function() return state.result end,
    playMenuBgm = playMenuBgm,
    playGameBgm = playGameBgm,
    startGame = startGame,
    isAnimating = function(phase) return TurnResolver.isAnimating(phase) end,
    advanceAnimation = advanceAnimation,
    resetCursorIfNeeded = function()
        if state.phase ~= GamePhase.INPUT then resetCursorKeyRepeat() end
    end,
    updatePlayingInput = function()
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
    end,
    updatePausedInput = function()
        if pd.buttonJustPressed(pd.kButtonB) then
            state.phase = GamePhase.INPUT
        end
    end,
    drawTitle = drawTitle,
    drawNormalFrame = function()
        drawHeader()
        drawBoard()
        drawRewindHint()
        if state.phase == GamePhase.PAUSED then
            gfx.fillRect(145, 93, 110, 44)
            gfx.setImageDrawMode(gfx.kDrawModeInverted)
            drawCenteredText("PAUSED", 102)
            drawCenteredText("B: RESUME", 120)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        elseif state.message ~= "" and pd.getCurrentTimeMilliseconds() < state.messageUntil then
            drawCenteredText(state.message, 216)
        end
    end,
    drawGameOverFrame = function()
        drawHeader()
        drawBoard()
        drawGameOver()
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
