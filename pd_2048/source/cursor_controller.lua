import "game_config"

local Config <const> = GameConfig
local CursorController = {}

function CursorController.new()
    return { direction = 0, nextAt = nil }
end

function CursorController.reset(controller)
    controller.direction = 0
    controller.nextAt = nil
end

function CursorController.update(controller, pd, now, move)
    if pd.buttonJustPressed(pd.kButtonLeft) then
        move(-1)
        controller.direction = -1
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif pd.buttonJustPressed(pd.kButtonRight) then
        move(1)
        controller.direction = 1
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif controller.direction ~= 0 then
        local button = controller.direction < 0 and pd.kButtonLeft or pd.kButtonRight
        if not pd.buttonIsPressed(button) then
            CursorController.reset(controller)
        elseif now >= controller.nextAt then
            move(controller.direction)
            controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INTERVAL_MS
        end
    end
end

_G.CursorController = CursorController
return CursorController
