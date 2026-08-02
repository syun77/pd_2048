import "CoreLibs/graphics"
import "array2d"
import "game_context"
import "game_config"
import "game_state"
import "game/merge_resolver"
import "game/game_session"
import "game/undo_controller"
import "board/board_transform"
import "tile_generator"
import "board/board_rules"
import "cursor_controller"
import "input/input_command"
import "input/auto_player"
import "render/game_renderer"
import "render/overlay_renderer"
import "turn_resolver"
import "scene/scene_manager"
import "scene/scene_context"
import "scene/scene_title"
import "scene/scene_game_normal"
import "scene/scene_game_over"

local pd <const> = playdate
local gfx <const> = pd.graphics
local gameContext <const> = GameContext.getInstance()
local sound <const> = gameContext.sound
local Config <const> = GameConfig
local cursorController <const> = CursorController.new()
local autoPlayer <const> = AutoPlayer.new()
local autoPlayEnabled = false

local DEFAULT_REFRESH_RATE <const> = Config.DEFAULT_REFRESH_RATE -- ディスプレイの更新レート (FPS。フレーム毎秒).
local CURSOR_KEY_REPEAT_INITIAL_DELAY_MS <const> = Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS -- 左右キーを押し続けたとき、最初にリピートするまでの待ち時間.
local CURSOR_KEY_REPEAT_INTERVAL_MS <const> = Config.CURSOR_KEY_REPEAT_INTERVAL_MS -- 左右キーを押し続けたときのリピート間隔.
local BOARD_SIZE <const> = Config.BOARD_SIZE
local CENTER <const> = Config.CENTER
-- 落下対象を除いたブロックを表示するため、表示数より1つ多く保持する.
local NEXT_QUEUE_COUNT <const> = Config.NEXT_QUEUE_COUNT
local MAX_REWIND_USES <const> = Config.MAX_REWIND_USES
local REWIND_HOLD_DURATION_MS <const> = Config.REWIND_HOLD_DURATION_MS
-- コンボ表示時間.
local Scene <const> = Config.SCENE
local GamePhase <const> = Config.GAME_PHASE
local GameResult <const> = Config.GAME_RESULT
local PREVIEW_ROTATION_MAX_DEGREES <const> = Config.PREVIEW_ROTATION_MAX_DEGREES
local PREVIEW_ROTATION_EVALUATION_MULTIPLIER <const> = Config.PREVIEW_ROTATION_EVALUATION_MULTIPLIER
local PREVIEW_IMPULSE_ROTATION_DEGREES <const> = Config.PREVIEW_IMPULSE_ROTATION_DEGREES
-- 回転方向の評価値.
local ROTATION_EVALUATION_POSITION_CENTER <const> = Config.ROTATION_EVALUATION_POSITION_CENTER -- 中央の位置を評価する値.
local ROTATION_EVALUATION_DROP_POSITION_WEIGHT <const> = Config.ROTATION_EVALUATION_DROP_POSITION_WEIGHT -- 落下位置の評価値の重み.
local ROTATION_EVALUATION_MERGE_DIRECTION_LEFT <const> = Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT -- マージ方向の評価値 (左方向).
local ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT <const> = Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT -- マージ方向の評価値 (右方向).
local state = GameState.new()
local finishHoldAnimation

-- メニューBGMの再生.
local function playMenuBgm()
    sound:setBgmRandomMode(BGMRandomMode.MENU)
    sound:play_bgm(-1, false)
end

-- メインゲームBGMの再生.
local function playGameBgm()
    sound:setBgmRandomMode(BGMRandomMode.NOMAL)
    sound:play_bgm(-1, false)
end

-- 方向の力を一時的なプレビュー反動として加算する.
local function addPreviewImpulse(direction)
    if direction == ROTATION_EVALUATION_POSITION_CENTER then
        return
    end
    if direction > 0 then
        state.previewImpulseRotationDegrees += PREVIEW_IMPULSE_ROTATION_DEGREES
    else
        state.previewImpulseRotationDegrees -= PREVIEW_IMPULSE_ROTATION_DEGREES
    end
