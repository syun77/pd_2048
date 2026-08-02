import "input/input_command"
import "input/input_history"
import "cursor_controller"

-- 入力源を統一するアダプタ。
-- source は poll(controller, context) -> command | nil を実装する。
local InputController = {}
InputController.__index = InputController

function InputController.new(source, history)
    return setmetatable({ source = source, history = history or InputHistory.new() }, InputController)
end

function InputController:setSource(source)
    self.source = source
end

function InputController:poll(context)
    if self.source == nil then
        return nil
    end

    local command = self.source:poll(self, context)
    if command ~= nil and InputCommand.isValid(command) then
        return command
    end
    return nil
end

-- ゲームロジックがコマンドを実際に受理したときに呼ぶ。
-- 無効な DROP/HOLD を履歴へ残さないため、poll と記録を分離する。
function InputController:recordAccepted(command)
    if InputCommand.isValid(command) then
        self.history:record(command)
    end
end

-- 実機入力。cursor repeat は既存の CursorController に委譲する。
function InputController.hardware(pd, cursorController, now, move)
    local source = { pd = pd, cursorController = cursorController, now = now, move = move }
    function source:poll(_, context)
        self.now = context.now
        if self.pd.buttonJustPressed(self.pd.kButtonA) then
            return InputCommand.HOLD
        end

        -- 左右移動は押下またはリピートの1イベントを1コマンドにする。
        local before = context.cursorX
        CursorController.update(self.cursorController, self.pd, self.now, self.move)
        if context.cursorX ~= before then
            return context.cursorX > before and InputCommand.MOVE_RIGHT or InputCommand.MOVE_LEFT
        end

        if self.pd.buttonJustPressed(self.pd.kButtonDown) then
            return InputCommand.DROP
        elseif self.pd.buttonJustPressed(self.pd.kButtonB) then
            return InputCommand.REWIND
        end
        return nil
    end
    return source
end

function InputController.replay(history)
    return {
        poll = function()
            return history:next()
        end,
    }
end

function InputController.auto(decide)
    return {
        poll = function(_, context)
            return decide(context)
        end,
    }
end

_G.InputController = InputController
return InputController
