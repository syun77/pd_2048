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
        self.context.sound:play_se("decide")
        self.context.startGame()
        self.manager:change("GAME_NORMAL")
    end
end

function TitleScene:draw()
    self.context.drawTitle()
end

_G.TitleScene = TitleScene
return TitleScene
