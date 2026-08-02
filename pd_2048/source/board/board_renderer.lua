import "CoreLibs/graphics"
import "game_config"

local gfx <const> = playdate.graphics
local Config <const> = GameConfig
local BoardRenderer = {}

local function rotatePoint(px, py, angle)
    local centerX = Config.BOARD_X + Config.BOARD_SIZE * Config.CELL_SIZE * 0.5
    local centerY = Config.BOARD_Y + Config.BOARD_SIZE * Config.CELL_SIZE * 0.5
    local x, y = px - centerX, py - centerY
    local c, s = math.cos(angle), math.sin(angle)
    return centerX + x * c - y * s, centerY + x * s + y * c
end

function BoardRenderer.tile(value, px, py)
    local shade = math.min(10, math.floor(math.log(value, 2)))
    if shade % 2 == 0 then
        gfx.fillRect(px + 2, py + 2, Config.CELL_SIZE - 4, Config.CELL_SIZE - 4)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        gfx.drawRect(px + 2, py + 2, Config.CELL_SIZE - 4, Config.CELL_SIZE - 4)
    end
    gfx.drawTextAligned(tostring(value), px + Config.CELL_SIZE / 2,
        py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function BoardRenderer.centerValue(value)
    local cellX = Config.BOARD_X + (Config.CENTER - 1) * Config.CELL_SIZE
    local py = Config.BOARD_Y + (Config.CENTER - 1) * Config.CELL_SIZE
    local tileWidth = Config.CORE_RUSH_VALUE_TILE_WIDTH
    local px = cellX + (Config.CELL_SIZE - tileWidth) * 0.5
    local previousColor = gfx.getColor()
    local previousDrawMode = gfx.getImageDrawMode()
    -- 背景はセル内に収め、数字はセル幅でクリップせず描画する。
    gfx.setColor(gfx.kColorBlack)
	gfx.setDitherPattern(0.1, gfx.image.kDitherTypeBayer8x8)
    gfx.fillRoundRect(px, py + 2, tileWidth, Config.CELL_SIZE - 4, 4)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    gfx.drawTextAligned(tostring(value), px + Config.CELL_SIZE / 2,
        py + 8, kTextAlignment.center)
    gfx.setImageDrawMode(previousDrawMode)
	gfx.setDitherPattern(1.0, gfx.image.kDitherTypeNone)
    gfx.setColor(previousColor)
end

function BoardRenderer.tilePosition(px, py, angle)
    if angle == 0 then return px, py end
    local x, y = rotatePoint(px + Config.CELL_SIZE * 0.5,
        py + Config.CELL_SIZE * 0.5, angle)
    return x - Config.CELL_SIZE * 0.5, y - Config.CELL_SIZE * 0.5
end

function BoardRenderer.grid(showCenterAxis)
    local size = Config.BOARD_SIZE * Config.CELL_SIZE
    gfx.setLineWidth(1)
    gfx.drawRect(Config.BOARD_X, Config.BOARD_Y, size, size)
    for i = 1, Config.BOARD_SIZE - 1 do
        gfx.drawLine(Config.BOARD_X + i * Config.CELL_SIZE, Config.BOARD_Y,
            Config.BOARD_X + i * Config.CELL_SIZE, Config.BOARD_Y + size)
        gfx.drawLine(Config.BOARD_X, Config.BOARD_Y + i * Config.CELL_SIZE,
            Config.BOARD_X + size, Config.BOARD_Y + i * Config.CELL_SIZE)
    end
    if showCenterAxis then
        gfx.setLineWidth(2)
        gfx.drawCircleAtPoint(Config.BOARD_X + (Config.CENTER - 0.5) * Config.CELL_SIZE,
            Config.BOARD_Y + (Config.CENTER - 0.5) * Config.CELL_SIZE, 7)
    end
end

function BoardRenderer.cells(board, skipX, skipY, angle)
    board:foreach(function(x, y, value)
        if value ~= 0 and (x ~= skipX or y ~= skipY) then
            local px, py = BoardRenderer.tilePosition(
                Config.BOARD_X + (x - 1) * Config.CELL_SIZE,
                Config.BOARD_Y + (y - 1) * Config.CELL_SIZE, angle)
            BoardRenderer.tile(value, px, py)
        end
    end)
end

_G.BoardRenderer = BoardRenderer
return BoardRenderer