end

local function addRotationEvaluation(value)
	-- 加算倍率を適用.
	value *= PREVIEW_ROTATION_EVALUATION_MULTIPLIER
    state.rotationEvaluation += value
	--print("state.rotationEvaluation"	 .. state.rotationEvaluation)
	-- 傾き制限を適用.
	state.rotationEvaluation = math.max(-PREVIEW_ROTATION_MAX_DEGREES,
		math.min(PREVIEW_ROTATION_MAX_DEGREES, state.rotationEvaluation))
end

local function setMessage(text, duration)
    state.message = text
    state.messageUntil = pd.getCurrentTimeMilliseconds() + duration
end

local gameSession = GameSession.new(state)
local undoController = UndoController.new({
    state = state,
    session = gameSession,
    sound = sound,
    setMessage = setMessage,
})

-- ハイスコアのロード.
local function loadHighScore()
    local ok, value = pcall(pd.datastore.read, "highScore")
    if ok and type(value) == "number" then
        state.highScore = value
    end
end

-- ハイスコアの保存.
local function saveHighScore()
    if state.score > state.highScore then
        state.highScore = state.score
        pd.datastore.write(state.highScore, "highScore")
    end
end

-- 盤面を初期化する.
local function clearBoard()
    state.board = Array2D(BOARD_SIZE, BOARD_SIZE, 0)
    state.board:set(CENTER, CENTER, 0)
end

-- Bボタン長押しによる巻き戻し入力を開始する。
local function beginRewindHold()
    if not undoController:isAvailable() then
		-- 巻き戻しはできない.
		if state.rewindUsesRemaining <= 0 then
            setMessage("NO REWINDS", 700)
        else
            setMessage("NO UNDO", 700)
        end
		sound:play_se("error")
        return
    end
    state.rewindHoldStartedAt = pd.getCurrentTimeMilliseconds()
    state.rewindHoldTriggered = false
	sound:play_se("rewind_button")
end

-- Bボタン長押しによる巻き戻し入力を終了する。
local function endRewindHold()
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
end

-- Bボタンの長押し時間を更新し、
-- 1秒 (REWIND_HOLD_DURATION_MS) 到達時にUNDOを実行する。
local function updateRewindHold()
    if not undoController:isAvailable() then
        endRewindHold()
        return
    end

    if state.rewindHoldStartedAt == nil or not pd.buttonIsPressed(pd.kButtonB) then
        if state.rewindHoldStartedAt ~= nil then
			-- 長押し完了.
            endRewindHold()
        end
        return
    end

    if not state.rewindHoldTriggered
        and pd.getCurrentTimeMilliseconds() - state.rewindHoldStartedAt >= REWIND_HOLD_DURATION_MS then
        state.rewindHoldTriggered = true
        undoController:restore()
    end
end

-- 落下可能なセルを見つける.
local function findDropCell(x)
    return BoardRules.findDropCell(state.board, x)
end

-- 現在のカーソル位置からブロックを落とせるかどうかを判定する.
local function isDropAvailable()
    return findDropCell(state.cursorX) ~= nil
end

-- 中心軸を空けておく.
local function applyGravity()
    -- 中心軸は見えない固定ブロックとして常に空けておく。
    state.board:set(CENTER, CENTER, 0)
end

local function canDropInAnyColumn()
    return BoardRules.canDropInAnyColumn(state.board)
end

-- 外周の各辺について、準危険状態と危険状態を判定する.
local function getDangerEdges()
    local bottomCount = 0
    for x = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, x, BOARD_SIZE) then
            bottomCount += 1
        end
    end

    local leftCount = 0
    local rightCount = 0
    for y = 1, BOARD_SIZE do
        if BoardRules.isOccupied(state.board, 1, y) then
            leftCount += 1
        end
        if BoardRules.isOccupied(state.board, BOARD_SIZE, y) then
            rightCount += 1
        end
    end

    return bottomCount >= 4, bottomCount == BOARD_SIZE,
        leftCount >= 4, leftCount == BOARD_SIZE,
        rightCount >= 4, rightCount == BOARD_SIZE
