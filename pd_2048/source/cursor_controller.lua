import "game_config"

local Config <const> = GameConfig

---@enum CURSOR_DIRECTION カーソルの方向.
local CURSOR_DIRECTION = {
	LEFT = -1, -- 左
	RIGHT = 1, -- 右
	NONE = 0, -- なし
}

---@class CursorController カーソルコントローラー.
---@field direction CURSOR_DIRECTION カーソルの方向. -1:左, 0:なし, 1:右
---@field nextAt integer|nil 次のカーソル移動が発生するフレーム番号. nilの場合は次の移動は発生しない.
local CursorController = {}

-- 生成.
---@return CursorController カーソルコントローラー.
function CursorController.new()
    return { direction = CURSOR_DIRECTION.NONE, nextAt = nil }
end

-- カーソルの状態をリセットする.
---@param controller CursorController カーソルコントローラー.
function CursorController.reset(controller)
    controller.direction = CURSOR_DIRECTION.NONE
    controller.nextAt = nil
end

-- カーソルの状態を更新する.
---@param controller CursorController カーソルコントローラー.
---@param pd playdate Playdateオブジェクト.
---@param now integer 現在のフレーム番号.
---@param move fun(direction: integer) カーソルを移動する関数.
function CursorController.update(controller, pd, now, move)
    if pd.buttonJustPressed(pd.kButtonLeft) then
		-- 左ボタンが押された場合はカーソルを左に移動し、次の移動タイミングを設定する.
        move(-1)
        controller.direction = CURSOR_DIRECTION.LEFT
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif pd.buttonJustPressed(pd.kButtonRight) then
		-- 右ボタンが押された場合はカーソルを右に移動し、次の移動タイミングを設定する.
        move(1)
        controller.direction = CURSOR_DIRECTION.RIGHT
        controller.nextAt = now + Config.CURSOR_KEY_REPEAT_INITIAL_DELAY_MS
    elseif controller.direction ~= CURSOR_DIRECTION.NONE then
		-- すでにカーソルが押されている場合は、次の移動タイミングを確認し、必要に応じてカーソルを移動する.
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
