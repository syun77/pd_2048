import "CoreLibs/graphics"
import "CoreLibs/ui"
import "array2d"

local pd <const> = playdate
local gfx <const> = pd.graphics

local BOARD_SIZE <const> = 5
local CENTER <const> = 3
local CELL_SIZE <const> = 32
local BOARD_X <const> = 100
local BOARD_Y <const> = 48

local board = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
local cursorX = 3
local nextValue = 2
local score = 0
local highScore = 0
local gameState = "TITLE"
local message = ""
local messageUntil = 0

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

local function randomBlockValue()
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

local function addScore(value)
    score += value
    if score > highScore then
        highScore = score
    end
end

-- A block with horizontal adhesion may remain in place. Otherwise it falls
-- one cell at a time until the next step is blocked or reaches the axis.
local function applyGravity()
    local moved = true
    while moved do
        moved = false
        for y = BOARD_SIZE - 1, 1, -1 do
            for x = 1, BOARD_SIZE do
                if isPlayable(x, y) and board:get(x, y) ~= 0 then
                    local horizontallyAttached = false
                    if x > 1 and isOccupied(x - 1, y) then
                        horizontallyAttached = true
                    end
                    if x < BOARD_SIZE and isOccupied(x + 1, y) then
                        horizontallyAttached = true
                    end

                    local nextY = y + 1
                    if not horizontallyAttached and isPlayable(x, nextY) and board:get(x, nextY) == 0 then
                        board:set(x, nextY, board:get(x, y))
                        board:set(x, y, 0)
                        moved = true
                    end
                end
            end
        end
    end
    board:set(CENTER, CENTER, 0)
end

local function findMerge()
    -- Scan bottom-up and left-to-right for a deterministic merge order.
    for y = BOARD_SIZE, 1, -1 do
        for x = 1, BOARD_SIZE do
            if isPlayable(x, y) then
                local value = board:get(x, y)
                if value ~= 0 then
                    if x < BOARD_SIZE and isPlayable(x + 1, y) and board:get(x + 1, y) == value then
                        return x, y, x + 1, y
                    end
                    if y < BOARD_SIZE and isPlayable(x, y + 1) and board:get(x, y + 1) == value then
                        return x, y, x, y + 1
                    end
                end
            end
        end
    end
    return nil
end

local function resolveBoard()
    local changed = true
    while changed do
        changed = false
        applyGravity()
        local x1, y1, x2, y2 = findMerge()
        if x1 ~= nil then
            local mergedValue = board:get(x1, y1) * 2
            board:set(x1, y1, 0)
            board:set(x2, y2, mergedValue)
            addScore(mergedValue)
            changed = true
        end
    end
    applyGravity()
end

local function rotateBoard(clockwise)
    local rotated = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    board:foreach(function(x, y, value)
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
    board = rotated
    board:set(CENTER, CENTER, 0)
end

local function rotateForColumn(x)
    if x < CENTER then
        rotateBoard(false)
    elseif x > CENTER then
        rotateBoard(true)
    end
end

local function canDropInAnyColumn()
    for x = 1, BOARD_SIZE do
        if findDropCell(x) ~= nil then
            return true
        end
    end
    return false
end

local function spawnInitialBlocks()
    local firstX = math.random(1, BOARD_SIZE)
    local x, y = findDropCell(firstX)
    if x ~= nil then
        board:set(x, y, randomBlockValue())
    end

    local secondX = math.random(1, BOARD_SIZE)
    for _ = 1, BOARD_SIZE do
        x, y = findDropCell(secondX)
        if x ~= nil then
            board:set(x, y, randomBlockValue())
            break
        end
        secondX = secondX % BOARD_SIZE + 1
    end
end

local function startGame()
    clearBoard()
    score = 0
    cursorX = CENTER
    nextValue = randomBlockValue()
    spawnInitialBlocks()
    gameState = "PLAYING"
    message = ""
end

local function dropBlock()
    local x, y = findDropCell(cursorX)
    if x == nil then
        setMessage("NO SPACE", 700)
        if not canDropInAnyColumn() then
            saveHighScore()
            gameState = "GAME_OVER"
        end
        return
    end

    board:set(x, y, nextValue)
    nextValue = randomBlockValue()
    resolveBoard()
    rotateForColumn(cursorX)
    resolveBoard()

    if not canDropInAnyColumn() then
        saveHighScore()
        gameState = "GAME_OVER"
    end
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

local function drawTile(value, x, y)
    local px = BOARD_X + (x - 1) * CELL_SIZE
    local py = BOARD_Y + (y - 1) * CELL_SIZE
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

local function drawBoard()
    gfx.setLineWidth(1)
    gfx.drawRect(BOARD_X, BOARD_Y, BOARD_SIZE * CELL_SIZE, BOARD_SIZE * CELL_SIZE)

    for i = 1, BOARD_SIZE - 1 do
        gfx.drawLine(BOARD_X + i * CELL_SIZE, BOARD_Y, BOARD_X + i * CELL_SIZE, BOARD_Y + BOARD_SIZE * CELL_SIZE)
        gfx.drawLine(BOARD_X, BOARD_Y + i * CELL_SIZE, BOARD_X + BOARD_SIZE * CELL_SIZE, BOARD_Y + i * CELL_SIZE)
    end

    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(BOARD_X + (CENTER - 0.5) * CELL_SIZE, BOARD_Y + (CENTER - 0.5) * CELL_SIZE, 7)

    board:foreach(function(x, y, value)
        if value ~= 0 then
            drawTile(value, x, y)
        end
    end)

    local cursorPx = BOARD_X + (cursorX - 1) * CELL_SIZE
    gfx.drawLine(cursorPx + 7, BOARD_Y - 7, cursorPx + CELL_SIZE - 7, BOARD_Y - 7)
    gfx.drawLine(cursorPx + 7, BOARD_Y - 7, cursorPx + 11, BOARD_Y - 11)
    gfx.drawLine(cursorPx + CELL_SIZE - 7, BOARD_Y - 7, cursorPx + CELL_SIZE - 11, BOARD_Y - 11)
end

local function drawHeader()
    gfx.drawText("ROTATE 2048", 8, 4)
    gfx.drawTextAligned("SCORE " .. tostring(score), 392, 4, kTextAlignment.right)
    gfx.drawText("NEXT " .. tostring(nextValue), 8, 220)
    gfx.drawTextAligned("←/→ SELECT   ↓ DROP", 392, 220, kTextAlignment.right)
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
            dropBlock()
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
pd.display.setRefreshRate(30)
