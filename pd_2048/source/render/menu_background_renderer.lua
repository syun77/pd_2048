import "CoreLibs/graphics"
import "game_config"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Config <const> = GameConfig

---@class MenuBackgroundRenderer メニューバックグラウンド描画クラス.
---@field load string 現在の負荷設定.
---@field image playdate.graphics.image|nil 幾何学模様の描画結果
---@field lastFrame integer|nil 最後に描画したフレーム番号.
local MenuBackgroundRenderer = {}
MenuBackgroundRenderer.__index = MenuBackgroundRenderer

local LOAD_ORDER <const> = { "OFF", "LOW", "MEDIUM", "HIGH" }
local LOAD_SETTINGS <const> = {
    OFF = { enabled = false },
    LOW = {
        enabled = true,
        frameInterval = 6,
        tileSize = 32,
        moireStep = 24,
        lissajousSegments = 0,
    },
    MEDIUM = {
        enabled = true,
        frameInterval = 4,
        tileSize = 24,
        moireStep = 18,
        lissajousSegments = 0,
    },
    HIGH = {
        enabled = true,
        frameInterval = 2,
        tileSize = 20,
        moireStep = 14,
        lissajousSegments = 80,
    },
}

local function normalizeLoad(load)
    return LOAD_SETTINGS[load] ~= nil and load or "MEDIUM"
end

function MenuBackgroundRenderer.new()
    return setmetatable({
        load = normalizeLoad(Config.MENU_BACKGROUND_LOAD),
        image = nil,
        lastFrame = nil,
    }, MenuBackgroundRenderer)
end

function MenuBackgroundRenderer:getLoad()
    return self.load
end

function MenuBackgroundRenderer:setLoad(load)
    self.load = normalizeLoad(load)
    Config.MENU_BACKGROUND_LOAD = self.load
    self.lastFrame = nil
end

function MenuBackgroundRenderer:cycleLoad()
    for index, load in ipairs(LOAD_ORDER) do
        if load == self.load then
            local nextIndex = index + 1
            if nextIndex > #LOAD_ORDER then nextIndex = 1 end
            self:setLoad(LOAD_ORDER[nextIndex])
            return self.load
        end
    end
    self:setLoad("MEDIUM")
    return self.load
end

function MenuBackgroundRenderer:ensureImage()
    if self.image == nil then
        self.image = gfx.image.new(Config.SCREEN_WIDTH, Config.SCREEN_HEIGHT,
            gfx.kColorClear)
    end
end

function MenuBackgroundRenderer:drawTruchetFlow(settings, frame)
    local tileSize = settings.tileSize
    local columns = math.ceil(Config.SCREEN_WIDTH / tileSize) + 1
    local rows = math.ceil(Config.SCREEN_HEIGHT / tileSize) + 1
    local phase = math.floor(frame / 2)

    gfx.setLineWidth(2)
    for row = 0, rows do
        for column = 0, columns do
            local x = column * tileSize
            local y = row * tileSize
            local turn = (column * 3 + row * 5 + phase) % 4
            if turn == 0 then
                gfx.drawLine(x, y, x + tileSize, y + tileSize)
                gfx.drawLine(x, y + math.floor(tileSize * 0.5),
                    x + math.floor(tileSize * 0.5), y + tileSize)
            elseif turn == 1 then
                gfx.drawLine(x + tileSize, y, x, y + tileSize)
                gfx.drawLine(x + math.floor(tileSize * 0.5), y,
                    x, y + math.floor(tileSize * 0.5))
            elseif turn == 2 then
                gfx.drawRect(x + 3, y + 3, tileSize - 6, tileSize - 6)
            else
                gfx.drawLine(x + math.floor(tileSize * 0.5), y,
                    x + math.floor(tileSize * 0.5), y + tileSize)
                gfx.drawLine(x, y + math.floor(tileSize * 0.5),
                    x + tileSize, y + math.floor(tileSize * 0.5))
            end
        end
    end
    gfx.setLineWidth(1)
end

