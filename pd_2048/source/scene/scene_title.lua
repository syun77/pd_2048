import "game_config"

local TitleScene = {}
TitleScene.__index = TitleScene

function TitleScene.new(context)
    return setmetatable({ context = context, manager = nil }, TitleScene)
end

function TitleScene:enter()
    self.context.playMenuBgm()
end

function TitleScene:update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        self.context.playDecideSound()
        self.context.game:start()
        self.manager:change(GameConfig.SCENE.GAME)
    end
end

function TitleScene:draw()
    self.context.drawTitle()
end

_G.TitleScene = TitleScene
return TitleScene
