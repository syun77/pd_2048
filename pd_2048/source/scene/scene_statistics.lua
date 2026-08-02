--[[===========================================
統計画面.
===============================================]]
import "game_config"

local StatisticsScene = {}
StatisticsScene.__index = StatisticsScene

function StatisticsScene.new(context)
    return setmetatable({ context = context, manager = nil }, StatisticsScene)
end

function StatisticsScene:enter()
    self.context.sound:playMenuBgm()
end

function StatisticsScene:update()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        self.context.sound:play_se("decide")
        self.manager:change(GameConfig.SCENE.TITLE)
    end
end

function StatisticsScene:draw()
    self.context.titleRenderer:drawStatistics()
end

_G.StatisticsScene = StatisticsScene
return StatisticsScene
