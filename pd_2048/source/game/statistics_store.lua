import "game_config"

local Config <const> = GameConfig
local DATASTORE_KEY <const> = "statistics"
local FORMAT_VERSION <const> = 3
local NORMAL_HISTORY_LIMIT <const> = 30

---@class StatisticsStore 統計情報の保存データ.
---@field version integer 保存データのフォーマットバージョン.
---@field totalPlayTimeMs integer 総プレイ時間（ミリ秒）.
---@field normal StatisticsStore.NormalModeStatistics NORMALモードの統計情報.
---@field timeAttack StatisticsStore.TimeAttackStatistics TIME ATTACKモードの統計情報.
---@class StatisticsStore.NormalModeStatistics NORMALモードの統計情報.
---@field plays integer プレイ回数.
---@field highScore integer ハイスコア.
---@field bestLevel integer 最高到達レベル.
---@field highestTile integer 最高到達タイル.
---@field maxCombo integer 最大コンボ数.
---@field history StatisticsStore.NormalHistory NORMALモードのプレイ履歴.
---@class StatisticsStore.NormalHistory NORMALモードのプレイ履歴.
---@field completedPlays integer 記録対象として完了した通算プレイ数.
---@field runs StatisticsStore.NormalRun[] 過去のプレイ情報（最大30件）.
---@class StatisticsStore.NormalRun NORMALモードの1プレイ分の情報.
---@field number integer 記録対象として完了したプレイ番号.
---@field level integer 最終到達レベル.
---@field score integer 最終スコア.
---@class StatisticsStore.TimeAttackStatistics TIME ATTACKモードの統計情報.
---@field sprint64 StatisticsStore.TimedModeStatistics SPRINT 64の統計情報.
---@field sprint256 StatisticsStore.TimedModeStatistics SPRINT 256の統計情報.
---@field sprint512 StatisticsStore.TimedModeStatistics SPRINT 512の統計情報.
---@field coreRush StatisticsStore.TimedModeStatistics COREの統計情報.
---@class StatisticsStore.TimedModeStatistics 各タイムアタックモードの統計情報.
---@field plays integer プレイ回数.
---@field clears integer クリア回数.
---@field highScore integer ハイスコア.
---@field bestTimeMs integer|nil ベストタイム（ミリ秒）.
local StatisticsStore = {}

local function nonNegativeInteger(value, fallback)
    if type(value) ~= "number" then return fallback or 0 end
    return math.max(0, math.floor(value))
end

local function optionalTime(value)
    if type(value) ~= "number" or value < 0 then return nil end
    return math.floor(value)
end

-- TIME ATTACKモードの新しい統計情報のデータを作成する.
---@return StatisticsStore 新しい統計情報のデータ.
local function newTimedMode()
    return { plays = 0, clears = 0, highScore = 0, bestTimeMs = nil }
end

-- 新しい統計情報のデータを作成する.
---@return false|StatisticsStore 新しい統計情報のデータ.
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
            history = {
                completedPlays = 0,
                runs = {},
            },
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
    target.highScore = nonNegativeInteger(source.highScore)
    target.bestTimeMs = optionalTime(source.bestTimeMs)
end

