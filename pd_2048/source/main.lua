import "CoreLibs/graphics"
import "game_context"
import "game_config"
import "game/game_controller"
import "board/board_rules"
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
local BOARD_SIZE <const> = Config.BOARD_SIZE
local CENTER <const> = Config.CENTER
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

-- 外周の各辺について、準危険状態と危険状態を判定する.
local function getDangerEdges()
    local bottomCount = 0
    for x = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, x, BOARD_SIZE) then
            bottomCount += 1
        end
    end

    local leftCount = 0
    local rightCount = 0
    for y = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, 1, y) then
            leftCount += 1
        end
        if BoardRules.isOccupied(state.board, BOARD_SIZE, y) then
            rightCount += 1
        end
    end

    return bottomCount >= 4, bottomCount == BOARD_SIZE,
        leftCount >= 4, leftCount == BOARD_SIZE,
        rightCount >= 4, rightCount == BOARD_SIZE
end

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

local gameRenderer = GameRenderer.new({
    state = state,
    findDropCell = function(column) return gameController:findDropCell(column) end,
    findMergeForBlock = function(sourceX, sourceY, activeValue)
        return gameController:findMergeForBlock(sourceX, sourceY, activeValue)
    end,
})

local overlayRenderer = OverlayRenderer.new({
    state = state,
    sound = sound,
    getDangerEdges = getDangerEdges,
    isRewindAvailable = function() return gameController:isRewindAvailable() end,
})

local sceneContext = SceneContext.new({
    game = gameController,
    playDecideSound = function() sound:play_se("decide") end,
    playMenuBgm = playMenuBgm,
    playGameBgm = playGameBgm,
    drawTitle = function()
        overlayRenderer:drawTitle()
    end,
    drawNormalFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawRewindHint()
        if state.phase == GamePhase.PAUSED then
            overlayRenderer:drawPause()
        else
            overlayRenderer:drawMessage()
        end
    end,
    drawGameOverFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawGameOver()
    end,
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
