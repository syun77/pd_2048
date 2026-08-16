--[[===========================================
タイトル画面.
===============================================]]
import "game_config"
import "menu_selection_controller"
import "practice_stage_loader"

local pd <const> = playdate

local TitleScene = {}
TitleScene.__index = TitleScene

local function replayLabel(data)
    local savedAt = data.savedAt
    local dateText = "[--/--/-- --:--]"
    if type(savedAt) == "table" then
        dateText = string.format("[%02d/%02d/%02d %02d:%02d]",
            (savedAt.year or 0) % 100,
            savedAt.month or 0,
            savedAt.day or 0,
            savedAt.hour or 0,
            savedAt.minute or 0)
    end
    local summary = type(data.summary) == "table" and data.summary or {}
    local levelText = summary.level == nil and "--" or tostring(summary.level)
    local scoreText = summary.score == nil and "--" or tostring(summary.score)
    return string.format("%s LV%s %s", dateText, levelText, scoreText)
end

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
            REPLAYS = 1,
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
            { label = "SOUND TEST", scene = GameConfig.SCENE.SOUND_TEST },
        },
        timeAttackItems = {
            { label = "64 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK },
            { label = "256 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK_256 },
            { label = "512 SPRINT", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.TIME_ATTACK_512 },
            { label = "2048 CORE RUSH", scene = GameConfig.SCENE.GAME,
              mode = GameConfig.GAME_MODE.CORE_RUSH },
        },
        replayItems = {},
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

function TitleScene:refreshReplayItems()
    self.replayItems = {}
    for _, data in ipairs(self.context.game:listReplays()) do
        table.insert(self.replayItems, {
            label = replayLabel(data),
            replayId = data.id,
            favorite = data.favorite == true,
            footer = "A PLAY  LEFT/RIGHT FAV  B BACK",
        })
    end
end

-- 開始.
function TitleScene:enter(params)
	-- メニュー用BGMを再生.
    self.context.sound:playMenuBgm()
    for index = #self.menuItems, 1, -1 do
        if self.menuItems[index].replayMenu then table.remove(self.menuItems, index) end
    end
    self:refreshReplayItems()
    if #self.replayItems > 0 then
        table.insert(self.menuItems, 2, {
            label = "REPLAYS",
            replayMenu = true,
            submenu = true,
            submenuPage = "REPLAYS",
        })
    end
    self.practiceItems = {}
    for _, stage in ipairs(PracticeStageLoader.loadAll()) do
        local cleared = self.context.game:isPracticeStageCleared(stage)
        table.insert(self.practiceItems, {
            label = stage.label,
            cleared = cleared,
            description = PracticeStageLoader.descriptionForLanguage(
                stage, GameConfig.LANGUAGE.ENGLISH),
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
    if self.page == "REPLAYS"
        and (pd.buttonJustPressed(pd.kButtonLeft)
            or pd.buttonJustPressed(pd.kButtonRight)) then
        local item = items[self.selectedIndex]
        if item ~= nil
            and self.context.game:toggleReplayFavorite(item.replayId) then
            self:refreshReplayItems()
            self:clampSelectedIndex()
            self.context.sound:play_se("decide")
        else
            self.context.sound:play_se("error")
        end
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
        if item == nil then
            self.context.sound:play_se("error")
            return
        end
        self.selectedByPage[self.page] = self.selectedIndex
        if item.replayId ~= nil then
            if self.context.game:startReplay(item.replayId) then
                self.manager:change(GameConfig.SCENE.GAME)
            else
                self:refreshReplayItems()
                self:clampSelectedIndex()
                self.context.sound:play_se("error")
            end
            return
        end
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
    if self.page == "REPLAYS" then return self.replayItems end
    if self.page == "TIME_ATTACK" then return self.timeAttackItems end
    return self.practiceItems
end

_G.TitleScene = TitleScene
return TitleScene
