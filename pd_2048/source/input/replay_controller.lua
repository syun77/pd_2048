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
local INDEX_DATASTORE_KEY <const> = "replayIndex"
local REPLAY_DATASTORE_PREFIX <const> = "replay_"
local COLLECTION_DATASTORE_KEY <const> = "replays"
local LEGACY_DATASTORE_KEY <const> = "lastReplay"
local SUSPEND_DATASTORE_KEY <const> = "normalSuspend"
local INDEX_VERSION <const> = 1
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

-- 現行ルールで復元できる中断データか判定する関数.
---@param data any 中断データ
---@return boolean 復元可能かどうか
local function isCompatibleSuspend(data)
    return isCompatibleReplay(data)
        and data.suspendVersion == Config.SUSPEND_FORMAT_VERSION
        and type(data.checkpointChecksum) == "number"
        and type(data.summary) == "table"
end

-- 一覧用メタデータが現行ルールと互換か判定する関数.
---@param entry any 一覧用メタデータ
---@return boolean 再生候補として表示できるかどうか
local function isCompatibleIndexEntry(entry)
    return type(entry) == "table"
        and type(entry.id) == "string"
        and entry.formatVersion == Config.REPLAY_FORMAT_VERSION
        and entry.rulesVersion == Config.REPLAY_RULES_VERSION
        and entry.rngVersion == Config.REPLAY_RNG_VERSION
        and entry.mode == Config.GAME_MODE.NORMAL
        and type(entry.summary) == "table"
end

-- datastoreへtableを書き込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param data table 保存するデータ
---@param key string datastoreキー
---@return boolean 成功したかどうか
local function writeDatastore(pd, data, key)
    local ok, result = pcall(pd.datastore.write, data, key)
    return ok and result ~= false
end

-- datastoreを削除する関数。削除失敗は呼び出し元の保存結果に影響させない。
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param key string datastoreキー
local function deleteDatastore(pd, key)
    pcall(pd.datastore.delete, key)
end

-- 個別リプレイのdatastoreキーを返す関数.
---@param id string リプレイID
---@return string datastoreキー
local function replayDatastoreKey(id)
    return REPLAY_DATASTORE_PREFIX .. id
end

-- リプレイ本体から一覧用メタデータを作る関数.
---@param data table リプレイ本体
---@param id string リプレイID
---@return table 一覧用メタデータ
local function indexEntryFromReplay(data, id)
    return {
        id = id,
        formatVersion = data.formatVersion,
        rulesVersion = data.rulesVersion,
        rngVersion = data.rngVersion,
        mode = data.mode,
        savedAt = data.savedAt,
        favorite = data.favorite == true,
        summary = data.summary or {},
    }
end

-- 保存用の個別リプレイデータを作る関数.
---@param data table 完了したリプレイデータ
---@param id string リプレイID
---@return table 個別リプレイデータ
local function replayDataForStorage(data, id)
    return {
        id = id,
        formatVersion = data.formatVersion,
        rulesVersion = data.rulesVersion,
        rngVersion = data.rngVersion,
        mode = data.mode,
        seed = data.seed,
        events = data.events,
        finalChecksum = data.finalChecksum,
    }
end

-- リプレイ一覧インデックスをdatastoreへ保存する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param indexData table 一覧インデックス
---@return boolean 成功したかどうか
local function writeIndex(pd, indexData)
    return writeDatastore(pd, indexData, INDEX_DATASTORE_KEY)
end

