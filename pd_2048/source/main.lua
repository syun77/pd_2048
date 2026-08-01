import "CoreLibs/graphics"
import "CoreLibs/ui"
import "array2d"
import "game_context"

local pd <const> = playdate
local gfx <const> = pd.graphics
local gameContext <const> = GameContext.getInstance()
local sound <const> = gameContext.sound

local DEFAULT_REFRESH_RATE <const> = 30 -- ディスプレイの更新レート (FPS。フレーム毎秒).
local BOARD_SIZE <const> = 5
local CENTER <const> = 3
local CELL_SIZE <const> = 32
local LAYOUT_BOARD_OFFSET_X <const> = 32 -- 盤面の横方向の調整値.
local LAYOUT_NEXT_OFFSET_X <const> = 8 -- NEXTブロックの横方向の調整値.
local BOARD_X <const> = 100 + LAYOUT_BOARD_OFFSET_X
local BOARD_Y <const> = 48
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
-- 方向定数.
local DIRECTION_DOWN <const> = 1
local DIRECTION_LEFT <const> = 2
local DIRECTION_RIGHT <const> = 3
local DIRECTION_UP <const> = 4
-- 状態定数.
local GAME_STATE_TITLE <const> = "TITLE"
local GAME_STATE_PLAYING <const> = "PLAYING"
local GAME_STATE_DROPPING <const> = "DROPPING"
local GAME_STATE_MERGING <const> = "MERGING"
local GAME_STATE_ROTATING <const> = "ROTATING"
local GAME_STATE_UNDO_ROTATING <const> = "UNDO_ROTATING"
local GAME_STATE_NEXT_ANIM <const> = "NEXT_ANIM"
local GAME_STATE_PAUSED <const> = "PAUSED"
local GAME_STATE_GAME_OVER <const> = "GAME_OVER"
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

local board = Array2D(BOARD_SIZE, BOARD_SIZE, 0) -- 盤面.
local cursorX = 3 -- カーソル位置.
local nextValues = {} -- 落下対象を先頭にした先読みキュー.
for i = 1, NEXT_QUEUE_COUNT do
    nextValues[i] = 2
end
local score = 0
local undoStates = {}
local rewindUsesRemaining = 0
local combo = 0
local comboDisplayFrame = 0
local comboSoundPlayed = false
local highScore = 0
local gameState = GAME_STATE_TITLE
local message = ""
local messageUntil = 0
local animationProgress = 0
local animationDuration = 0
local pendingDropX = 0
local pendingDropY = 0
local pendingDropValue = 0
local rotationStartBoard = nil
local rotationEndBoard = nil
local rotationClockwise = false
local mergeSourceX = 0
local mergeSourceY = 0
local mergeTargetX = 0
local mergeTargetY = 0
local mergeValue = 0
local mergeNextAction = "FINISH"
local activeMergeX = 0
local activeMergeY = 0
local nextAnimationGameOver = false
local rotationEvaluation = 0 -- 傾きプレビューの評価値.
local previewImpulseRotationDegrees = 0 -- プレビュー反動の角度.
local crisisBgmActive = false

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
    return x == CENTER and y == CENTER
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
        previewImpulseRotationDegrees += PREVIEW_IMPULSE_ROTATION_DEGREES
    else
        previewImpulseRotationDegrees -= PREVIEW_IMPULSE_ROTATION_DEGREES
    end
end

local function addRotationEvaluation(value)
	-- 加算倍率を適用.
	value *= PREVIEW_ROTATION_EVALUATION_MULTIPLIER
    rotationEvaluation += value
	--print("rotationEvaluation"	 .. rotationEvaluation)
	-- 傾き制限を適用.
	rotationEvaluation = math.max(-PREVIEW_ROTATION_MAX_DEGREES,
		math.min(PREVIEW_ROTATION_MAX_DEGREES, rotationEvaluation))
end

local function isPlayable(x, y)
    return x >= 1 and x <= BOARD_SIZE and y >= 1 and y <= BOARD_SIZE and not isCenter(x, y)
end

local function isOccupied(x, y)
    return isPlayable(x, y) and board:get(x, y) ~= 0
end

local function setMessage(text, duration)
    message = text
    messageUntil = pd.getCurrentTimeMilliseconds() + duration
end

-- ハイスコアのロード.
local function loadHighScore()
    local ok, value = pcall(pd.datastore.read, "highScore")
    if ok and type(value) == "number" then
        highScore = value
    end
