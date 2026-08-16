--[[===========================================
統計画面.
===============================================]]
import "game_config"
import "practice_stage_loader"

local StatisticsScene = {}
StatisticsScene.__index = StatisticsScene

function StatisticsScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        page = 1,
        practiceTotal = 0,
        practiceCleared = 0,
    }, StatisticsScene)
end

function StatisticsScene:enter()
    self.context.sound:playMenuBgm()
    self.page = 1
    self.context.titleRenderer:resetStatisticsPageCursor()
    self.practiceTotal = 0
    self.practiceCleared = 0
    for _, stage in ipairs(PracticeStageLoader.loadAll()) do
        self.practiceTotal += 1
        if self.context.game:isPracticeStageCleared(stage) then
            self.practiceCleared += 1
        end
    end
end

function StatisticsScene:update()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        self.context.sound:play_se("cancel")
        self.manager:change(GameConfig.SCENE.TITLE)
    elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
        self.page = self.page == 1 and 3 or self.page - 1
        self.context.sound:play_se("pi")
    elseif playdate.buttonJustPressed(playdate.kButtonRight) then
        self.page = self.page == 3 and 1 or self.page + 1
        self.context.sound:play_se("pi")
    end
end

function StatisticsScene:draw()
    self.context.titleRenderer:drawStatistics(
        self.page, self.practiceCleared, self.practiceTotal)
end

function StatisticsScene:getSystemMenuItems()
    return {
        {
            title = "Back to Title",
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE)
            end,
        },
    }
end

_G.StatisticsScene = StatisticsScene
return StatisticsScene
