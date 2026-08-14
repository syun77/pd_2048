import "game_config"

local Config <const> = GameConfig
local LevelProgress = {}

local function emptyXpBySource()
    return { drop = 0, merge = 0, firstTile = 0, combo = 0 }
end

function LevelProgress.reset(state, recordEligible)
    state.level = 1
    state.levelXp = 0
    state.levelDropCount = 0
    state.levelCreatedMilestones = {}
    state.levelXpBySource = emptyXpBySource()
    state.levelUpFrom = 0
    state.levelUpTo = 0
    state.levelUpUntil = 0
    state.levelNewBest = false
    state.levelRecordEligible = recordEligible ~= false
end

function LevelProgress.xpForNextLevel(level)
    return Config.LEVEL_BASE_NEXT_XP
        + Config.LEVEL_NEXT_XP_INCREMENT * (level - 1)
end

function LevelProgress.xpForLevel(level)
    if level <= 1 then return 0 end
    local completedLevels = level - 1
    return completedLevels * Config.LEVEL_BASE_NEXT_XP
        + Config.LEVEL_NEXT_XP_INCREMENT
            * completedLevels * (completedLevels - 1) / 2
end

function LevelProgress.currentLevelXp(state)
    return state.levelXp - LevelProgress.xpForLevel(state.level)
end

function LevelProgress.addXp(state, amount, source)
    if state.mode ~= Config.GAME_MODE.NORMAL or amount <= 0 then return false end
    local previousLevel = state.level
    state.levelXp += amount
    if state.levelXpBySource[source] ~= nil then
        state.levelXpBySource[source] += amount
    end
    while state.levelXp >= LevelProgress.xpForLevel(state.level + 1) do
        state.level += 1
    end
    return state.level > previousLevel, previousLevel
end

function LevelProgress.recordDrop(state)
    if state.mode ~= Config.GAME_MODE.NORMAL then return false end
    state.levelDropCount += 1
    return LevelProgress.addXp(state, Config.LEVEL_DROP_XP, "drop")
end

function LevelProgress.mergeXp(value)
    return math.max(1, math.ceil(math.log(value, 2) / 2))
end

function LevelProgress.recordMerge(state, value)
    if state.mode ~= Config.GAME_MODE.NORMAL then return false end
    local levelUp, previousLevel = LevelProgress.addXp(
        state, LevelProgress.mergeXp(value), "merge")
    local firstTileXp = Config.LEVEL_FIRST_TILE_XP[value]
    if firstTileXp ~= nil and not state.levelCreatedMilestones[value] then
        state.levelCreatedMilestones[value] = true
        local milestoneLevelUp, milestonePreviousLevel = LevelProgress.addXp(
            state, firstTileXp, "firstTile")
        if milestoneLevelUp then
            levelUp = true
            previousLevel = previousLevel or milestonePreviousLevel
        end
    end
    return levelUp, previousLevel
end

function LevelProgress.recordCombo(state)
    if state.mode ~= Config.GAME_MODE.NORMAL or state.combo < 2 then return false end
    local amount = (state.combo - 1) ^ 2
    return LevelProgress.addXp(state, amount, "combo")
end

_G.LevelProgress = LevelProgress
return LevelProgress
