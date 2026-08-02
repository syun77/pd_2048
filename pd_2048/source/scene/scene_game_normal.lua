local NormalGameScene = {}
NormalGameScene.__index = NormalGameScene

function NormalGameScene.new(context)
    return setmetatable({ context = context, manager = nil }, NormalGameScene)
end

function NormalGameScene:enter()
    self.context.sound:playGameBgm()
end

function NormalGameScene:update()
    local result = self.context.game:update()
    if result ~= nil and result.scene ~= nil then
        self.manager:change(result.scene)
    end
end

function NormalGameScene:draw()
    self.context.renderer:drawNormalFrame()
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
