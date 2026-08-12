--[[===========================================
サウンドテスト画面.
===============================================]]
import "game_config"
import "menu_selection_controller"

local pd <const> = playdate
local BGM_DB_DIRECTORY <const> = "assets/bgm_db"
local DB_DISPLAY_LERP <const> = 0.25

local SoundTestScene = {}
SoundTestScene.__index = SoundTestScene

function SoundTestScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        selectedIndex = 1,
        selectedTab = "BGM",
        selectedByTab = {
            BGM = 1,
            SE = 1,
        },
        menuSelectionController = MenuSelectionController.new(),
        bgmItems = {},
        seItems = {},
        playingBgmName = nil,
        bgmDb = nil,
        displayBands = nil,
    }, SoundTestScene)
end

local function makeItems(names)
    local items = {}
    for _, name in ipairs(names) do
        table.insert(items, { label = name, name = name })
    end
    return items
end

function SoundTestScene:getCurrentItems()
    if self.selectedTab == "SE" then return self.seItems end
    return self.bgmItems
end

function SoundTestScene:clampSelectedIndex()
    local items = self:getCurrentItems()
    if #items == 0 then
        self.selectedIndex = 1
    elseif self.selectedIndex < 1 then
        self.selectedIndex = 1
    elseif self.selectedIndex > #items then
        self.selectedIndex = #items
    end
    self.selectedByTab[self.selectedTab] = self.selectedIndex
end

function SoundTestScene:enter()
    self.bgmItems = makeItems(self.context.sound:getBgmNames())
    self.seItems = makeItems(self.context.sound:getSeNames())
    self.selectedIndex = self.selectedByTab[self.selectedTab] or 1
    self:clampSelectedIndex()
    MenuSelectionController.reset(self.menuSelectionController)
end

function SoundTestScene:loadBgmDb(bgmName)
    self.playingBgmName = bgmName
    self.bgmDb = nil
    self.displayBands = nil

    local path = BGM_DB_DIRECTORY .. "/" .. bgmName .. ".json"
    local ok, data = pcall(json.decodeFile, path)
    if ok and type(data) == "table" and type(data.levels) == "table" then
        self.bgmDb = data
    else
        print("SoundTestScene:loadBgmDb() - failed to load " .. path)
    end
end

local function lerpValue(current, target, rate)
    if target == nil then return current end
    if current == nil then return target end
    return current + (target - current) * rate
end

function SoundTestScene:returnToTitle()
    self.context.sound:stop_bgm()
    self.context.sound:play_se("cancel")
    self.manager:change(GameConfig.SCENE.TITLE)
end

function SoundTestScene:moveSelection(delta, items)
    if #items == 0 then return end

    local previousIndex = self.selectedIndex
    self.selectedIndex += delta
    if self.selectedIndex < 1 then
        self.selectedIndex = #items
    elseif self.selectedIndex > #items then
        self.selectedIndex = 1
    end

    if self.selectedIndex ~= previousIndex then
        self.selectedByTab[self.selectedTab] = self.selectedIndex
        self.context.sound:play_se("pi")
    end
end

function SoundTestScene:switchTab(nextTab)
    if self.selectedTab == nextTab then return end

    self.selectedByTab[self.selectedTab] = self.selectedIndex
    self.selectedTab = nextTab
    self.selectedIndex = self.selectedByTab[self.selectedTab] or 1
    self:clampSelectedIndex()
    MenuSelectionController.reset(self.menuSelectionController)
    self.context.sound:play_se("pi")
end

function SoundTestScene:playSelectedItem()
    local items = self:getCurrentItems()
    local item = items[self.selectedIndex]
    if item == nil then return end

    if self.selectedTab == "BGM" then
        self.context.sound:playBgmByName(item.name)
        self:loadBgmDb(item.name)
    else
        self.context.sound:play_se(item.name)
    end
end

function SoundTestScene:getBgmDbStatus()
    if self.playingBgmName == nil then return nil end

    local offset = self.context.sound:getBgmOffset()
    local target = self:getBgmDbTarget(offset)
    if target == nil then
        return {
            name = self.playingBgmName,
            offset = offset,
            bands = nil,
        }
    end

    return {
        name = self.playingBgmName,
        offset = offset,
        bands = self.displayBands or target.bands,
    }
end

local function levelToDb(level, minDb)
    return minDb + (level / 100) * (0 - minDb)
end

function SoundTestScene:getBgmDbTarget(offset)
    local db = self.bgmDb
    if offset == nil or db == nil then return nil end

    local interval = db.interval or 0.2
    local minDb = db.minDb or -60
    local bands = {}
    local sourceBands = db.bands
    if type(sourceBands) == "table" then
        for _, bandName in ipairs({ "low", "mid", "high" }) do
            local bandLevels = sourceBands[bandName]
            local level = 0
            if type(bandLevels) == "table" then
                local index = math.floor(offset / interval) + 1
                index = math.max(1, math.min(#bandLevels, index))
                level = bandLevels[index]
            end
            if type(level) ~= "number" then level = 0 end
            bands[bandName] = {
                level = level,
                db = levelToDb(level, minDb),
            }
        end
        return { bands = bands }
    end

    local levels = db.levels
    if type(levels) ~= "table" then return nil end
    local index = math.floor(offset / interval) + 1
    index = math.max(1, math.min(#levels, index))
    local level = levels[index]
    if type(level) ~= "number" then level = 0 end
    return {
        bands = {
            mid = {
                level = level,
                db = levelToDb(level, minDb),
            },
        },
    }
end

function SoundTestScene:updateBgmDbDisplay()
    if self.playingBgmName == nil then return end

    local target = self:getBgmDbTarget(self.context.sound:getBgmOffset())
    if target == nil then return end

    self.displayBands = self.displayBands or {}
    for bandName, targetBand in pairs(target.bands) do
        local displayBand = self.displayBands[bandName] or {}
        displayBand.level = lerpValue(displayBand.level, targetBand.level, DB_DISPLAY_LERP)
        displayBand.db = lerpValue(displayBand.db, targetBand.db, DB_DISPLAY_LERP)
        self.displayBands[bandName] = displayBand
    end
end

function SoundTestScene:update()
    self:updateBgmDbDisplay()

    local items = self:getCurrentItems()
    if pd.buttonJustPressed(pd.kButtonB) then
        self:returnToTitle()
        return
    end
    if pd.buttonJustPressed(pd.kButtonLeft) then
        self:switchTab("BGM")
        return
    elseif pd.buttonJustPressed(pd.kButtonRight) then
        self:switchTab("SE")
        return
    end

    local previousIndex = self.selectedIndex
    MenuSelectionController.update(self.menuSelectionController, pd,
        pd.getCurrentTimeMilliseconds(),
        function(delta) self:moveSelection(delta, items) end)
    if self.selectedIndex ~= previousIndex then return end

    if pd.buttonJustPressed(pd.kButtonA) then
        self.context.sound:play_se("decide")
        self:playSelectedItem()
    end
end

function SoundTestScene:draw()
    local items = self:getCurrentItems()
    local labels = {}
    for _, item in ipairs(items) do
        table.insert(labels, item.label)
    end
    self.context.titleRenderer:drawSoundTest(self.selectedTab, self.selectedIndex,
        labels, self:getBgmDbStatus())
end

function SoundTestScene:getSystemMenuItems()
    return {
        {
            title = "Back to Title",
            callback = function()
                self:returnToTitle()
            end,
        },
    }
end

_G.SoundTestScene = SoundTestScene
return SoundTestScene
