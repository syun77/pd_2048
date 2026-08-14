import "CoreLibs/graphics"
import "easing"
import "game_config"
import "board/board_rules"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE

---@class OverlayRendererDependencies オーバーレイ描画クラスの依存関係.
---@field state GameState ゲーム状態.
---@field sound Sound サウンド管理.
---@field isRewindAvailable fun(): boolean リワインドが可能かどうかを返す関数.
---@field menuScrollLastOffset integer? 前回のスクロールオフセット.

---@class OverlayRenderer オーバーレイ描画クラス.
---@field state GameState
---@field sound Sound サウンド管理.
---@field isRewindAvailable fun(): boolean リワインドが可能かどうかを返す関数.
local OverlayRenderer = {}
OverlayRenderer.__index = OverlayRenderer

-- 生成.
---@param dependencies OverlayRendererDependencies 依存関係.
---@return OverlayRenderer オーバーレイ描画クラス.
function OverlayRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        sound = dependencies.sound,
        isRewindAvailable = dependencies.isRewindAvailable,
        menuScrollLastOffset = nil,
        menuScrollUpAnimationOffset = 0,
        menuScrollDownAnimationOffset = 0,
    }, OverlayRenderer)
end

function OverlayRenderer:drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

function OverlayRenderer:drawLevelUp()
    local state = self.state
    if state.mode ~= Config.GAME_MODE.NORMAL
        or state.levelUpUntil <= pd.getCurrentTimeMilliseconds() then return end
    local text = "LEVEL UP  " .. tostring(state.levelUpTo)
    local width, height = gfx.getTextSize(text)
    local x = (Config.SCREEN_WIDTH - width) * 0.5
    local y = 28
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(x - 10, y - 5, width + 20, height + 10, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(x - 10, y - 5, width + 20, height + 10, 4)
    gfx.drawText(text, x, y)
end

-- 危険アイコンの描画.
---@param x integer アイコンの左上X座標.
---@param y integer アイコンの左上Y座標.
---@param size integer アイコンのサイズ.
---@param blinking boolean 点滅するかどうか.
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

function OverlayRenderer:drawStartReady()
    local state = self.state
    if state.startReadyUntil == 0
        or pd.getCurrentTimeMilliseconds() >= state.startReadyUntil then
        return
    end
    gfx.fillRect(120, 101, 160, 38)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    self:drawCenteredText("GET READY", 112)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function OverlayRenderer:drawCoreRushGain()
    local state = self.state
    if state.mode ~= Config.GAME_MODE.CORE_RUSH
        or state.coreRushGainUntil == 0
        or pd.getCurrentTimeMilliseconds() >= state.coreRushGainUntil then
        return
    end

    local comboText = tostring(state.coreRushGainCombo) .. " COMBO"
    local calculationText = string.format("%d x %d = %d",
        state.coreRushGainMergeValue, state.coreRushGainCombo,
        state.coreRushGainTotal)
    local comboWidth, lineHeight = gfx.getTextSize(comboText)
    local calculationWidth = gfx.getTextSize(calculationText)
    local boxWidth = math.max(comboWidth, calculationWidth) + 32
    local boxHeight = lineHeight * 2 + 20
    -- 右下のサイドパネル内。NEXTとREWINDの表示領域を避ける。
    local boxX = 400 - boxWidth - 8
    local boxY = 148
    gfx.fillRoundRect(boxX, boxY, boxWidth, boxHeight, 6)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    local boxCenterX = boxX + boxWidth * 0.5
    gfx.drawTextAligned(comboText, boxCenterX, boxY + 6, kTextAlignment.center)
    gfx.drawTextAligned(calculationText, boxCenterX, boxY + 6 + lineHeight,
        kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function OverlayRenderer:drawCoreRushComplete()
    local state = self.state
    if (state.mode ~= Config.GAME_MODE.CORE_RUSH
        and state.mode ~= Config.GAME_MODE.TIME_ATTACK
        and state.mode ~= Config.GAME_MODE.TIME_ATTACK_256
        and state.mode ~= Config.GAME_MODE.TIME_ATTACK_2048)
        or state.coreRushCompleteUntil == 0
        or pd.getCurrentTimeMilliseconds() >= state.coreRushCompleteUntil then
        return
    end

    local text = "COMPLETE"
    local textWidth, textHeight = gfx.getTextSize(text)
    local boxWidth = textWidth + 32
    local boxHeight = textHeight + 16
    local boxX = math.floor(Config.CORE_RUSH_COMPLETE_CENTER_X - boxWidth * 0.5)
    local boxY = math.floor(Config.CORE_RUSH_COMPLETE_CENTER_Y - boxHeight * 0.5)
    gfx.fillRoundRect(boxX, boxY, boxWidth, boxHeight, 6)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    gfx.drawTextAligned(text, Config.CORE_RUSH_COMPLETE_CENTER_X,
        boxY + (boxHeight - textHeight) * 0.5, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function OverlayRenderer:drawPracticeComplete()
    local state = self.state
    if state.mode ~= Config.GAME_MODE.PRACTICE
        or state.practiceCompleteUntil == 0
        or pd.getCurrentTimeMilliseconds() >= state.practiceCompleteUntil then
        return
    end

    local text = "COMPLETE"
    local textWidth, textHeight = gfx.getTextSize(text)
    local boxWidth = textWidth + 32
    local boxHeight = textHeight + 16
    local boxX = math.floor(Config.CORE_RUSH_COMPLETE_CENTER_X - boxWidth * 0.5)
    local boxY = math.floor(Config.CORE_RUSH_COMPLETE_CENTER_Y - boxHeight * 0.5)
    gfx.fillRoundRect(boxX, boxY, boxWidth, boxHeight, 6)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    gfx.drawTextAligned(text, Config.CORE_RUSH_COMPLETE_CENTER_X,
        boxY + (boxHeight - textHeight) * 0.5, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- 中心座標を基準に、選択可能なメニューを描画する。
---@param centerX integer メニューの中心座標X.
---@param centerY integer メニューの中心座標Y.
---@param items string[] メニュー項目文字列の配列.
---@param selectedIndex integer 選択中の項目のインデックス.
---@param backgroundColor integer? メニューの背景色 (playdate.graphics.kColor). nilの場合は黒.
---@param maxVisibleItems integer? 最大表示項目数. nilの場合は全て表示.
---@param itemOptions table[]? メニュー項目ごとの描画オプション.
function OverlayRenderer:drawMenu(centerX, centerY, items, selectedIndex, backgroundColor, maxVisibleItems, itemOptions)
    if items == nil or #items == 0 then return end
    backgroundColor = backgroundColor or gfx.kColorBlack

	-- 最大の幅と高さの合計を計算する.
    local maxTextWidth = 0
    local textHeight = 0
    local maxIconHeight = 0
    local iconGap = 4
    for index, item in ipairs(items) do
        local textWidth, height = gfx.getTextSize(item)
        textHeight = math.max(textHeight, height)
        local icon = itemOptions ~= nil
            and itemOptions[index] ~= nil
            and itemOptions[index].icon or nil
        local iconWidth = 0
        if icon ~= nil then
            local width, height = icon:getSize()
            iconWidth = width + iconGap
            maxIconHeight = math.max(maxIconHeight, height)
        end
        maxTextWidth = math.max(maxTextWidth, textWidth + iconWidth)
    end

	local mergin = 32 -- 左右の余白を32pxに設定.
    local horizontalPadding = 16
    local verticalPadding = 8
    local rowHeight = math.max(textHeight, maxIconHeight)
    local itemHeight = rowHeight + 8
    local menuWidth = maxTextWidth + horizontalPadding * 2
    local contentHeight = #items * itemHeight
    local scrollable = maxVisibleItems ~= nil and #items > maxVisibleItems
    local scrollIndicatorHeight = scrollable and textHeight or 0
    local visibleItemCount = scrollable and maxVisibleItems or #items
    local visibleContentHeight = visibleItemCount * itemHeight
    local menuHeight = visibleContentHeight + verticalPadding * 2
        + scrollIndicatorHeight * 2
	menuWidth += mergin * 2 -- 左右に余白を追加.

    local menuX = math.floor(centerX - menuWidth * 0.5)
    local menuY = math.floor(centerY - menuHeight * 0.5)
    local contentTop = menuY + verticalPadding + scrollIndicatorHeight
    local contentBottom = contentTop + visibleContentHeight
    local scrollOffset = 0
    if scrollable and selectedIndex ~= nil then
        local clampedIndex = math.max(1, math.min(#items, selectedIndex))
        local firstVisibleIndex = clampedIndex - math.floor(maxVisibleItems * 0.5)
        local maxFirstVisibleIndex = #items - maxVisibleItems + 1
        firstVisibleIndex = math.max(1, math.min(maxFirstVisibleIndex,
            firstVisibleIndex))
        scrollOffset = (firstVisibleIndex - 1) * itemHeight
    end
    if scrollable then
        if self.menuScrollLastOffset ~= nil then
			-- スクロール方向の変化を検出して、スクロールカーソルのアニメーションを開始する.
            if scrollOffset < self.menuScrollLastOffset then
                self.menuScrollUpAnimationOffset = -8
            elseif scrollOffset > self.menuScrollLastOffset then
                self.menuScrollDownAnimationOffset = 8
            end
        end
        self.menuScrollLastOffset = scrollOffset
    else
        self.menuScrollLastOffset = nil
        self.menuScrollUpAnimationOffset = 0
        self.menuScrollDownAnimationOffset = 0
    end

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
        local itemY = contentTop + (index - 1) * itemHeight - scrollOffset
        if itemY >= contentTop and itemY + rowHeight <= contentBottom then
            local icon = itemOptions ~= nil
                and itemOptions[index] ~= nil
                and itemOptions[index].icon or nil
            local textWidth = gfx.getTextSize(item)
            local contentWidth = textWidth
            local iconWidth = 0
            local iconHeight = 0
            if icon ~= nil then
                iconWidth, iconHeight = icon:getSize()
                contentWidth += iconWidth + iconGap
            end

            local contentX = math.floor(centerX - contentWidth * 0.5)
            if icon ~= nil then
                icon:draw(contentX, math.floor(itemY + (rowHeight - iconHeight) * 0.5))
                contentX += iconWidth + iconGap
            end
            gfx.drawTextAligned(item, contentX + textWidth * 0.5,
                itemY + math.floor((rowHeight - textHeight) * 0.5),
                kTextAlignment.center)
        end
    end
    if scrollable then
        local hasHiddenAbove = scrollOffset > 0
        local hasHiddenBelow = scrollOffset + (contentBottom - contentTop) < contentHeight
		-- スクロールカーソルのサイズ.
        local indicatorHalfWidth = 10 -- 幅.
		local indicatorHeight = 12 -- 高さ.
        local indicatorOffsetY = -8 -- 上下Y座標調整用.
        if hasHiddenAbove then
			-- 上方向のスクロールカーソル描画.
            local topY = menuY - indicatorOffsetY
                + self.menuScrollUpAnimationOffset
            gfx.fillPolygon(centerX, topY,
                centerX - indicatorHalfWidth, topY + indicatorHeight,
                centerX + indicatorHalfWidth, topY + indicatorHeight)
        end
        if hasHiddenBelow then
			-- 下方向のスクロールカーソル描画.
            local bottomY = menuY + menuHeight + indicatorOffsetY - 8
                + self.menuScrollDownAnimationOffset
            gfx.fillPolygon(centerX, bottomY,
                centerX - indicatorHalfWidth, bottomY - indicatorHeight,
                centerX + indicatorHalfWidth, bottomY - indicatorHeight)
        end
        if self.menuScrollUpAnimationOffset < 0 then
            self.menuScrollUpAnimationOffset += 1
        end
        if self.menuScrollDownAnimationOffset > 0 then
            self.menuScrollDownAnimationOffset -= 1
        end
    end
    gfx.setImageDrawMode(previousDrawMode)

    if selectedIndex == nil then
        gfx.setColor(previousColor)
        return
    end
    selectedIndex = math.max(1, math.min(#items, selectedIndex))
    local selectedY = contentTop + (selectedIndex - 1) * itemHeight - scrollOffset

	-- カーソルを XORで描画.
	gfx.setColor(gfx.kColorXOR)
	if backgroundColor == gfx.kColorBlack then
		gfx.drawRoundRect(menuX + 4, selectedY - 4, menuWidth - 8, rowHeight + 6, 4)
	else
	    gfx.fillRoundRect(menuX + 4, selectedY - 4, menuWidth - 8, rowHeight + 6, 4)
	end
	gfx.setColor(gfx.kColorBlack)
    gfx.setColor(previousColor)
end

-- ゲームオーバーメニューの描画.
function OverlayRenderer:drawGameOver(selectedIndex)
    selectedIndex = selectedIndex or 1
    local resultTitle = "GAME OVER"
    if self.state.result == Config.GAME_RESULT.TIME_UP then
        resultTitle = "TIME UP"
    elseif self.state.result == Config.GAME_RESULT.VICTORY then
        resultTitle = (self.state.mode == Config.GAME_MODE.TIME_ATTACK
            or self.state.mode == Config.GAME_MODE.TIME_ATTACK_256
            or self.state.mode == Config.GAME_MODE.TIME_ATTACK_2048
            or self.state.mode == Config.GAME_MODE.PRACTICE)
            and "COMPLETE" or "VICTORY"
    end
    local resultDetail = "SCORE " .. tostring(self.state.score)
    if self.state.mode == Config.GAME_MODE.NORMAL then
        resultDetail = resultDetail .. "  LEVEL " .. tostring(self.state.level)
    end
    if self.state.result == Config.GAME_RESULT.VICTORY then
        if self.state.mode == Config.GAME_MODE.PRACTICE then
            resultDetail = "CLEAR " .. (self.state.practiceObjectiveText or "PRACTICE")
        else
			-- TIME ATTACKモードでは、経過時間を表示する。
            local centiseconds = math.floor(self.state.elapsedTimeMs / 10)
			local minutes = math.floor(centiseconds / 6000)
			local seconds = math.floor(centiseconds / 100) % 60	
            resultDetail = string.format("TIME %02d:%02d.%02d", minutes, seconds, centiseconds % 100)
        end
    end
    local returnLabel = "TITLE"
    if self.state.mode == Config.GAME_MODE.PRACTICE then
        returnLabel = "STAGE SELECT"
    elseif self.state.mode == Config.GAME_MODE.TIME_ATTACK
        or self.state.mode == Config.GAME_MODE.TIME_ATTACK_256
        or self.state.mode == Config.GAME_MODE.TIME_ATTACK_2048
        or self.state.mode == Config.GAME_MODE.CORE_RUSH then
        returnLabel = "MODE SELECT"
    end
    local items = { resultTitle, resultDetail }
    local selectionOffset = 2
    if self.state.mode == Config.GAME_MODE.NORMAL and self.state.levelNewBest then
        table.insert(items, "NEW BEST LEVEL " .. tostring(self.state.normalBestLevel))
        selectionOffset += 1
    end
    table.insert(items, "RETRY")
    table.insert(items, returnLabel)
    self:drawMenu(200, 130, items, selectedIndex + selectionOffset)
end

_G.OverlayRenderer = OverlayRenderer
return OverlayRenderer
