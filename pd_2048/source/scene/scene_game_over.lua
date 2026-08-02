import "game_config"

local GameOverScene = {}
GameOverScene.__index = GameOverScene

function GameOverScene.new(context)
    return setmetatable({ context = context, manager = nil, selectedIndex = 1 }, GameOverScene)
end

function GameOverScene:enter()
    self.selectedIndex = 1
end

function GameOverScene:update()
    local previousIndex = self.selectedIndex
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self.selectedIndex -= 1
        if self.selectedIndex < 1 then self.selectedIndex = 2 end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self.selectedIndex += 1
        if self.selectedIndex > 2 then self.selectedIndex = 1 end
    end

    if self.selectedIndex ~= previousIndex then
        self.context.sound:play_se("pi")
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        self.context.sound:play_se("decide")
        if self.selectedIndex == 1 then
            self.context.game:start()
            self.manager:change(GameConfig.SCENE.GAME)
        else
            self.manager:change(GameConfig.SCENE.TITLE)
        end
    end
end

function GameOverScene:draw()
    self.context.renderer:drawGameOverFrame(self.selectedIndex)
end

_G.GameOverScene = GameOverScene
return GameOverScene
