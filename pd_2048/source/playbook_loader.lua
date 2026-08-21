import "game_config"

local pd <const> = playdate

---@class PlaybookLoader PLAYBOOK定義の読み込みとローカライズを行うクラス.
local PlaybookLoader = {}
local PLAYBOOK_PATH <const> = "assets/playbook/playbooks.json"
local IMAGE_DIRECTORY <const> = "assets/playbook"
local FORMAT_VERSION <const> = 1

local function isJapaneseSystemLanguage()
    if pd.getSystemLanguage == nil then return false end
    local language = tostring(pd.getSystemLanguage() or ""):lower()
    return string.find(language, GameConfig.LANGUAGE.JAPANESE) ~= nil
        or string.find(language, "japanese") ~= nil
end

---@param value any 日英ローカライズ文字列.
---@param languageKey LANGUAGE 優先言語.
---@return string ローカライズ済み文字列.
function PlaybookLoader.localizedText(value, languageKey)
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return "" end

    local japanese <const> = GameConfig.LANGUAGE.JAPANESE
    local english <const> = GameConfig.LANGUAGE.ENGLISH
    local primaryKey = languageKey == japanese and japanese or english
    local fallbackKey = primaryKey == japanese and english or japanese
    local primary = value[primaryKey]
    if type(primary) == "string" and primary ~= "" then return primary end
    local fallback = value[fallbackKey]
    if type(fallback) == "string" then return fallback end
    return ""
end

function PlaybookLoader.systemLanguageKey()
    return isJapaneseSystemLanguage()
        and GameConfig.LANGUAGE.JAPANESE
        or GameConfig.LANGUAGE.ENGLISH
end

local function isUnlocked(unlockNo, unlockedNumbers)
    if unlockNo == 0 then return true end
    if type(unlockNo) ~= "number" or unlockNo < 1 then return false end
    if type(unlockedNumbers) ~= "table" then return false end
    return unlockedNumbers[unlockNo] == true
        or unlockedNumbers[tostring(unlockNo)] == true
end

local function normalizePage(page, languageKey)
    if type(page) ~= "table" or type(page.image) ~= "string"
        or page.image == "" then return nil end
    local description = PlaybookLoader.localizedText(
        page.description, languageKey)
    if description == "" then return nil end
    return {
        image = page.image,
        imagePath = IMAGE_DIRECTORY .. "/" .. page.image,
        description = description,
    }
end

local function normalizeHint(hint, languageKey, unlockedNumbers)
    if type(hint) ~= "table" or type(hint.id) ~= "string"
        or not isUnlocked(hint.unlockNo, unlockedNumbers)
        or type(hint.pages) ~= "table" then return nil end
    local title = PlaybookLoader.localizedText(hint.title, languageKey)
    if title == "" then return nil end

    local pages = {}
    for _, page in ipairs(hint.pages) do
        local normalized = normalizePage(page, languageKey)
        if normalized ~= nil then table.insert(pages, normalized) end
    end
    if #pages == 0 then return nil end
    return {
        id = hint.id,
        unlockNo = hint.unlockNo,
        title = title,
        label = title,
        pages = pages,
    }
end

---@param unlockedNumbers table|nil 取得済みアンロック番号の集合.
---@return table[] 表示可能なPLAYBOOKヒント.
function PlaybookLoader.loadVisible(unlockedNumbers)
    local ok, data = pcall(json.decodeFile, PLAYBOOK_PATH)
    if not ok or type(data) ~= "table" or data.version ~= FORMAT_VERSION
        or type(data.playbooks) ~= "table" then
        print("PlaybookLoader: failed to load " .. PLAYBOOK_PATH)
        return {}
    end

    local languageKey = PlaybookLoader.systemLanguageKey()
    local hints = {}
    for _, hint in ipairs(data.playbooks) do
        local normalized = normalizeHint(hint, languageKey, unlockedNumbers)
        if normalized ~= nil then table.insert(hints, normalized) end
    end
    return hints
end

_G.PlaybookLoader = PlaybookLoader
return PlaybookLoader
