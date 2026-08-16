import "game_config"

local Config <const> = GameConfig
local DATASTORE_KEY <const> = "statistics"
local FORMAT_VERSION <const> = 1

local StatisticsStore = {}

local function nonNegativeInteger(value, fallback)
    if type(value) ~= "number" then return fallback or 0 end
    return math.max(0, math.floor(value))
end

local function optionalTime(value)
    if type(value) ~= "number" or value < 0 then return nil end
    return math.floor(value)
end

local function newTimedMode()
    return { plays = 0, clears = 0, bestTimeMs = nil }
end

function StatisticsStore.newData()
    return {
        version = FORMAT_VERSION,
        totalPlayTimeMs = 0,
        normal = {
            plays = 0,
            highScore = 0,
            bestLevel = 1,
            highestTile = 0,
            maxCombo = 0,
        },
        timeAttack = {
            sprint64 = newTimedMode(),
            sprint256 = newTimedMode(),
            sprint512 = newTimedMode(),
            coreRush = newTimedMode(),
        },
    }
end

local function normalizeTimedMode(target, source)
    source = type(source) == "table" and source or {}
    target.plays = nonNegativeInteger(source.plays)
    target.clears = math.min(target.plays, nonNegativeInteger(source.clears))
    target.bestTimeMs = optionalTime(source.bestTimeMs)
end

local function normalize(data, legacy)
    local result = StatisticsStore.newData()
    data = type(data) == "table" and data or {}
    legacy = type(legacy) == "table" and legacy or {}

    result.totalPlayTimeMs = nonNegativeInteger(data.totalPlayTimeMs)
    local normal = type(data.normal) == "table" and data.normal or {}
    result.normal.plays = nonNegativeInteger(normal.plays)
    result.normal.highScore = nonNegativeInteger(normal.highScore,
        nonNegativeInteger(legacy.normalHighScore))
    result.normal.highScore = math.max(result.normal.highScore,
        nonNegativeInteger(legacy.normalHighScore))
    result.normal.bestLevel = math.max(1,
        nonNegativeInteger(normal.bestLevel, nonNegativeInteger(
            legacy.normalBestLevel, 1)))
    result.normal.bestLevel = math.max(result.normal.bestLevel,
        nonNegativeInteger(legacy.normalBestLevel, 1))
    result.normal.highestTile = nonNegativeInteger(normal.highestTile)
    result.normal.maxCombo = nonNegativeInteger(normal.maxCombo)

    local timeAttack = type(data.timeAttack) == "table" and data.timeAttack or {}
    normalizeTimedMode(result.timeAttack.sprint64, timeAttack.sprint64)
    normalizeTimedMode(result.timeAttack.sprint256, timeAttack.sprint256)
    normalizeTimedMode(result.timeAttack.sprint512, timeAttack.sprint512)
    normalizeTimedMode(result.timeAttack.coreRush, timeAttack.coreRush)
    if result.timeAttack.coreRush.bestTimeMs == nil then
        result.timeAttack.coreRush.bestTimeMs = optionalTime(legacy.coreRushBestTimeMs)
    end
    return result
end

function StatisticsStore.load(pd, legacy)
    local ok, data = pcall(pd.datastore.read, DATASTORE_KEY)
    if not ok then data = nil end
    return normalize(data, legacy)
end

function StatisticsStore.save(pd, statistics)
    statistics.version = FORMAT_VERSION
    return pcall(pd.datastore.write, statistics, DATASTORE_KEY)
end

function StatisticsStore.timedModeFor(statistics, mode)
    if mode == Config.GAME_MODE.TIME_ATTACK then
        return statistics.timeAttack.sprint64
    elseif mode == Config.GAME_MODE.TIME_ATTACK_256 then
        return statistics.timeAttack.sprint256
    elseif mode == Config.GAME_MODE.TIME_ATTACK_512 then
        return statistics.timeAttack.sprint512
    elseif mode == Config.GAME_MODE.CORE_RUSH then
        return statistics.timeAttack.coreRush
    end
    return nil
end

function StatisticsStore.recordPlay(statistics, mode)
    if mode == Config.GAME_MODE.NORMAL then
        statistics.normal.plays += 1
        return true
    end
    local timedMode = StatisticsStore.timedModeFor(statistics, mode)
    if timedMode == nil then return false end
    timedMode.plays += 1
    return true
end

function StatisticsStore.removePlay(statistics, mode)
    if mode == Config.GAME_MODE.NORMAL then
        statistics.normal.plays = math.max(0, statistics.normal.plays - 1)
        return true
    end
    local timedMode = StatisticsStore.timedModeFor(statistics, mode)
    if timedMode == nil then return false end
    timedMode.plays = math.max(0, timedMode.plays - 1)
    return true
end

function StatisticsStore.recordTimedClear(statistics, mode, elapsedTimeMs)
    local timedMode = StatisticsStore.timedModeFor(statistics, mode)
    if timedMode == nil then return false end
    timedMode.clears += 1
    if timedMode.bestTimeMs == nil or elapsedTimeMs < timedMode.bestTimeMs then
        timedMode.bestTimeMs = math.max(0, math.floor(elapsedTimeMs))
    end
    return true
end

function StatisticsStore.totalPlays(statistics)
    local timed = statistics.timeAttack
    return statistics.normal.plays + timed.sprint64.plays
        + timed.sprint256.plays + timed.sprint512.plays + timed.coreRush.plays
end

_G.StatisticsStore = StatisticsStore
return StatisticsStore
