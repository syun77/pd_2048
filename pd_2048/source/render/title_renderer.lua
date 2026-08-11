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

function TitleRenderer:drawTitle(selectedIndex, menuItems, title)
    local labels = {}
    for _, item in ipairs(menuItems) do
        table.insert(labels, item.label)
    end
    if title ~= nil then self:drawCenteredText(title, 42) end
    self.menuRenderer:drawMenu(200, title == nil and 132 or 132,
        labels, selectedIndex, gfx.kColorWhite, title == nil and nil or 5)
    if title ~= nil then self:drawCenteredText("B: BACK", 214) end
end

function TitleRenderer:drawMenuPage(title)
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