local function normalizeNormalHistory(target, source)
    source = type(source) == "table" and source or {}
    local sourceRuns = type(source.runs) == "table" and source.runs or {}
    local firstIndex = math.max(1, #sourceRuns - NORMAL_HISTORY_LIMIT + 1)
    local highestNumber = 0
    for index = firstIndex, #sourceRuns do
        local run = sourceRuns[index]
        if type(run) == "table" then
            local number = math.max(1, nonNegativeInteger(run.number, index))
            local level = math.max(1, nonNegativeInteger(run.level, 1))
            local score = nonNegativeInteger(run.score)
            target.runs[#target.runs + 1] = {
                number = number,
                level = level,
                score = score,
            }
            highestNumber = math.max(highestNumber, number)
        end
    end
    target.completedPlays = math.max(highestNumber,
        nonNegativeInteger(source.completedPlays))
end

-- 古い統計情報のデータを新しい形式に変換する.
---@param data table|nil 古い統計情報のデータ.
---@param legacy table|nil 古い統計情報のデータ（旧形式）.
---@return StatisticsStore|false 新しい統計情報のデータ.
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
    normalizeNormalHistory(result.normal.history, normal.history)

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

-- 統計情報のデータを読み込む.
---@param pd playdate Playdate SDK.
---@param legacy table|nil 古い統計情報のデータ（旧形式）.
---@return StatisticsStore|false 統計情報のデータ.
function StatisticsStore.load(pd, legacy)
    local ok, data = pcall(pd.datastore.read, DATASTORE_KEY)
    if not ok then data = nil end
    return normalize(data, legacy)
end

-- 統計情報のデータを保存する.
---@param pd playdate Playdate SDK.
---@param statistics StatisticsStore 統計情報のデータ.
---@return boolean 成功した場合はtrue、失敗した場合はfalse.
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

-- 対象モードのハイスコアを更新する.
---@param statistics StatisticsStore 統計情報のデータ.
---@param mode GAME_MODE ゲームモード.
---@param score integer 今回のスコア.
---@return boolean ハイスコアを更新した場合はtrue.
function StatisticsStore.recordHighScore(statistics, mode, score)
    local modeStatistics = mode == Config.GAME_MODE.NORMAL
        and statistics.normal
        or StatisticsStore.timedModeFor(statistics, mode)
    if modeStatistics == nil then return false end
    score = nonNegativeInteger(score)
    if score <= modeStatistics.highScore then return false end
    modeStatistics.highScore = score
    return true
end

-- 統計情報のプレイ回数を記録する.
---@param statistics StatisticsStore 統計情報のデータ.
---@param mode GAME_MODE ゲームモード.
---@return boolean 成功した場合はtrue、失敗した場合はfalse.
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

-- 統計情報のプレイ回数を削除する.
---@param statistics StatisticsStore 統計情報のデータ.
---@param mode GAME_MODE ゲームモード.
---@return boolean 成功した場合はtrue、失敗した場合はfalse.
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

-- NORMALモードで完了したプレイ情報を記録する.
---@param statistics StatisticsStore 統計情報のデータ.
---@param level integer 最終到達レベル.
---@param score integer 最終スコア.
function StatisticsStore.recordNormalCompletion(statistics, level, score)
    local history = statistics.normal.history
    history.completedPlays += 1
    history.runs[#history.runs + 1] = {
        number = history.completedPlays,
        level = math.max(1, math.floor(level)),
        score = math.max(0, math.floor(score)),
    }
    while #history.runs > NORMAL_HISTORY_LIMIT do
        table.remove(history.runs, 1)
    end
end

-- NORMALモードの保存済み履歴から平均値を計算する.
---@param statistics StatisticsStore 統計情報のデータ.
---@return number|nil averageLevel 平均到達レベル.
---@return number|nil averageScore 平均スコア.
---@return integer count 集計したプレイ数.
function StatisticsStore.normalHistoryAverages(statistics)
    local runs = statistics.normal.history.runs
    if #runs == 0 then return nil, nil, 0 end
    local totalLevel = 0
    local totalScore = 0
    for _, run in ipairs(runs) do
        totalLevel += run.level
        totalScore += run.score
    end
    return totalLevel / #runs, totalScore / #runs, #runs
end

-- 統計情報の総プレイ回数を取得する.
---@param statistics StatisticsStore 統計情報のデータ.
---@return integer 総プレイ回数.
function StatisticsStore.totalPlays(statistics)
    local timed = statistics.timeAttack
    return statistics.normal.plays + timed.sprint64.plays
        + timed.sprint256.plays + timed.sprint512.plays + timed.coreRush.plays
end

_G.StatisticsStore = StatisticsStore
return StatisticsStore
