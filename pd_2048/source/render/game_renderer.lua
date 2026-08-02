import "CoreLibs/graphics"
import "easing"
import "game_config"
import "board/board_renderer"
import "hud_renderer"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig
local GamePhase <const> = Config.GAME_PHASE

local GameRenderer = {}
GameRenderer.__index = GameRenderer

function GameRenderer.new(dependencies)
    return setmetatable({
        state = dependencies.state,
        findDropCell = dependencies.findDropCell,
        findMergeForBlock = dependencies.findMergeForBlock,
        overlay = dependencies.overlay,
    }, GameRenderer)
end

function GameRenderer:getRotatedTilePosition(px, py, angle)
    return BoardRenderer.tilePosition(px, py, angle)
end

function GameRenderer:drawFallingBlock(rotationAngle)
    local state = self.state
    local startY = Config.BOARD_Y - Config.CELL_SIZE
    local targetY = Config.BOARD_Y + (state.pendingDropY - 1) * Config.CELL_SIZE
    local y = startY + (targetY - startY) * state.animationProgress
    local px, py = self:getRotatedTilePosition(
        Config.BOARD_X + (state.pendingDropX - 1) * Config.CELL_SIZE, y, rotationAngle)
    BoardRenderer.tile(state.pendingDropValue, px, py)
end

