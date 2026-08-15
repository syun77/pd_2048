import "array2d"
import "game_config"

local Config <const> = GameConfig

---@class GameState ゲーム状態クラス.
---@field phase GAME_PHASE 現在のゲームフェーズ.
---@field result GAME_RESULT 現在のゲーム結果.
---@field replayActive boolean リプレイ再生中かどうか.
---@field mode GAME_MODE 現在のゲームモード
---@field board Array2D ゲーム盤面.
---■カーソル関連.
---@field cursorX integer カーソルのX座標 (1始まり)
---@field cursorY integer カーソルのY座標 (1始まり)
---@field cursorRepeatDirection DIRECTION カーソルの連続移動方向 (0:なし, 1:上, 2:右, 3:下, 4:左)
---@field cursorRepeatNextAt integer? カーソルの次の連続移動が発生する時刻 (ミリ秒)
---■NEXT/HOLD関連.
---@field nextValues table<integer, integer> 次に出現する値のキュー
---@field lastRandomBlockValue integer 直前に出現したランダムブロックの値
---@field holdValue integer HOLD中の値
---@field holdAvailable boolean HOLDが可能かどうか.
---@field consecutiveRandomBlockCount integer 連続して出現したランダムブロックの数
---@field holdAnimationSourceValue integer HOLDアニメーションの元の値
---@field holdAnimationReturnValue integer HOLDアニメーションの戻る値
---@field holdAnimationNextValue integer HOLDアニメーションの次の値
---■タイマー関連.
---@field elapsedTimeMs integer 経過時間 (ミリ秒)
---@field remainingTimeMs integer? 残り時間 (ミリ秒)
---@field timerStartedAt integer? タイマーが開始された時刻 (ミリ秒)
---@field timerLastUpdateAt integer? タイマーが最後に更新された時刻 (ミリ秒)
---@field timeoutPending boolean タイムアウトが保留中かどうか
---■メッセージ関連.
---@field message string 現在表示中のメッセージ
---@field messageUntil integer メッセージの表示終了時刻 (ミリ秒)
---■ブロック制御.
---@field pendingDropValue integer ドロップ中のブロックの値
---@field pendingDropX integer? ドロップ中のブロックのX座標
---@field pendingDropY integer? ドロップ中のブロックのY座標
---@field animationProgress number アニメーションの進行度 (0.0 - 1.0)
---@field animationDuration number アニメーションの総時間 (ミリ秒)
---@field rotationEvaluation number 回転評価値
---@field mergeSourceX integer マージ元のX座標
---@field mergeSourceY integer? マージ元のY座標
---@field mergeTargetX integer? マージ先のX座標
---@field mergeTargetY integer? マージ先のY座標
---@field mergeValue integer マージするブロックの値
---@field mergeNextAction string マージ後の次のアクション ("FINISH" または "ROTATE")
---@field activeMergeX integer 現在マージ中のブロックのX座標
---@field activeMergeY integer 現在マージ中のブロックのY座標
---■回転アニメーション関連
---@field rotationClockwise boolean 回転方向が時計回りかどうか
---@field rotationStartBoard Array2D 回転開始時の盤面
---@field rotationEndBoard Array2D 回転終了時の盤面
---@field hasRotation boolean 回転アニメーションがあるかどうか
---■UNDO関連.
---@field undoStates table<integer, GameState> UNDO用のゲーム状態の履歴.
---@field rewindUsesRemaining integer リワインドの残り使用回数.
---@field rewindHoldStartedAt integer? HOLD巻き戻しが開始された時刻 (ミリ秒)
---@field rewindHoldTriggered boolean HOLD巻き戻しがトリガーされたかどう
---■スコア関連.
---@field score integer 現在のスコア
---@field highScore integer ハイスコア
---@field normalHighScore integer ノーマルモードのハイスコア
---■レベル関連.
---@field level integer 現在のレベル
---@field levelXp integer 現在のレベルでの経験値
---@field levelDropCount integer 現在のレベルでのドロップ数
---@field levelCreatedMilestones table<integer, boolean> 現在のレベルで作成されたマイルストーンの記録
---@field levelXpBySource table<"drop" | "merge" | "firstTile" | "combo", integer> 経験値のソースごとの累計
---@field levelUpFrom integer レベルアップ前のレベル.
---@field levelUpTo integer レベルアップ後のレベル
---@field levelUpDisplayFrame integer レベルアップ表示の経過フレーム数
---@field normalBestLevel integer ノーマルモードの最高レベル
---@field levelNewBest boolean レベルアップ時に新記録かどうか
---@field levelRecordEligible boolean レベルアップ時に記録対象かどうか
---■コンボ関連.
---@field combo integer 現在のコンボ数
---@field comboBonusScore integer 現在のコンボボーナススコア
---@field comboDisplayFrame integer コンボ表示のフレーム数
---@field comboSoundPlayed boolean コンボサウンドが再生済みかどうか
---@field rewindHoldAnimationActive boolean HOLD巻き戻しアニメーションがアクティブかどうか
---■演出制御.
---@field startReadyUntil integer ゲーム開始前の準備演出の終了時刻
---@field nextAnimationGameOver boolean 次のアニメーションでゲームオーバーになるかどうか
---@field previewImpulseRotationDegrees number プレビューのインパルス回転角度
---■BGM制御.
---@field crisisBgmActive boolean 危機BGMがアクティブかどうか
---■PRACTICEモード関連.
---@field practiceObjectiveText string PRACTICEモードでのクリア目標のテキスト
---@field practiceClearedStages table<integer, boolean> PRACTICEモードでクリア済みのステージの記録
---@field practiceScenarioId integer PRACTICEモードでのシナリオID
---@field practiceNextValues table<integer, integer> PRACTICEモードでの次に出現する値のキュー
---@field practiceNextIndex integer PRACTICEモードでの次に出現する値のインデックス
---@field practiceSpawnCount integer PRACTICEモードでの出現済みのブロック数
---@field practiceNextPolicy string PRACTICEモードでの次に出現する値のポリシー
---@field practiceNextExhausted boolean PRACTICEモードでの次に出現する値のキューが尽きたかどうか
---@field practiceTurnLimit integer PRACTICEモードでのターン制限
---@field practiceTurnCount integer PRACTICEモードでの現在のターン数
---@field practiceObjectives table<integer, any> PRACTICEモードでのクリア目標のリスト
---@field practiceObjectiveMode string PRACTICEモードでのクリア目標の達成条件 ("ANY" または "ALL")
---@field practiceMergeCount integer PRACTICEモードでのマージ回数
---@field practiceVictoryPending boolean PRACTICEモードでのクリア演出が保留中かどうか
---@field practiceCompleteUntil integer PRACTICEモードでのクリア演出の終了時刻
---@field practiceDescriptionText string PRACTICEモードでのシナリオの説明テキスト
---■実績関連.
---@field timeAttackBestTimeMs integer タイムアタックモードでの最短クリア時間（ミリ秒）
---@field coreRushBestTimeMs integer コアラッシュモードでの最短クリア時間（ミリ秒）
---@field coreRushValue integer コアラッシュモードでの現在の値
---@field coreRushGainCombo integer コアラッシュモードでのコンボによる獲得値
---@field coreRushGainMergeValue integer コアラッシュモードでのマージによる獲得値
---@field coreRushGainTotal integer コアラッシュモードでの合計�獲得値
---@field coreRushGainUntil integer コアラッシュモードでの獲得値表示の終了時刻
---@field coreRushCompleteUntil integer コアラッシュモードでのクリア演出の終了時刻
---@field coreRushVictoryPending boolean コアラッシュモードでのクリア演出が保留中かどうか
---@field timeAttackVictoryPending boolean タイムアタックモードでのクリア演出が保留中かどうか
local GameState = {}

