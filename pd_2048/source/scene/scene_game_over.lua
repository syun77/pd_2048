import "game_config"

local GameOverScene = {}
GameOverScene.__index = GameOverScene

function GameOverScene.new(context)
    return setmetatable({ context = context, manager = nil, selectedIndex = 1 }, GameOverScene)
end

function GameOverScene:enter()
    self.selectedIndex = 1
end

function GameOverScene:update()
    local previousIndex = self.selectedIndex
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self.context.sound:play_se("pi")
        self.selectedIndex -= 1
        if self.selectedIndex < 1 then self.selectedIndex = 2 end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self.context.sound:play_se("pi")
        self.selectedIndex += 1
        if self.selectedIndex > 2 then self.selectedIndex = 1 end
    end

    if self.selectedIndex ~= previousIndex then
        self.context.sound:play_se("pi")
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        self.context.sound:play_se("decide")
        if self.selectedIndex == 1 then
            local state = self.context.game:getState()
            self.context.game:start(state.mode)
            self.manager:change(GameConfig.SCENE.GAME)
        elseif self.context.game:getState().mode == GameConfig.GAME_MODE.PRACTICE then
            self.manager:change(GameConfig.SCENE.TITLE, { page = "PRACTICE" })
        else
            self.manager:change(GameConfig.SCENE.TITLE)
        end
    end
end

function GameOverScene:draw()
    self.context.renderer:drawGameOverFrame(self.selectedIndex)
end

_G.GameOverScene = GameOverScene
return GameOverScene