function GameRenderer:drawLandingPreview()
    local state = self.state
    local landingX, landingY = self.findDropCell(state.cursorX)
    if landingX == nil then return end

    local px = Config.BOARD_X + (landingX - 1) * Config.CELL_SIZE
    local py = Config.BOARD_Y + (landingY - 1) * Config.CELL_SIZE

    gfx.setDitherPattern(0.9, gfx.image.kDitherTypeBayer8x8)
    gfx.fillRect(px + 2, py + 2, Config.CELL_SIZE - 4, Config.CELL_SIZE - 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawTextAligned(tostring(state.nextValues[1]),
        px + Config.CELL_SIZE / 2, py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    local _, _, targetX, targetY = self.findMergeForBlock(
        landingX, landingY, state.nextValues[1])
    if targetX == nil then return end

    local sourceCenterX = Config.BOARD_X + (landingX - 0.5) * Config.CELL_SIZE
    local sourceCenterY = Config.BOARD_Y + (landingY - 0.5) * Config.CELL_SIZE
    local targetCenterX = Config.BOARD_X + (targetX - 0.5) * Config.CELL_SIZE
    local targetCenterY = Config.BOARD_Y + (targetY - 0.5) * Config.CELL_SIZE
    local directionX = targetX - landingX
    local directionY = targetY - landingY
    local arrowStartX = sourceCenterX + (targetCenterX - sourceCenterX) * 0.25
    local arrowStartY = sourceCenterY + (targetCenterY - sourceCenterY) * 0.25
    local arrowTipX = sourceCenterX + (targetCenterX - sourceCenterX) * 0.75
    local arrowTipY = sourceCenterY + (targetCenterY - sourceCenterY) * 0.75
    local arrowBaseX = arrowTipX - directionX * 7
    local arrowBaseY = arrowTipY - directionY * 7
    local perpendicularX = -directionY * 4
    local perpendicularY = directionX * 4

    gfx.setLineWidth(2)
    gfx.drawLine(arrowStartX, arrowStartY, arrowTipX, arrowTipY)
    gfx.setLineWidth(1)
    gfx.drawLine(arrowTipX, arrowTipY,
        arrowBaseX + perpendicularX, arrowBaseY + perpendicularY)
    gfx.drawLine(arrowTipX, arrowTipY,
        arrowBaseX - perpendicularX, arrowBaseY - perpendicularY)
end

function GameRenderer:drawDropPreview()
    local state = self.state
    local px = Config.BOARD_X + (state.cursorX - 1) * Config.CELL_SIZE
    local py = Config.BOARD_Y - Config.CELL_SIZE

    BoardRenderer.tile(state.nextValues[1], px, py)

    if (pd.getCurrentTimeMilliseconds() % 600) < 300 then
        gfx.setLineWidth(2)
        gfx.drawRect(px, py, Config.CELL_SIZE, Config.CELL_SIZE)
        gfx.setLineWidth(1)
    end
end

function GameRenderer:getPreviewRotationEvaluation()
    local state = self.state
    local evaluation = state.rotationEvaluation
    if state.phase == GamePhase.MERGING then
        local mergeEvaluation = Config.ROTATION_EVALUATION_DISAPPEARED_BLOCK_WEIGHT
            * self:getPositionEvaluation(state.mergeSourceX)
            + Config.ROTATION_EVALUATION_MERGED_BLOCK_WEIGHT
            * self:getPositionEvaluation(state.mergeTargetX)
            + self:getMergeDirectionEvaluation(state.mergeSourceX, state.mergeTargetX)
        evaluation += mergeEvaluation * self:easeInOut(state.animationProgress)
    end
    return evaluation * Config.PREVIEW_ROTATION_DEGREES_PER_POINT
end

function GameRenderer:getPositionEvaluation(x)
    if x > Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_RIGHT end
    if x < Config.CENTER then return Config.ROTATION_EVALUATION_POSITION_LEFT end
    return Config.ROTATION_EVALUATION_POSITION_CENTER
end

function GameRenderer:getMergeDirectionEvaluation(sourceX, targetX)
    if targetX < sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_LEFT end
    if targetX > sourceX then return Config.ROTATION_EVALUATION_MERGE_DIRECTION_RIGHT end
    return Config.ROTATION_EVALUATION_VERTICAL_DIRECTION_WEIGHT
        * self:getPositionEvaluation(targetX)
end

function GameRenderer:getPreviewRotationDegrees()
    local state = self.state
    if state.phase ~= GamePhase.DROPPING and state.phase ~= GamePhase.MERGING then
        return 0
    end
    return self:getPreviewRotationEvaluation() + state.previewImpulseRotationDegrees
end

function GameRenderer:getPreviewRotationAngle()
    local degrees = self:getPreviewRotationDegrees()
    degrees = math.max(-Config.PREVIEW_ROTATION_MAX_DEGREES,
        math.min(Config.PREVIEW_ROTATION_MAX_DEGREES, degrees))
    return math.rad(degrees + self.state.previewImpulseRotationDegrees)
end

function GameRenderer:easeInOut(value)
    return value * value * (3 - 2 * value)
end

function GameRenderer:drawRotatingBoard()
    local state = self.state
    local progress = Easing.back_out(state.animationProgress)
    local angle = math.pi * 0.5 * progress
    if not state.rotationClockwise then angle = -angle end

    state.rotationStartBoard:foreach(function(x, y, value)
        if value ~= 0 then
            local px, py = self:getRotatedTilePosition(
                Config.BOARD_X + (x - 1) * Config.CELL_SIZE,
                Config.BOARD_Y + (y - 1) * Config.CELL_SIZE, angle)
            BoardRenderer.tile(value, px, py)
        end
    end)
end

function GameRenderer:drawRotationDirectionArrow()
    local state = self.state
    if state.phase ~= GamePhase.MERGING and state.phase ~= GamePhase.ROTATING then return end

    local evaluation = self:getPreviewRotationEvaluation()
    if evaluation == 0 then return end

    local centerX = Config.BOARD_X + (Config.CENTER - 0.5) * Config.CELL_SIZE
    local centerY = Config.BOARD_Y + (Config.CENTER - 0.5) * Config.CELL_SIZE
        + Config.ROTATION_DIRECTION_ARROW_OFFSET_Y
    local direction = evaluation > 0 and 1 or -1
    local evaluationRatio = math.min(1,
        math.abs(evaluation) / Config.ROTATION_DIRECTION_ARROW_MAX_EVALUATION)
    local arrowLength = Config.ROTATION_DIRECTION_ARROW_MIN_LENGTH
        + (Config.ROTATION_DIRECTION_ARROW_MAX_LENGTH
            - Config.ROTATION_DIRECTION_ARROW_MIN_LENGTH) * evaluationRatio
    local arrowStartX = centerX - direction * arrowLength * 0.5
    local arrowTipX = centerX + direction * arrowLength * 0.5
    local arrowBaseX = arrowTipX - direction * Config.ROTATION_DIRECTION_ARROW_HEAD_LENGTH

    gfx.setLineWidth(2)
    gfx.drawLine(arrowStartX, centerY, arrowTipX, centerY)
    gfx.setLineWidth(1)
    gfx.drawLine(arrowTipX, centerY, arrowBaseX,
        centerY - Config.ROTATION_DIRECTION_ARROW_HEAD_WIDTH)
    gfx.drawLine(arrowTipX, centerY, arrowBaseX,
        centerY + Config.ROTATION_DIRECTION_ARROW_HEAD_WIDTH)
end

function GameRenderer:drawMergeAnimation(rotationAngle)
    local state = self.state
    BoardRenderer.cells(state.board, state.mergeSourceX, state.mergeSourceY, rotationAngle)

    local progress = self:easeInOut(state.animationProgress)
    local sourcePx = Config.BOARD_X + (state.mergeSourceX - 1) * Config.CELL_SIZE
    local sourcePy = Config.BOARD_Y + (state.mergeSourceY - 1) * Config.CELL_SIZE
    local targetPx = Config.BOARD_X + (state.mergeTargetX - 1) * Config.CELL_SIZE
    local targetPy = Config.BOARD_Y + (state.mergeTargetY - 1) * Config.CELL_SIZE
    local rotatedTargetPx, rotatedTargetPy = self:getRotatedTilePosition(
        targetPx, targetPy, rotationAngle)
    BoardRenderer.tile(state.board:get(state.mergeTargetX, state.mergeTargetY),
        rotatedTargetPx, rotatedTargetPy)

    local sourceCenterX = sourcePx + Config.CELL_SIZE * 0.5
    local sourceCenterY = sourcePy + Config.CELL_SIZE * 0.5
    local targetCenterX = targetPx + Config.CELL_SIZE * 0.5
    local targetCenterY = targetPy + Config.CELL_SIZE * 0.5
    local currentCenterX = sourceCenterX + (targetCenterX - sourceCenterX) * progress
    local currentCenterY = sourceCenterY + (targetCenterY - sourceCenterY) * progress
    local rotatedSourcePx, rotatedSourcePy = self:getRotatedTilePosition(
        currentCenterX - Config.CELL_SIZE * 0.5,
        currentCenterY - Config.CELL_SIZE * 0.5, rotationAngle)
    BoardRenderer.tile(math.floor(state.mergeValue / 2), rotatedSourcePx, rotatedSourcePy)
end

function GameRenderer:drawNextAnimation()
    local state = self.state
    local progress = self:easeInOut(state.animationProgress)
    local sourceCenterX = Config.NEXT_BOX_X + Config.NEXT_BOX_WIDTH * 0.5
    local sourceCenterY = Config.NEXT_BOX_Y + Config.NEXT_BOX_HEIGHT * 0.5
    local sourceX = sourceCenterX - Config.CELL_SIZE * 0.5
    local sourceY = sourceCenterY - Config.CELL_SIZE * 0.5
    local targetX = Config.BOARD_X + (state.cursorX - 1) * Config.CELL_SIZE
    local targetY = Config.BOARD_Y - Config.CELL_SIZE
    BoardRenderer.tile(state.nextValues[1],
        sourceX + (targetX - sourceX) * progress,
        sourceY + (targetY - sourceY) * progress)
end

function GameRenderer:getHoldTilePosition()
    return Config.HOLD_BOX_X + (Config.NEXT_BOX_WIDTH - Config.CELL_SIZE) * 0.5,
        Config.HOLD_BOX_Y + (Config.NEXT_BOX_HEIGHT - Config.CELL_SIZE) * 0.5
end

function GameRenderer:drawHoldAnimation()
    local state = self.state
    local progress = self:easeInOut(state.animationProgress)
    local currentX = Config.BOARD_X + (state.cursorX - 1) * Config.CELL_SIZE
    local currentY = Config.BOARD_Y - Config.CELL_SIZE
    local holdX, holdY = self:getHoldTilePosition()

    if state.holdAnimationSourceValue ~= 0 then
        BoardRenderer.tile(state.holdAnimationSourceValue,
            currentX + (holdX - currentX) * progress,
            currentY + (holdY - currentY) * progress)
    end
    if state.holdAnimationReturnValue ~= 0 then
        BoardRenderer.tile(state.holdAnimationReturnValue,
            holdX + (currentX - holdX) * progress,
            holdY + (currentY - holdY) * progress)
    end
end

function GameRenderer:drawBoard()
    local state = self.state
    BoardRenderer.grid()
    local previewRotationAngle = self:getPreviewRotationAngle()

    if state.phase == GamePhase.ROTATING or state.phase == GamePhase.UNDO_ROTATING then
        self:drawRotatingBoard()
    elseif state.phase == GamePhase.MERGING then
        self:drawMergeAnimation(previewRotationAngle)
    else
        BoardRenderer.cells(state.board, nil, nil, previewRotationAngle)
    end

    if state.phase == GamePhase.MERGING or state.phase == GamePhase.ROTATING then
        self:drawRotationDirectionArrow()
    end
    if state.phase == GamePhase.INPUT then
        self:drawLandingPreview()
    elseif state.phase == GamePhase.DROPPING then
        self:drawFallingBlock(previewRotationAngle)
    end
    if state.phase == GamePhase.INPUT then
        self:drawDropPreview()
    elseif state.phase == GamePhase.NEXT_ANIM then
        self:drawNextAnimation()
    elseif state.phase == GamePhase.HOLD_ANIM then
        self:drawHoldAnimation()
    end
end

function GameRenderer:drawHeader()
    local state = self.state
    HudRenderer.header({
        score = state.score, combo = state.combo,
        comboDisplayFrame = state.comboDisplayFrame,
        comboBonusScore = state.comboBonusScore, holdValue = state.holdValue,
        nextValues = state.nextValues, phase = state.phase,
    })
    state.comboDisplayFrame += 1
end

function GameRenderer:drawNormalFrame()
    local state = self.state
    self:drawHeader()
    self.overlay:drawDangerIcons()
    self:drawBoard()
    self.overlay:drawRewindHint()
    if state.phase == GamePhase.PAUSED then
        self.overlay:drawPause()
    else
        self.overlay:drawMessage()
    end
end

function GameRenderer:drawGameOverFrame()
    self:drawHeader()
    self.overlay:drawDangerIcons()
    self:drawBoard()
    self.overlay:drawGameOver()
end

_G.GameRenderer = GameRenderer
return GameRenderer