end

-- ハイスコアの保存.
local function saveHighScore()
    if score > highScore then
        highScore = score
        pd.datastore.write(highScore, "highScore")
    end
end

-- 盤面を初期化する.
local function clearBoard()
    board = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    board:set(CENTER, CENTER, 0)
end

-- 盤面を値ごと複製する。Array2Dは参照型なので、取り消し用に別の盤面を作る。
local function copyBoard(source)
    local copied = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    source:foreach(function(x, y, value)
        copied:set(x, y, value)
    end)
    return copied
end

-- 1手前の状態を履歴に保存する。
local function saveUndoState()
    local state = {
        board = copyBoard(board),
        score = score,
        cursorX = cursorX,
        hasRotation = false,
        rotationClockwise = false,
        nextValues = {}
    }
    for i = 1, NEXT_QUEUE_COUNT do
        state.nextValues[i] = nextValues[i]
    end

    table.insert(undoStates, state)
    if #undoStates > MAX_UNDO_COUNT then
        table.remove(undoStates, 1)
    end
end

-- 直前の手を取り消す。取り消しは最大MAX_UNDO_COUNT手分可能。
local function undoLastTurn()
    if rewindUsesRemaining <= 0 then
        setMessage("NO REWINDS", 700)
        return false
    end
    if #undoStates == 0 then
        setMessage("NO UNDO", 700)
        return false
    end

    local state = table.remove(undoStates)
    rewindUsesRemaining -= 1
    local currentBoard = board
    board = state.board
    score = state.score
    cursorX = state.cursorX
    nextValues = state.nextValues

    combo = 0
    comboDisplayFrame = 0
    comboSoundPlayed = false
    rotationEvaluation = 0
    previewImpulseRotationDegrees = 0
    pendingDropValue = 0
    rotationStartBoard = nil
    rotationEndBoard = nil
    nextAnimationGameOver = false
    message = ""
    crisisBgmActive = false
    playGameBgm()

    if state.hasRotation then
        -- 現在の盤面を逆回転させながら、取り消し前の盤面へ戻す。
        board = currentBoard
        rotationStartBoard = currentBoard
        rotationEndBoard = state.board
        rotationClockwise = not state.rotationClockwise
        animationProgress = 0
        animationDuration = 0.38
        sound:play_se("rotate")
        gameState = GAME_STATE_UNDO_ROTATING
    else
        gameState = GAME_STATE_PLAYING
    end
    return true
end

local function getMaxTileValue()
    local maxValue = 0
    board:foreach(function(x, y, value)
        if value > maxValue then
            maxValue = value
        end
    end)
    return maxValue
end

-- ランダムでブロックを抽選する.
local function randomBlockValue()
    local maxHalf = math.floor(getMaxTileValue() / 2)

	-- 8以上のブロックがある場合、まれに最大値の半分のブロックを出現させる。通常の2/4の分布は維持される。
    if maxHalf > 4 then
        local roll = math.random(1, 100)
        if roll <= 2 then
            return maxHalf
        elseif roll <= 12 then
            return 4
        end
        return 2
    end
    if math.random(1, 10) == 10 then
        return 4
    end
    return 2
end

-- 落下可能かどうかを判定する.
local function isSupported(x, y)
    if not isPlayable(x, y) or board:get(x, y) ~= 0 then
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
    for y = 1, BOARD_SIZE do
        if isCenter(x, y) then
            return nil
        end
        if board:get(x, y) ~= 0 then
            return nil
        end
        if isSupported(x, y) then
            return x, y
        end
    end
    return nil
end

-- スコアを加算.
local function addScore(value)
    score += value
    if score > highScore then
        highScore = score -- ハイスコア更新.
    end
end

-- 重力を適用する.
local function applyGravity()
    -- 中心軸は見えない固定ブロックとして常に空けておく。
    board:set(CENTER, CENTER, 0)
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
            and board:get(neighborX, neighborY) == activeValue then
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
    return findMergeForBlock(activeMergeX, activeMergeY,
        board:get(activeMergeX, activeMergeY))
end

