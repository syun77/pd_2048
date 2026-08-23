local DATASTORE_KEY <const> = "achievements"
local FORMAT_VERSION <const> = 1

local REWARD_GROUP_BY_TYPE <const> = {
    SOUND_UNLOCK = "sound",
    TIMEATTACK_UNLOCK = "timeAttack",
    REPLAY_UNLOCK = "replay",
    EXTEND_PLAY = "extend",
    PLAYBOOK_UNLOCK = "playbook",
}

local REWARD_IDS <const> = {
    SOUND_UNLOCK = { soundtest = true },
    TIMEATTACK_UNLOCK = {
        sprint64 = true,
        sprint256 = true,
        sprint512 = true,
        corerush2048 = true,
    },
    REPLAY_UNLOCK = { replay = true },
    EXTEND_PLAY = { extend = true },
}

---@class AchievementStoreData
---@field version integer
---@field unlockedIds table<string, boolean>
---@field rewards table<string, table<string|integer, boolean>>
---@class AchievementStore 実績達成状態と取得済み報酬を保存するクラス.
---@field pd playdate
---@field data AchievementStoreData
local AchievementStore = {}
AchievementStore.__index = AchievementStore

local function newData()
    return {
        version = FORMAT_VERSION,
        unlockedIds = {},
        rewards = {
            sound = {},
            timeAttack = {},
            replay = {},
            extend = {},
            playbook = {},
        },
    }
end

local function copyUnlockedSet(source, allowedIds, numericKeys)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, unlocked in pairs(source) do
        if unlocked == true then
            local normalizedKey = numericKeys and tonumber(key) or tostring(key)
            if numericKeys and (normalizedKey == nil or normalizedKey < 1
                or normalizedKey ~= math.floor(normalizedKey)) then
                normalizedKey = nil
            end
            if normalizedKey ~= nil
                and (allowedIds == nil or allowedIds[normalizedKey] == true) then
                result[normalizedKey] = true
            end
        end
    end
    return result
end

local function normalize(data)
    if type(data) ~= "table" or data.version ~= FORMAT_VERSION then
        return newData()
    end
    local result = newData()
    result.unlockedIds = copyUnlockedSet(data.unlockedIds)
    local rewards = type(data.rewards) == "table" and data.rewards or {}
    result.rewards.sound = copyUnlockedSet(
        rewards.sound, REWARD_IDS.SOUND_UNLOCK)
    result.rewards.timeAttack = copyUnlockedSet(
        rewards.timeAttack, REWARD_IDS.TIMEATTACK_UNLOCK)
    result.rewards.replay = copyUnlockedSet(
        rewards.replay, REWARD_IDS.REPLAY_UNLOCK)
    result.rewards.extend = copyUnlockedSet(
        rewards.extend, REWARD_IDS.EXTEND_PLAY)
    result.rewards.playbook = copyUnlockedSet(rewards.playbook, nil, true)
    return result
end

---@param pd playdate
---@return AchievementStore
function AchievementStore.new(pd)
    local ok, data = pcall(pd.datastore.read, DATASTORE_KEY)
    if not ok then data = nil end
    return setmetatable({ pd = pd, data = normalize(data) }, AchievementStore)
end

function AchievementStore:save()
    self.data.version = FORMAT_VERSION
    local ok, result = pcall(self.pd.datastore.write, self.data, DATASTORE_KEY)
    return ok and result ~= false
end

---@param rewardType string
---@param rewardId string|integer
---@return boolean
function AchievementStore:isRewardUnlocked(rewardType, rewardId)
    local groupName = REWARD_GROUP_BY_TYPE[rewardType]
    if groupName == nil then return false end
    local key = tostring(rewardId)
    if rewardType == "PLAYBOOK_UNLOCK" then key = tonumber(rewardId) end
    return key ~= nil and self.data.rewards[groupName][key] == true
end

local function normalizedRewardId(rewardType, rewardId)
    if rewardType == "PLAYBOOK_UNLOCK" then
        local number = tonumber(rewardId)
        if number == nil or number < 1 or number ~= math.floor(number) then return nil end
        return number
    end
    local id = tostring(rewardId or "")
    local allowedIds = REWARD_IDS[rewardType]
    if allowedIds == nil or allowedIds[id] ~= true then return nil end
    return id
