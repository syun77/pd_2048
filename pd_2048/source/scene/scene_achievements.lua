--[[===========================================
実績画面.
===============================================]]
import "game_config"
import "menu_selection_controller"

local pd <const> = playdate

local AchievementsScene = {}
AchievementsScene.__index = AchievementsScene

function AchievementsScene.new(context)
    return setmetatable({
        context = context,
        manager = nil,
        selectedIndex = 1,
        items = {},
        menuSelectionController = MenuSelectionController.new(),
    }, AchievementsScene)
end

function AchievementsScene:enter()
    self.context.sound:playMenuBgm()
    self.selectedIndex = 1
    self.items = {}
    local language = self.context.language:get()
    for _, definition in ipairs(
        self.context.achievementManager:getDefinitions()) do
        local unlocked = self.context.achievementManager:isUnlocked(definition.id)
        local hidden = definition.hidden and not unlocked
        local name = hidden and "???"
            or self.context.achievementManager:localizedName(
                definition, language)
        local description = hidden and "???"
            or self.context.achievementManager:localizedDescription(
                definition, language)
        local current, target = self.context.achievementManager:getProgress(
            definition)
        if definition.progressVisible and not unlocked
            and current ~= nil and target ~= nil then
            description = string.format("%s  (%d/%d)",
                description, math.min(current, target), target)
        end
        table.insert(self.items, {
            label = string.format("No.%02d  %s", definition.displayNo, name),
            description = description,
            unlocked = unlocked,
        })
    end
    MenuSelectionController.reset(self.menuSelectionController)
end

function AchievementsScene:update()
    if pd.buttonJustPressed(pd.kButtonB) then
        self.context.sound:play_se("cancel")
        self.manager:change(GameConfig.SCENE.TITLE)
        return
    end
    MenuSelectionController.update(self.menuSelectionController, pd,
        pd.getCurrentTimeMilliseconds(), function(delta)
            if #self.items == 0 then return end
            self.selectedIndex += delta
            if self.selectedIndex < 1 then self.selectedIndex = #self.items
            elseif self.selectedIndex > #self.items then self.selectedIndex = 1 end
            self.context.sound:play_se("pi")
        end)
end

function AchievementsScene:draw()
    self.context.titleRenderer:drawAchievements(
        self.selectedIndex, self.items, self.context.language:get())
end

function AchievementsScene:getSystemMenuItems()
    return {
        {
            title = self.context.language:get() == GameConfig.LANGUAGE.JAPANESE
                and "タイトルへ" or "Back to Title",
            callback = function()
                self.manager:change(GameConfig.SCENE.TITLE)
            end,
        },
    }
end

_G.AchievementsScene = AchievementsScene
return AchievementsScene
