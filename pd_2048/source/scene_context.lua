-- シーン間で共有する依存関係をまとめるコンテキスト。
-- ゲーム状態そのものは保持せず、通常モード側の操作をコールバックとして受け取る。
local SceneContext = {}

function SceneContext.new(dependencies)
    return dependencies
end

_G.SceneContext = SceneContext
return SceneContext