local function makeRotatedBoard(source, clockwise)
    local rotated = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    source:foreach(function(x, y, value)
        if isPlayable(x, y) and value ~= 0 then
            local newX
            local newY
            if clockwise then
                newX = BOARD_SIZE + 1 - y
                newY = x
            else
                newX = y
                newY = BOARD_SIZE + 1 - x
            end
            if isPlayable(newX, newY) then
                rotated:set(newX, newY, value)
            end
        end
    end)
    rotated:set(CENTER, CENTER, 0)
    return rotated
end

local function canDropInAnyColumn()
    for x = 1, BOARD_SIZE do
        if findDropCell(x) ~= nil then
            return true
        end
    end
    return false
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
        nextValues[i] = nextValues[i + 1]
    end
    nextValues[NEXT_QUEUE_COUNT] = randomBlockValue()
end

local function finishTurn()
    rotationStartBoard = nil
    rotationEndBoard = nil
    advanceNextQueue()
    nextAnimationGameOver = not canDropInAnyColumn()
    animationProgress = 0
    animationDuration = 0.30
    gameState = GAME_STATE_NEXT_ANIM
end

-- ゲームオーバー開始.
local function beginGameOver()
	saveHighScore()
	gameState = GAME_STATE_GAME_OVER
	sound:play_se("gameover")
	sound:stop_bgm(1.0)
end

local function finishNextAnimation()
    if nextAnimationGameOver then
		-- ゲームオーバー開始.
		beginGameOver()
    else
        gameState = GAME_STATE_PLAYING
    end
end

-- 回転開始.
local function startRotation()
    if rotationEvaluation == 0 then
        finishTurn()
        return
    end

    rotationClockwise = rotationEvaluation > 0
    local latestUndoState = undoStates[#undoStates]
    if latestUndoState ~= nil then
        latestUndoState.hasRotation = true
        latestUndoState.rotationClockwise = rotationClockwise
    end
    rotationStartBoard = board
    rotationEndBoard = makeRotatedBoard(rotationStartBoard, rotationClockwise)

    local oldActiveX = activeMergeX
    local oldActiveY = activeMergeY
    if rotationClockwise then
        activeMergeX = BOARD_SIZE + 1 - oldActiveY
        activeMergeY = oldActiveX
    else
        activeMergeX = oldActiveY
        activeMergeY = BOARD_SIZE + 1 - oldActiveX
    end

    animationProgress = 0
    animationDuration = 0.38
    sound:play_se("rotate")
    gameState = GAME_STATE_ROTATING
end

-- 連鎖が確定した時点でコンボSEを再生する.
local function playComboSoundIfNeeded()
    if combo < 2 or comboSoundPlayed then
        return
    end

    comboSoundPlayed = true
    comboDisplayFrame = 0
    if combo < 3 then
        sound:play_se("combo1")
    elseif combo < 5 then
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
    mergeSourceX = x1
    mergeSourceY = y1
    mergeTargetX = x2
    mergeTargetY = y2
    mergeValue = board:get(x1, y1) * 2
    mergeNextAction = nextAction
    animationProgress = 0
    animationDuration = 0.22
	sound:play_se("merge")
    gameState = GAME_STATE_MERGING
end

local function finishMerge()
    combo += 1
    local v = getMergeEvaluation(mergeSourceX, mergeTargetX)
    addRotationEvaluation(v)
    if mergeTargetX < mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_LEFT)
    elseif mergeTargetX > mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT)
    end
    board:set(mergeSourceX, mergeSourceY, 0)
    board:set(mergeTargetX, mergeTargetY, mergeValue)
    addScore(mergeValue)
    activeMergeX = mergeTargetX
    activeMergeY = mergeTargetY
    startResolve(mergeNextAction)
end

-- 落下完了.
local function finishDrop()
    board:set(pendingDropX, pendingDropY, pendingDropValue)
    pendingDropValue = 0
    activeMergeX = pendingDropX
    activeMergeY = pendingDropY
    addRotationEvaluation(ROTATION_EVALUATION_DROP_POSITION_WEIGHT
        * getPositionEvaluation(pendingDropX)
    )
    addPreviewImpulse(getPositionEvaluation(pendingDropX))
    startResolve("ROTATE")
	if gameState ~= GAME_STATE_MERGING then
		sound:play_se("fixed")
	end
end