end

-- 次の手番のブロックを配り、先読みキューを更新する.
-- 落下開始時ではなく、マージ・回転まで完了した手番の切り替え時に行う.
local function advanceNextQueue()
    for i = 1, NEXT_QUEUE_COUNT - 1 do
        state.nextValues[i] = state.nextValues[i + 1]
    end
    state.nextValues[NEXT_QUEUE_COUNT] = TileGenerator.nextForState(state.board, state)
end

local function finishTurn()
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    -- ブロックを落として手が完了したので、次の手でHOLD可能にする.
    state.holdAvailable = true
    advanceNextQueue()
    state.nextAnimationGameOver = not canDropInAnyColumn()
    state.animationProgress = 0
    state.animationDuration = 0.30
    state.phase = GamePhase.NEXT_ANIM
end

-- ゲームオーバー開始.
local function beginGameOver()
	saveHighScore()
	state.result = GameResult.GAME_OVER
	state.phase = GamePhase.INPUT
	sound:play_se("gameover")
	sound:stop_bgm(1.0)
end

local function finishNextAnimation()
    if state.nextAnimationGameOver then
		-- ゲームオーバー開始.
		beginGameOver()
    else
        state.phase = GamePhase.INPUT
    end
end

-- 回転開始.
local function startRotation()
    if state.rotationEvaluation == 0 then
        finishTurn()
        return
    end

    state.rotationClockwise = state.rotationEvaluation > 0
    local latestUndoState = state.undoStates[#state.undoStates]
    if latestUndoState ~= nil then
        latestUndoState.hasRotation = true
        latestUndoState.rotationClockwise = state.rotationClockwise
    end
    state.rotationStartBoard = state.board
    state.rotationEndBoard = BoardTransform.rotate(
        state.rotationStartBoard, state.rotationClockwise, BoardRules.isPlayable)

    local oldActiveX = state.activeMergeX
    local oldActiveY = state.activeMergeY
    if state.rotationClockwise then
        state.activeMergeX = BOARD_SIZE + 1 - oldActiveY
        state.activeMergeY = oldActiveX
    else
        state.activeMergeX = oldActiveY
        state.activeMergeY = BOARD_SIZE + 1 - oldActiveX
    end

    state.animationProgress = 0
    state.animationDuration = 0.38
    sound:play_se("rotate")
    state.phase = GamePhase.ROTATING
end

-- 連鎖が確定した時点でコンボSEを再生する.
local function playComboSoundIfNeeded()
    if state.combo < 2 or state.comboSoundPlayed then
        return
    end

    state.comboSoundPlayed = true
    state.comboDisplayFrame = 0
    if state.combo < 3 then
        sound:play_se("combo1")
    elseif state.combo < 5 then
        sound:play_se("combo2")
    else
        sound:play_se("combo3")
    end
end

local function startResolve(nextAction)
    applyGravity()
    local x1, y1, x2, y2 = MergeResolver.findForActive(
        state.board, state.activeMergeX, state.activeMergeY)
    if x1 == nil then
        if nextAction == "ROTATE" then
            -- これ以上マージが発生しないことが確定した直後に再生する.
            -- 回転アニメーション開始より前になる.
            playComboSoundIfNeeded()
            startRotation()
        else
            -- 回転後に初めてコンボが成立した場合はこちらで再生する.
            playComboSoundIfNeeded()
            finishTurn()
        end
        return
    end

	-- マージ開始.
    state.mergeSourceX = x1
    state.mergeSourceY = y1
    state.mergeTargetX = x2
    state.mergeTargetY = y2
    state.mergeValue = state.board:get(x1, y1) * 2
    state.mergeNextAction = nextAction
    state.animationProgress = 0
    state.animationDuration = 0.22
	sound:play_se("merge")
    state.phase = GamePhase.MERGING
end

local function finishMerge()
    local v = MergeResolver.getEvaluation(state.mergeSourceX, state.mergeTargetX)
    addRotationEvaluation(v)
    if state.mergeTargetX < state.mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_LEFT)
    elseif state.mergeTargetX > state.mergeSourceX then
        addPreviewImpulse(ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT)
    end
    state.board:set(state.mergeSourceX, state.mergeSourceY, 0)
    state.board:set(state.mergeTargetX, state.mergeTargetY, state.mergeValue)
    gameSession:recordMerge(state.mergeValue)

    state.activeMergeX = state.mergeTargetX
    state.activeMergeY = state.mergeTargetY
    startResolve(state.mergeNextAction)
