local pd <const> = playdate
local PracticeStageLoader = {}
local STAGE_DIRECTORY <const> = "assets/practice"

local function stageNumber(filename)
    return tonumber(string.match(filename, "^(%d+)%.json$"))
end

local function isJapaneseSystemLanguage()
    if pd.getSystemLanguage == nil then return false end
    local language = tostring(pd.getSystemLanguage() or ""):lower()
    return string.find(language, "ja") ~= nil
        or string.find(language, "japanese") ~= nil
end

function PracticeStageLoader.descriptionForSystemLanguage(stage)
    local description = stage ~= nil and stage.description or nil
    if type(description) == "string" then return description end
    if type(description) ~= "table" then return "" end

    local primaryKey = isJapaneseSystemLanguage() and "ja" or "en"
    local fallbackKey = primaryKey == "ja" and "en" or "ja"
    local primary = description[primaryKey]
    if type(primary) == "string" and primary ~= "" then return primary end
    local fallback = description[fallbackKey]
    if type(fallback) == "string" then return fallback end
    return ""
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
