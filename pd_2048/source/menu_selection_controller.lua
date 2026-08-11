import "game_config"

local Config <const> = GameConfig
local MenuSelectionController = {}

function MenuSelectionController.new()
    return { direction = 0, nextAt = nil }
end

function MenuSelectionController.reset(controller)
    controller.direction = 0
    controller.nextAt = nil
end

function MenuSelectionController.update(controller, pd, now, move)
    if pd.buttonJustPressed(pd.kButtonUp) then
        move(-1)
        controller.direction = -1
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif pd.buttonJustPressed(pd.kButtonDown) then
        move(1)
        controller.direction = 1
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif controller.direction ~= 0 then
        local button = controller.direction < 0 and pd.kButtonUp or pd.kButtonDown
        if not pd.buttonIsPressed(button) then
            MenuSelectionController.reset(controller)
        elseif now >= controller.nextAt then
            move(controller.direction)
            controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INTERVAL_MS
        end
    end
end

_G.MenuSelectionController = MenuSelectionController
return MenuSelectionController
