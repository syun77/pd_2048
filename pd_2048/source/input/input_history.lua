-- リプレイ用の論理入力履歴。
-- フレーム数ではなく、ゲームが受理した入力の順番を保持する。
local InputHistory = {}
InputHistory.__index = InputHistory

function InputHistory.new()
    return setmetatable({ entries = {}, cursor = 1, recording = true }, InputHistory)
end

function InputHistory:clear()
    self.entries = {}
    self.cursor = 1
end

function InputHistory:startRecording()
    self:clear()
    self.recording = true
end

function InputHistory:stopRecording()
    self.recording = false
end

function InputHistory:record(command)
    if self.recording then
        table.insert(self.entries, command)
    end
end

function InputHistory:load(entries)
    self.entries = {}
    for i = 1, #entries do
        self.entries[i] = entries[i]
    end
    self.cursor = 1
    self.recording = false
end

function InputHistory:next()
    local command = self.entries[self.cursor]
    if command ~= nil then
        self.cursor += 1
    end
    return command
end

function InputHistory:rewind()
    self.cursor = math.max(1, self.cursor - 1)
end

function InputHistory:isFinished()
    return self.cursor > #self.entries
end

function InputHistory:export()
    local result = {}
    for i = 1, #self.entries do
        result[i] = self.entries[i]
    end
    return result
end

_G.InputHistory = InputHistory
return InputHistory
