local ACHIEVEMENT_PATH <const> = "assets/achievement/achievements.json"
local FORMAT_VERSION <const> = 1

local SUPPORTED <const> = {
    category = {
        SYSTEM = true,
        NORMAL = true,
        TIME_ATTACK = true,
        CORE_RUSH = true,
        PRACTICE = true,
        MAIN_GAME = true,
    },
    conditionType = {
        UNLOCK_ACHIEVEMENT = true,
        PRACTICE_CLEAR_COUNT = true,
        TILE_VALUE = true,
        COMBO = true,
        LEVEL = true,
        CLEAR_TIME_MINUTE = true,
    },
    scope = { RUN = true, LIFETIME = true },
    operator = { [">="] = true, ["=="] = true, ["<="] = true,
        [">"] = true, ["<"] = true },
    rewardType = {
        NONE = true,
        SOUND_UNLOCK = true,
        TIMEATTACK_UNLOCK = true,
        REPLAY_UNLOCK = true,
        EXTEND_PLAY = true,
        PLAYBOOK_UNLOCK = true,
    },
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

local CONDITION_CATEGORY_SCOPE <const> = {
    UNLOCK_ACHIEVEMENT = { "SYSTEM", "LIFETIME" },
    PRACTICE_CLEAR_COUNT = { "PRACTICE", "LIFETIME" },
    TILE_VALUE = { "NORMAL", "RUN" },
    COMBO = { "MAIN_GAME", "RUN" },
    LEVEL = { "NORMAL", "RUN" },
}

local TIME_ATTACK_MODES <const> = {
    TIME_ATTACK = true,
    TIME_ATTACK_256 = true,
    TIME_ATTACK_512 = true,
}

---@class AchievementDefinitionLoader
local AchievementDefinitionLoader = {}

local function isPositiveInteger(value)
    return type(value) == "number" and value >= 1
        and value == math.floor(value)
end

local function hasExactKeys(value, expected)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if expected[key] ~= true then return false end
    end
    for key in pairs(expected) do
        if value[key] == nil then return false end
    end
    return true
end

---@param value any 日英ローカライズ文字列.
---@param languageKey string|nil 優先言語。省略時は英語.
---@return string
function AchievementDefinitionLoader.localizedText(value, languageKey)
    if type(value) == "string" and value ~= "" then return value end
    if type(value) ~= "table" then return "" end
    local primaryKey = languageKey == "ja" and "ja" or "en"
    local fallbackKey = primaryKey == "ja" and "en" or "ja"
    if type(value[primaryKey]) == "string" and value[primaryKey] ~= "" then
        return value[primaryKey]
    end
    if type(value[fallbackKey]) == "string" then return value[fallbackKey] end
    return ""
end

local function validateCondition(item)
    local condition = item.condition
    if type(condition) ~= "table"
        or not SUPPORTED.conditionType[condition.type]
        or not SUPPORTED.scope[condition.scope]
        or not SUPPORTED.operator[condition.operator] then
        return false, "unsupported condition"
    end

    local expected = CONDITION_CATEGORY_SCOPE[condition.type]
    if expected ~= nil
        and (item.category ~= expected[1] or condition.scope ~= expected[2]) then
        return false, "invalid category or scope for " .. condition.type
    end

    local params = condition.params
    if condition.type == "UNLOCK_ACHIEVEMENT"
        or condition.type == "TILE_VALUE"
        or condition.type == "COMBO"
        or condition.type == "LEVEL" then
        if not hasExactKeys(params, { value = true })
            or not isPositiveInteger(params.value) then
            return false, "value must be a positive integer"
        end
    elseif condition.type == "PRACTICE_CLEAR_COUNT" then
        local allStages = hasExactKeys(params, { all = true })
            and params.all == true and condition.operator == "=="
        local count = hasExactKeys(params, { count = true })
            and isPositiveInteger(params.count)
        if not allStages and not count then
            return false, "invalid PRACTICE clear params"
        end
    elseif condition.type == "CLEAR_TIME_MINUTE" then
        if not hasExactKeys(params, { mode = true, value = true })
            or type(params.value) ~= "number" or params.value <= 0
            or condition.scope ~= "RUN" then
            return false, "invalid clear time params"
        end
        if item.category == "TIME_ATTACK" then
            if not TIME_ATTACK_MODES[params.mode] then
                return false, "invalid TIME ATTACK mode"
            end
        elseif item.category == "CORE_RUSH" then
            if params.mode ~= "CORE_RUSH" then
                return false, "invalid CORE RUSH mode"
            end
        else
            return false, "invalid clear time category"
        end
    end
    return true
end

local function validateReward(reward)
    if type(reward) ~= "table" or not SUPPORTED.rewardType[reward.type] then
        return false, "unsupported reward"
    end
    if reward.type == "NONE" then
        return reward.id == "", "NONE reward id must be empty"
    end
    if reward.type == "PLAYBOOK_UNLOCK" then
        local rewardNo = tonumber(reward.id)
        return isPositiveInteger(rewardNo),
            "PLAYBOOK reward id must be a positive integer"
    end
    local allowed = REWARD_IDS[reward.type]
    return allowed ~= nil and allowed[reward.id] == true,
        "unsupported reward id"
end

local function normalize(item, displayNo, seenIds)
    if type(item) ~= "table" or type(item.id) ~= "string"
        or item.id == "" or string.match(item.id, "^[a-z][a-z0-9_]*$") == nil then
        return nil, "invalid id"
    end
    if seenIds[item.id] then return nil, "duplicate id" end
    if not SUPPORTED.category[item.category] then
        return nil, "unsupported category"
    end
    local name = AchievementDefinitionLoader.localizedText(item.name)
    if name == "" then return nil, "name is empty" end
    local description = AchievementDefinitionLoader.localizedText(item.description)
    if type(item.hidden) ~= "boolean"
        or type(item.progressVisible) ~= "boolean" then
        return nil, "display flags must be boolean"
    end
    local conditionValid, conditionReason = validateCondition(item)
    if not conditionValid then return nil, conditionReason end
    local rewardValid, rewardReason = validateReward(item.reward)
    if not rewardValid then return nil, rewardReason end

    seenIds[item.id] = true
    return {
        id = item.id,
        displayNo = displayNo,
        name = item.name,
        displayName = name,
        description = item.description,
        displayDescription = description,
        category = item.category,
        condition = item.condition,
        reward = item.reward,
        hidden = item.hidden,
        progressVisible = item.progressVisible,
    }
end

---@return table[] 実行可能な実績定義.
function AchievementDefinitionLoader.load()
    local ok, data = pcall(json.decodeFile, ACHIEVEMENT_PATH)
    if not ok or type(data) ~= "table" or data.version ~= FORMAT_VERSION
        or type(data.achievements) ~= "table" then
        print("AchievementDefinitionLoader: failed to load " .. ACHIEVEMENT_PATH)
        return {}
    end

    local definitions = {}
    local seenIds = {}
    for displayNo, item in ipairs(data.achievements) do
        local definition, reason = normalize(item, displayNo, seenIds)
        if definition ~= nil then
            table.insert(definitions, definition)
        else
            local id = type(item) == "table" and tostring(item.id or "?") or "?"
            print("AchievementDefinitionLoader: skipped " .. id .. ": " .. reason)
        end
    end
    return definitions
end

_G.AchievementDefinitionLoader = AchievementDefinitionLoader
return AchievementDefinitionLoader
