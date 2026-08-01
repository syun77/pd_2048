import "CoreLibs/graphics"
import "CoreLibs/ui"
import "array2d"
import "game_context"

local pd <const> = playdate
local gfx <const> = pd.graphics
local gameContext <const> = GameContext.getInstance()
local sound <const> = gameContext.sound

local BOARD_SIZE <const> = 5
local CENTER <const> = 3
local CELL_SIZE <const> = 32
local BOARD_X <const> = 100
local BOARD_Y <const> = 48
local NEXT_BOX_X <const> = 343
local NEXT_BOX_Y <const> = 48
local NEXT_BOX_WIDTH <const> = 25
local NEXT_BOX_HEIGHT <const> = 20

local board = Array2D(BOARD_SIZE, BOARD_SIZE, 0) -- 盤面.
local cursorX = 3 -- カーソル位置.
local nextValue = 2 -- nextブロック.
local followingValue = 2 -- nextの次のブロック.
local score = 0
local highScore = 0
local gameState = "TITLE"
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

local function playMenuBgm()
    sound:setBgmRandomMode(BGMRandomMode.MENU)
    sound:play_bgm(-1, false)
end

local function playGameBgm()
    sound:setBgmRandomMode(BGMRandomMode.NOMAL)
    sound:play_bgm(-1, true)
end

local function isCenter(x, y)
    return x == CENTER and y == CENTER
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

local function loadHighScore()
    local ok, value = pcall(pd.datastore.read, "highScore")
    if ok and type(value) == "number" then
        highScore = value
    end
end

local function saveHighScore()
    if score > highScore then
        highScore = score
        pd.datastore.write(highScore, "highScore")
    end
end

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

    -- Once the board has a tile above 8, very occasionally introduce half
    -- of the current maximum. The normal 2/4 distribution remains intact.
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

-- Find the first legal cell encountered while falling from the top.
-- The center axis blocks the vertical path in the center column.
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

-- Gravity is intentionally disabled. Rotation changes the board coordinates,
-- but blocks do not subsequently fall toward the bottom of the screen.
local function applyGravity()
    board:set(CENTER, CENTER, 0)
end

local function mergeKeepsBlockConnected(sourceX, sourceY, targetX, targetY)
    -- The source disappears into the target. The resulting block is
    -- considered connected when it has any other orthogonal neighbor.
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

local function findMergeForActiveBlock()
    -- The active block is the newly dropped block, or the result of the
    -- previous merge in the current chain. Direction priority is down, left,
    -- right, up, but preserving a neighbor connection takes precedence.
    local fallbackSourceX = 0
    local fallbackSourceY = 0
    local fallbackTargetX = 0
    local fallbackTargetY = 0
    local activeValue = board:get(activeMergeX, activeMergeY)

    for direction = 1, 4 do
        local dx = 0
        local dy = 0
        if direction == 1 then
            dy = 1       -- down
        elseif direction == 2 then
            dx = -1      -- left
        elseif direction == 3 then
            dx = 1       -- right
        else
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
    gameState = "NEXT_ANIM"
end

local function finishNextAnimation()
    if nextAnimationGameOver then
        saveHighScore()
        gameState = "GAME_OVER"
        playMenuBgm()
    else
        gameState = "PLAYING"
    end
end

local function startRotation()
    if pendingDropX == CENTER then
        finishTurn()
        return
    end

    rotationClockwise = pendingDropX > CENTER
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
    gameState = "ROTATING"
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
    gameState = "MERGING"
end

local function finishMerge()
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
    startResolve("ROTATE")
end

local function advanceAnimation()
    animationProgress += 1 / (animationDuration * 30)
    if animationProgress < 1 then
        return
    end

    animationProgress = 1
    if gameState == "DROPPING" then
        finishDrop()
    elseif gameState == "MERGING" then
        finishMerge()
    elseif gameState == "ROTATING" then
        board = rotationEndBoard
        startResolve("FINISH")
    elseif gameState == "NEXT_ANIM" then
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
    spawnInitialBlocks()
    gameState = "PLAYING"
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
            gameState = "GAME_OVER"
            playMenuBgm()
        end
        return
    end

    pendingDropX = x
    pendingDropY = y
    pendingDropValue = nextValue
    nextValue = followingValue
    followingValue = randomBlockValue()
    animationProgress = 0
    animationDuration = math.max(0.18, (y + 1) * 0.07)
    gameState = "DROPPING"
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

local function drawBoardCells(skipX, skipY)
    board:foreach(function(x, y, value)
        if value ~= 0 and (x ~= skipX or y ~= skipY) then
            drawTileAt(value, BOARD_X + (x - 1) * CELL_SIZE, BOARD_Y + (y - 1) * CELL_SIZE)
        end
    end)