local function advanceAnimation()
    previewImpulseRotationDegrees *= PREVIEW_IMPULSE_DECAY
    animationProgress += 1 / (animationDuration * 30)
    if animationProgress < 1 then
        return
    end

    animationProgress = 1
    if gameState == GAME_STATE_DROPPING then
        finishDrop()
    elseif gameState == GAME_STATE_MERGING then
        finishMerge()
    elseif gameState == GAME_STATE_ROTATING then
        board = rotationEndBoard
        startResolve("FINISH")
    elseif gameState == GAME_STATE_UNDO_ROTATING then
        board = rotationEndBoard
        rotationStartBoard = nil
        rotationEndBoard = nil
        gameState = GAME_STATE_PLAYING
    elseif gameState == GAME_STATE_NEXT_ANIM then
        finishNextAnimation()
    end
end

local function spawnInitialBlocks()
    -- Start with one block immediately to each side of the rotation axis.
    -- Coordinates are 1-based: the axis is (3, 3), so the two cells are
    -- (2, 3) and (4, 3).
    board:set(CENTER - 1, CENTER, randomBlockValue())
    board:set(CENTER + 1, CENTER, randomBlockValue())
end

local function startGame()
    clearBoard()
    score = 0
    undoStates = {}
    rewindUsesRemaining = MAX_REWIND_USES
    combo = 0
    comboDisplayFrame = 0
    comboSoundPlayed = false
    cursorX = CENTER
    nextValues = {}
    for i = 1, NEXT_QUEUE_COUNT do
        nextValues[i] = randomBlockValue()
    end
    previewImpulseRotationDegrees = 0
    spawnInitialBlocks()
    gameState = GAME_STATE_PLAYING
    message = ""
    crisisBgmActive = false
    playGameBgm()
end

-- 落下開始.
local function beginDrop()
    local x, y = findDropCell(cursorX)
    if x == nil then
        setMessage("NO SPACE", 700)
        if not canDropInAnyColumn() then
			-- ゲームオーバー開始.
            beginGameOver()
        end
        return
    end

    -- 落下開始.
    saveUndoState()
    combo = 0
    comboDisplayFrame = 0
    comboSoundPlayed = false
    pendingDropX = x
    pendingDropY = y
    pendingDropValue = nextValues[1]
    rotationEvaluation = 0
    animationProgress = 0
    animationDuration = math.max(0.18, (y + 1) * 0.07)
	sound:play_se("fall")
    gameState = GAME_STATE_DROPPING
end

-- カーソルを移動.
local function moveCursor(delta)
	local prev = cursorX
    cursorX += delta
    if cursorX < 1 then
        cursorX = 1
    elseif cursorX > BOARD_SIZE then
        cursorX = BOARD_SIZE
    end

	if prev ~= cursorX then
		-- 移動した.
		sound:play_se("pi")
	end
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
    if dangerActive and not crisisBgmActive then
        sound:setBgmRandomMode(BGMRandomMode.CRISIS)
        crisisBgmActive = true
    elseif not dangerActive and crisisBgmActive then
		crisisBgmActive = false
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
    local shade = math.min(10, math.floor(math.log(value, 2)))

    if shade % 2 == 0 then
        gfx.fillRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.drawRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
    end
	-- 数字の描画.
    gfx.drawTextAligned(tostring(value), px + CELL_SIZE / 2, py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

local function rotatePointAroundBoardCenter(px, py, angle)
    local rotationCenterX = BOARD_X + BOARD_SIZE * CELL_SIZE * 0.5
    local rotationCenterY = BOARD_Y + BOARD_SIZE * CELL_SIZE * 0.5
    local relativeX = px - rotationCenterX
    local relativeY = py - rotationCenterY
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)

    return rotationCenterX + relativeX * cosAngle - relativeY * sinAngle,
        rotationCenterY + relativeX * sinAngle + relativeY * cosAngle
end

local function getRotatedTilePosition(px, py, angle)
    if angle == 0 then
        return px, py
    end

    local centerX, centerY = rotatePointAroundBoardCenter(
        px + CELL_SIZE * 0.5, py + CELL_SIZE * 0.5, angle)
    return centerX - CELL_SIZE * 0.5, centerY - CELL_SIZE * 0.5
end

