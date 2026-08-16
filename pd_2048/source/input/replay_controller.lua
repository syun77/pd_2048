import "game_config"

---@class ReplayController ターン単位の圧縮リプレイを記録・保存する。
---@field pd playdate Playdate SDKのグローバルオブジェクト
---@field data table? 記録中のリプレイデータ
---@field recording boolean 記録中かどうか
---@field decisionStartedAt integer? 現在のターンの意思決定が開始された時刻 (ミリ秒)
---@field decisionWaitMs integer 現在のターンの意思決定にかかった待機時間 (ミリ秒)
---@field lastInputAt integer? 最後の入力があった時刻 (ミリ秒)
---@field decisionHoldWasEmpty boolean 現在のターンのHOLDが空だったかどうか
local ReplayController = {}
ReplayController.__index = ReplayController

local Config <const> = GameConfig
local DATASTORE_KEY <const> = "lastReplay"

-- HOLDの使用回数を正規化する関数.
---@param rawCount integer 生のHOLD使用回数
---@param holdWasEmpty boolean 現在のターンのHOLDが空だったかどうか
---@return integer 正規化されたHOLD使用回数 (0, 1, 2のいずれか)
local function normalizedHoldCount(rawCount, holdWasEmpty)
    if rawCount <= 0 then return 0 end
    if holdWasEmpty then return rawCount % 2 == 0 and 2 or 1 end
    return rawCount % 2
end

-- ハッシュを計算する関数.
---@param hash integer 現在のハッシュ値
---@param value any ハッシュに加える値
---@return integer 新しいハッシュ値
local function addHash(hash, value)
    local text = tostring(value or "")
    for index = 1, #text do
        hash = (hash * 131 + string.byte(text, index)) % 2147483647
    end
    return (hash * 131 + 31) % 2147483647
end

-- リプレイのチェックサムを計算する関数.
---@param state GameState ゲーム状態
---@param randomGeneratorState integer ランダムジェネレーターの状態
---@return integer チェックサム値
function ReplayController.checksum(state, randomGeneratorState)
    local hash = 17
    for y = 1, Config.BOARD_SIZE do
        for x = 1, Config.BOARD_SIZE do
            hash = addHash(hash, state.board:get(x, y))
        end
    end
    hash = addHash(hash, state.score)
    hash = addHash(hash, state.holdValue)
    hash = addHash(hash, state.cursorX)
    hash = addHash(hash, state.coreRushValue)
    hash = addHash(hash, state.practiceTurnCount)
    hash = addHash(hash, state.practiceMergeCount)
    hash = addHash(hash, state.result)
    for index = 1, Config.NEXT_QUEUE_COUNT do
        hash = addHash(hash, state.nextValues[index])
    end
    return addHash(hash, randomGeneratorState)
end

-- 生成.
---@param pd playdate Playdate SDKのグローバルオブジェクト
function ReplayController.new(pd)
    return setmetatable({
        pd = pd,
        data = nil,
        recording = false,
        decisionStartedAt = nil,
        decisionWaitMs = 0,
        lastInputAt = nil,
        decisionHoldWasEmpty = false,
        rawHoldCount = 0,
    }, ReplayController)
end

-- 読み込み
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table? 読み込まれたリプレイデータ、またはnil
function ReplayController.load(pd)
    local ok, data = pcall(pd.datastore.read, DATASTORE_KEY)
    if not ok or type(data) ~= "table"
        or data.formatVersion ~= Config.REPLAY_FORMAT_VERSION
        or data.rulesVersion ~= Config.REPLAY_RULES_VERSION
        or data.rngVersion ~= Config.REPLAY_RNG_VERSION
        or type(data.seed) ~= "number"
        or type(data.events) ~= "table" then
        return nil
    end
    return data
end

-- 保存されているリプレイが存在するかどうかを確認する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return boolean 保存されているリプレイが存在するかどうか
function ReplayController.hasSavedReplay(pd)
    local data = ReplayController.load(pd)
    return data ~= nil and data.mode == Config.GAME_MODE.NORMAL
end

-- 記録をキャンセルする関数.
function ReplayController:cancelRecording()
    self.data = nil
    self.recording = false
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.rawHoldCount = 0
end