-- 現行の一覧インデックスを読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table? indexData 読み込めない場合はnil
local function readIndex(pd)
    local ok, indexData = pcall(pd.datastore.read, INDEX_DATASTORE_KEY)
    if not ok or type(indexData) ~= "table"
        or indexData.indexVersion ~= INDEX_VERSION
        or type(indexData.entries) ~= "table" then
        return nil
    end

    local nextId = math.floor(tonumber(indexData.nextId) or 1)
    if nextId < 1 then nextId = 1 end
    local entries = {}
    local seenIds = {}
    for _, entry in ipairs(indexData.entries) do
        if isCompatibleIndexEntry(entry) and not seenIds[entry.id] then
            seenIds[entry.id] = true
            table.insert(entries, entry)
            local numericId = tonumber(entry.id)
            if numericId ~= nil then
                nextId = math.max(nextId, math.floor(numericId) + 1)
            end
            if #entries >= Config.MAX_REPLAY_COUNT then break end
        end
    end
    return {
        indexVersion = INDEX_VERSION,
        nextId = nextId,
        entries = entries,
    }
end

-- 旧一括保存形式を読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table[] 互換性のあるリプレイ（新しい順）
local function readLegacyReplays(pd)
    local ok, collection = pcall(pd.datastore.read, COLLECTION_DATASTORE_KEY)
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

    local legacyOk, legacyData = pcall(pd.datastore.read, LEGACY_DATASTORE_KEY)
    if legacyOk and isCompatibleReplay(legacyData) then return { legacyData } end
    return {}
end

-- 旧一括保存形式を個別ファイルと一覧インデックスへ移行する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table? indexData 移行対象がないか失敗した場合はnil
local function migrateLegacyReplays(pd)
    local legacyEntries = readLegacyReplays(pd)
    if #legacyEntries == 0 then return nil end

    local indexData = {
        indexVersion = INDEX_VERSION,
        nextId = #legacyEntries + 1,
        entries = {},
    }
    local writtenKeys = {}
    for index, data in ipairs(legacyEntries) do
        local id = string.format("%08d", index)
        local key = replayDatastoreKey(id)
        if not writeDatastore(pd, replayDataForStorage(data, id), key) then
            for _, writtenKey in ipairs(writtenKeys) do
                deleteDatastore(pd, writtenKey)
            end
            return nil
        end
        table.insert(writtenKeys, key)
        table.insert(indexData.entries, indexEntryFromReplay(data, id))
    end

    if not writeIndex(pd, indexData) then
        for _, writtenKey in ipairs(writtenKeys) do
            deleteDatastore(pd, writtenKey)
        end
        return nil
    end

    deleteDatastore(pd, COLLECTION_DATASTORE_KEY)
    deleteDatastore(pd, LEGACY_DATASTORE_KEY)
    return indexData
end

-- 一覧インデックスを読み、必要なら旧形式から移行する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table indexData
local function loadIndex(pd)
    return readIndex(pd) or migrateLegacyReplays(pd) or {
        indexVersion = INDEX_VERSION,
        nextId = 1,
        entries = {},
    }
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

local function addFlatTableHash(hash, values)
    local keys = {}
    for key in pairs(values or {}) do table.insert(keys, tostring(key)) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        hash = addHash(hash, key)
        hash = addHash(hash, values[key] or values[tonumber(key)])
    end
    return hash
end

