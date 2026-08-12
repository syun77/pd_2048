import "CoreLibs/graphics"
import "game_config"

local gfx <const> = playdate.graphics
local Config <const> = GameConfig

local TitleRenderer = {}
TitleRenderer.__index = TitleRenderer

function TitleRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        menuRenderer = dependencies.menuRenderer,
        background = dependencies.background,
        titleImage = gfx.image.new("assets/images/title2"),
        practiceClearedImage = gfx.image.new("assets/images/check"),
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
            icon = item.cleared and self.practiceClearedImage or nil,
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
    local timeAttackBest = self.state.timeAttackBestTimeMs
    local timeAttackText = timeAttackBest == nil and "--" or string.format("%02d.%02d",
        math.floor(timeAttackBest / 1000), math.floor(timeAttackBest / 10) % 100)
    self:drawCenteredText("TIME ATTACK  " .. timeAttackText, 144)
    local best = self.state.coreRushBestTimeMs
    local bestText = best == nil and "--" or string.format("%02d.%02d",
        math.floor(best / 1000), math.floor(best / 10) % 100)
    self:drawCenteredText("CORE RUSH  " .. bestText, 168)
end

function TitleRenderer:drawSoundTest(selectedTab, selectedIndex, menuItems, bgmDbStatus)
    self:drawBackground()
    self:drawCenteredText("SOUND TEST", 34)
    self:drawCenteredText(selectedTab, 58)
    self.menuRenderer:drawMenu(Config.SCREEN_CENTER_X, 142,
        menuItems, selectedIndex, gfx.kColorWhite, 6)

    if bgmDbStatus == nil then return end

	-- 再生時間の描画.
    local x = 310
    local y = 96
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(x - 4, y, 80, 40, 4)

    gfx.drawText("TIME", x, y)
    if bgmDbStatus.offset ~= nil then
		local minutes = math.floor(bgmDbStatus.offset / 60)
		local seconds = bgmDbStatus.offset - minutes * 60
		gfx.drawText(string.format("%02d:%02.1f", minutes, seconds), x, y + 18)
    else
        gfx.drawText("--.-s", x, y + 18)
    end

	-- dBの描画.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(x - 4, y + 60, 48, 20, 4)

	gfx.drawText("DB", x, y + 44)
    if bgmDbStatus.db ~= nil then
        gfx.drawText(string.format("%+04.0f", bgmDbStatus.db), x, y + 62)
        gfx.drawText(string.format("LV %03d", bgmDbStatus.level), x, y + 80)
    else
        gfx.drawText("--", x, y + 62)
    end
end

_G.TitleRenderer = TitleRenderer
return TitleRenderer
