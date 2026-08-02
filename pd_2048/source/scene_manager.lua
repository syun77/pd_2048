local SceneManager = {}
SceneManager.__index = SceneManager

function SceneManager.new(context, scenes)
    local self = setmetatable({ context = context, scenes = scenes or {}, current = nil, currentName = nil }, SceneManager)
    return self
end

function SceneManager:register(name, scene)
    self.scenes[name] = scene
    scene.manager = self
end

function SceneManager:change(name, params)
    if self.current ~= nil and self.current.exit ~= nil then
        self.current:exit()
    end
    local nextScene = self.scenes[name]
    assert(nextScene ~= nil, "Unknown scene: " .. tostring(name))
    self.currentName = name
    self.current = nextScene
    if nextScene.enter ~= nil then nextScene:enter(params) end
end

function SceneManager:update()
    if self.current ~= nil and self.current.update ~= nil then
        self.current:update()
    end
end

function SceneManager:draw()
    if self.current ~= nil and self.current.draw ~= nil then
        self.current:draw()
    end
end

_G.SceneManager = SceneManager
return SceneManager
