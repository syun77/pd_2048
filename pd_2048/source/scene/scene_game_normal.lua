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
    local phase = self.context.getPhase()
    if phase == self.context.phases.INPUT then
        self.context.updatePlayingInput()
    elseif phase == self.context.phases.PAUSED then
        self.context.updatePausedInput()
    end
    if self.context.isAnimating(self.context.getPhase()) then
        self.context.advanceAnimation()
    end
    if self.context.getResult() ~= nil then
        self.manager:change("GAME_OVER")
    end
end

function NormalGameScene:draw()
    self.context.drawNormalFrame()
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
