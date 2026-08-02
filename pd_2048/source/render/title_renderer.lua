import "CoreLibs/graphics"

local gfx <const> = playdate.graphics

local TitleRenderer = {}
TitleRenderer.__index = TitleRenderer

function TitleRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        menuRenderer = dependencies.menuRenderer,
    }, TitleRenderer)
end

function TitleRenderer:drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

function TitleRenderer:drawTitle(selectedIndex, menuItems)
    self:drawCenteredText("ROTATE 2048", 32)
    self:drawCenteredText("5 x 5 MERGE PUZZLE", 56)
    local labels = {}
    for _, item in ipairs(menuItems) do
        table.insert(labels, item.label)
    end
    self.menuRenderer:drawMenu(200, 132, labels, selectedIndex, gfx.kColorWhite)
    self:drawCenteredText("UP / DOWN: SELECT    A: ENTER", 218)
end

function TitleRenderer:drawMenuPage(title)
    self:drawCenteredText("ROTATE 2048", 42)
    self:drawCenteredText(title, 78)
    gfx.drawLine(100, 94, 300, 94)
    self:drawCenteredText("B: BACK", 202)
end

function TitleRenderer:drawAchievements()
    self:drawMenuPage("ACHIEVEMENTS")
    self:drawCenteredText("NO ACHIEVEMENTS YET", 124)
end

function TitleRenderer:drawStatistics()
    self:drawMenuPage("STATISTICS")
    self:drawCenteredText("NORMAL  " .. tostring(self.state.normalHighScore), 120)
    self:drawCenteredText("TIME ATTACK  " .. tostring(self.state.timeAttackHighScore), 144)
end

_G.TitleRenderer = TitleRenderer
return TitleRenderer
