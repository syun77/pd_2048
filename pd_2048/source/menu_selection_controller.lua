import "game_config"

local Config <const> = GameConfig
---@class MenuSelectionController メニュー選択コントローラー.
---@field direction integer カーソルの方向. -1:上, 0:なし, 1:下
---@field nextAt integer|nil 次のカーソル移動が発生するフレーム番号. nilの場合は次の移動は発生しない.
local MenuSelectionController = {}

-- 生成.
function MenuSelectionController.new()
    return { direction = 0, nextAt = nil }
end

-- リセット.
---@param controller MenuSelectionController メニュー選択コントローラー.
function MenuSelectionController.reset(controller)
    controller.direction = 0
    controller.nextAt = nil
end

-- 更新.
---@param controller MenuSelectionController メニュー選択コントローラー.
---@param pd playdate Playdateオブジェクト.
---@param now integer 現在のフレーム番号.
---@param move fun(direction: integer) カーソルを移動する関数.
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
