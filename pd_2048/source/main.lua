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
local BOARD_X <const> = 100
local BOARD_Y <const> = 48
local NEXT_BOX_X <const> = 343
local NEXT_BOX_Y <const> = 48
local NEXT_BOX_WIDTH <const> = 25
local NEXT_BOX_HEIGHT <const> = 20
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
local nextValue = 2 -- nextブロック.
local followingValue = 2 -- nextの次のブロック.
local score = 0
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
    if y == BOARD_SIZE then
        return true
    end
    if isOccupied(x, y + 1) then
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

-- アクティブなブロックのマージ先を見つける.
local function findMergeForActiveBlock()
	-- Activeブロックは新たに追加されたブロックまたは前回のマージで残ったブロック.
	-- 方向の優先順位は「下・左・右・上」の順で、最初に見つかったマージ可能なブロックの位置を返す.
    local fallbackSourceX = 0
    local fallbackSourceY = 0
    local fallbackTargetX = 0
    local fallbackTargetY = 0
    local activeValue = board:get(activeMergeX, activeMergeY)

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
        local neighborX = activeMergeX + dx
        local neighborY = activeMergeY + dy
        if activeValue ~= 0 and isPlayable(neighborX, neighborY)
            and board:get(neighborX, neighborY) == activeValue then
            if mergeKeepsBlockConnected(activeMergeX, activeMergeY, neighborX, neighborY) then
                return activeMergeX, activeMergeY, neighborX, neighborY
            end
            if fallbackSourceX == 0 then
                fallbackSourceX = activeMergeX
                fallbackSourceY = activeMergeY
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

local function finishTurn()
    rotationStartBoard = nil
    rotationEndBoard = nil
    nextAnimationGameOver = not canDropInAnyColumn()
    animationProgress = 0
    animationDuration = 0.30
    gameState = GAME_STATE_NEXT_ANIM
end

local function finishNextAnimation()
    if nextAnimationGameOver then
        saveHighScore()
        gameState = GAME_STATE_GAME_OVER
        sound:stop_bgm(1.0)
    else
        gameState = GAME_STATE_PLAYING
    end
end

local function startRotation()
    if rotationEvaluation == 0 then
        finishTurn()
        return
    end

    rotationClockwise = rotationEvaluation > 0
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
    gameState = GAME_STATE_ROTATING
end

local function startResolve(nextAction)
    applyGravity()
    local x1, y1, x2, y2 = findMergeForActiveBlock()
    if x1 == nil then
        if nextAction == "ROTATE" then
            startRotation()
        else
            finishTurn()
        end
        return
    end

    mergeSourceX = x1
    mergeSourceY = y1
    mergeTargetX = x2
    mergeTargetY = y2
    mergeValue = board:get(x1, y1) * 2
    mergeNextAction = nextAction
    animationProgress = 0
    animationDuration = 0.22
    gameState = GAME_STATE_MERGING
end

local function finishMerge()
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
    cursorX = CENTER
    nextValue = randomBlockValue()
    followingValue = randomBlockValue()
    previewImpulseRotationDegrees = 0
    spawnInitialBlocks()
    gameState = GAME_STATE_PLAYING
    message = ""
    playGameBgm()
end

-- 落下開始.
local function beginDrop()
    local x, y = findDropCell(cursorX)
    if x == nil then
        setMessage("NO SPACE", 700)
        if not canDropInAnyColumn() then
            saveHighScore()
            gameState = GAME_STATE_GAME_OVER
            playMenuBgm()
        end
        return
    end

    pendingDropX = x
    pendingDropY = y
    pendingDropValue = nextValue
    rotationEvaluation = 0
    nextValue = followingValue
    followingValue = randomBlockValue()
    animationProgress = 0
    animationDuration = math.max(0.18, (y + 1) * 0.07)
    gameState = GAME_STATE_DROPPING
end

