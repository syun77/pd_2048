local DATASTORE_KEYS <const> = {
    "highScore",
    "normalBestLevel",
    "timeAttackBestTimeMs",
    "coreRushBestTimeMs",
    "practiceClearedStages",
    "statistics",
    "achievements",
    "normalSuspend",
    "languageSettings",
}

local REPLAY_INDEX_KEY <const> = "replayIndex"
local REPLAY_KEY_PREFIX <const> = "replay_"

local SaveDataReset = {}

local function deleteDatastore(pd, key)
    local readOk, data = pcall(pd.datastore.read, key)
    if readOk and data == nil then return true end
    local deleteOk, result = pcall(pd.datastore.delete, key)
    return deleteOk and result ~= false
end

---@param pd playdate Playdate SDK.
---@return boolean 全セーブデータの削除に成功したか.
function SaveDataReset.reset(pd)
    local success = true
    local readOk, replayIndex = pcall(pd.datastore.read, REPLAY_INDEX_KEY)
    if readOk and type(replayIndex) == "table"
        and type(replayIndex.entries) == "table" then
        local deletedIds = {}
        for _, entry in ipairs(replayIndex.entries) do
            local id = type(entry) == "table" and entry.id or nil
            if type(id) == "string" and id ~= "" and not deletedIds[id] then
                deletedIds[id] = true
                if not deleteDatastore(pd, REPLAY_KEY_PREFIX .. id) then
                    success = false
                end
            end
        end
    end

    if not deleteDatastore(pd, REPLAY_INDEX_KEY) then success = false end
    for _, key in ipairs(DATASTORE_KEYS) do
        if not deleteDatastore(pd, key) then success = false end
    end
    return success
end

_G.SaveDataReset = SaveDataReset
return SaveDataReset
