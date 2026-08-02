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
local gameContext <const> = GameContext.getInstance()
local sound <const> = gameContext.sound
local Config <const> = GameConfig

local DEFAULT_REFRESH_RATE <const> = Config.DEFAULT_REFRESH_RATE
local Scene <const> = Config.SCENE
local GamePhase <const> = Config.GAME_PHASE

-- メニューBGMの再生.
local function playMenuBgm()
    sound:setBgmRandomMode(BGMRandomMode.MENU)
    sound:play_bgm(-1, false)
end

-- メインゲームBGMの再生.
local function playGameBgm()
    sound:setBgmRandomMode(BGMRandomMode.NOMAL)
    sound:play_bgm(-1, false)
end

local gameController = GameController.new({
    sound = sound,
    playGameBgm = playGameBgm,
})
local state = gameController.state

playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)

local sceneManager

-- Playdateのシステムメニューからゲームを最初からやり直せるようにする.
pd.getSystemMenu():addCheckmarkMenuItem("Auto Play", false, function(value)
    gameController:setAutoPlayEnabled(value)
end)

pd.getSystemMenu():addMenuItem("Retry", function()
    gameController:start()
    if sceneManager ~= nil then
        sceneManager:change(Scene.GAME)
    end
end)

local overlayRenderer = OverlayRenderer.new({
    state = state,
    sound = sound,
    isRewindAvailable = function() return gameController:isRewindAvailable() end,
})

local gameRenderer = GameRenderer.new({
    state = state,
    findDropCell = function(column) return gameController:findDropCell(column) end,
    findMergeForBlock = function(sourceX, sourceY, activeValue)
        return gameController:findMergeForBlock(sourceX, sourceY, activeValue)
    end,
    overlay = overlayRenderer,
})

local sceneContext = SceneContext.new({
    game = gameController,
    renderer = gameRenderer,
    playDecideSound = function() sound:play_se("decide") end,
    playMenuBgm = playMenuBgm,
    playGameBgm = playGameBgm,
})

sceneManager = SceneManager.new(sceneContext)
sceneManager:register(Scene.TITLE, TitleScene.new(sceneContext))
sceneManager:register(Scene.GAME, NormalGameScene.new(sceneContext))
sceneManager:register(Scene.GAME_OVER, GameOverScene.new(sceneContext))
sceneManager:change(Scene.TITLE)

function pd.update()
    gfx.clear(gfx.kColorWhite)
    sceneManager:update()
    sceneManager:draw()
    pd.drawFPS(4, 4)

    if state.phase == GamePhase.UNDO_ROTATING or state.rewindHoldAnimationActive then
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end