local function drawBoardGrid()
    gfx.setLineWidth(1)
    gfx.drawRect(BOARD_X, BOARD_Y, BOARD_SIZE * CELL_SIZE, BOARD_SIZE * CELL_SIZE)

    for i = 1, BOARD_SIZE - 1 do
        gfx.drawLine(BOARD_X + i * CELL_SIZE, BOARD_Y, BOARD_X + i * CELL_SIZE, BOARD_Y + BOARD_SIZE * CELL_SIZE)
        gfx.drawLine(BOARD_X, BOARD_Y + i * CELL_SIZE, BOARD_X + BOARD_SIZE * CELL_SIZE, BOARD_Y + i * CELL_SIZE)
    end

    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(BOARD_X + (CENTER - 0.5) * CELL_SIZE, BOARD_Y + (CENTER - 0.5) * CELL_SIZE, 7)
end

local function drawBoardCells(skipX, skipY, rotationAngle)
    board:foreach(function(x, y, value)
        if value ~= 0 and (x ~= skipX or y ~= skipY) then
            local px, py = getRotatedTilePosition(
                BOARD_X + (x - 1) * CELL_SIZE,
                BOARD_Y + (y - 1) * CELL_SIZE,
                rotationAngle)
            drawTileAt(value, px, py)
        end
    end)
end

-- 落下するブロックの描画.
local function drawFallingBlock(rotationAngle)
    local startY = BOARD_Y - CELL_SIZE
    local targetY = BOARD_Y + (pendingDropY - 1) * CELL_SIZE
    local y = startY + (targetY - startY) * animationProgress
    local px, py = getRotatedTilePosition(
        BOARD_X + (pendingDropX - 1) * CELL_SIZE, y, rotationAngle)
    drawTileAt(pendingDropValue, px, py)
end

