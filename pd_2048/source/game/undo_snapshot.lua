import "board/board_transform"
import "game_config"

local Config <const> = GameConfig

---@class UndoSnapshotState UNDOで復元するゲーム状態.
---@field board Array2D ボードの状態.
---@field score integer スコア.
---@field coreRushValue integer コアラッシュの値.
---@field cursorX integer カーソルのX座標.
---@field holdValue integer ホールド中のブロックの値.
---@field holdAvailable boolean ホールドが可能かどうか.
---@field lastRandomBlockValue integer 最後に生成されたランダムブロックの値.
---@field consecutiveRandomBlockCount integer 連続して生成されたランダムブロックの数.
---@field randomGeneratorState integer ランダムジェネレーターの状態.
---@field practiceNextIndex integer プラクティスモードの次のブロックのインデックス.
---@field practiceSpawnCount integer プラクティスモードの生成回数.
---@field practiceTurnCount integer プラクティスモードのターン数.
---@field practiceNextExhausted boolean プラクティスモードの次のブロックが尽きているかどうか.
---@field practiceMergeCount integer プラクティスモードのマージ回数.
---@field level integer レベル.
---@field levelXp integer レベルの経験値.
---@field levelDropCount integer レベルのドロップ回数.
---@field levelCreatedMilestones table<integer, boolean> レベルの作成済みマイルストーン.
---@field levelXpBySource table<"drop" | "merge" | "firstTile" | "combo", integer> レベルの経験値のソースごとの値.
---@field nextValues table<integer, integer> 次のブロックの値の配列.

---@class UndoSnapshotTurn UNDO対象の手に関する情報.
---@field rotationClockwise boolean? 回転が発生した場合の回転方向. nilなら回転なし.

---@class UndoSnapshot UNDO履歴のスナップショット.
---@field state UndoSnapshotState 復元するゲーム状態.
---@field turn UndoSnapshotTurn UNDO対象の手に関する情報.
local UndoSnapshot = {}

---@generic K, V
---@param source table<K, V>?
---@return table<K, V>
local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

---@param source table<integer, integer>
---@return table<integer, integer>
local function copyNextValues(source)
    local result = {}
    for i = 1, Config.NEXT_QUEUE_COUNT do result[i] = source[i] end
    return result
end

-- 現在のゲーム状態から独立したUNDOスナップショットを作成する.
---@param state GameState
---@param randomGeneratorState integer
---@return UndoSnapshot
function UndoSnapshot.capture(state, randomGeneratorState)
    return {
		---@see UndoSnapshotState UNDOで復元するゲーム状態.
        state = {
            board = BoardTransform.copy(state.board),
            score = state.score,
            coreRushValue = state.coreRushValue,
            cursorX = state.cursorX,
            holdValue = state.holdValue,
            holdAvailable = state.holdAvailable,
            lastRandomBlockValue = state.lastRandomBlockValue,
            consecutiveRandomBlockCount = state.consecutiveRandomBlockCount,
            randomGeneratorState = randomGeneratorState,
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
            nextValues = copyNextValues(state.nextValues),
        },
		---@see UndoSnapshotTurn UNDO対象の手に関する情報.
        turn = {
            rotationClockwise = nil,
        },
    }
end

-- スナップショットに保存したゲーム状態を復元する.
---@param snapshot UndoSnapshot UNDO履歴のスナップショット.
---@param state GameState ゲーム状態.
---@param randomGenerator GameRandom ブロック生成専用の決定的乱数生成器
function UndoSnapshot.apply(snapshot, state, randomGenerator)
    local restored = snapshot.state
    state.board = restored.board
    state.score = restored.score
    state.coreRushValue = restored.coreRushValue
    state.cursorX = restored.cursorX
    state.holdValue = restored.holdValue
    state.holdAvailable = restored.holdAvailable
    state.lastRandomBlockValue = restored.lastRandomBlockValue
    state.consecutiveRandomBlockCount = restored.consecutiveRandomBlockCount
    state.practiceNextIndex = restored.practiceNextIndex
    state.practiceSpawnCount = restored.practiceSpawnCount
    state.practiceTurnCount = restored.practiceTurnCount
    state.practiceNextExhausted = restored.practiceNextExhausted
    state.practiceMergeCount = restored.practiceMergeCount
    state.level = restored.level
    state.levelXp = restored.levelXp
    state.levelDropCount = restored.levelDropCount
    state.levelCreatedMilestones = restored.levelCreatedMilestones
    state.levelXpBySource = restored.levelXpBySource
    state.nextValues = restored.nextValues
    randomGenerator:setState(restored.randomGeneratorState)
end

_G.UndoSnapshot = UndoSnapshot
return UndoSnapshot
