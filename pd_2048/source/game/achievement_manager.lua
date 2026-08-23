import "game_config"
import "achievement_definition_loader"

local Config <const> = GameConfig
local NOTIFICATION_DURATION_MS <const> = 3000

---@class AchievementManager
---@field definitions table[] 実行可能な実績定義.
---@field store AchievementStore 永続ストア.
---@field run table ラン内最大値.
---@field notificationQueue table[] 通知待ち定義.
---@field activeNotification table|nil 表示中定義.
---@field activeNotificationStartedAt integer|nil 表示開始時刻.
local AchievementManager = {}
AchievementManager.__index = AchievementManager

local function compare(actual, operator, target)
    if operator == ">=" then return actual >= target end
    if operator == "==" then return actual == target end
    if operator == "<=" then return actual <= target end
    if operator == ">" then return actual > target end
    if operator == "<" then return actual < target end
    return false
end

local function countSet(values)
    local count = 0
    if type(values) ~= "table" then return count end
    for _, value in pairs(values) do
        if value == true then count += 1 end
    end
    return count
end

local function categoryMatchesMode(category, mode)
    if category == "SYSTEM" then return true end
    if category == "NORMAL" then return mode == Config.GAME_MODE.NORMAL end
    if category == "TIME_ATTACK" then
        return mode == Config.GAME_MODE.TIME_ATTACK
            or mode == Config.GAME_MODE.TIME_ATTACK_256
            or mode == Config.GAME_MODE.TIME_ATTACK_512
    end
    if category == "CORE_RUSH" then
        return mode == Config.GAME_MODE.CORE_RUSH
    end
    if category == "PRACTICE" then return mode == Config.GAME_MODE.PRACTICE end
    if category == "MAIN_GAME" then return mode ~= Config.GAME_MODE.PRACTICE end
    return false
end

---@param definitions table[]
---@param store AchievementStore
---@return AchievementManager
function AchievementManager.new(definitions, store)
    local self = setmetatable({
        definitions = definitions or {},
        store = store,
        run = {},
        notificationQueue = {},
        activeNotification = nil,
        activeNotificationStartedAt = nil,
        practiceClearedIds = {},
        practiceAllStageIds = {},
    }, AchievementManager)
    self:startRun(nil)
    return self
end

function AchievementManager:startRun(mode)
    self.run = {
        mode = mode,
        maxMergedTile = 0,
        maxCombo = 0,
        maxLevel = 1,
    }
end

function AchievementManager:isUnlocked(id)
    return self.store:isAchievementUnlocked(id)
end

function AchievementManager:getUnlockedIds()
    return self.store:getUnlockedAchievementIds()
end

function AchievementManager:getDefinitions()
    return self.definitions
end

function AchievementManager:hasReward(rewardType, rewardId)
    return self.store:isRewardUnlocked(rewardType, rewardId)
end

function AchievementManager:getPlaybookUnlockNumbers()
    return self.store:getPlaybookUnlockNumbers()
end

function AchievementManager:countUnlockedDefinitions(extraUnlocked)
    local count = 0
    for _, definition in ipairs(self.definitions) do
        if self.store:isAchievementUnlocked(definition.id)
            or (type(extraUnlocked) == "table"
                and extraUnlocked[definition.id]) then
            count += 1
        end
    end
    return count
end

local function practiceAllCleared(allStageIds, clearedIds)
    local stageCount = 0
    for stageId, included in pairs(allStageIds or {}) do
        if included == true then
            stageCount += 1
            if type(clearedIds) ~= "table" or clearedIds[stageId] ~= true then
                return false
            end
        end
    end
    return stageCount > 0
end

function AchievementManager:conditionMet(definition, event)
    local condition = definition.condition
    local params = condition.params
    if condition.type == "TILE_VALUE" then
        return event.type == "RUN_PROGRESS"
            and categoryMatchesMode(definition.category, self.run.mode)
            and compare(self.run.maxMergedTile, condition.operator, params.value)
    elseif condition.type == "COMBO" then
        return event.type == "RUN_PROGRESS"
            and categoryMatchesMode(definition.category, self.run.mode)
            and compare(self.run.maxCombo, condition.operator, params.value)
    elseif condition.type == "LEVEL" then
        return event.type == "RUN_PROGRESS"
            and categoryMatchesMode(definition.category, self.run.mode)
            and compare(self.run.maxLevel, condition.operator, params.value)
    elseif condition.type == "CLEAR_TIME_MINUTE" then
        return event.type == "MODE_CLEARED"
            and type(event.elapsedTimeMs) == "number"
            and categoryMatchesMode(definition.category, event.mode)
            and params.mode == event.mode
            and compare(event.elapsedTimeMs, condition.operator,
                params.value * 60000)
    elseif condition.type == "PRACTICE_CLEAR_COUNT" then
        if event.type ~= "PRACTICE_CLEARED" then return false end
        if params.all == true then
            return practiceAllCleared(
                self.practiceAllStageIds, self.practiceClearedIds)
        end
        return compare(countSet(self.practiceClearedIds),
            condition.operator, params.count)
    end
    return false