end

-- 落下完了.
local function finishDrop()
    state.board:set(state.pendingDropX, state.pendingDropY, state.pendingDropValue)
    state.pendingDropValue = 0
    state.activeMergeX = state.pendingDropX
    state.activeMergeY = state.pendingDropY
    addRotationEvaluation(ROTATION_EVALUATION_DROP_POSITION_WEIGHT
        * MergeResolver.getPositionEvaluation(state.pendingDropX)
    )
    addPreviewImpulse(MergeResolver.getPositionEvaluation(state.pendingDropX))
    startResolve("ROTATE")
	if state.phase ~= GamePhase.MERGING then
		sound:play_se("fixed")
	end
end

local function advanceAnimation()
    local context = {
        previewImpulseRotationDegrees = state.previewImpulseRotationDegrees,
        animationProgress = state.animationProgress,
        animationDuration = state.animationDuration,
        refreshRate = DEFAULT_REFRESH_RATE,
        phase = state.phase,
        board = state.board,
        rotationEndBoard = state.rotationEndBoard,
        finishDrop = finishDrop,
        finishMerge = finishMerge,
        startResolve = startResolve,
        finishNextAnimation = finishNextAnimation,
        finishHoldAnimation = finishHoldAnimation,
        setPhase = function(value) state.phase = value end,
        setBoard = function(value) state.board = value end,
    }
    TurnResolver.advance(context)
    if not context.completed then
        state.previewImpulseRotationDegrees = context.previewImpulseRotationDegrees
        state.animationProgress = context.animationProgress
        state.board = context.board
        state.rotationEndBoard = context.rotationEndBoard
    elseif context.phase == GamePhase.ROTATING
        or context.phase == GamePhase.UNDO_ROTATING then
        state.board = context.board
        state.rotationEndBoard = context.rotationEndBoard
    end
end

local function spawnInitialBlocks()
    -- Start with one value-8 block immediately to each side of the rotation axis.
    -- Coordinates are 1-based: the axis is (3, 3), so the two cells are
    -- (2, 3) and (4, 3).
    state.board:set(CENTER - 1, CENTER, 8)
    state.board:set(CENTER + 1, CENTER, 8)
end

local function startGame()
    clearBoard()
    state.result = nil
    state.score = 0
    state.holdValue = 0
    state.holdAvailable = true
    state.lastRandomBlockValue = 0
    state.consecutiveRandomBlockCount = 0
    state.undoStates = {}
    state.rewindUsesRemaining = MAX_REWIND_USES
    gameSession:resetCombo()
    state.cursorX = CENTER
    state.rewindHoldStartedAt = nil
    state.rewindHoldTriggered = false
    state.rewindHoldAnimationActive = false
    state.animationProgress = 0
    state.animationDuration = 0
    state.pendingDropX = 0
    state.pendingDropY = 0
    state.pendingDropValue = 0
    state.rotationStartBoard = nil
    state.rotationEndBoard = nil
    state.rotationClockwise = false
    state.mergeSourceX = 0
    state.mergeSourceY = 0
    state.mergeTargetX = 0
    state.mergeTargetY = 0
    state.mergeValue = 0
    state.mergeNextAction = "FINISH"
    state.activeMergeX = 0
    state.activeMergeY = 0
    state.nextAnimationGameOver = false
    state.holdAnimationSourceValue = 0
    state.holdAnimationReturnValue = 0
    state.rotationEvaluation = 0
    state.nextValues = {}
    autoPlayer:reset()
    for i = 1, NEXT_QUEUE_COUNT do
        state.nextValues[i] = TileGenerator.nextForState(state.board, state)
    end
    state.previewImpulseRotationDegrees = 0
    spawnInitialBlocks()
    state.phase = GamePhase.INPUT
    state.message = ""
    state.crisisBgmActive = false
    playGameBgm()
