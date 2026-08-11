import "game_config"

local NormalGameScene = {}
NormalGameScene.__index = NormalGameScene

local function getModeSelectItem(scene)
    local game = scene.context.game
    local state = game:getState()
    if state.mode == GameConfig.GAME_MODE.PRACTICE then
        return "Stage Select", { page = "PRACTICE" }
    elseif game:isTimeAttack() or game:isCoreRush() then
        return "Mode Select", { page = "TIME_ATTACK" }
    end

    return "Back to Title", nil
end

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

function NormalGameScene:getSystemMenuItems()
    local returnTitle, returnParams = getModeSelectItem(self)
    return {
        {
            type = "checkmark",
            title = "Auto Play",
            value = self.context.game:isAutoPlayEnabled(),
            callback = function(value)
                self.context.game:setAutoPlayEnabled(value)
            end,
        },
        {
            title = returnTitle,
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE, returnParams)
            end,
        },
        {
            title = "Retry",
            callback = function()
                local state = self.context.game:getState()
                self.context.game:start(state.mode)
                self.manager:change(GameConfig.SCENE.GAME)
            end,
        },
    }
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
