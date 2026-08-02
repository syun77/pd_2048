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

-- ポーズメニューの描画.
function OverlayRenderer:drawPause()
    gfx.fillRect(145, 93, 110, 44)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    self:drawCenteredText("PAUSED", 102)
    self:drawCenteredText("B: RESUME", 120)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- 通知メッセージの描画.
function OverlayRenderer:drawMessage()
    local state = self.state
    if state.message ~= ""
        and pd.getCurrentTimeMilliseconds() < state.messageUntil then
        self:drawCenteredText(state.message, 216)
    end
end

-- 中心座標を基準に、選択可能なメニューを描画する。
function OverlayRenderer:drawMenu(centerX, centerY, items, selectedIndex, backgroundColor)
    if items == nil or #items == 0 then return end
    backgroundColor = backgroundColor or gfx.kColorBlack

    local maxTextWidth = 0
    local textHeight = 0
    for _, item in ipairs(items) do
        local textWidth, height = gfx.getTextSize(item)
        maxTextWidth = math.max(maxTextWidth, textWidth)
        textHeight = math.max(textHeight, height)
    end

	local mergin = 32 -- 左右の余白を32pxに設定.
    local horizontalPadding = 16
    local verticalPadding = 8
    local itemHeight = textHeight + 8
    local menuWidth = maxTextWidth + horizontalPadding * 2
    local menuHeight = #items * itemHeight + verticalPadding * 2
	menuWidth += mergin * 2 -- 左右に余白を追加.

    local menuX = math.floor(centerX - menuWidth * 0.5)
    local menuY = math.floor(centerY - menuHeight * 0.5)

    local previousColor = gfx.getColor()
    local previousDrawMode = gfx.getImageDrawMode()
    gfx.setColor(backgroundColor)
    gfx.fillRoundRect(menuX, menuY, menuWidth, menuHeight, 6)
    if backgroundColor == gfx.kColorBlack then
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setColor(gfx.kColorBlack)
    end
    for index, item in ipairs(items) do
        local itemY = menuY + verticalPadding + (index - 1) * itemHeight
        self:drawCenteredText(item, itemY)
    end
    gfx.setImageDrawMode(previousDrawMode)

    if selectedIndex == nil then
        gfx.setColor(previousColor)
        return
    end
    selectedIndex = math.max(1, math.min(#items, selectedIndex))
    local selectedY = menuY + verticalPadding + (selectedIndex - 1) * itemHeight

	-- カーソルを XORで描画.
	gfx.setColor(gfx.kColorXOR)
	if backgroundColor == gfx.kColorBlack then
		gfx.drawRoundRect(menuX + 4, selectedY - 4, menuWidth - 8, textHeight + 6, 4)
	else
	    gfx.fillRoundRect(menuX + 4, selectedY - 4, menuWidth - 8, textHeight + 6, 4)
	end
	gfx.setColor(gfx.kColorBlack)
    gfx.setColor(previousColor)
end

-- ゲームオーバーメニューの描画.
function OverlayRenderer:drawGameOver(selectedIndex)
    selectedIndex = selectedIndex or 1
    local resultTitle = self.state.result == Config.GAME_RESULT.TIME_UP
        and "TIME UP" or "GAME OVER"
    self:drawMenu(200, 130, {
        resultTitle,
        "SCORE " .. tostring(self.state.score),
        "RETRY",
        "TITLE",
    }, selectedIndex + 2)
end

_G.OverlayRenderer = OverlayRenderer
return OverlayRenderer
