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
    return setmetatable({
        context = context,
        manager = nil,
        restoreMenuPending = false,
    }, NormalGameScene)
end

function NormalGameScene:enter()
    self.restoreMenuPending = self.context.game:isSuspendRestoring()
    if not self.restoreMenuPending then
        self.context.sound:playGameBgm()
    end
end

function NormalGameScene:exit()
    self.context.game:flushStatistics()
end

function NormalGameScene:update()
    local result = self.context.game:update()
    if self.restoreMenuPending
        and not self.context.game:isSuspendRestoring() then
        self.restoreMenuPending = false
        self.manager:refreshSystemMenu()
    end
    if result ~= nil and result.scene ~= nil then
        self.manager:change(result.scene)
    end
end

function NormalGameScene:draw()
    self.context.renderer:drawNormalFrame()
end

function NormalGameScene:getSystemMenuItems()
    if self.context.game:isSuspendRestoring() then return {} end
    local returnTitle, returnParams = getModeSelectItem(self)
    local items = {}

    if GameConfig.SHOW_AUTO_PLAY_MENU_ITEM then
        items[#items + 1] = {
            type = "checkmark",
            title = "Auto Play",
            value = self.context.game:isAutoPlayEnabled(),
            callback = function(value)
                self.context.game:setAutoPlayEnabled(value)
            end,
        }
    end

    local state = self.context.game:getState()
    if state.mode == GameConfig.GAME_MODE.NORMAL
        and not self.context.game:isReplayMode()
        and not self.context.game:isSuspendRestoring() then
        items[#items + 1] = {
            title = "Suspend",
            callback = function()
                if self.context.game:suspendNormalGame() then
                    self.manager:change(GameConfig.SCENE.TITLE)
                else
                    self.context.game:setMessage("SUSPEND FAILED", 1800)
                end
            end,
        }
    else
        items[#items + 1] = {
            title = returnTitle,
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE, returnParams)
            end,
        }
    end
    items[#items + 1] = {
        title = "Retry",
        callback = function()
            if self.context.game:isReplayMode() then
                self.context.game:restartReplay()
            else
                local state = self.context.game:getState()
                self.context.game:start(state.mode)
            end
            self.manager:change(GameConfig.SCENE.GAME)
        end,
    }

    return items
end

_G.NormalGameScene = NormalGameScene
return NormalGameScene
