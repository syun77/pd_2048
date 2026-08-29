import "game_config"
import "menu_selection_controller"

local GameOverScene = {}
GameOverScene.__index = GameOverScene

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

function GameOverScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        selectedIndex = 1,
        menuSelectionController = MenuSelectionController.new(),
    }, GameOverScene)
end

function GameOverScene:enter()
    local state = self.context.game:getState()
    if state.mode == GameConfig.GAME_MODE.PRACTICE
        and state.result == GameConfig.GAME_RESULT.VICTORY then
        self.selectedIndex = 2
    else
        self.selectedIndex = 1
    end
    MenuSelectionController.reset(self.menuSelectionController)
end

function GameOverScene:moveSelection(delta)
    local previousIndex = self.selectedIndex
    self.selectedIndex += delta
    if self.selectedIndex < 1 then
        self.selectedIndex = 2
    elseif self.selectedIndex > 2 then
        self.selectedIndex = 1
    end

    if self.selectedIndex ~= previousIndex then
        self.context.sound:play_se("pi")
    end
end

function GameOverScene:update()
    local previousIndex = self.selectedIndex
    MenuSelectionController.update(self.menuSelectionController, playdate,
        playdate.getCurrentTimeMilliseconds(),
        function(delta) self:moveSelection(delta) end)

    if self.selectedIndex ~= previousIndex then
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        self.context.sound:play_se("decide")
        if self.selectedIndex == 1 then
            self.context.game:restartCurrentRun()
            self.manager:change(GameConfig.SCENE.GAME)
        else
            local returnTitle, returnParams = getModeSelectItem(self)
            self.manager:change(GameConfig.SCENE.TITLE, returnParams)
        end
    end
end

function GameOverScene:draw()
    self.context.renderer:drawGameOverFrame(self.selectedIndex)
end

function GameOverScene:getSystemMenuItems()
    local returnTitle, returnParams = getModeSelectItem(self)
    return {
        {
            title = returnTitle,
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE, returnParams)
            end,
        },
        {
            title = "Retry",
            callback = function()
                self.context.game:restartCurrentRun()
                self.manager:change(GameConfig.SCENE.GAME)
            end,
        },
    }
end

_G.GameOverScene = GameOverScene
return GameOverScene