end

local function achievementEntry(definition)
    return {
        id = definition.id,
        rewardType = definition.reward.type,
        rewardId = definition.reward.id,
    }
end

function AchievementManager:evaluate(event)
    local pending = {}
    for _, definition in ipairs(self.definitions) do
        if definition.condition.type ~= "UNLOCK_ACHIEVEMENT"
            and not self.store:isAchievementUnlocked(definition.id)
            and self:conditionMet(definition, event) then
            pending[definition.id] = true
        end
    end

    local changed = true
    while changed do
        changed = false
        for _, definition in ipairs(self.definitions) do
            if definition.condition.type == "UNLOCK_ACHIEVEMENT"
                and not self.store:isAchievementUnlocked(definition.id)
                and not pending[definition.id] then
                local afterUnlockCount = self:countUnlockedDefinitions(pending) + 1
                local condition = definition.condition
                if compare(afterUnlockCount, condition.operator,
                    condition.params.value) then
                    pending[definition.id] = true
                    changed = true
                end
            end
        end
    end

    local entries = {}
    local orderedDefinitions = {}
    for _, definition in ipairs(self.definitions) do
        if pending[definition.id] then
            table.insert(entries, achievementEntry(definition))
            table.insert(orderedDefinitions, definition)
        end
    end
    if #entries == 0 then return true, {} end

    local saved, newIds = self.store:unlockAchievements(entries)
    if not saved then return false, {} end
    local savedSet = {}
    for _, id in ipairs(newIds) do savedSet[id] = true end
    for _, definition in ipairs(orderedDefinitions) do
        if savedSet[definition.id] then
            table.insert(self.notificationQueue, definition)
        end
    end
    return true, newIds
end

---@param event table ゲーム側の確定イベント.
---@return boolean, string[] 保存成功か, 新規達成ID.
function AchievementManager:emit(event)
    if type(event) ~= "table" or event.eligible ~= true then return true, {} end
    if event.type == "RUN_PROGRESS" then
        if event.mode ~= self.run.mode then self:startRun(event.mode) end
        if type(event.mergedTile) == "number" then
            self.run.maxMergedTile = math.max(
                self.run.maxMergedTile, event.mergedTile)
        end
        if type(event.combo) == "number" then
            self.run.maxCombo = math.max(self.run.maxCombo, event.combo)
        end
        if type(event.level) == "number" then
            self.run.maxLevel = math.max(self.run.maxLevel, event.level)
        end
    elseif event.type == "PRACTICE_CLEARED" then
        self.practiceAllStageIds = event.allStageIds or {}
        self.practiceClearedIds = event.clearedIds or {}
    elseif event.type ~= "MODE_CLEARED" then
        return true, {}
    end
    return self:evaluate(event)
end

function AchievementManager:update(now)
    if self.activeNotification ~= nil
        and now - self.activeNotificationStartedAt >= NOTIFICATION_DURATION_MS then
        self.activeNotification = nil
        self.activeNotificationStartedAt = nil
    end
    if self.activeNotification == nil and #self.notificationQueue > 0 then
        self.activeNotification = table.remove(self.notificationQueue, 1)
        self.activeNotificationStartedAt = now
    end
end

function AchievementManager:currentNotification()
    return self.activeNotification
end

function AchievementManager:getProgress(definition)
    if definition.condition.type == "UNLOCK_ACHIEVEMENT" then
        return self:countUnlockedDefinitions(), definition.condition.params.value
    elseif definition.condition.type == "PRACTICE_CLEAR_COUNT" then
        local current = countSet(self.practiceClearedIds)
        if definition.condition.params.all == true then
            return current, countSet(self.practiceAllStageIds)
        end
        return current, definition.condition.params.count
    end
    return nil, nil
end

function AchievementManager:localizedName(definition, languageKey)
    return AchievementDefinitionLoader.localizedText(definition.name, languageKey)
end

function AchievementManager:localizedDescription(definition, languageKey)
    return AchievementDefinitionLoader.localizedText(
        definition.description, languageKey)
end

_G.AchievementManager = AchievementManager
return AchievementManager
