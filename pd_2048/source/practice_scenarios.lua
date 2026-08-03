-- 練習モードで使用する固定シナリオ。
-- nextValues は現在ブロックを含む固定生成列で、LOOP で循環する。
local PracticeScenarios = {
    {
        id = "BASIC_MERGE",
        label = "BASIC MERGE",
        initialBoard = {
            { x = 2, y = 3, value = 8 },
            { x = 4, y = 3, value = 8 },
        },
        nextValues = { 2, 2, 4, 8 },
        nextPolicy = "LOOP",
        objectiveMode = "ANY",
        objectives = {
            { type = "TILE_VALUE", value = 64 },
        },
    },
}

_G.PracticeScenarios = PracticeScenarios
return PracticeScenarios