end

-- 現在のブロックをHOLDする。HOLD自体を1手として履歴に保存する.
local function holdCurrentBlock()
    if not state.holdAvailable then
        sound:play_se("error")
        setMessage("HOLD USED", 700)
        return
    end

    undoController:save("HOLD")

    local currentValue = state.nextValues[1]
    state.holdAnimationSourceValue = currentValue
    state.holdAnimationReturnValue = state.holdValue
    if state.holdValue == 0 then
        -- 初回は現在ブロックをHOLDし、NEXTの先頭を現在ブロックにする.
        state.holdValue = currentValue
        advanceNextQueue()
    else
        -- HOLD済みの場合は現在ブロックと交換する.
        state.holdValue, state.nextValues[1] = currentValue, state.holdValue
    end

    state.holdAvailable = false
    state.rewindHoldAnimationActive = false
    sound:play_se("hold")

    state.animationProgress = 0
    state.animationDuration = 0.30
    state.phase = GamePhase.HOLD_ANIM
end

-- HOLDアニメーションを終了し、HOLDで出現したブロックの配置可能性を確認する.
finishHoldAnimation = function()
    state.holdAnimationSourceValue = 0
    state.holdAnimationReturnValue = 0
    state.rewindHoldAnimationActive = false
    if not canDropInAnyColumn() then
        beginGameOver()
    else
        state.phase = GamePhase.INPUT
    end
end

-- 落下開始.
local function beginDrop()
    if not isDropAvailable() then
        setMessage("NO SPACE", 700)
		sound:play_se("error")
        return
    end

    local x, y = findDropCell(state.cursorX)

    -- 落下開始.
    undoController:save("DROP")
    gameSession:resetCombo()
    state.pendingDropX = x
    state.pendingDropY = y
    state.pendingDropValue = state.nextValues[1]
    state.rotationEvaluation = 0
    state.animationProgress = 0
    state.animationDuration = math.max(0.18, (y + 1) * 0.07)
	sound:play_se("fall")
    state.phase = GamePhase.DROPPING
end

-- カーソルを移動.
local function moveCursor(delta)
	local prev = state.cursorX
    state.cursorX += delta
    if state.cursorX < 1 then
        state.cursorX = 1
    elseif state.cursorX > BOARD_SIZE then
        state.cursorX = BOARD_SIZE
    end

	if prev ~= state.cursorX then
		-- 移動した.
		sound:play_se("pi")
	end
end

-- 左右キーのリピート状態を解除する.
local function resetCursorKeyRepeat()
    CursorController.reset(cursorController)
    state.cursorRepeatDirection = 0
    state.cursorRepeatNextAt = nil
end

-- 左右キーの押しっぱなしによるカーソル移動を処理する.
local function updateCursorKeyRepeat()
    CursorController.update(cursorController, pd, pd.getCurrentTimeMilliseconds(), moveCursor)
    state.cursorRepeatDirection = cursorController.direction
    state.cursorRepeatNextAt = cursorController.nextAt
end

