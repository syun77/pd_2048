import "CoreLibs/graphics"
import "game_config"

local gfx <const> = playdate.graphics
local pd <const> = playdate
local Config <const> = GameConfig
local HudRenderer = {}

function HudRenderer.score(score)
    gfx.drawTextAligned("SCORE: ", 12 + Config.PANEL_OFFSET_X,
        Config.PANEL_OFFSET_Y, kTextAlignment.left)
    gfx.drawTextAligned(tostring(score), 80 + Config.PANEL_OFFSET_X,
        24 + Config.PANEL_OFFSET_Y, kTextAlignment.right)
end

function HudRenderer.timeAttack(remainingTimeMs)
    local totalTenths = math.max(0, math.floor(remainingTimeMs / 100))
    local seconds = math.floor(totalTenths / 10)
    local tenths = totalTenths % 10
    local text = string.format("TIME %02d.%d", seconds, tenths)
    gfx.drawTextAligned(text, 200, 4, kTextAlignment.center)
end

function HudRenderer.combo(combo, comboDisplayFrame, comboBonusScore)
    if combo <= 1 then return end
    if comboDisplayFrame >= Config.COMBO_BLINK_DURATION_FRAMES
        + Config.COMBO_STEADY_DURATION_FRAMES then return end
    local blinking = comboDisplayFrame < Config.COMBO_BLINK_DURATION_FRAMES
    if blinking and (comboDisplayFrame % Config.COMBO_BLINK_PERIOD_FRAMES)
        < Config.COMBO_BLINK_ON_FRAMES then
        gfx.drawRoundRect(4 + Config.PANEL_OFFSET_X, 50 + Config.PANEL_OFFSET_Y, 88, 24, 4)
    end
    gfx.drawText("COMBO: " .. tostring(combo), 12 + Config.PANEL_OFFSET_X,
        54 + Config.PANEL_OFFSET_Y)
    if comboBonusScore > 0 then
        gfx.drawTextAligned("+" .. tostring(comboBonusScore * Config.SCORE_MULTIPLIER),
            80 + Config.PANEL_OFFSET_X, 72 + Config.PANEL_OFFSET_Y, kTextAlignment.right)
    end
end

local function drawPreviewBox(value, x, y, width, height)
    local shade = math.min(10, math.floor(math.log(value, 2)))
    if shade % 2 == 0 then
        gfx.fillRect(x, y, width, height)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.drawRect(x, y, width, height)
    end
    gfx.drawTextAligned(tostring(value), x + width * 0.5, y + 3, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function HudRenderer.next(values, phase)
    gfx.drawText("NEXT", Config.NEXT_LABEL_X, 20)
    for i = 1, Config.NEXT_PREVIEW_COUNT do
        if i == 1 and (pd.getCurrentTimeMilliseconds() % 400) < 200 then
            gfx.setLineWidth(2)
            gfx.drawRect(Config.NEXT_BOX_X, Config.NEXT_BOX_Y,
                Config.NEXT_BOX_WIDTH, Config.NEXT_BOX_HEIGHT)
            gfx.setLineWidth(1)
        end
        local index = phase == Config.GAME_PHASE.NEXT_ANIM and i or i + 1
        local y = Config.NEXT_BOX_Y + (i - 1) * (Config.NEXT_BOX_HEIGHT + Config.NEXT_BOX_GAP)
        drawPreviewBox(values[index], Config.NEXT_BOX_X, y,
            Config.NEXT_BOX_WIDTH, Config.NEXT_BOX_HEIGHT)
    end
end

function HudRenderer.hold(value, phase)
    gfx.drawText("A: HOLD", Config.HOLD_LABEL_X, 20)
    gfx.setLineWidth(1)
    gfx.drawRect(Config.HOLD_BOX_X, Config.HOLD_BOX_Y,
        Config.NEXT_BOX_WIDTH, Config.NEXT_BOX_HEIGHT)
    if phase == Config.GAME_PHASE.HOLD_ANIM or value == 0 then return end
    drawPreviewBox(value, Config.HOLD_BOX_X, Config.HOLD_BOX_Y,
        Config.NEXT_BOX_WIDTH, Config.NEXT_BOX_HEIGHT)
end

function HudRenderer.header(ctx)
    if ctx.mode == Config.GAME_MODE.TIME_ATTACK then
        HudRenderer.timeAttack(ctx.remainingTimeMs)
    end
    HudRenderer.score(ctx.score)
    ctx.comboDisplayFrame += 1
    HudRenderer.combo(ctx.combo, ctx.comboDisplayFrame, ctx.comboBonusScore)
    HudRenderer.hold(ctx.holdValue, ctx.phase)
    HudRenderer.next(ctx.nextValues, ctx.phase)
end

_G.HudRenderer = HudRenderer
return HudRenderer
