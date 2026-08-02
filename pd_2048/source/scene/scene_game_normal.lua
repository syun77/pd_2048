local NormalGameScene = {}
NormalGameScene.__index = NormalGameScene

function NormalGameScene.new(context)
    return setmetatable({ context = context, manager = nil }, NormalGameScene)
end

function NormalGameScene:enter()
    self.context.playGameBgm()
end

function NormalGameScene:update()
    local nextScene = self.context.updateGame()
    if nextScene ~= nil then
        self.manager:change(nextScene)
    end
end

function NormalGameScene:draw()
    self.context.drawNormalFrame()
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