end

local function drawFallingBlock()
    local startY = BOARD_Y - CELL_SIZE
    local targetY = BOARD_Y + (pendingDropY - 1) * CELL_SIZE
    local y = startY + (targetY - startY) * animationProgress
    drawTileAt(pendingDropValue, BOARD_X + (pendingDropX - 1) * CELL_SIZE, y)
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

local function drawRotatingBoard()
    local progress = easeInOut(animationProgress)
    local angle = math.pi * 0.5 * progress
    if not rotationClockwise then
        angle = -angle
    end

    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)
    local rotationCenterX = BOARD_X + BOARD_SIZE * CELL_SIZE * 0.5
    local rotationCenterY = BOARD_Y + BOARD_SIZE * CELL_SIZE * 0.5

    rotationStartBoard:foreach(function(x, y, value)
        if value ~= 0 then
            local tileCenterX = BOARD_X + (x - 0.5) * CELL_SIZE
            local tileCenterY = BOARD_Y + (y - 0.5) * CELL_SIZE
            local relativeX = tileCenterX - rotationCenterX
            local relativeY = tileCenterY - rotationCenterY

            -- Screen coordinates have Y growing downward. With this sign
            -- convention, a positive angle is a clockwise rotation.
            local rotatedX = relativeX * cosAngle - relativeY * sinAngle
            local rotatedY = relativeX * sinAngle + relativeY * cosAngle
            local rotatedCenterX = rotationCenterX + rotatedX
            local rotatedCenterY = rotationCenterY + rotatedY

            drawTileAt(value,
                rotatedCenterX - CELL_SIZE * 0.5,
                rotatedCenterY - CELL_SIZE * 0.5)
        end
    end)
end

local function drawMergeAnimation()
    drawBoardCells(mergeSourceX, mergeSourceY)

    local progress = easeInOut(animationProgress)
    local sourcePx = BOARD_X + (mergeSourceX - 1) * CELL_SIZE
    local sourcePy = BOARD_Y + (mergeSourceY - 1) * CELL_SIZE
    local targetPx = BOARD_X + (mergeTargetX - 1) * CELL_SIZE
    local targetPy = BOARD_Y + (mergeTargetY - 1) * CELL_SIZE
    drawTileAt(board:get(mergeTargetX, mergeTargetY), targetPx, targetPy)
    drawTileAt(mergeValue / 2,
        sourcePx + (targetPx - sourcePx) * progress,
        sourcePy + (targetPy - sourcePy) * progress)
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

    if gameState == "ROTATING" then
        drawRotatingBoard()
    elseif gameState == "MERGING" then
        drawMergeAnimation()
    else
        drawBoardCells()
    end

    if gameState == "DROPPING" then
        drawFallingBlock()
    end

    if gameState == "PLAYING" then
        drawDropPreview()
    elseif gameState == "NEXT_ANIM" then
        drawNextAnimation()
    end
end

local function drawHeader()
    gfx.drawText("ROTATE 2048", 8, 4)
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

    if gameState == "TITLE" then
        drawTitle()
        if pd.buttonJustPressed(pd.kButtonA) then
            startGame()
        end
        return
    end

    if gameState == "PLAYING" then
        if pd.buttonJustPressed(pd.kButtonLeft) then
            moveCursor(-1)
        elseif pd.buttonJustPressed(pd.kButtonRight) then
            moveCursor(1)
        elseif pd.buttonJustPressed(pd.kButtonDown) then
            beginDrop()
        elseif pd.buttonJustPressed(pd.kButtonB) then
            gameState = "PAUSED"
        end
    elseif gameState == "PAUSED" then
        if pd.buttonJustPressed(pd.kButtonB) then
            gameState = "PLAYING"
        end
    elseif gameState == "GAME_OVER" then
        if pd.buttonJustPressed(pd.kButtonA) then
            startGame()
        end
    end

    if gameState == "DROPPING" or gameState == "MERGING" or gameState == "ROTATING"
        or gameState == "NEXT_ANIM" then
        advanceAnimation()
    end

    drawHeader()
    drawBoard()

    if gameState == "PAUSED" then
        gfx.fillRect(145, 93, 110, 44)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
        drawCenteredText("PAUSED", 102)
        drawCenteredText("B: RESUME", 120)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    elseif gameState == "GAME_OVER" then
        drawGameOver()
    elseif message ~= "" and pd.getCurrentTimeMilliseconds() < messageUntil then
        drawCenteredText(message, 226)
    end
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(30)