-- 中断復元で必要な進行状態を含むチェックサムを計算する関数.
---@param state GameState ゲーム状態
---@param randomGeneratorState integer ランダムジェネレーターの状態
---@return integer チェックサム値
function ReplayController.suspendChecksum(state, randomGeneratorState)
    local hash = ReplayController.checksum(state, randomGeneratorState)
    hash = addHash(hash, state.level)
    hash = addHash(hash, state.levelXp)
    hash = addHash(hash, state.levelDropCount)
    hash = addFlatTableHash(hash, state.levelCreatedMilestones)
    hash = addFlatTableHash(hash, state.levelXpBySource)
    hash = addHash(hash, state.rewindUsesRemaining)
    hash = addHash(hash, state.holdAvailable)
    hash = addHash(hash, state.lastRandomBlockValue)
    hash = addHash(hash, state.consecutiveRandomBlockCount)
    hash = addHash(hash, state.levelRecordEligible)
    hash = addHash(hash, #(state.undoStates or {}))
    for _, snapshot in ipairs(state.undoStates or {}) do
        local restored = snapshot.state or {}
        if restored.board ~= nil then
            for y = 1, Config.BOARD_SIZE do
                for x = 1, Config.BOARD_SIZE do
                    hash = addHash(hash, restored.board:get(x, y))
                end
            end
        end
        hash = addHash(hash, restored.score)
        hash = addHash(hash, restored.cursorX)
        hash = addHash(hash, restored.holdValue)
        hash = addHash(hash, restored.holdAvailable)
        hash = addHash(hash, restored.lastRandomBlockValue)
        hash = addHash(hash, restored.consecutiveRandomBlockCount)
        hash = addHash(hash, restored.randomGeneratorState)
        hash = addHash(hash, restored.level)
        hash = addHash(hash, restored.levelXp)
        hash = addHash(hash, restored.levelDropCount)
        hash = addFlatTableHash(hash, restored.levelCreatedMilestones)
        hash = addFlatTableHash(hash, restored.levelXpBySource)
        for index = 1, Config.NEXT_QUEUE_COUNT do
            hash = addHash(hash, (restored.nextValues or {})[index])
        end
        hash = addHash(hash, snapshot.turn ~= nil
            and snapshot.turn.rotationClockwise or nil)
    end
    return hash
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
        pendingTurnUsedHold = false,
    }, ReplayController)
end

-- 保存済みリプレイの一覧を新しい順で読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table[] 読み込まれたリプレイ一覧
function ReplayController.loadAll(pd)
    return loadIndex(pd).entries
end

-- 中断データを読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return table? 中断データ
function ReplayController.loadSuspend(pd)
    local ok, data = pcall(pd.datastore.read, SUSPEND_DATASTORE_KEY)
    if not ok or not isCompatibleSuspend(data) then return nil end
    return data
end

-- 互換性のある中断データが存在するか判定する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@return boolean
function ReplayController.hasSuspend(pd)
    return ReplayController.loadSuspend(pd) ~= nil
end

-- 中断データを削除する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
function ReplayController.deleteSuspend(pd)
    deleteDatastore(pd, SUSPEND_DATASTORE_KEY)
end

-- IDで指定した個別リプレイを読み込む関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param id string リプレイID
---@return table? 読み込まれたリプレイ本体
function ReplayController.load(pd, id)
    if type(id) ~= "string" then return nil end
    local ok, data = pcall(pd.datastore.read, replayDatastoreKey(id))
    if not ok or not isCompatibleReplay(data) or data.id ~= id then
        local indexData = loadIndex(pd)
        for index, entry in ipairs(indexData.entries) do
            if entry.id == id then
                table.remove(indexData.entries, index)
                if writeIndex(pd, indexData) then
                    deleteDatastore(pd, replayDatastoreKey(id))
                end
                break
            end
        end
        return nil
    end
    return data
end

-- 指定リプレイのお気に入りを切り替える関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param id string リプレイID
---@return boolean 成功したかどうか
function ReplayController.toggleFavorite(pd, id)
    local indexData = loadIndex(pd)
    for _, entry in ipairs(indexData.entries) do
        if entry.id == id then
            entry.favorite = entry.favorite ~= true
            return writeIndex(pd, indexData)
        end
    end
    return false
end

-- 新しいリプレイを一覧へ保存する関数.
---@param pd playdate Playdate SDKのグローバルオブジェクト
---@param data table 新しいリプレイデータ
---@return boolean 成功したかどうか
function ReplayController.save(pd, data)
    local indexData = loadIndex(pd)
    local removeIndex = nil
    if #indexData.entries >= Config.MAX_REPLAY_COUNT then
        for index = #indexData.entries, 1, -1 do
            if indexData.entries[index].favorite ~= true then
                removeIndex = index
                break
            end
        end
        if removeIndex == nil then return false end
    end

    local id = string.format("%08d", indexData.nextId)
    local key = replayDatastoreKey(id)
    if not writeDatastore(pd, replayDataForStorage(data, id), key) then
        return false
    end

    local removedEntry = nil
    if removeIndex ~= nil then
        removedEntry = table.remove(indexData.entries, removeIndex)
    end
    data.favorite = false
    table.insert(indexData.entries, 1, indexEntryFromReplay(data, id))
    indexData.nextId += 1

    if not writeIndex(pd, indexData) then
        deleteDatastore(pd, key)
        return false
    end
    if removedEntry ~= nil then
        deleteDatastore(pd, replayDatastoreKey(removedEntry.id))
    end
    return true
