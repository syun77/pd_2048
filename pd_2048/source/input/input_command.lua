-- ゲーム入力をPlaydateのボタンから切り離すための論理コマンド定義。
local InputCommand = {
    MOVE_LEFT = "MOVE_LEFT",
    MOVE_RIGHT = "MOVE_RIGHT",
    DROP = "DROP",
    HOLD = "HOLD",
    REWIND = "REWIND",
}

function InputCommand.isValid(command)
    return command == InputCommand.MOVE_LEFT
        or command == InputCommand.MOVE_RIGHT
        or command == InputCommand.DROP
        or command == InputCommand.HOLD
        or command == InputCommand.REWIND
end

_G.InputCommand = InputCommand
return InputCommand
