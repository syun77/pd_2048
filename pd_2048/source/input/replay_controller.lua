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
local DATASTORE_KEY <const> = "replays"
local LEGACY_DATASTORE_KEY <const> = "lastReplay"
local COLLECTION_VERSION <const> = 1

-- 本体のローカル日時をdatastoreへ保存できる単純なtableへ変換する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table 保存日時
local function currentLocalTime(pd)
    local time = pd.getTime()
    return {
        year = time.year,
        month = time.month,
        day = time.day,
        weekday = time.weekday,
        hour = time.hour,
        minute = time.minute,
        second = time.second,
        millisecond = time.millisecond,
    }
end

-- 現行ルールで再生できるリプレイか判定する関数.
---@param data any リプレイデータ
---@return boolean 再生可能かどうか
local function isCompatibleReplay(data)
    return type(data) == "table"
        and data.formatVersion == Config.REPLAY_FORMAT_VERSION
        and data.rulesVersion == Config.REPLAY_RULES_VERSION
        and data.rngVersion == Config.REPLAY_RNG_VERSION
        and data.mode == Config.GAME_MODE.NORMAL
        and type(data.seed) == "number"
        and type(data.events) == "table"
end

-- リプレイ一覧をdatastoreへ保存する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param entries table[] リプレイ一覧（新しい順）
---@return boolean 成功したかどうか
local function writeCollection(pd, entries)
    local ok = pcall(pd.datastore.write, {
        collectionVersion = COLLECTION_VERSION,
        entries = entries,
    }, DATASTORE_KEY)
    return ok
end

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

-- 保存済みリプレイの一覧を新しい順で読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table[] 読み込まれたリプレイ一覧
function ReplayController.loadAll(pd)
    local ok, collection = pcall(pd.datastore.read, DATASTORE_KEY)
    if ok and type(collection) == "table"
        and collection.collectionVersion == COLLECTION_VERSION
        and type(collection.entries) == "table" then
        local entries = {}
        for _, data in ipairs(collection.entries) do
            if isCompatibleReplay(data) then
                table.insert(entries, data)
                if #entries >= Config.MAX_REPLAY_COUNT then break end
            end
        end
        return entries
    end

    -- 単一保存形式からの移行。次回の保存またはお気に入り切替時に新形式へ書き込む。
    local legacyOk, legacyData = pcall(pd.datastore.read, LEGACY_DATASTORE_KEY)
    if legacyOk and isCompatibleReplay(legacyData) then return { legacyData } end
    return {}
end

-- 指定リプレイのお気に入りを切り替える関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param index integer リプレイ一覧の番号
---@return boolean 成功したかどうか
function ReplayController.toggleFavorite(pd, index)
    local entries = ReplayController.loadAll(pd)
    local data = entries[index]
    if data == nil then return false end
    data.favorite = data.favorite ~= true
    return writeCollection(pd, entries)
end

-- 新しいリプレイを一覧へ保存する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param data table 新しいリプレイデータ
---@return boolean 成功したかどうか
function ReplayController.save(pd, data)
    local entries = ReplayController.loadAll(pd)
    data.favorite = false
    table.insert(entries, 1, data)

    while #entries > Config.MAX_REPLAY_COUNT do
        local removeIndex = nil
        for index = #entries, 1, -1 do
            if entries[index].favorite ~= true then
                removeIndex = index
                break
            end
        end
        if removeIndex == nil or removeIndex == 1 then
            return false
        end
        table.remove(entries, removeIndex)
    end
    return writeCollection(pd, entries)
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
    self.data.summary.level = state.level
    self.data.summary.elapsedTimeMs = state.elapsedTimeMs
    self.data.summary.result = state.result
    self.data.summary.holdValue = state.holdValue
    self.data.summary.nextValue = state.nextValues[1]
    self.data.savedAt = currentLocalTime(self.pd)
    self.data.finalChecksum = ReplayController.checksum(
        state, randomGeneratorState)
    if not ReplayController.save(self.pd, self.data) then
		return false -- 保存に失敗した場合は何もしない.
	end
    return true
end

_G.ReplayController = ReplayController
return ReplayController