function GameState.new()
    local self = {
        board = Array2D(Config.BOARD_SIZE, Config.BOARD_SIZE, 0),
        cursorX = Config.CENTER,
        nextValues = {},
        score = 0,
        highScore = 0,
        normalHighScore = 0,
        level = 1,
        levelXp = 0,
        levelDropCount = 0,
        levelCreatedMilestones = {},
        levelXpBySource = { drop = 0, merge = 0, firstTile = 0, combo = 0 },
        levelUpFrom = 0,
        levelUpTo = 0,
        levelUpDisplayFrame = Config.LEVEL_UP_DISPLAY_FRAMES,
        normalBestLevel = 1,
        levelNewBest = false,
        levelRecordEligible = true,
        timeAttackBestTimeMs = nil,
        coreRushBestTimeMs = nil,
        coreRushValue = 0,
        coreRushGainCombo = 0,
        coreRushGainMergeValue = 0,
        coreRushGainTotal = 0,
        coreRushGainUntil = 0,
        coreRushCompleteUntil = 0,
        coreRushVictoryPending = false,
        timeAttackVictoryPending = false,
        mode = Config.GAME_MODE.NORMAL,
        practiceClearedStages = {},
        practiceScenarioId = nil,
        practiceNextValues = {},
        practiceNextIndex = 1,
        practiceSpawnCount = 0,
        practiceNextPolicy = nil,
        practiceNextExhausted = false,
        practiceTurnLimit = 0,
        practiceTurnCount = 0,
        practiceObjectives = {},
        practiceObjectiveMode = "ANY",
        practiceMergeCount = 0,
        practiceVictoryPending = false,
        practiceCompleteUntil = 0,
        practiceObjectiveText = "",
        practiceDescriptionText = "",
        elapsedTimeMs = 0,
        remainingTimeMs = nil,
        timerStartedAt = nil,
        timerLastUpdateAt = nil,
        timeoutPending = false,
        startReadyUntil = 0,
        holdValue = 0,
        holdAvailable = true,
        lastRandomBlockValue = 0,
        consecutiveRandomBlockCount = 0,
        undoStates = {},
        rewindUsesRemaining = 0,
        combo = 0,
        comboBonusScore = 0,
        comboDisplayFrame = 0,
        comboSoundPlayed = false,
        phase = Config.GAME_PHASE.INPUT,
        result = nil,
        replayActive = false,
        message = "",
        messageUntil = 0,
        animationProgress = 0,
        animationDuration = 0,
        pendingDropX = 0, pendingDropY = 0, pendingDropValue = 0,
        rotationStartBoard = nil, rotationEndBoard = nil, rotationClockwise = false,
        mergeSourceX = 0, mergeSourceY = 0, mergeTargetX = 0, mergeTargetY = 0,
        mergeValue = 0, mergeNextAction = "FINISH",
        activeMergeX = 0, activeMergeY = 0,
        nextAnimationGameOver = false,
        holdAnimationSourceValue = 0, holdAnimationReturnValue = 0,
        holdAnimationNextValue = 0,
        rewindHoldAnimationActive = false,
        rotationEvaluation = 0,
        previewImpulseRotationDegrees = 0,
        crisisBgmActive = false,
        rewindHoldStartedAt = nil,
        rewindHoldTriggered = false,
        cursorRepeatDirection = 0,
        cursorRepeatNextAt = nil,
    }
    for i = 1, Config.NEXT_QUEUE_COUNT do
        self.nextValues[i] = 2
    end
    return self
end

function GameState:isAnimating()
    local s = self.phase
    local states = Config.GAME_PHASE
    return s == states.DROPPING or s == states.MERGING or s == states.ROTATING
        or s == states.UNDO_ROTATING or s == states.NEXT_ANIM or s == states.HOLD_ANIM
end

_G.GameState = GameState
return GameState
