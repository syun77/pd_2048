--[[===========================================
PLAYBOOK画面.
===============================================]]
import "game_config"
import "menu_selection_controller"
import "playbook_loader"

local pd <const> = playdate
local gfx <const> = pd.graphics

local PlaybookScene = {}
PlaybookScene.__index = PlaybookScene

function PlaybookScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        screen = "LIST",
        hints = {},
        selectedIndex = 1,
        pageIndex = 1,
        imageCache = {},
        menuSelectionController = MenuSelectionController.new(),
    }, PlaybookScene)
end

function PlaybookScene:enter()
    self.context.sound:playMenuBgm()
    self.screen = "LIST"
    self.hints = PlaybookLoader.loadVisible(nil)
    self.selectedIndex = 1
    self.pageIndex = 1
    self.imageCache = {}
    MenuSelectionController.reset(self.menuSelectionController)
end

function PlaybookScene:moveSelection(delta)
    if #self.hints == 0 then return end
    local previousIndex = self.selectedIndex
    self.selectedIndex += delta
    if self.selectedIndex < 1 then
        self.selectedIndex = #self.hints
    elseif self.selectedIndex > #self.hints then
        self.selectedIndex = 1
    end
    if self.selectedIndex ~= previousIndex then
        self.context.sound:play_se("pi")
    end
end

function PlaybookScene:showList()
    self.screen = "LIST"
    self.pageIndex = 1
    self.imageCache = {}
    MenuSelectionController.reset(self.menuSelectionController)
    self.manager:refreshSystemMenu()
end

function PlaybookScene:showDetail()
    if self.hints[self.selectedIndex] == nil then return end
    self.screen = "DETAIL"
    self.pageIndex = 1
    self.imageCache = {}
    self.manager:refreshSystemMenu()
end

function PlaybookScene:getCurrentHint()
    return self.hints[self.selectedIndex]
end

function PlaybookScene:getCurrentPage()
    local hint = self:getCurrentHint()
    if hint == nil then return nil end
    return hint.pages[self.pageIndex]
end

function PlaybookScene:getCurrentImage()
    local page = self:getCurrentPage()
    if page == nil then return nil end
    local cached = self.imageCache[page.imagePath]
    if cached == false then return nil end
    if cached == nil then
        cached = gfx.image.new(page.imagePath)
        self.imageCache[page.imagePath] = cached or false
    end
    return cached or nil
end

function PlaybookScene:update()
    if self.screen == "DETAIL" then
        local hint = self:getCurrentHint()
        if pd.buttonJustPressed(pd.kButtonB) then
            self.context.sound:play_se("cancel")
            self:showList()
        elseif hint ~= nil and pd.buttonJustPressed(pd.kButtonLeft)
            and self.pageIndex > 1 then
            self.pageIndex -= 1
            self.context.sound:play_se("pi")
        elseif hint ~= nil and pd.buttonJustPressed(pd.kButtonRight)
            and self.pageIndex < #hint.pages then
            self.pageIndex += 1
            self.context.sound:play_se("pi")
        end
        return
    end

    if pd.buttonJustPressed(pd.kButtonB) then
        self.context.sound:play_se("cancel")
        self.manager:change(GameConfig.SCENE.TITLE)
        return
    end

    local previousIndex = self.selectedIndex
    MenuSelectionController.update(self.menuSelectionController, pd,
        pd.getCurrentTimeMilliseconds(),
        function(delta) self:moveSelection(delta) end)
    if self.selectedIndex ~= previousIndex then return end

    if pd.buttonJustPressed(pd.kButtonA)
        and self.hints[self.selectedIndex] ~= nil then
        self.context.sound:play_se("decide")
        self:showDetail()
    end
end

function PlaybookScene:draw()
    if self.screen == "LIST" then
        self.context.titleRenderer:drawPlaybookList(
            self.selectedIndex, self.hints)
        return
    end
    local hint = self:getCurrentHint()
    local page = self:getCurrentPage()
    if hint == nil or page == nil then
        self.context.titleRenderer:drawPlaybookList(
            self.selectedIndex, self.hints)
        return
    end
    self.context.titleRenderer:drawPlaybookDetail(
        hint.title, self.pageIndex, #hint.pages,
        self:getCurrentImage(), page.description)
end

function PlaybookScene:getSystemMenuItems()
    if self.screen == "DETAIL" then
        return {
            {
                title = "Back to Playbook",
                callback = function() self:showList() end,
            },
        }
    end
    return {
        {
            title = "Back to Title",
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE)
            end,
        },
    }
end

_G.PlaybookScene = PlaybookScene
return PlaybookScene
