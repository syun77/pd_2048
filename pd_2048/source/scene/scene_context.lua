---@class SceneContext シーン間で共有する依存関係をまとめるコンテキスト。
---@field game GameController ゲームコントローラー.
---@field achievementManager AchievementManager 実績判定と通知キューの管理.
---@field renderer GameRenderer ゲーム描画クラス.
---@field titleRenderer TitleRenderer タイトルメニューの描画.
---@field menuBackground MenuBackgroundRenderer メニューバックグラウンド描画クラス.
---@field language LanguageManager 表示言語の管理クラス.
---@field sound Sound サウンド管理.
---@field systemMenu SystemMenuController システムメニューコントローラー.
local SceneContext = {}

-- 生成
---@param dependencies SceneContext シーン間で共有する依存関係.
---@return SceneContext シーン間で共有する依存関係をまとめるコンテキスト.
function SceneContext.new(dependencies)
    return dependencies
end

_G.SceneContext = SceneContext
return SceneContext