end

-- 記録をキャンセルする関数.
function ReplayController:cancelRecording()
    self.data = nil
    self.recording = false
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.rawHoldCount = 0
    self.pendingTurnUsedHold = false
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
        pendingTurnUsedHold = false,
    }
    self.recording = true
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.rawHoldCount = 0
    self.pendingTurnUsedHold = false
end

-- 中断復元後に既存イベント列を引き継いで記録を再開する関数.
---@param data table 中断データ
function ReplayController:resume(data)
    self.data = data
    self.data.summary = self.data.summary
        or { turnsWithHold = 0, turnsWithoutHold = 0 }
    self.recording = true
    self.decisionStartedAt = nil
    self.decisionWaitMs = 0
    self.lastInputAt = nil
    self.decisionHoldWasEmpty = false
    self.rawHoldCount = 0
    self.pendingTurnUsedHold = self.data.pendingTurnUsedHold == true
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
    local usedHold = holdCount > 0 or self.pendingTurnUsedHold
    table.insert(self.data.events, {
        type = "TURN",
        waitMs = self:getDecisionWait(now),
        targetColumn = targetColumn,
        holdClass = usedHold and "USED" or "NONE",
        holdApplications = holdCount,
        drop = shouldDrop ~= false,
    })
    if usedHold then
        self.data.summary.turnsWithHold += 1
    else
        self.data.summary.turnsWithoutHold += 1
    end
    self.pendingTurnUsedHold = false
    self.data.pendingTurnUsedHold = false
    self:finishDecision()
end

-- DROP前のカーソルとHOLD結果を中断チェックポイントとして記録する関数.
---@param now integer 現在の時刻 (ミリ秒)
---@param targetColumn integer 現在のカーソル列
function ReplayController:recordCheckpoint(now, targetColumn)
    if not self.recording or self.data == nil
        or self.decisionStartedAt == nil then return end
    local holdCount = normalizedHoldCount(
        self.rawHoldCount, self.decisionHoldWasEmpty)
    table.insert(self.data.events, {
        type = "CHECKPOINT",
        waitMs = self:getDecisionWait(now),
        targetColumn = targetColumn,
        holdClass = holdCount == 0 and "NONE" or "USED",
        holdApplications = holdCount,
        drop = false,
    })
    self.pendingTurnUsedHold = self.pendingTurnUsedHold or holdCount > 0
    self.data.pendingTurnUsedHold = self.pendingTurnUsedHold
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
    self.pendingTurnUsedHold = false
    self.data.pendingTurnUsedHold = false
    self:finishDecision()
end

-- 記録中のNORMALを中断データとして保存する関数.
---@param state GameState ゲーム状態
---@param randomGeneratorState integer ランダムジェネレーターの状態
---@param statisticsRun table? 統計上のプレイ状態
---@return boolean 成功したかどうか
function ReplayController:saveSuspend(state, randomGeneratorState, statisticsRun)
    if not self.recording or self.data == nil
        or self.data.mode ~= Config.GAME_MODE.NORMAL then return false end
    self:recordCheckpoint(self.pd.getCurrentTimeMilliseconds(), state.cursorX)
    self.data.suspendVersion = Config.SUSPEND_FORMAT_VERSION
    self.data.savedAt = currentLocalTime(self.pd)
    self.data.levelRecordEligible = state.levelRecordEligible ~= false
    self.data.statisticsRun = statisticsRun
    self.data.checkpointChecksum = ReplayController.suspendChecksum(
        state, randomGeneratorState)
    return writeDatastore(self.pd, self.data, SUSPEND_DATASTORE_KEY)
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
