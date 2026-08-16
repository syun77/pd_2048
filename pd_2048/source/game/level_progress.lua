import "game_config"

local Config <const> = GameConfig
---@class LevelProgress ゲームのレベル進行を管理するクラス.
---@field level integer 現在のレベル
---@field levelXp integer 現在のレベル経験値
---@field levelDropCount integer 現在のレベルでのドロップ数
---@field levelCreatedMilestones table<integer, boolean> 現在のレベルで作成済みのマイルストーンの記録
---@field levelXpBySource tablelib<"drop"|"merge"|"firstTile"|"combo", integer> 現在のレベルでの経験値獲得元ごとの経験値
local LevelProgress = {}

-- 空の経験値獲得元ごとの経験値テーブルを作成する関数.
---@return tablelib<"drop"|"merge"|"firstTile"|"combo", integer> 空の経験値獲得元ごとの経験値テーブル
local function emptyXpBySource()
    return { drop = 0, merge = 0, firstTile = 0, combo = 0 }
end

-- レベル進行をリセットする関数.
---@param state GameState ゲーム状態
---@param recordEligible boolean レベル進行の記録が可能かどうか
function LevelProgress.reset(state, recordEligible)
    state.level = 1
    state.levelXp = 0
    state.levelDropCount = 0
    state.levelCreatedMilestones = {}
    state.levelXpBySource = emptyXpBySource()
    state.levelUpFrom = 0
    state.levelUpTo = 0
    state.levelUpDisplayFrame = Config.LEVEL_UP_DISPLAY_FRAMES
    state.levelNewBest = false
    state.levelRecordEligible = recordEligible ~= false
end

-- レベルアップに必要な経験値を計算する関数.
---@param level integer レベル
---@return integer レベルアップに必要な経験値
function LevelProgress.xpForNextLevel(level)
    return Config.LEVEL_BASE_NEXT_XP
        + Config.LEVEL_NEXT_XP_INCREMENT * (level - 1)
end

-- レベルに到達するために必要な累積経験値を計算する関数.
---@param level integer レベル
---@return integer レベルに到達するために必要な累積経験値
function LevelProgress.xpForLevel(level)
    if level <= 1 then return 0 end
    local completedLevels = level - 1
    return completedLevels * Config.LEVEL_BASE_NEXT_XP
        + Config.LEVEL_NEXT_XP_INCREMENT
            * completedLevels * (completedLevels - 1) / 2
end

-- 現在のレベルでの経験値を取得する関数.
---@param state GameState ゲーム状態
---@return integer 現在のレベルでの経験値
function LevelProgress.currentLevelXp(state)
    return state.levelXp - LevelProgress.xpForLevel(state.level)
end

-- 経験値を追加する関数.
---@param state GameState ゲーム状態
---@param amount integer 追加する経験値
---@param source "drop"|"merge"|"firstTile"|"combo" 経験値の獲得元
---@return boolean レベルアップしたかどうか, integer? 以前のレベル (レベルアップしていない場合はnil)
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

-- ドロップを記録する関数.
---@param state GameState ゲーム状態
---@return boolean レベルアップしたかどうか
function LevelProgress.recordDrop(state)
    if state.mode ~= Config.GAME_MODE.NORMAL then return false end
    state.levelDropCount += 1
    return LevelProgress.addXp(state, Config.LEVEL_DROP_XP, "drop")
end

-- マージによる経験値を計算する関数.
---@param value integer マージされたブロックの値
---@return integer マージによる経験値
function LevelProgress.mergeXp(value)
    return math.max(1, math.ceil(math.log(value, 2) / 2))
end

-- マージを記録する関数.
---@param state GameState ゲーム状態
---@param value integer マージされたブロックの値
---@return boolean レベルアップしたかどうか, integer? 以前のレベル (レベルアップしていない場合はnil)
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

-- コンボを記録する関数.
---@param state GameState ゲーム状態
---@return boolean レベルアップしたかどうか, integer? 以前のレベル (レベルアップしていない場合はnil)
function LevelProgress.recordCombo(state)
    if state.mode ~= Config.GAME_MODE.NORMAL or state.combo < 2 then return false end
    local amount = (state.combo - 1) ^ 2
    return LevelProgress.addXp(state, amount, "combo")
end

_G.LevelProgress = LevelProgress
return LevelProgress