function MenuBackgroundRenderer:drawMoire(settings, frame)
    if settings.moireStep == nil then return end

    local function drawEllipseArc(centerX, centerY, radiusX, radiusY,
        startAngle, endAngle, segments, dashOffset)
        local previousX = nil
        local previousY = nil
        for index = 0, segments do
            local progress = index / segments
            local angle = startAngle + (endAngle - startAngle) * progress
            local x = centerX + math.cos(angle) * radiusX
            local y = centerY + math.sin(angle) * radiusY
            if previousX ~= nil
                and (dashOffset == nil or (index + dashOffset) % 3 ~= 0) then
                gfx.drawLine(previousX, previousY, x, y)
            end
            previousX = x
            previousY = y
        end
    end

    local function drawEllipsoidLayer(centerX, centerY, step, maxRadius,
        yScale, phase, backSkip, speed)
        local frontStart = 0
        local frontEnd = math.pi
        local backStart = math.pi
        local backEnd = math.pi * 2
        local rippleCount = math.ceil(maxRadius / step)
        local rippleOffset = (phase * speed) % maxRadius

        for ringIndex = 0, rippleCount do
            local radius = (ringIndex * step + rippleOffset) % maxRadius
            if radius < 2 then radius = 2 end
            local wave = math.sin(phase + radius * 0.025) * 0.08
            local radiusX = radius * (1 + wave)
            local radiusY = radius * yScale
            local segments = math.max(8, math.floor(radiusX / 10))

            drawEllipseArc(centerX, centerY, radiusX, radiusY,
                frontStart, frontEnd, segments)
            if ringIndex % backSkip == 0 then
                drawEllipseArc(centerX, centerY, radiusX, radiusY,
                    backStart, backEnd, segments, ringIndex)
            end
        end
    end

    local function resetRadiusForScreen(centerX, centerY, yScale, margin)
        local maxRadius = 0
        local corners = {
            { x = 0, y = 0 },
            { x = Config.SCREEN_WIDTH, y = 0 },
            { x = 0, y = Config.SCREEN_HEIGHT },
            { x = Config.SCREEN_WIDTH, y = Config.SCREEN_HEIGHT },
        }
        for _, corner in ipairs(corners) do
            local dx = corner.x - centerX
            local dy = (corner.y - centerY) / yScale
            maxRadius = math.max(maxRadius, math.sqrt(dx * dx + dy * dy))
        end
        return maxRadius + margin
    end

    local t = frame * 0.075
    local yScaleA = 0.48 + math.sin(t * 0.7) * 0.1
    local yScaleB = 0.38
    local centerAX = Config.SCREEN_CENTER_X + math.floor(math.sin(t) * 44)
    local centerAY = Config.SCREEN_CENTER_Y + math.floor(math.cos(t * 0.55) * 18)
    local centerBX = Config.SCREEN_CENTER_X + math.floor(math.cos(t * 0.38) * 30)
    local centerBY = Config.SCREEN_CENTER_Y + math.floor(math.sin(t * 0.46) * 14)
    local resetRadiusA = resetRadiusForScreen(centerAX, centerAY, yScaleA,
        settings.moireStep)
    local resetRadiusB = resetRadiusForScreen(centerBX, centerBY, yScaleB,
        settings.moireStep * 2)

    drawEllipsoidLayer(centerBX, centerBY, settings.moireStep * 2,
        resetRadiusB, yScaleB, t * 0.5, 3, 34)
    drawEllipsoidLayer(centerAX, centerAY, settings.moireStep, resetRadiusA,
        yScaleA, t, 2, 48)
end

function MenuBackgroundRenderer:drawLissajous(settings, frame)
    if settings.lissajousSegments <= 0 then return end

    local segments = settings.lissajousSegments
    local phase = frame * 0.035
    local previousX = nil
    local previousY = nil

    gfx.setLineWidth(1)
    for index = 0, segments do
        local t = index / segments * math.pi * 2
        local x = Config.SCREEN_CENTER_X + math.sin(t * 3 + phase) * 168
        local y = Config.SCREEN_CENTER_Y + math.sin(t * 4 + phase * 1.7) * 92
        if previousX ~= nil then
            gfx.drawLine(previousX, previousY, x, y)
        end
        previousX = x
        previousY = y
    end
end

function MenuBackgroundRenderer:redraw(settings, frame, isClear)
    self:ensureImage()
    gfx.pushContext(self.image)

	if isClear then
		-- 消去指定がある場合はいったん画面をクリアする.
	    gfx.clear(gfx.kColorWhite)
	else
		-- 背景画像に重ねる場合は、幾何学模様だけを透明レイヤーとして描く.
	    gfx.clear(gfx.kColorClear)
	end
    gfx.setColor(gfx.kColorBlack)
    --gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.setDitherPattern(0.5, gfx.image.kDitherTypeDiagonalLine)

    --self:drawTruchetFlow(settings, frame)
    self:drawMoire(settings, frame)
    self:drawLissajous(settings, frame)

	gfx.setDitherPattern(1.0, gfx.image.kDitherTypeNone)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.popContext()
end

-- 幾何学模様の描画.
function MenuBackgroundRenderer:draw(isClear)
    local settings = LOAD_SETTINGS[self.load]
    if settings == nil or not settings.enabled then return end

    local now = pd.getCurrentTimeMilliseconds()
    local refreshIntervalMs = 1000 / Config.DEFAULT_REFRESH_RATE
    local frame = math.floor(now / (refreshIntervalMs * settings.frameInterval))
    if self.lastFrame ~= frame then
		-- 幾何学模様の作成.
        self:redraw(settings, frame, isClear)
        self.lastFrame = frame
    end
    self.image:draw(0, 0)
end

_G.MenuBackgroundRenderer = MenuBackgroundRenderer
return MenuBackgroundRenderer
