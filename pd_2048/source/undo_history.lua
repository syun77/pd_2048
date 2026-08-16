import "game_config"

local Config <const> = GameConfig

---@class UndoHistory UNDO履歴管理クラス.
---@field push fun(history: table<integer, UndoSnapshot>, snapshot: UndoSnapshot) UNDO履歴に新しい状態を追加する関数.
---@field peek fun(history: table<integer, UndoSnapshot>): UndoSnapshot? UNDO履歴の最新状態を取得する関数.
---@field canRestore fun(history: table<integer, UndoSnapshot>, rewindUsesRemaining: integer): boolean UNDOが可能かどうかを判定する関数.
---@field pop fun(history: table<integer, UndoSnapshot>): UndoSnapshot? UNDO履歴から最新の状態を取り除く関数.
local UndoHistory = {}

-- UNDO履歴に新しい状態を追加する.
---@param history table<integer, UndoSnapshot> UNDO履歴のテーブル
---@param snapshot UndoSnapshot UNDO履歴に追加するスナップショット
function UndoHistory.push(history, snapshot)
    table.insert(history, snapshot)
    if #history > Config.MAX_UNDO_COUNT then table.remove(history, 1) end
end

-- UNDO履歴の最新状態を取得する.
---@param history table<integer, UndoSnapshot> UNDO履歴のテーブル
---@return UndoSnapshot? 最新の状態のスナップショット、または nil
function UndoHistory.peek(history)
    return history[#history]
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
