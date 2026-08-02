--[[===========================================
タイトル画面.
===============================================]]
import "game_config"

local pd <const> = playdate

local TitleScene = {}
TitleScene.__index = TitleScene

-- コンストラクタ.
function TitleScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        selectedIndex = 1,
        menuItems = {
            { label = "NORMAL GAME", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.NORMAL },
            { label = "TIME ATTACK", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK },
            { label = "ACHIEVEMENTS", scene = GameConfig.SCENE.ACHIEVEMENTS },
            { label = "STATISTICS", scene = GameConfig.SCENE.STATISTICS },
        },
    }, TitleScene)
end

-- 開始.
function TitleScene:enter()
	-- メニュー用BGMを再生.
    self.context.sound:playMenuBgm()
end

-- 更新.
function TitleScene:update()
	-- 選択項目.
    local previousIndex = self.selectedIndex
    if pd.buttonJustPressed(pd.kButtonUp) then
        self.selectedIndex -= 1
        if self.selectedIndex < 1 then self.selectedIndex = #self.menuItems end
    elseif pd.buttonJustPressed(pd.kButtonDown) then
        self.selectedIndex += 1
        if self.selectedIndex > #self.menuItems then self.selectedIndex = 1 end
    end

    if self.selectedIndex ~= previousIndex then
		-- 項目移動SEを再生.
        self.context.sound:play_se("pi")
        return
    end

    if pd.buttonJustPressed(pd.kButtonA) then
        self.context.sound:play_se("decide")
        local item = self.menuItems[self.selectedIndex]
        if item.mode ~= nil then
            self.context.game:start(item.mode)
        end
        self.manager:change(item.scene)
    end
end

-- 描画.
function TitleScene:draw()
    self.context.titleRenderer:drawTitle(self.selectedIndex, self.menuItems)
end

_G.TitleScene = TitleScene
return TitleScene
