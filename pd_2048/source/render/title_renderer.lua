import "CoreLibs/graphics"

local gfx <const> = playdate.graphics

local TitleRenderer = {}
TitleRenderer.__index = TitleRenderer

function TitleRenderer.new(dependencies)
    return setmetatable({ state = dependencies.state }, TitleRenderer)
end

function TitleRenderer:drawCenteredText(text, y)
    gfx.drawTextAligned(text, 200, y, kTextAlignment.center)
end

function TitleRenderer:drawTitle(selectedIndex, menuItems)
    self:drawCenteredText("ROTATE 2048", 62)
    self:drawCenteredText("5 x 5 MERGE PUZZLE", 88)
    for index, item in ipairs(menuItems) do
        local y = 118 + (index - 1) * 22
        local label = (index == selectedIndex and "> " or "  ") .. item.label
        self:drawCenteredText(label, y)
    end
    self:drawCenteredText("UP / DOWN: SELECT    A: ENTER", 198)
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
