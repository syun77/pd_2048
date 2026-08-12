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
        practiceClearedImage = gfx.image.new("assets/images/check"),
    }, TitleRenderer)
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

_G.TitleRenderer = TitleRenderer
return TitleRenderer
