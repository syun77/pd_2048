import "CoreLibs/graphics"
import "game_config"
import "game/statistics_store"

local gfx <const> = playdate.graphics
local Config <const> = GameConfig

---@class TitleRendererDependencies タイトル描画クラスの依存関係.
---@field state GameState ゲーム状態.
---@field menuRenderer OverlayRenderer メニュー描画クラス.
---@field background MenuBackgroundRenderer メニューバックグラウンド描画クラス.

---@class TitleRenderer タイトル描画クラス.
---@field state GameState ゲーム状態.
---@field menuRenderer OverlayRenderer メニュー描画クラス.
---@field background MenuBackgroundRenderer メニューバックグラウンド描画クラス.
---@field titleImage playdate.graphics.image|nil タイトル背景画像.
---@field practiceClearedImage playdate.graphics.image|nil PRACTICEモードのクリア済みアイコン.
---@field favoriteImage playdate.graphics.image|nil リプレイのお気に入りアイコン.
local TitleRenderer = {}
TitleRenderer.__index = TitleRenderer

-- 生成.
---@param dependencies TitleRendererDependencies 依存関係.
---@return TitleRenderer
function TitleRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        menuRenderer = dependencies.menuRenderer,
        background = dependencies.background,
        titleImage = gfx.image.new("assets/images/title2"),
        practiceClearedImage = gfx.image.new("assets/images/check"),
        favoriteImage = gfx.image.new("assets/images/fav"),
        statisticsLastPage = nil,
        statisticsLeftAnimationOffset = 0,
        statisticsRightAnimationOffset = 0,
    }, TitleRenderer)
end

function TitleRenderer:drawBackground()
	local isClear = true
    if self.titleImage ~= nil then
		-- 背景画像があればそれで描画.
        self.titleImage:draw(0, 0)
		isClear = false -- 背景画像があるので消去は不要.
	else
		-- 存在しない場合は gfx.clear() で画面をクリアする.
		gfx.clear()
	end

    if self.background ~= nil then
		-- 幾何学模様で描画.
		self.background:draw(isClear)
	end
end

function TitleRenderer:drawCenteredText(text, y)
    gfx.drawTextAligned(text, Config.SCREEN_CENTER_X, y, kTextAlignment.center)
end

-- PRACTICEモードの説明文を描画.
---@param menuItems any[] 項目リスト.
---@param selectedIndex integer 選択番号.
function TitleRenderer:drawPracticeDescription(menuItems, selectedIndex)
    if menuItems == nil or selectedIndex == nil then return end
    local item = menuItems[selectedIndex]
    local description = item ~= nil and item.description or nil
    if description == nil or description == "" then return end

	local centerX = Config.TITLE_PRACTICE_DESCRIPTION_X + Config.TITLE_PRACTICE_DESCRIPTION_WIDTH * 0.5
	local centerY = Config.TITLE_PRACTICE_DESCRIPTION_Y + Config.TITLE_PRACTICE_DESCRIPTION_HEIGHT * 0.5
	gfx.drawTextAligned(description, centerX, centerY, kTextAlignment.center)
end

-- タイトルを描画.
---@param selectedIndex integer 選択している項目番号
---@param menuItems any[] 項目リスト
---@param title string|nil
---@param notice string|nil
function TitleRenderer:drawTitle(selectedIndex, menuItems, title, notice)
    self:drawBackground()
    local labels = {}
    local itemOptions = {}
    for _, item in ipairs(menuItems) do
        table.insert(labels, item.label)
        table.insert(itemOptions, {
            icon = item.cleared and self.practiceClearedImage
                or item.favorite and self.favoriteImage
                or nil,
        })
    end
    if title ~= nil then self:drawCenteredText(title, 42) end
    local menuCenterY = Config.TITLE_MENU_CENTER_Y
    if title == "PRACTICE" then
        menuCenterY = Config.TITLE_PRACTICE_MENU_CENTER_Y
    elseif title == "REPLAYS" then
        menuCenterY = Config.TITLE_REPLAY_MENU_CENTER_Y
    elseif title ~= nil then
        menuCenterY = Config.TITLE_SUBMENU_CENTER_Y
    end
    self.menuRenderer:drawMenu(Config.SCREEN_CENTER_X, menuCenterY,
        labels, selectedIndex, gfx.kColorWhite, title == nil and nil or 5,
        itemOptions)
    if title == "PRACTICE" then
		-- PRACTICEモードの説明文の描画.
		-- 背景枠の描画.
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(0, 210, 400, 30)
		-- 文字の描画.
		gfx.setColor(gfx.kColorBlack)
        self:drawPracticeDescription(menuItems, selectedIndex)
    elseif title == "REPLAYS" then
        local item = menuItems[selectedIndex]
        if item ~= nil and item.footer ~= nil then
			-- リプレイ説明文の描画.
			-- 背景枠の描画.
			gfx.setColor(gfx.kColorWhite)
			gfx.fillRect(0, 216, 400, 24)
			-- 文字の描画.
			gfx.setColor(gfx.kColorBlack)
            self:drawCenteredText(item.footer, 220)
        end
    elseif notice ~= nil then
        self:drawCenteredText(notice, 220)
    end
