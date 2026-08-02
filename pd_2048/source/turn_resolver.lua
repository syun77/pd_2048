import "game_config"

local Config <const> = GameConfig
local TurnResolver = {}

function TurnResolver.isAnimating(phase)
    local s = Config.GAME_PHASE
    return phase == s.DROPPING or phase == s.MERGING
        or phase == s.ROTATING or phase == s.UNDO_ROTATING
        or phase == s.NEXT_ANIM or phase == s.HOLD_ANIM
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

    local s = Config.GAME_PHASE
    if ctx.phase == s.DROPPING then complete(); ctx.finishDrop()
    elseif ctx.phase == s.MERGING then complete(); ctx.finishMerge()
    elseif ctx.phase == s.ROTATING then
        complete()
        ctx.board = ctx.rotationEndBoard
        ctx.setBoard(ctx.board)
        ctx.startResolve("FINISH")
    elseif ctx.phase == s.UNDO_ROTATING then
        complete()
        ctx.board = ctx.rotationEndBoard
        ctx.rotationStartBoard, ctx.rotationEndBoard = nil, nil
        ctx.setPhase(s.INPUT)
    elseif ctx.phase == s.NEXT_ANIM then complete(); ctx.finishNextAnimation()
    elseif ctx.phase == s.HOLD_ANIM then complete(); ctx.finishHoldAnimation()
    end
end

_G.TurnResolver = TurnResolver
return TurnResolver
