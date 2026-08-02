import "game_config"

local Config <const> = GameConfig
local TurnResolver = {}

function TurnResolver.isAnimating(gameState)
    local s = Config.GAME_STATE
    return gameState == s.DROPPING or gameState == s.MERGING
        or gameState == s.ROTATING or gameState == s.UNDO_ROTATING
        or gameState == s.NEXT_ANIM or gameState == s.HOLD_ANIM
end

-- 状態遷移そのものをここで管理し、個別のゲーム処理はctxのコールバックへ委譲する。
function TurnResolver.advance(ctx)
    ctx.previewImpulseRotationDegrees *= Config.PREVIEW_IMPULSE_DECAY
    ctx.animationProgress += 1 / (ctx.animationDuration * ctx.refreshRate)
    if ctx.animationProgress < 1 then return end
    ctx.animationProgress = 1
    local function complete()
        ctx.completed = true
    end

    local s = Config.GAME_STATE
    if ctx.gameState == s.DROPPING then complete(); ctx.finishDrop()
    elseif ctx.gameState == s.MERGING then complete(); ctx.finishMerge()
    elseif ctx.gameState == s.ROTATING then
        complete()
        ctx.board = ctx.rotationEndBoard
        ctx.setBoard(ctx.board)
        ctx.startResolve("FINISH")
    elseif ctx.gameState == s.UNDO_ROTATING then
        complete()
        ctx.board = ctx.rotationEndBoard
        ctx.rotationStartBoard, ctx.rotationEndBoard = nil, nil
        ctx.setGameState(s.PLAYING)
    elseif ctx.gameState == s.NEXT_ANIM then complete(); ctx.finishNextAnimation()
    elseif ctx.gameState == s.HOLD_ANIM then complete(); ctx.finishHoldAnimation()
    end
end

_G.TurnResolver = TurnResolver
return TurnResolver