-- ゲームシーンを1フレーム進める。Sceneからゲーム内部状態を隠す窓口。
local function updateGame()
    if state.phase ~= GamePhase.INPUT then
        resetCursorKeyRepeat()
    end

    if state.phase == GamePhase.INPUT then
        if autoPlayEnabled then
            local command = autoPlayer:poll(nil, {
                phase = state.phase,
                cursorX = state.cursorX,
                nextValue = state.nextValues[1],
                holdValue = state.holdValue,
                holdAvailable = state.holdAvailable,
                getCandidates = function(activeValue)
                    return MergeResolver.getAutoPlayCandidates(state.board, activeValue)
                end,
            })
            if command == InputCommand.HOLD then
                holdCurrentBlock()
            elseif command == InputCommand.MOVE_LEFT then
                moveCursor(-1)
            elseif command == InputCommand.MOVE_RIGHT then
                moveCursor(1)
            elseif command == InputCommand.DROP then
                beginDrop()
            end
        else
            updateRewindHold()
            if pd.buttonJustPressed(pd.kButtonA) then
                holdCurrentBlock()
            elseif pd.buttonJustPressed(pd.kButtonLeft)
                or pd.buttonJustPressed(pd.kButtonRight) then
                updateCursorKeyRepeat()
            elseif pd.buttonJustPressed(pd.kButtonDown) then
                beginDrop()
            elseif pd.buttonJustPressed(pd.kButtonB) then
                beginRewindHold()
            elseif state.cursorRepeatDirection ~= 0 then
                updateCursorKeyRepeat()
            end
        end
    elseif state.phase == GamePhase.PAUSED then
        if pd.buttonJustPressed(pd.kButtonB) then
            state.phase = GamePhase.INPUT
        end
    end

    if TurnResolver.isAnimating(state.phase) then
        advanceAnimation()
    end

    if state.result ~= nil then
        return Scene.GAME_OVER
    end
    return nil
end

loadHighScore()
playMenuBgm()
pd.display.setRefreshRate(DEFAULT_REFRESH_RATE)

local sceneManager

-- Playdateのシステムメニューからゲームを最初からやり直せるようにする.
pd.getSystemMenu():addCheckmarkMenuItem("Auto Play", autoPlayEnabled, function(value)
    autoPlayEnabled = value
    autoPlayer:reset()
end)

pd.getSystemMenu():addMenuItem("Retry", function()
    startGame()
    if sceneManager ~= nil then
        sceneManager:change(Scene.GAME)
    end
end)

local gameRenderer = GameRenderer.new({
    state = state,
    findDropCell = findDropCell,
    findMergeForBlock = function(sourceX, sourceY, activeValue)
        return MergeResolver.find(state.board, sourceX, sourceY, activeValue)
    end,
})

local overlayRenderer = OverlayRenderer.new({
    state = state,
    sound = sound,
    getDangerEdges = getDangerEdges,
    isRewindAvailable = function()
        return undoController:isAvailable()
    end,
})

local sceneContext = SceneContext.new({
    playDecideSound = function() sound:play_se("decide") end,
    playMenuBgm = playMenuBgm,
    playGameBgm = playGameBgm,
    startGame = startGame,
    updateGame = updateGame,
    drawTitle = function()
        overlayRenderer:drawTitle()
    end,
    drawNormalFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawRewindHint()
        if state.phase == GamePhase.PAUSED then
            overlayRenderer:drawPause()
        else
            overlayRenderer:drawMessage()
        end
    end,
    drawGameOverFrame = function()
        gameRenderer:drawHeader()
        overlayRenderer:drawDangerIcons()
        gameRenderer:drawBoard()
        overlayRenderer:drawGameOver()
    end,
})

sceneManager = SceneManager.new(sceneContext)
sceneManager:register(Scene.TITLE, TitleScene.new(sceneContext))
sceneManager:register(Scene.GAME, NormalGameScene.new(sceneContext))
sceneManager:register(Scene.GAME_OVER, GameOverScene.new(sceneContext))
sceneManager:change(Scene.TITLE)

function pd.update()
    gfx.clear(gfx.kColorWhite)
    sceneManager:update()
    sceneManager:draw()
    pd.drawFPS(4, 4)

    if state.phase == GamePhase.UNDO_ROTATING or state.rewindHoldAnimationActive then
        local previousColor = gfx.getColor()
        gfx.setColor(gfx.kColorXOR)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(previousColor)
    end
end
