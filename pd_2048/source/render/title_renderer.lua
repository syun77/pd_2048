import "CoreLibs/graphics"
import "game_config"

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
function TitleRenderer:drawTitle(selectedIndex, menuItems, title)
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
    elseif title ~= nil then
        menuCenterY = Config.TITLE_SUBMENU_CENTER_Y
    end
    self.menuRenderer:drawMenu(Config.SCREEN_CENTER_X, menuCenterY,
        labels, selectedIndex, gfx.kColorWhite, title == nil and nil or 5,
        itemOptions)
    if title == "PRACTICE" then
        self:drawPracticeDescription(menuItems, selectedIndex)
    elseif title == "REPLAYS" then
        local item = menuItems[selectedIndex]
        if item ~= nil and item.footer ~= nil then
            self:drawCenteredText(item.footer, 220)
        end
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

function TitleRenderer:drawStatistics()
    self:drawMenuPage("STATISTICS")
    self:drawCenteredText("NORMAL  " .. tostring(self.state.normalHighScore), 120)
    self:drawCenteredText("NORMAL LEVEL  " .. tostring(self.state.normalBestLevel), 144)
    local timeAttackBest = self.state.timeAttackBestTimeMs
    local timeAttackText = timeAttackBest == nil and "--" or string.format("%02d.%02d",
        math.floor(timeAttackBest / 1000), math.floor(timeAttackBest / 10) % 100)
    self:drawCenteredText("TIME ATTACK  " .. timeAttackText, 168)
    local best = self.state.coreRushBestTimeMs
    local bestText = best == nil and "--" or string.format("%02d.%02d",
        math.floor(best / 1000), math.floor(best / 10) % 100)
    self:drawCenteredText("CORE RUSH  " .. bestText, 192)
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
