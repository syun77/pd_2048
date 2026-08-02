-- シーン間で共有する依存関係をまとめるコンテキスト。
local SceneContext = {}

function SceneContext.new(dependencies)
    return dependencies
end

_G.SceneContext = SceneContext
return SceneContext