end

---@param rewardType string
---@param rewardId string|integer
---@return boolean 保存または取得済みの場合はtrue.
function AchievementStore:unlockReward(rewardType, rewardId)
    local groupName = REWARD_GROUP_BY_TYPE[rewardType]
    local key = normalizedRewardId(rewardType, rewardId)
    if groupName == nil or key == nil then return false end
    local group = self.data.rewards[groupName]
    if group[key] == true then return true end
    group[key] = true
    local saved = self:save()
    if not saved then group[key] = nil end
    return saved
end

---@param entries table[] 達成IDと報酬を持つ新規達成候補.
---@return boolean, string[] 保存成功か, 今回新規保存した実績IDの配列.
function AchievementStore:unlockAchievements(entries)
    if type(entries) ~= "table" then return false, {} end
    local previousData = self.data
    local pendingData = normalize(previousData)
    local newIds = {}
    local seenIds = {}

    for _, entry in ipairs(entries) do
        local achievementId = type(entry) == "table" and entry.id or nil
        local rewardType = type(entry) == "table" and entry.rewardType or nil
        if type(achievementId) ~= "string" or achievementId == ""
            or type(rewardType) ~= "string" then
            return false, {}
        end
        if seenIds[achievementId] then return false, {} end
        local groupName = nil
        local rewardKey = nil
        if rewardType ~= "NONE" then
            groupName = REWARD_GROUP_BY_TYPE[rewardType]
            rewardKey = normalizedRewardId(rewardType, entry.rewardId)
            if groupName == nil or rewardKey == nil then return false, {} end
        end
        if pendingData.unlockedIds[achievementId] ~= true then
            pendingData.unlockedIds[achievementId] = true
            if groupName ~= nil then
                pendingData.rewards[groupName][rewardKey] = true
            end
            table.insert(newIds, achievementId)
        end
        seenIds[achievementId] = true
    end

    if #newIds == 0 then return true, newIds end
    self.data = pendingData
    if self:save() then return true, newIds end
    self.data = previousData
    return false, {}
end

---@param achievementId string
---@param rewardType string
---@param rewardId string|integer
---@return boolean, boolean 保存成功か, 新規達成か.
function AchievementStore:unlockAchievement(achievementId, rewardType, rewardId)
    local saved, newIds = self:unlockAchievements({ {
        id = achievementId,
        rewardType = rewardType,
        rewardId = rewardId,
    } })
    return saved, #newIds > 0
end

---@param achievementId string
---@return boolean
function AchievementStore:isAchievementUnlocked(achievementId)
    return self.data.unlockedIds[achievementId] == true
end

---@return table<string, boolean>
function AchievementStore:getUnlockedAchievementIds()
    return copyUnlockedSet(self.data.unlockedIds)
end

---@return integer
function AchievementStore:getUnlockedAchievementCount()
    local count = 0
    for _, unlocked in pairs(self.data.unlockedIds) do
        if unlocked == true then count += 1 end
    end
    return count
end

---@return table<integer, boolean>
function AchievementStore:getPlaybookUnlockNumbers()
    return copyUnlockedSet(self.data.rewards.playbook, nil, true)
end

---@param rewardId string
---@return boolean
function AchievementStore:isTimeAttackUnlocked(rewardId)
    return self:isRewardUnlocked("TIMEATTACK_UNLOCK", rewardId)
end

---@param rewardId string
---@return boolean
function AchievementStore:unlockTimeAttack(rewardId)
    return self:unlockReward("TIMEATTACK_UNLOCK", rewardId)
end

function AchievementStore:isReplayUnlocked()
    return self:isRewardUnlocked("REPLAY_UNLOCK", "replay")
end

function AchievementStore:isReplayExtendUnlocked()
    return self:isRewardUnlocked("EXTEND_PLAY", "extend")
end

function AchievementStore:isSoundTestUnlocked()
    return self:isRewardUnlocked("SOUND_UNLOCK", "soundtest")
end

_G.AchievementStore = AchievementStore
return AchievementStore