-- 記録を開始する関数.
---@param mode GAME_MODE 記録するゲームモード
---@param practiceStageId integer? PRACTICEモードのステージID (nilの場合は通常モード)
---@param seed integer ランダムジェネレーターのシード値
function ReplayController:start(mode, practiceStageId, seed)
    self.data = {
        formatVersion = Config.REPLAY_FORMAT_VERSION,
        rulesVersion = Config.REPLAY_RULES_VERSION,
        rngVersion = Config.REPLAY_RNG_VERSION,
        mode = mode,
        practiceStageId = practiceStageId,
        seed = seed,
        events = {},
        summary = { turnsWithHold = 0, turnsWithoutHold = 0 },
    }
    self.recording = true
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.rawHoldCount = 0
end

-- 記録中のターンの意思決定を開始する関数.
---@param now integer 現在の時刻 (ミリ秒)
---@param holdWasEmpty boolean 現在のターンのHOLDが空だったかどうか
function ReplayController:beginDecision(now, holdWasEmpty)
    if not self.recording then return end
    if self.decisionStartedAt ~= nil then
        if self.lastInputAt == nil then self.lastInputAt = now end
        return
    end
    self.decisionStartedAt = now
    self.decisionWaitMs = 0
    self.lastInputAt = now
    self.decisionHoldWasEmpty = holdWasEmpty
    self.rawHoldCount = 0
end

-- 記録中のターンの意思決定を一時停止する関数.
---@param now integer 現在の時刻 (ミリ秒)
function ReplayController:pauseDecision(now)
    if not self.recording or self.decisionStartedAt == nil
        or self.lastInputAt == nil then return end
    self.decisionWaitMs += math.max(0, now - self.lastInputAt)
    self.lastInputAt = nil
end

-- 決定までの待ち時間を取得する.
---@param now integer 
---@return integer 
function ReplayController:getDecisionWait(now)
    local wait = self.decisionWaitMs
    if self.lastInputAt ~= nil then wait += math.max(0, now - self.lastInputAt) end
    return math.max(0, math.min(Config.REPLAY_MAX_WAIT_MS, math.floor(wait)))
end

-- 記録中のターンのHOLD使用を記録する関数.
function ReplayController:noteHold()
    if self.recording and self.decisionStartedAt ~= nil then
        self.rawHoldCount += 1
    end
end

-- 記録中のターンの意思決定を終了する関数.
function ReplayController:finishDecision()
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.rawHoldCount = 0
end

-- 記録中のターンの情報を記録する関数.
---@param now integer 現在の時刻 (ミリ秒)
---@param targetColumn integer ターンのターゲット列
---@param shouldDrop boolean ターンでドロップが行われたかどうか
function ReplayController:recordTurn(now, targetColumn, shouldDrop)
    if not self.recording or self.decisionStartedAt == nil then return end
    local holdCount = normalizedHoldCount(
        self.rawHoldCount, self.decisionHoldWasEmpty)
    table.insert(self.data.events, {
        type = "TURN",
        waitMs = self:getDecisionWait(now),
        targetColumn = targetColumn,
        holdClass = holdCount == 0 and "NONE" or "USED",
        holdApplications = holdCount,
        drop = shouldDrop ~= false,
    })
    if holdCount == 0 then
        self.data.summary.turnsWithoutHold += 1
    else
        self.data.summary.turnsWithHold += 1
    end
    self:finishDecision()
end

-- 記録中のターンの巻き戻しを記録する関数.
---@param now integer 現在の時刻 (ミリ秒)
function ReplayController:recordRewind(now)
    if not self.recording or self.decisionStartedAt == nil then return end
    table.insert(self.data.events, {
        type = "REWIND",
        waitMs = self:getDecisionWait(now),
    })
    self:finishDecision()
end

-- 記録中のリプレイを終了し、保存する関数.
---@param state GameState ゲーム状態
---@param randomGeneratorState integer ランダムジェネレーターの状態
---@return boolean 成功したかどうか
function ReplayController:finish(state, randomGeneratorState)
    if not self.recording or self.data == nil then
		return false -- 記録が開始されていない場合は何もしない.
	end
    self.recording = false
    self.data.summary.score = state.score
    self.data.summary.elapsedTimeMs = state.elapsedTimeMs
    self.data.summary.result = state.result
    self.data.summary.holdValue = state.holdValue
    self.data.summary.nextValue = state.nextValues[1]
    self.data.finalChecksum = ReplayController.checksum(
        state, randomGeneratorState)
    local ok = pcall(self.pd.datastore.write, self.data, DATASTORE_KEY)
    if not ok then
		return false -- 保存に失敗した場合は何もしない.
	end
    return true
end

_G.ReplayController = ReplayController
return ReplayController