-- 落下させたときの着地点を薄いゴースト表示する.
local function drawLandingPreview()
    local landingX, landingY = findDropCell(cursorX)
    if landingX == nil then
        return
    end

    local px = BOARD_X + (landingX - 1) * CELL_SIZE
    local py = BOARD_Y + (landingY - 1) * CELL_SIZE

    gfx.setDitherPattern(0.9, gfx.image.kDitherTypeBayer8x8)
    gfx.fillRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
    gfx.setColor(gfx.kColorBlack)
	-- 外枠は表示しない.
    --gfx.drawRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
	-- 数字の描画.
    gfx.drawTextAligned(tostring(nextValues[1]),
        px + CELL_SIZE / 2, py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- マージ予測方向の描画.
    local _, _, targetX, targetY = findMergeForBlock(landingX, landingY, nextValues[1])
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
    local px = BOARD_X + (cursorX - 1) * CELL_SIZE
    local py = BOARD_Y - CELL_SIZE

    drawTileAt(nextValues[1], px, py)

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
    local evaluation = rotationEvaluation
    if gameState == GAME_STATE_MERGING then
        local mergeEvaluation = getMergeEvaluation(mergeSourceX, mergeTargetX)
        evaluation += mergeEvaluation * easeInOut(animationProgress)
    end

	-- 最終的な倍率を加算した値を返す.
    return evaluation * PREVIEW_ROTATION_DEGREES_PER_POINT
end

local function getPreviewRotationDegrees()
    if gameState ~= GAME_STATE_DROPPING and gameState ~= GAME_STATE_MERGING then
        return 0
    end

    local previewEvaluation = getPreviewRotationEvaluation()
	-- 反動値を加算.
	previewEvaluation += previewImpulseRotationDegrees
	return previewEvaluation
end

-- 傾きプレビューの値をラジアンに変換して返す.
local function getPreviewRotationAngle()
    local degrees = getPreviewRotationDegrees()
    degrees = math.max(-PREVIEW_ROTATION_MAX_DEGREES,
        math.min(PREVIEW_ROTATION_MAX_DEGREES, degrees))
	-- 反動値は傾き制限を考慮しない.
	degrees += previewImpulseRotationDegrees
    return math.rad(degrees)
end

local function drawRotatingBoard()
    local progress = easeInOut(animationProgress)
    local angle = math.pi * 0.5 * progress
    if not rotationClockwise then
        angle = -angle
    end

    rotationStartBoard:foreach(function(x, y, value)
        if value ~= 0 then
            local px, py = getRotatedTilePosition(
                BOARD_X + (x - 1) * CELL_SIZE,
                BOARD_Y + (y - 1) * CELL_SIZE,
                angle)
            drawTileAt(value, px, py)
        end
    end)
end

local function drawMergeAnimation(rotationAngle)
    drawBoardCells(mergeSourceX, mergeSourceY, rotationAngle)

    local progress = easeInOut(animationProgress)
    local sourcePx = BOARD_X + (mergeSourceX - 1) * CELL_SIZE
    local sourcePy = BOARD_Y + (mergeSourceY - 1) * CELL_SIZE
    local targetPx = BOARD_X + (mergeTargetX - 1) * CELL_SIZE
    local targetPy = BOARD_Y + (mergeTargetY - 1) * CELL_SIZE
    local rotatedTargetPx, rotatedTargetPy = getRotatedTilePosition(
        targetPx, targetPy, rotationAngle)
    drawTileAt(board:get(mergeTargetX, mergeTargetY), rotatedTargetPx, rotatedTargetPy)

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
    drawTileAt(math.floor(mergeValue / 2),
        rotatedSourcePx, rotatedSourcePy)
end

local function drawNextAnimation()
    local progress = easeInOut(animationProgress)
    local sourceCenterX = NEXT_BOX_X + NEXT_BOX_WIDTH * 0.5
    local sourceCenterY = NEXT_BOX_Y + NEXT_BOX_HEIGHT * 0.5
    local sourceX = sourceCenterX - CELL_SIZE * 0.5
    local sourceY = sourceCenterY - CELL_SIZE * 0.5
    local targetX = BOARD_X + (cursorX - 1) * CELL_SIZE
    local targetY = BOARD_Y - CELL_SIZE
    drawTileAt(nextValues[1],
        sourceX + (targetX - sourceX) * progress,
        sourceY + (targetY - sourceY) * progress)
end

-- 盤面の描画.
local function drawBoard()
    drawBoardGrid()
    local previewRotationAngle = getPreviewRotationAngle()

    if gameState == GAME_STATE_ROTATING or gameState == GAME_STATE_UNDO_ROTATING then
        drawRotatingBoard()
    elseif gameState == GAME_STATE_MERGING then
        drawMergeAnimation(previewRotationAngle)
    else
        drawBoardCells(nil, nil, previewRotationAngle)
    end

    if gameState == GAME_STATE_PLAYING then
        drawLandingPreview()
    end

    if gameState == GAME_STATE_DROPPING then
		-- 落下ブロックの描画.
        drawFallingBlock(previewRotationAngle)
    end

    if gameState == GAME_STATE_PLAYING then
        drawDropPreview()
    elseif gameState == GAME_STATE_NEXT_ANIM then
        drawNextAnimation()
    end
end

-- コンボの描画.
local function drawCombo()
	if combo <= 1 then
		return -- 描画不要.
	end

    comboDisplayFrame += 1
	if comboDisplayFrame >= COMBO_BLINK_DURATION_FRAMES + COMBO_STEADY_DURATION_FRAMES then
		return -- 描画不要.
	end

	local isBlinking = comboDisplayFrame < COMBO_BLINK_DURATION_FRAMES
	if isBlinking then
		local isBlinkOn = (comboDisplayFrame % COMBO_BLINK_PERIOD_FRAMES)
			< COMBO_BLINK_ON_FRAMES
		-- 点滅中は枠を描画.
		if isBlinkOn then
			gfx.drawRoundRect(4 + PANEL_OFFSET_X, 50 + PANEL_OFFSET_Y, 88, 24, 4)
		end
	end
	gfx.drawText("COMBO: " .. tostring(combo), 12 + PANEL_OFFSET_X, 54 + PANEL_OFFSET_Y)
end

-- NEXTブロックの描画.
local function drawNextBlocks()
    gfx.drawText("NEXT", NEXT_LABEL_X, 20)
    for i = 1, NEXT_PREVIEW_COUNT do
		if i == 1 then
			-- 1番目は点滅する.
			local isBlink = (pd.getCurrentTimeMilliseconds() % 400) < 200
			if isBlink then
				gfx.setLineWidth(2)
				gfx.drawRect(NEXT_BOX_X, NEXT_BOX_Y, NEXT_BOX_WIDTH, NEXT_BOX_HEIGHT)
				gfx.setLineWidth(1)
			end
		else
			-- 2番目以降は点滅しない.
			gfx.setLineWidth(1)
		end

        -- 通常時は落下対象(nextValues[1])を除き、次の次から表示する.
        -- NEXT_ANIM中だけは、アニメーション元のブロックを1番目に表示する.
        local valueIndex = i + 1
        if gameState == GAME_STATE_NEXT_ANIM then
            valueIndex = i
        end
        local value = nextValues[valueIndex]
        local boxY = NEXT_BOX_Y + (i - 1) * (NEXT_BOX_HEIGHT + NEXT_BOX_GAP)
        local shade = math.min(10, math.floor(math.log(value, 2)))
        if shade % 2 == 0 then
            gfx.fillRect(NEXT_BOX_X, boxY, NEXT_BOX_WIDTH, NEXT_BOX_HEIGHT)
            gfx.setImageDrawMode(gfx.kDrawModeInverted)
        else
            gfx.drawRect(NEXT_BOX_X, boxY, NEXT_BOX_WIDTH, NEXT_BOX_HEIGHT)
        end
        gfx.drawTextAligned(tostring(value),
            NEXT_BOX_X + NEXT_BOX_WIDTH * 0.5,
            boxY + 3,
            kTextAlignment.center)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end
end

local function drawHeader()
	-- スコアの描画.
    gfx.drawTextAligned("SCORE: ", 12 + PANEL_OFFSET_X, PANEL_OFFSET_Y, kTextAlignment.left)
    gfx.drawTextAligned(tostring(score), 80 + PANEL_OFFSET_X, 24 + PANEL_OFFSET_Y, kTextAlignment.right)
	-- コンボ数の描画.
    drawCombo()

	-- NEXtの描画.
	drawNextBlocks()

	-- 危険アイコンの描画.
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
    if (gameState == GAME_STATE_PLAYING or gameState == GAME_STATE_GAME_OVER)
        and #undoStates > 0 and rewindUsesRemaining > 0 then
		-- 巻き戻し可能であることを表示.
        gfx.drawText("B: REWIND [" .. tostring(rewindUsesRemaining) .. "]", 280, 220)
    end
end

-- ゲームオーバー表示.
local function drawGameOver()
    gfx.fillRect(122, 86, 156, 68)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    drawCenteredText("GAME OVER", 96)
    drawCenteredText("SCORE " .. tostring(score), 116)
    drawCenteredText("A: RETRY", 136)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function pd.update()
    gfx.clear(gfx.kColorWhite)

    if gameState == GAME_STATE_TITLE then
        drawTitle()
        if pd.buttonJustPressed(pd.kButtonA) then
			sound:play_se("decide")
            startGame()
        end
        return
    end

    if gameState == GAME_STATE_PLAYING then
        if pd.buttonJustPressed(pd.kButtonLeft) then
            moveCursor(-1)
        elseif pd.buttonJustPressed(pd.kButtonRight) then
            moveCursor(1)
        elseif pd.buttonJustPressed(pd.kButtonDown) then
            beginDrop()
        elseif pd.buttonJustPressed(pd.kButtonB) then
            undoLastTurn()
        end
    elseif gameState == GAME_STATE_PAUSED then
        if pd.buttonJustPressed(pd.kButtonB) then
            gameState = GAME_STATE_PLAYING
        end
    elseif gameState == GAME_STATE_GAME_OVER then
        if pd.buttonJustPressed(pd.kButtonB) then
            undoLastTurn()
        elseif pd.buttonJustPressed(pd.kButtonA) then
			sound:play_se("decide")
            startGame()
        end
    end

    if gameState == GAME_STATE_DROPPING or gameState == GAME_STATE_MERGING
        or gameState == GAME_STATE_ROTATING or gameState == GAME_STATE_UNDO_ROTATING
        or gameState == GAME_STATE_NEXT_ANIM then
        advanceAnimation()
    end

	-- 各種情報の描画.
    drawHeader()

	-- 盤面の描画.
    drawBoard()

    drawRewindHint()

    if gameState == GAME_STATE_PAUSED then
        gfx.fillRect(145, 93, 110, 44)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
        drawCenteredText("PAUSED", 102)
        drawCenteredText("B: RESUME", 120)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    elseif gameState == GAME_STATE_GAME_OVER then
        drawGameOver()
    elseif message ~= "" and pd.getCurrentTimeMilliseconds() < messageUntil then
        drawCenteredText(message, 226)
    end

	-- FPSを描画.
	pd.drawFPS(4, 4)

    if gameState == GAME_STATE_UNDO_ROTATING then
        -- 巻き戻し中であることを示すため、画面全体をXOR反転する。
        -- kDrawModeXORは画像・フォント用で、fillRectには適用されないため、
        -- プリミティブ用のkColorXORを使う。
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)
