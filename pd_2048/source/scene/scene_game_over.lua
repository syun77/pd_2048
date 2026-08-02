local GameOverScene = {}
GameOverScene.__index = GameOverScene

function GameOverScene.new(context)
    return setmetatable({ context = context, manager = nil }, GameOverScene)
end

function GameOverScene:update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        self.context.sound:play_se("decide")
        self.context.startGame()
        self.manager:change("GAME_NORMAL")
    end
end

function GameOverScene:draw()
    self.context.drawGameOverFrame()
end

_G.GameOverScene = GameOverScene
return GameOverScene