local function moveCursor(delta)
    cursorX += delta
    if cursorX < 1 then
        cursorX = 1
    elseif cursorX > BOARD_SIZE then
        cursorX = BOARD_SIZE
    end
end

local function drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

local function drawTileAt(value, px, py)
    local shade = math.min(10, math.floor(math.log(value, 2)))

    if shade % 2 == 0 then
        gfx.fillRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.drawRect(px + 2, py + 2, CELL_SIZE - 4, CELL_SIZE - 4)
    end
    gfx.drawTextAligned(tostring(value), px + CELL_SIZE / 2, py + 14, kTextAlignment.center)
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

local function drawFallingBlock(rotationAngle)
    local startY = BOARD_Y - CELL_SIZE
    local targetY = BOARD_Y + (pendingDropY - 1) * CELL_SIZE
    local y = startY + (targetY - startY) * animationProgress
    local px, py = getRotatedTilePosition(
        BOARD_X + (pendingDropX - 1) * CELL_SIZE, y, rotationAngle)
    drawTileAt(pendingDropValue, px, py)
end

local function drawDropPreview()
    local px = BOARD_X + (cursorX - 1) * CELL_SIZE
    local py = BOARD_Y - CELL_SIZE

    drawTileAt(nextValue, px, py)

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
    drawTileAt(mergeValue / 2,
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
    drawTileAt(nextValue,
        sourceX + (targetX - sourceX) * progress,
        sourceY + (targetY - sourceY) * progress)
end

local function drawBoard()
    drawBoardGrid()
    local previewRotationAngle = getPreviewRotationAngle()

    if gameState == GAME_STATE_ROTATING then
        drawRotatingBoard()
    elseif gameState == GAME_STATE_MERGING then
        drawMergeAnimation(previewRotationAngle)
    else
        drawBoardCells(nil, nil, previewRotationAngle)
    end

    if gameState == GAME_STATE_DROPPING then
        drawFallingBlock(previewRotationAngle)
    end

    if gameState == GAME_STATE_PLAYING then
        drawDropPreview()
    elseif gameState == GAME_STATE_NEXT_ANIM then
        drawNextAnimation()
    end
end

local function drawHeader()
    gfx.drawTextAligned("SCORE " .. tostring(score), 392, 4, kTextAlignment.right)
    gfx.drawText("NEXT", 300, 50)

    local shade = math.min(10, math.floor(math.log(followingValue, 2)))
    if shade % 2 == 0 then
        gfx.fillRect(NEXT_BOX_X, NEXT_BOX_Y, NEXT_BOX_WIDTH, NEXT_BOX_HEIGHT)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.drawRect(NEXT_BOX_X, NEXT_BOX_Y, NEXT_BOX_WIDTH, NEXT_BOX_HEIGHT)
    end
    gfx.drawTextAligned(tostring(followingValue),
        NEXT_BOX_X + NEXT_BOX_WIDTH * 0.5,
        NEXT_BOX_Y + 3,
        kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

local function drawTitle()
    drawCenteredText("ROTATE 2048", 62)
    drawCenteredText("5 x 5 MERGE PUZZLE", 88)
    drawCenteredText("PRESS A TO START", 132)
    drawCenteredText("LEFT / RIGHT: SELECT   DOWN: DROP", 164)
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
            gameState = GAME_STATE_PAUSED
        end
    elseif gameState == GAME_STATE_PAUSED then
        if pd.buttonJustPressed(pd.kButtonB) then
            gameState = GAME_STATE_PLAYING
        end
    elseif gameState == GAME_STATE_GAME_OVER then
        if pd.buttonJustPressed(pd.kButtonA) then
            startGame()
        end
    end

    if gameState == GAME_STATE_DROPPING or gameState == GAME_STATE_MERGING
        or gameState == GAME_STATE_ROTATING or gameState == GAME_STATE_NEXT_ANIM then
        advanceAnimation()
    end

    drawHeader()
    drawBoard()

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
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)