end

function TitleRenderer:drawMenuPage(title)
    self:drawBackground()
    self:drawCenteredText(title, 78)
    gfx.drawLine(100, 94, 300, 94)
end

function TitleRenderer:drawAchievements()
    self:drawMenuPage("ACHIEVEMENTS")
    self:drawCenteredText("NO ACHIEVEMENTS YET", 124)
end

local function statisticsTimeText(timeMs)
    if timeMs == nil then return "--:--.--" end
    local centiseconds = math.floor(timeMs / 10)
    local minutes = math.floor(centiseconds / 6000)
    local seconds = math.floor(centiseconds / 100) % 60
    return string.format("%02d:%02d.%02d", minutes, seconds, centiseconds % 100)
end

local function playTimeText(timeMs)
    local totalMinutes = math.floor(timeMs / 60000)
    local hours = math.floor(totalMinutes / 60)
    return string.format("%d:%02d", hours, totalMinutes % 60)
end

local STATISTICS_PANEL_WIDTH <const> = 320
local STATISTICS_PANEL_X <const> =
    (Config.SCREEN_WIDTH - STATISTICS_PANEL_WIDTH) / 2

local function drawStatisticsPanel(y, height)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(STATISTICS_PANEL_X, y, STATISTICS_PANEL_WIDTH, height)
    gfx.setColor(gfx.kColorBlack)
end

function TitleRenderer:resetStatisticsPageCursor()
    self.statisticsLastPage = nil
    self.statisticsLeftAnimationOffset = 0
    self.statisticsRightAnimationOffset = 0
end

