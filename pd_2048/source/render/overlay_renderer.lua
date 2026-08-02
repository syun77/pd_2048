import "CoreLibs/graphics"
import "easing"
import "game_config"
import "board/board_rules"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE

local OverlayRenderer = {}
OverlayRenderer.__index = OverlayRenderer

function OverlayRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        sound = dependencies.sound,
        isRewindAvailable = dependencies.isRewindAvailable,
    }, OverlayRenderer)
end

function OverlayRenderer:drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

function OverlayRenderer:drawDangerIcon(x, y, size, blinking)
    if blinking then
        local blinkProgress = pd.getCurrentTimeMilliseconds() % Config.DANGER_ICON_BLINK_PERIOD
        if blinkProgress >= Config.DANGER_ICON_BLINK_ON_DURATION then return end
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

function OverlayRenderer:drawDangerIcons()
    local bottomDanger, bottomCritical,
        leftDanger, leftCritical,
        rightDanger, rightCritical = self:getDangerEdges()
    local dangerActive = bottomDanger or leftDanger or rightDanger
    if dangerActive and not self.state.crisisBgmActive then
        self.sound:setBgmRandomMode(BGMRandomMode.CRISIS)
        self.state.crisisBgmActive = true
    elseif not dangerActive and self.state.crisisBgmActive then
        self.state.crisisBgmActive = false
    end

    local boardSize = Config.BOARD_SIZE * Config.CELL_SIZE
    local size = Config.DANGER_ICON_SIZE
    local offset = Config.DANGER_ICON_OFFSET
    local bottomX = Config.BOARD_X + (boardSize - size) * 0.5
    local bottomY = Config.BOARD_Y + boardSize + offset
    local leftX = Config.BOARD_X - size - offset
    local leftY = Config.BOARD_Y + (boardSize - size) * 0.5
    local rightX = Config.BOARD_X + boardSize + offset

    if bottomDanger then self:drawDangerIcon(bottomX, bottomY, size, bottomCritical) end
    if leftDanger then self:drawDangerIcon(leftX, leftY, size, leftCritical) end
    if rightDanger then self:drawDangerIcon(rightX, leftY, size, rightCritical) end
end

function OverlayRenderer:getDangerEdges()
    local board = self.state.board
    local bottomCount = 0
    for x = 1, Config.BOARD_SIZE do
        if BoardRules.isOccupied(board, x, Config.BOARD_SIZE) then
            bottomCount += 1
        end
    end

    local leftCount = 0
    local rightCount = 0
    for y = 1, Config.BOARD_SIZE do
        if BoardRules.isOccupied(board, 1, y) then leftCount += 1 end
        if BoardRules.isOccupied(board, Config.BOARD_SIZE, y) then rightCount += 1 end
    end

    return bottomCount >= 4, bottomCount == Config.BOARD_SIZE,
        leftCount >= 4, leftCount == Config.BOARD_SIZE,
        rightCount >= 4, rightCount == Config.BOARD_SIZE
end

function OverlayRenderer:drawRewindHint()
    local state = self.state
    if state.phase ~= GamePhase.INPUT or not self.isRewindAvailable() then return end

    local isHolding = state.rewindHoldStartedAt ~= nil
    local rewindText = "B: REWIND [" .. tostring(state.rewindUsesRemaining) .. "]"
    gfx.drawText(rewindText, 280, 218)
    gfx.drawRoundRect(270, 216, Config.REWIND_GAUGE_WIDTH, 20, 4)
    if not isHolding then return end

    local elapsed = pd.getCurrentTimeMilliseconds() - state.rewindHoldStartedAt
    local progress = math.min(1, Easing.cube_out(
        elapsed / Config.REWIND_HOLD_DURATION_MS))
    local previousColor = gfx.getColor()
    gfx.setColor(gfx.kColorXOR)
    gfx.fillRoundRect(270, 216,
        math.floor(Config.REWIND_GAUGE_WIDTH * progress), 20, 4)
    gfx.setColor(previousColor)
end

function OverlayRenderer:drawPause()
    gfx.fillRect(145, 93, 110, 44)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    self:drawCenteredText("PAUSED", 102)
    self:drawCenteredText("B: RESUME", 120)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function OverlayRenderer:drawMessage()
    local state = self.state
    if state.message ~= ""
        and pd.getCurrentTimeMilliseconds() < state.messageUntil then
        self:drawCenteredText(state.message, 216)
    end
end

function OverlayRenderer:drawTitle()
    self:drawCenteredText("ROTATE 2048", 62)
    self:drawCenteredText("5 x 5 MERGE PUZZLE", 88)
    self:drawCenteredText("PRESS A TO START", 132)
    self:drawCenteredText("LEFT / RIGHT: SELECT   DOWN: DROP", 164)
end

function OverlayRenderer:drawGameOver()
    gfx.fillRect(122, 86, 156, 68)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    self:drawCenteredText("GAME OVER", 96)
    self:drawCenteredText("SCORE " .. tostring(self.state.score), 116)
    self:drawCenteredText("A: RETRY", 136)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

_G.OverlayRenderer = OverlayRenderer
return OverlayRenderer
