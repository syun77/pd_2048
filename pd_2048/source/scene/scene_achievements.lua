--[[===========================================
実績画面.
===============================================]]
import "game_config"

local AchievementsScene = {}
AchievementsScene.__index = AchievementsScene

function AchievementsScene.new(context)
    return setmetatable({ context = context, manager = nil }, AchievementsScene)
end

function AchievementsScene:enter()
    self.context.sound:playMenuBgm()
end

function AchievementsScene:update()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        self.context.sound:play_se("cancel")
        self.manager:change(GameConfig.SCENE.TITLE)
    end
end

function AchievementsScene:draw()
    self.context.titleRenderer:drawAchievements()
end

function AchievementsScene:getSystemMenuItems()
    return {
        {
            title = "Back to Title",
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE)
            end,
        },
    }
end

_G.AchievementsScene = AchievementsScene
return AchievementsScene
