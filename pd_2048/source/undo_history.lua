import "board/board_transform"
import "game_config"

local Config <const> = GameConfig

---@class UndoSnapshot UNDO履歴のスナップショット.
---@field board Array2D ボードの状態.
---@field score integer スコア.
---@field coreRushValue integer コアラッシュの値.
---@field cursorX integer カーソルのX座標.
---@field holdValue integer ホールド中のブロックの値.
---@field holdAvailable boolean ホールドが可能かどうか.
---@field lastRandomBlockValue integer 最後に生成されたランダムブロックの値.
---@field consecutiveRandomBlockCount integer 連続して生成されたランダムブロックの数.
---@field randomGeneratorState any ランダムジェネレーターの状態.
---@field practiceNextIndex integer プラクティスモードの次のブロックのインデックス.
---@field practiceSpawnCount integer プラクティスモードの生成回数
---@field practiceTurnCount integer プラクティスモードのターン数
---@field practiceNextExhausted boolean プラクティスモードの次のブロックが尽きているかどうか
---@field practiceMergeCount integer プラクティスモードのマージ回数
---@field level integer レベル
---@field levelXp integer レベルの経験値
---@field levelDropCount integer レベルのドロップ回数
---@field levelCreatedMilestones table<integer, boolean> レベルの作成済みマイルストーン
---@field levelXpBySource table<integer, integer> レベルの経験値のソースごとの値
---@field hasRotation boolean 回転が発生したかどうか
---@field rotationClockwise boolean 回転が時計回りかどうか
---@field action string アクションの説明
---@field nextValues table<integer, integer> 次のブロックの値の配列

---@class UndoHistory UNDO履歴管理クラス.
---@field push fun(history: table<integer, table>, state: table, action: string) UNDO履歴に新しい状態を追加する関数.
---@field canRestore fun(history: table<integer, table>, rewindUsesRemaining: integer): boolean UNDOが可能かどうかを判定する関数.
---@field pop fun(history: table<integer, table>): table? UNDO履歴から最新の状態を取得する関数.
local UndoHistory = {}

-- UNDO履歴のテーブルを初期化する.
---@param source any
---@return table<integer, table> UNDO履歴のテーブル
local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

-- UNDO履歴に新しい状態を追加する.
---@param history table<integer, UndoSnapshot> UNDO履歴のテーブル
---@param state UndoControllerSnapshot 現在のゲーム状態のスナップショット
---@param action string UNDO履歴に追加するアクションの説明
function UndoHistory.push(history, state, action)
    local snapshot = {
        board = BoardTransform.copy(state.board), score = state.score,
        coreRushValue = state.coreRushValue,
        cursorX = state.cursorX, holdValue = state.holdValue,
        holdAvailable = state.holdAvailable,
        lastRandomBlockValue = state.lastRandomBlockValue,
        consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
        randomGeneratorState = state.randomGeneratorState,
        practiceNextIndex = state.practiceNextIndex,
        practiceSpawnCount = state.practiceSpawnCount,
        practiceTurnCount = state.practiceTurnCount,
        practiceNextExhausted = state.practiceNextExhausted,
        practiceMergeCount = state.practiceMergeCount,
        level = state.level,
        levelXp = state.levelXp,
        levelDropCount = state.levelDropCount,
        levelCreatedMilestones = copyTable(state.levelCreatedMilestones),
        levelXpBySource = copyTable(state.levelXpBySource),
        hasRotation = false, rotationClockwise = false, action = action, nextValues = {},
    }
    for i = 1, Config.NEXT_QUEUE_COUNT do snapshot.nextValues[i] = state.nextValues[i] end
    table.insert(history, snapshot)
    if #history > Config.MAX_UNDO_COUNT then table.remove(history, 1) end
end

-- UNDOが可能かどうかを判定する.
---@param history table<integer, UndoSnapshot> UNDO履歴のテーブル
---@param rewindUsesRemaining integer 残りのリワインド使用回数
---@return boolean UNDOが可能かどうか
function UndoHistory.canRestore(history, rewindUsesRemaining)
    return rewindUsesRemaining > 0 and #history > 0
end

-- UNDO履歴から最新の状態を取得する.
---@param history table<integer, UndoSnapshot> UNDO履歴のテーブル
---@return UndoSnapshot? 最新の状態のスナップショット、または nil
function UndoHistory.pop(history)
    return table.remove(history)
end

_G.UndoHistory = UndoHistory
return UndoHistory
