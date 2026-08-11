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

function HudRenderer.timeAttack(elapsedTimeMs)
    local totalCentiseconds = math.floor(math.max(0, elapsedTimeMs) / 10)
	local minutes = math.floor(totalCentiseconds / 6000)
    local seconds = math.floor(totalCentiseconds / 100) % 60
    local centiseconds = totalCentiseconds % 100
	gfx.drawText("TIME: ", 152, 4)
    local text = string.format("%02d:%02d.%02d", minutes, seconds, centiseconds)
    gfx.drawTextAligned(text, 200, 4, kTextAlignment.left)
end

-- 旧TIME ATTACKの残り時間と制限時間バー描画。
-- 現行の64 SPRINTでは使用せず、時間制限モード用に保持する。
function HudRenderer.timeAttackLimit(remainingTimeMs, totalTimeMs)
    totalTimeMs = totalTimeMs or Config.TIME_ATTACK_LIMIT_MS
    remainingTimeMs = math.max(0, math.min(totalTimeMs, remainingTimeMs))
    local totalTenths = math.floor(remainingTimeMs / 100)
    local seconds = math.floor(totalTenths / 10)
    local tenths = totalTenths % 10
    gfx.drawText("TIME: ", 152, 4)
    local text = string.format("%02d.%d", seconds, tenths)
    gfx.drawTextAligned(text, 248, 4, kTextAlignment.right)

    -- XORで反転描画.
    gfx.setLineWidth(1)
    gfx.setColor(gfx.kColorXOR)
    local barWidth = 160
    local barWidthProgress = barWidth * (remainingTimeMs / totalTimeMs)
    local barHeight = 18
    local barX = 132
    local barY = 2
    gfx.fillRoundRect(barX, barY, barWidthProgress, barHeight, 4)
    -- 外枠を描画.
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(barX, barY, barWidth, barHeight, 4)
end

function HudRenderer.coreRush(elapsedTimeMs)
    local totalCentiseconds = math.floor(math.max(0, elapsedTimeMs) / 10)
    local seconds = math.floor(totalCentiseconds / 100)
    local centiseconds = totalCentiseconds % 100
    gfx.drawText("TIME: ", 152, 4)
    gfx.drawTextAligned(string.format("%02d.%02d", seconds, centiseconds),
        248, 4, kTextAlignment.right)
end

-- PRACTICEモードでの残り手数の描画.
function HudRenderer.practice(turnCount, turnLimit)
    local displayTurn = math.min(turnCount + 1, turnLimit)
	-- 手数テキストの描画.
    gfx.drawText("MOVES: ", 152, 4)
    gfx.drawTextAligned(string.format("%d/%d", displayTurn, turnLimit),
        260, 4, kTextAlignment.right)
	-- 最後の手は点滅.
    if displayTurn >= turnLimit then
        local blinkProgress = pd.getCurrentTimeMilliseconds()
            % Config.PRACTICE_TURN_WARNING_BLINK_PERIOD
        if blinkProgress < Config.PRACTICE_TURN_WARNING_BLINK_ON_DURATION then
            gfx.setLineWidth(2)
            gfx.drawRoundRect(136, 2, 140, 20, 4)
            gfx.setLineWidth(1)
        end
    end
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
        local value = values[index]
        if value ~= nil and value ~= 0 then
            drawPreviewBox(value, Config.NEXT_BOX_X, y,
                Config.NEXT_BOX_WIDTH, Config.NEXT_BOX_HEIGHT)
        end
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
    if ctx.mode == Config.GAME_MODE.PRACTICE then
		if ctx.practiceTurnLimit > 0 then
			HudRenderer.practice(ctx.practiceTurnCount, ctx.practiceTurnLimit)
		end
		-- PRACTICEモードでのクリア目標.
        gfx.drawText(ctx.practiceObjectiveText ~= nil and "GOAL: " or "PRACTICE",
            Config.PRACTICE_GOAL_X, Config.PRACTICE_GOAL_Y)
        if ctx.practiceObjectiveText ~= nil then
            gfx.drawText(ctx.practiceObjectiveText,
                Config.PRACTICE_OBJECTIVE_X, Config.PRACTICE_OBJECTIVE_Y)
        end
    elseif ctx.mode == Config.GAME_MODE.TIME_ATTACK then
        HudRenderer.timeAttack(ctx.elapsedTimeMs)
    elseif ctx.mode == Config.GAME_MODE.TIME_LIMIT_TEST then
        HudRenderer.timeAttackLimit(ctx.remainingTimeMs)
    elseif ctx.mode == Config.GAME_MODE.CORE_RUSH then
        HudRenderer.coreRush(ctx.elapsedTimeMs)
    end
    HudRenderer.score(ctx.score)
    ctx.comboDisplayFrame += 1
    HudRenderer.combo(ctx.combo, ctx.comboDisplayFrame, ctx.comboBonusScore)
    HudRenderer.hold(ctx.holdValue, ctx.phase)
    HudRenderer.next(ctx.nextValues, ctx.phase)
end

_G.HudRenderer = HudRenderer
return HudRenderer
