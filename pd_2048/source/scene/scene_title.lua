--[[===========================================
タイトル画面.
===============================================]]
import "game_config"
import "practice_stage_loader"

local pd <const> = playdate

local TitleScene = {}
TitleScene.__index = TitleScene

-- コンストラクタ.
function TitleScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        selectedIndex = 1,
        page = "ROOT",
        menuItems = {
            { label = "NORMAL GAME", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.NORMAL },
            { label = "TIME ATTACK", submenu = true, submenuPage = "TIME_ATTACK" },
            { label = "PRACTICE", submenu = true, submenuPage = "PRACTICE" },
            { label = "ACHIEVEMENTS", scene = GameConfig.SCENE.ACHIEVEMENTS },
            { label = "STATISTICS", scene = GameConfig.SCENE.STATISTICS },
        },
        timeAttackItems = {
            { label = "64 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK },
            { label = "256 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK_256 },
            { label = "2048 CORE RUSH", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.CORE_RUSH },
        },
        practiceItems = {},
    }, TitleScene)
end

-- 開始.
function TitleScene:enter()
	-- メニュー用BGMを再生.
    self.context.sound:playMenuBgm()
    self.page = "ROOT"
    self.selectedIndex = 1
    self.practiceItems = {}
    for _, stage in ipairs(PracticeStageLoader.loadAll()) do
        table.insert(self.practiceItems, {
            label = stage.label,
            scene = GameConfig.SCENE.GAME,
            mode = GameConfig.GAME_MODE.PRACTICE,
            practiceStage = stage,
        })
    end
end

-- 更新.
function TitleScene:update()
    local items = self:getCurrentItems()
    -- 選択項目.
    local previousIndex = self.selectedIndex
    if pd.buttonJustPressed(pd.kButtonB) and self.page ~= "ROOT" then
        self.page = "ROOT"
        self.selectedIndex = 1
        self.context.sound:play_se("pi")
        return
    elseif pd.buttonJustPressed(pd.kButtonUp) then
        self.selectedIndex -= 1
        if self.selectedIndex < 1 then self.selectedIndex = #items end
    elseif pd.buttonJustPressed(pd.kButtonDown) then
        self.selectedIndex += 1
        if self.selectedIndex > #items then self.selectedIndex = 1 end
    end

    if self.selectedIndex ~= previousIndex then
		-- 項目移動SEを再生.
        self.context.sound:play_se("pi")
        return
    end

    if pd.buttonJustPressed(pd.kButtonA) then
        self.context.sound:play_se("decide")
        local item = items[self.selectedIndex]
        if item.submenu then
            self.page = item.submenuPage
            self.selectedIndex = 1
            return
        end
        if item.mode ~= nil then
            self.context.game:start(item.mode, item.practiceStage)
        end
        self.manager:change(item.scene)
    end
end

-- 描画.
function TitleScene:draw()
    local items = self:getCurrentItems()
    local title = self.page == "ROOT" and nil or self.page
    self.context.titleRenderer:drawTitle(self.selectedIndex, items, title)
end

function TitleScene:getCurrentItems()
    if self.page == "ROOT" then return self.menuItems end
    if self.page == "TIME_ATTACK" then return self.timeAttackItems end
    return self.practiceItems
end

_G.TitleScene = TitleScene
return TitleScene