function TitleRenderer:drawStatisticsPageCursor(page)
    if self.statisticsLastPage ~= nil and page ~= self.statisticsLastPage then
        local movedLeft = page == self.statisticsLastPage - 1
            or self.statisticsLastPage == 1 and page == 3
        if movedLeft then
            self.statisticsLeftAnimationOffset = -8
        else
            self.statisticsRightAnimationOffset = 8
        end
    end
    self.statisticsLastPage = page

    local centerY <const> = 124
    local indicatorHalfHeight <const> = 10
    local indicatorWidth <const> = 12
    local leftX = STATISTICS_PANEL_X + 8
        + self.statisticsLeftAnimationOffset
    local rightX = STATISTICS_PANEL_X + STATISTICS_PANEL_WIDTH - 8
        + self.statisticsRightAnimationOffset
    gfx.setColor(gfx.kColorWhite)
    gfx.fillPolygon(leftX, centerY,
        leftX + indicatorWidth, centerY - indicatorHalfHeight,
        leftX + indicatorWidth, centerY + indicatorHalfHeight)
    gfx.fillPolygon(rightX, centerY,
        rightX - indicatorWidth, centerY - indicatorHalfHeight,
        rightX - indicatorWidth, centerY + indicatorHalfHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillPolygon(leftX + 3, centerY,
        leftX + indicatorWidth - 2, centerY - indicatorHalfHeight + 3,
        leftX + indicatorWidth - 2, centerY + indicatorHalfHeight - 3)
    gfx.fillPolygon(rightX - 3, centerY,
        rightX - indicatorWidth + 2, centerY - indicatorHalfHeight + 3,
        rightX - indicatorWidth + 2, centerY + indicatorHalfHeight - 3)

    if self.statisticsLeftAnimationOffset < 0 then
        self.statisticsLeftAnimationOffset += 2
    end
    if self.statisticsRightAnimationOffset > 0 then
        self.statisticsRightAnimationOffset -= 2
    end
end

local function drawDottedHorizontalLine(x1, x2, y)
    for x = x1, x2, 4 do
        gfx.drawLine(x, y, math.min(x + 1, x2), y)
    end
end

local function drawNormalHistory(renderer, statistics)
    local normal = statistics.normal
    local runs = normal.history.runs
    local plotLeft <const> = 88
    local plotRight <const> = 328
    local plotTop <const> = 60
    local plotBottom <const> = 132
    local plotWidth <const> = plotRight - plotLeft
    local plotHeight <const> = plotBottom - plotTop
    local labelX <const> = 72
    local valueX <const> = 328

    drawStatisticsPanel(52, 160)
	gfx.setLineWidth(1)
    if #runs == 0 then
        renderer:drawCenteredText("NO PLAY HISTORY", 100)
    else
        local maxLevel = 1
        for _, run in ipairs(runs) do
            maxLevel = math.max(maxLevel, run.level)
        end
        local axisMax = math.max(5, math.ceil(maxLevel / 5) * 5)
        local middleY = math.floor((plotTop + plotBottom) / 2)
        drawDottedHorizontalLine(plotLeft, plotRight, plotTop)
        drawDottedHorizontalLine(plotLeft, plotRight, middleY)
        gfx.drawLine(plotLeft, plotBottom, plotRight, plotBottom)
        gfx.drawLine(plotLeft, plotTop, plotLeft, plotBottom)
        gfx.drawTextAligned(tostring(axisMax), plotLeft - 6,
            plotTop - 6, kTextAlignment.right)
        gfx.drawTextAligned("0", plotLeft - 6,
            plotBottom - 6, kTextAlignment.right)

        local previousX = nil
        local previousY = nil
        for index, run in ipairs(runs) do
            local x = #runs == 1 and math.floor((plotLeft + plotRight) / 2)
                or math.floor(plotLeft
                    + (index - 1) * plotWidth / (#runs - 1) + 0.5)
            local y = math.floor(plotBottom
                - math.min(axisMax, run.level) * plotHeight / axisMax + 0.5)
            if previousX ~= nil then gfx.drawLine(previousX, previousY, x, y) end
            gfx.fillRect(x - 1, y - 1, 3, 3)
            previousX, previousY = x, y
        end
        if #runs == 1 then
            gfx.drawTextAligned(tostring(runs[1].number),
                math.floor((plotLeft + plotRight) / 2), 136,
                kTextAlignment.center)
        else
            gfx.drawTextAligned(tostring(runs[1].number),
                plotLeft, 136, kTextAlignment.left)
            gfx.drawTextAligned(tostring(runs[#runs].number),
                plotRight, 136, kTextAlignment.right)
        end
    end

    local averageLevel, averageScore =
        StatisticsStore.normalHistoryAverages(statistics)
    gfx.drawTextAligned("AVG LEVEL", labelX, 164, kTextAlignment.left)
    gfx.drawTextAligned(averageLevel == nil and "--"
        or string.format("%.1f", averageLevel),
        valueX, 164, kTextAlignment.right)
    gfx.drawTextAligned("AVG SCORE", labelX, 188, kTextAlignment.left)
    gfx.drawTextAligned(averageScore == nil and "--"
        or tostring(math.floor(averageScore + 0.5)),
        valueX, 188, kTextAlignment.right)
end

-- 統計情報の描画.
---@param page integer ページ番号.
---@param practiceCleared integer PRACTICEモードのクリア済みステージ数.
---@param practiceTotal integer PRACTICEモードの総ステージ数.
---@param normalHistoryVisible boolean NORMAL履歴グラフを表示するか.
function TitleRenderer:drawStatistics(
    page, practiceCleared, practiceTotal, normalHistoryVisible)
    self:drawBackground()
	-- タイトルの背景枠を描画.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(64, 16, Config.SCREEN_WIDTH-128, 24, 4)
	-- タイトルの文字を描画.
    gfx.setColor(gfx.kColorBlack)
    local category = page == 1 and "OVERALL"
        or page == 2 and "NORMAL" or "TIME ATTACK"
    self:drawCenteredText("STATISTICS " .. tostring(page) .. "/3 [" .. category .. "]", 20)
    gfx.drawLine(100, 40, 300, 40)
    local statistics = self.state.statistics
    if page == 1 then
		-- OVERALL.
        local labelX <const> = 72
        local valueX <const> = 328
        drawStatisticsPanel(52, 118)
        local function drawOverall(label, value, y)
            gfx.drawTextAligned(label, labelX, y, kTextAlignment.left)
            gfx.drawTextAligned(value, valueX, y, kTextAlignment.right)
        end
        drawOverall("PLAY TIME", playTimeText(statistics.totalPlayTimeMs), 64)
        drawOverall("TOTAL PLAYS",
            tostring(StatisticsStore.totalPlays(statistics)), 104)
        drawOverall("PRACTICE CLEARED",
            string.format("%d/%d", practiceCleared, practiceTotal), 144)
    elseif page == 2 then
		-- NORMAL.
        local normal = statistics.normal
        if normalHistoryVisible then
            drawNormalHistory(self, statistics)
        else
            local labelX <const> = 72
            local valueX <const> = 328
            drawStatisticsPanel(52, 151)
            local function drawNormal(label, value, y)
                gfx.drawTextAligned(label, labelX, y, kTextAlignment.left)
                gfx.drawTextAligned(tostring(value), valueX, y, kTextAlignment.right)
            end
            drawNormal("PLAYS", normal.plays, 60)
            drawNormal("HIGH SCORE", normal.highScore, 88)
            drawNormal("BEST LEVEL", normal.bestLevel, 116)
            drawNormal("HIGHEST TILE", normal.highestTile, 144)
            drawNormal("MAX COMBO", normal.maxCombo, 172)
        end
    else
		-- TIME ATTACK.
        local timed = statistics.timeAttack
        local modeX <const> = 72
        local bestX <const> = 206
        local clearX <const> = 320
        drawStatisticsPanel(52, 143)
        gfx.drawTextAligned("MODE", modeX, 60, kTextAlignment.left)
        gfx.drawTextAligned("BEST", bestX, 60, kTextAlignment.center)
        gfx.drawTextAligned("CLEAR", clearX, 60, kTextAlignment.center)
        local function drawTimed(label, value, y)
            gfx.drawTextAligned(label, modeX, y, kTextAlignment.left)
            gfx.drawTextAligned(statisticsTimeText(value.bestTimeMs),
                bestX, y, kTextAlignment.center)
            gfx.drawTextAligned(string.format("%d/%d", value.clears, value.plays),
                clearX, y, kTextAlignment.center)
        end
        drawTimed("64", timed.sprint64, 88)
        drawTimed("256", timed.sprint256, 116)
        drawTimed("512", timed.sprint512, 144)
        drawTimed("CORE", timed.coreRush, 172)
    end
	-- 説明文の白い枠の描画.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(0, 216, Config.SCREEN_WIDTH, 24)
	-- 説明文の描画.
    self:drawStatisticsPageCursor(page)
    if page == 2 then
        self:drawCenteredText(normalHistoryVisible
            and "A: SUMMARY" or "A: GRAPH", 220)
    end
end

function TitleRenderer:drawSoundTest(selectedTab, selectedIndex, menuItems, bgmDbStatus)
    self:drawBackground()
    self:drawCenteredText("SOUND TEST", 34)
    self:drawCenteredText(selectedTab, 58)
    self.menuRenderer:drawMenu(Config.SCREEN_CENTER_X, 142,
        menuItems, selectedIndex, gfx.kColorWhite, 6)

    if bgmDbStatus == nil then return end

    local graphX = 320
    local graphY = 216
    local graphWidth = 60
    local graphHeight = 20
	-- 白で塗る.
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(graphX - 10, graphY - 24, graphWidth + 20, graphHeight + 34, 4)
	-- 時間の描画.
    local timeText = "--:--.-s"
    if bgmDbStatus.offset ~= nil then
		local minutes = math.floor(bgmDbStatus.offset / 60)
		local seconds = math.floor(bgmDbStatus.offset - minutes * 60)
		local milliseconds = math.floor((bgmDbStatus.offset - minutes * 60 - seconds) * 10)
		timeText = string.format("%02d:%02d.%01d", minutes, seconds, milliseconds)
    end

    local timeX = graphX + 8
    local timeY = graphY - 20
    gfx.drawText(timeText, timeX, timeY)
	-- 全体の時間の描画.
    local progressX = graphX - 8
    local progressY = graphY - 22
    local progressWidth = graphWidth + 16
    local timeHeight = 16
    local progressHeight = timeHeight + 4
    if bgmDbStatus.offset ~= nil
        and bgmDbStatus.duration ~= nil
        and bgmDbStatus.duration > 0 then
        local progress = math.max(0, math.min(1,
            bgmDbStatus.offset / bgmDbStatus.duration))
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(progressX, progressY,
            math.floor(progressWidth * progress), progressHeight)
        gfx.setColor(previousColor)
    end
	-- 擬似3バンドイコライザーの描画.
	-- イコライザーを描画.
    gfx.setColor(gfx.kColorBlack)
    local bandLabels = {
        { key = "low", label = "L" },
        { key = "mid", label = "M" },
        { key = "high", label = "H" },
    }
    local barWidth = 12
    local barGap = 6
    local firstBarX = graphX + 6
    local hasBands = bgmDbStatus.bands ~= nil
    for index, band in ipairs(bandLabels) do
        local barX = firstBarX + (index - 1) * (barWidth + barGap)
        local bandStatus = hasBands and bgmDbStatus.bands[band.key] or nil
        if bandStatus ~= nil and bandStatus.level ~= nil then
            local level = math.max(0, math.min(100, bandStatus.level))
            local barHeight = math.floor(graphHeight * level / 100)
            if barHeight > 0 then
                gfx.fillRect(barX, graphY + graphHeight - barHeight,
                    barWidth, barHeight)
            end
        end
    end
end

_G.TitleRenderer = TitleRenderer
return TitleRenderer
