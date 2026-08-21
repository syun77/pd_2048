import "game_config"
---@class SceneManager シーン管理.
---@field context SceneContext シーン間で共有する依存関係をまとめるコンテキスト。
---@field scenes table<SCENE, any> 登録済みシーンのテーブル.
---@field current any 現在のシーン.
---@field currentName string 現在のシーン名.
local SceneManager = {}
SceneManager.__index = SceneManager

function SceneManager.new(context, scenes)
    local self = setmetatable({ context = context, scenes = scenes or {}, current = nil, currentName = nil }, SceneManager)
    return self
end

-- シーンの登録
---@param name SCENE 登録するシーン名.
---@param scene any 登録するシーン.
function SceneManager:register(name, scene)
    self.scenes[name] = scene
    scene.manager = self
end

-- シーンの切り替え
---@param name SCENE 切り替えるシーン名.
---@param params any|nil シーン切り替え時に渡すパラメータ.
function SceneManager:change(name, params)
    if self.current ~= nil and self.current.exit ~= nil then self.current:exit() end
    local nextScene = self.scenes[name]
    assert(nextScene ~= nil, "Unknown scene: " .. tostring(name))
    self.currentName = name
    self.current = nextScene
    if nextScene.enter ~= nil then nextScene:enter(params) end
    self:refreshSystemMenu()
end

function SceneManager:refreshSystemMenu()
    local menuItems = nil
    local nextScene = self.current
    if nextScene.getSystemMenuItems ~= nil then
        menuItems = nextScene:getSystemMenuItems()
    end
    local isBackgroundScene = self.currentName == GameConfig.SCENE.TITLE
        or self.currentName == GameConfig.SCENE.PLAYBOOK
        or self.currentName == GameConfig.SCENE.ACHIEVEMENTS
        or self.currentName == GameConfig.SCENE.STATISTICS
        or self.currentName == GameConfig.SCENE.SOUND_TEST
    if isBackgroundScene
        and GameConfig.SHOW_MENU_BACKGROUND_MENU_ITEM
        and self.context.menuBackground ~= nil then
        menuItems = menuItems or {}
        table.insert(menuItems, {
            title = "BG: " .. self.context.menuBackground:getLoad(),
            callback = function()
                self.context.menuBackground:cycleLoad()
                self:refreshSystemMenu()
            end,
        })
    end
    self.context.systemMenu:setItems(menuItems)
end

function SceneManager:update()
    if self.current ~= nil and self.current.update ~= nil then self.current:update() end
end

function SceneManager:draw()
    if self.current ~= nil and self.current.draw ~= nil then self.current:draw() end
end

_G.SceneManager = SceneManager
return SceneManager
