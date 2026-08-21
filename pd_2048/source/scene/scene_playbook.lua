--[[===========================================
PLAYBOOK画面.
===============================================]]
import "game_config"

local PlaybookScene = {}
PlaybookScene.__index = PlaybookScene

function PlaybookScene.new(context)
    return setmetatable({ context = context, manager = nil }, PlaybookScene)
end

function PlaybookScene:enter()
    self.context.sound:playMenuBgm()
end

function PlaybookScene:update()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        self.context.sound:play_se("cancel")
        self.manager:change(GameConfig.SCENE.TITLE)
    end
end

function PlaybookScene:draw()
    self.context.titleRenderer:drawPlaybook()
end

function PlaybookScene:getSystemMenuItems()
    return {
        {
            title = "Back to Title",
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE)
            end,
        },
    }
end

_G.PlaybookScene = PlaybookScene
return PlaybookScene
