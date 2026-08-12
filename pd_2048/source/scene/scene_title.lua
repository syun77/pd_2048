--[[===========================================
タイトル画面.
===============================================]]
import "game_config"
import "menu_selection_controller"
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
        menuSelectionController = MenuSelectionController.new(),
        page = "ROOT",
        selectedByPage = {
            ROOT = 1,
            TIME_ATTACK = 1,
            PRACTICE = 1,
        },
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
            { label = "2048 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK_2048 },
            { label = "2048 CORE RUSH", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.CORE_RUSH },
        },
        practiceItems = {},
    }, TitleScene)
end

local function getRootIndexForPage(scene, page)
    for index, item in ipairs(scene.menuItems) do
        if item.submenuPage == page then return index end
    end
    return scene.selectedByPage.ROOT or 1
end

function TitleScene:clampSelectedIndex()
    local items = self:getCurrentItems()
    if #items == 0 then
        self.selectedIndex = 1
    elseif self.selectedIndex < 1 then
        self.selectedIndex = 1
    elseif self.selectedIndex > #items then
        self.selectedIndex = #items
    end
    self.selectedByPage[self.page] = self.selectedIndex
end

-- 開始.
function TitleScene:enter(params)
	-- メニュー用BGMを再生.
    self.context.sound:playMenuBgm()
    self.practiceItems = {}
    for _, stage in ipairs(PracticeStageLoader.loadAll()) do
        local cleared = self.context.game:isPracticeStageCleared(stage)
        table.insert(self.practiceItems, {
            label = stage.label,
            cleared = cleared,
            description = PracticeStageLoader.descriptionForLanguage(stage, "en"),
            scene = GameConfig.SCENE.GAME,
            mode = GameConfig.GAME_MODE.PRACTICE,
            practiceStage = stage,
        })
    end
    self.page = params ~= nil and params.page or "ROOT"
    self.selectedIndex = params ~= nil and params.selectedIndex
        or self.selectedByPage[self.page]
        or 1
    self:clampSelectedIndex()
    MenuSelectionController.reset(self.menuSelectionController)
end

function TitleScene:moveSelection(delta, items)
    if #items == 0 then return end

    local previousIndex = self.selectedIndex
    self.selectedIndex += delta
    if self.selectedIndex < 1 then
        self.selectedIndex = #items
    elseif self.selectedIndex > #items then
        self.selectedIndex = 1
    end

    if self.selectedIndex ~= previousIndex then
        self.context.sound:play_se("pi")
    end
end

-- 更新.
function TitleScene:update()
    local items = self:getCurrentItems()
    -- 選択項目.
    local previousIndex = self.selectedIndex
    if pd.buttonJustPressed(pd.kButtonB) and self.page ~= "ROOT" then
        local parentIndex = getRootIndexForPage(self, self.page)
        self.selectedByPage[self.page] = 1
        self.page = "ROOT"
        self.selectedIndex = parentIndex
        self.selectedByPage.ROOT = self.selectedIndex
        MenuSelectionController.reset(self.menuSelectionController)
        self.context.sound:play_se("cancel")
        return
    end

    MenuSelectionController.update(self.menuSelectionController, pd,
        pd.getCurrentTimeMilliseconds(),
        function(delta) self:moveSelection(delta, items) end)

    if self.selectedIndex ~= previousIndex then
        return
    end

    if pd.buttonJustPressed(pd.kButtonA) then
        self.context.sound:play_se("decide")
        local item = items[self.selectedIndex]
        self.selectedByPage[self.page] = self.selectedIndex
        if item.submenu then
            self.page = item.submenuPage
            self.selectedIndex = 1
            self.selectedByPage[self.page] = self.selectedIndex
            MenuSelectionController.reset(self.menuSelectionController)
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

-- 選択している項目リストを取得.
function TitleScene:getCurrentItems()
    if self.page == "ROOT" then return self.menuItems end
    if self.page == "TIME_ATTACK" then return self.timeAttackItems end
    return self.practiceItems
end

_G.TitleScene = TitleScene
return TitleScene
