import "CoreLibs/graphics"
import "game_context"
import "game_config"
import "game/game_controller"
import "render/game_renderer"
import "render/overlay_renderer"
import "render/title_renderer"
import "render/menu_background_renderer"
import "system_menu_controller"
import "scene/scene_manager"
import "scene/scene_context"
import "scene/scene_title"
import "scene/scene_game_normal"
import "scene/scene_game_over"
import "scene/scene_playbook"
import "scene/scene_achievements"
import "scene/scene_statistics"
import "scene/scene_sound_test"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig

---@class App アプリケーションクラス.
---@field sound Sound サウンド管理.
---@field game GameController ゲームコントローラー.
---@field overlayRenderer OverlayRenderer オーバーレイ描画クラス.
---@field menuBackgroundRenderer MenuBackgroundRenderer メニューバックグラウンド描画クラス.
---@field titleRenderer TitleRenderer タイトルメニューの描画.
---@field renderer GameRenderer ゲーム描画クラス.
---@field sceneContext SceneContext シーンコンテキスト.
---@field sceneManager SceneManager シーンマネージャ.
local App = {}
App.__index = App

-- 生成.
---@return App
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
    self.menuBackgroundRenderer = MenuBackgroundRenderer.new()
    self.titleRenderer = TitleRenderer.new({
        state = self.game:getState(),
        menuRenderer = self.overlayRenderer,
        background = self.menuBackgroundRenderer,
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

	-- シーンコンテキストを生成.
    self.sceneContext = SceneContext.new({
        game = self.game,
        renderer = self.renderer,
        titleRenderer = self.titleRenderer,
        menuBackground = self.menuBackgroundRenderer,
        sound = sound,
        systemMenu = SystemMenuController.new(pd.getSystemMenu()),
    })
	
	-- 各種シーンを登録.
    self.sceneManager = SceneManager.new(self.sceneContext)
    self.sceneManager:register(Config.SCENE.TITLE, TitleScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.GAME, NormalGameScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.GAME_OVER, GameOverScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.PLAYBOOK, PlaybookScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.ACHIEVEMENTS, AchievementsScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.STATISTICS, StatisticsScene.new(self.sceneContext))
    self.sceneManager:register(Config.SCENE.SOUND_TEST, SoundTestScene.new(self.sceneContext))

	-- FPSを設定.
    pd.display.setRefreshRate(Config.DEFAULT_REFRESH_RATE)
	-- メニューBGMを再生.
    sound:playMenuBgm()
	-- タイトル画面を開始.
    self.sceneManager:change(Config.SCENE.TITLE)

    return self
end

-- 更新.
function App:update()
    self.sceneManager:update()
end

-- OSからゲーム終了または低バッテリースリープを通知されたとき、
-- プレイヤー操作中のNORMALだけを中断保存する.
---@return boolean 保存に成功したかどうか
function App:autoSuspendNormal()
    self.game:flushStatistics()
    if self.sceneManager.currentName ~= Config.SCENE.GAME then return false end
    return self.game:suspendNormalGame()
end

-- 描画.
function App:draw()
    local state = self.game:getState()
	-- 画面全体をクリア.
	-- フレームレートを上げるには Dirty Rect での実装が必要.
    gfx.clear(gfx.kColorWhite)
    self.sceneManager:draw()

	if Config.SHOW_FPS then
		-- FPSの描画.
		pd.drawFPS(2, 2)
	end

    if not state.suspendRestoreActive
        and state.phase == Config.GAME_PHASE.UNDO_ROTATING then
		-- XORの反転描画.
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end

_G.App = App
return App
