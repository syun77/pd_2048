import "game_config"

local pd <const> = playdate

---@class LanguageManager 表示言語の読み込み・保存を行うクラス.
---@field language LANGUAGE 現在の表示言語.
local LanguageManager = {}
LanguageManager.__index = LanguageManager

local DATASTORE_KEY <const> = "languageSettings"

local function isSupported(language)
    return language == GameConfig.LANGUAGE.ENGLISH
        or language == GameConfig.LANGUAGE.JAPANESE
end

local function systemLanguage()
    if pd.getSystemLanguage == nil then
        return GameConfig.LANGUAGE.ENGLISH
    end
    local language = tostring(pd.getSystemLanguage() or ""):lower()
    if language == "jp"
        or string.find(language, GameConfig.LANGUAGE.JAPANESE) ~= nil
        or string.find(language, "japanese") ~= nil then
        return GameConfig.LANGUAGE.JAPANESE
    end
    return GameConfig.LANGUAGE.ENGLISH
end

function LanguageManager.new()
    local language = nil
    local ok, data = pcall(pd.datastore.read, DATASTORE_KEY)
    if ok and type(data) == "table" and isSupported(data.language) then
        language = data.language
    end
    return setmetatable({ language = language or systemLanguage() }, LanguageManager)
end

---@return LANGUAGE 現在の表示言語.
function LanguageManager:get()
    return self.language
end

---@param language LANGUAGE 設定する表示言語.
---@return boolean 言語を設定できたか.
function LanguageManager:set(language)
    if not isSupported(language) then return false end
    self.language = language
    local ok, result = pcall(pd.datastore.write,
        { language = language }, DATASTORE_KEY)
    return ok and result ~= false
end

_G.LanguageManager = LanguageManager
return LanguageManager
