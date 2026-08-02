import "CoreLibs/graphics"
import "game_context"
import "game_config"
import "game/game_controller"
import "render/game_renderer"
import "render/overlay_renderer"
import "scene/scene_manager"
import "scene/scene_context"
import "scene/scene_title"
import "scene/scene_game_normal"
import "scene/scene_game_over"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig

local App = {}
App.__index = App

function App.new()
    local self = setmetatable({}, App)
    local gameContext = GameContext.getInstance()
    local sound = gameContext.sound

    self.sound = sound
    self.game = GameController.new({ sound = sound })
    self.overlayRenderer = OverlayRenderer.new({
        state = self.game:getState(),
        sound = sound,
        isRewindAvailable = function()
            return self.game:isRewindAvailable()
        end,
    })
    self.renderer = GameRenderer.new({
        state = self.game:getState(),
        findDropCell = function(column)
            return self.game:findDropCell(column)
        end,
        findMergeForBlock = function(sourceX, sourceY, activeValue)
            return self.game:findMergeForBlock(sourceX, sourceY, activeValue)
        end,
        overlay = self.overlayRenderer,
    })

    self.sceneContext = SceneContext.new({
        game = self.game,
        renderer = self.renderer,
        sound = sound,
    })
    self.sceneManager = SceneManager.new(self.sceneContext)
    self.sceneManager:register(Config.SCENE.TITLE, TitleScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.GAME, NormalGameScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.GAME_OVER, GameOverScene.new(self.sceneContext))

    self:registerSystemMenu()
    pd.display.setRefreshRate(Config.DEFAULT_REFRESH_RATE)
    sound:playMenuBgm()
    self.sceneManager:change(Config.SCENE.TITLE)
    return self
end

function App:registerSystemMenu()
    pd.getSystemMenu():addCheckmarkMenuItem("Auto Play", false, function(value)
        self.game:setAutoPlayEnabled(value)
    end)
    pd.getSystemMenu():addMenuItem("Retry", function()
        self.game:start()
        self.sceneManager:change(GameConfig.SCENE.GAME)
    end)
end

function App:update()
    self.sceneManager:update()
end

function App:draw()
    local state = self.game:getState()
    gfx.clear(gfx.kColorWhite)
    self.sceneManager:draw()
    pd.drawFPS(4, 4)

    if state.phase == Config.GAME_PHASE.UNDO_ROTATING
        or state.rewindHoldAnimationActive then
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end

_G.App = App
return App
