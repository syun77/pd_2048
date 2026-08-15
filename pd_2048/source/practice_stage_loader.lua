import "game_config"

local pd <const> = playdate
---@class PracticeStageLoader PRACTICEステージのロードを行うクラス.
---@field STAGE_DIRECTORY string ステージファイルのディレクトリパス.
---@field stageNumber fun(filename: string): integer? ステージ番号を取得する関数.
---@field isJapaneseSystemLanguage fun(): boolean システム言語が日本語かどうかを判定する関数.
---@field descriptionForLanguage fun(stage: table, languageKey: string): string 指定された言語のステージ説明を取得する関数.
---@field descriptionForSystemLanguage fun(stage: table): string システム言語に基づいてステージ説明を取得する関数.
---@field loadAll fun(): table[] PRACTICEステージをすべてロードする関数.
local PracticeStageLoader = {}
local STAGE_DIRECTORY <const> = "assets/practice"

-- ステージ番号を取得する関数.
---@param filename string ファイル名
---@return integer? ステージ番号（取得できない場合はnil）
local function stageNumber(filename)
    return tonumber(string.match(filename, "^(%d+)%.json$"))
end

-- システム言語が日本語かどうかを判定する関数.
---@return false|true システム言語が日本語の場合はtrue、それ以外はfalse
local function isJapaneseSystemLanguage()
    if pd.getSystemLanguage == nil then return false end
    local language = tostring(pd.getSystemLanguage() or ""):lower()
    return string.find(language, GameConfig.LANGUAGE.JAPANESE) ~= nil
        or string.find(language, "japanese") ~= nil
end

-- 指定された言語のステージ説明を取得する関数.
---@param stage any ステージ情報.
---@param languageKey LANGUAGE 言語定義文字列.
---@return string ステージ説明テキスト.
function PracticeStageLoader.descriptionForLanguage(stage, languageKey)
    local description = stage ~= nil and stage.description or nil
    if type(description) == "string" then return description end
    if type(description) ~= "table" then return "" end

    local japanese <const> = GameConfig.LANGUAGE.JAPANESE
    local english <const> = GameConfig.LANGUAGE.ENGLISH
    local primaryKey = languageKey == japanese and japanese or english
    local fallbackKey = primaryKey == japanese and english or japanese
    local primary = description[primaryKey]
    if type(primary) == "string" and primary ~= "" then return primary end
    local fallback = description[fallbackKey]
    if type(fallback) == "string" then return fallback end
    return ""
end

function PracticeStageLoader.descriptionForSystemLanguage(stage)
    return PracticeStageLoader.descriptionForLanguage(stage,
        isJapaneseSystemLanguage()
            and GameConfig.LANGUAGE.JAPANESE
            or GameConfig.LANGUAGE.ENGLISH)
end

function PracticeStageLoader.loadAll()
    local stages = {}
    local filenames = pd.file.listFiles(STAGE_DIRECTORY) or {}

    table.sort(filenames, function(a, b)
        return (stageNumber(a) or math.huge) < (stageNumber(b) or math.huge)
    end)

    for _, filename in ipairs(filenames) do
        local number = stageNumber(filename)
        if number ~= nil then
            local path = STAGE_DIRECTORY .. "/" .. filename
            local ok, stage = pcall(json.decodeFile, path)
            if ok and type(stage) == "table" and type(stage.label) == "string" then
                stage.id = stage.id or string.format("%03d", number)
                stage.fileName = filename
                table.insert(stages, stage)
            end
        end
    end

    return stages
end

_G.PracticeStageLoader = PracticeStageLoader
return PracticeStageLoader
