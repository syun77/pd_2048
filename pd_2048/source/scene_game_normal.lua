local NormalGameScene = {}
NormalGameScene.__index = NormalGameScene

function NormalGameScene.new(context)
    return setmetatable({ context = context, manager = nil }, NormalGameScene)
end

function NormalGameScene:enter()
    self.context.playGameBgm()
end

function NormalGameScene:update()
    self.context.resetCursorIfNeeded()
    if self.context.getGameState() == self.context.states.PLAYING then
        self.context.updatePlayingInput()
    elseif self.context.getGameState() == self.context.states.PAUSED then
        self.context.updatePausedInput()
    end

    if self.context.isAnimating(self.context.getGameState()) then
        self.context.advanceAnimation()
    end

    if self.context.getGameState() == self.context.states.GAME_OVER then
        self.manager:change("GAME_OVER")
    end
end

function NormalGameScene:draw()
    self.context.drawNormalFrame()
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
