import "input/input_command"

-- 自動テスト用の論理入力生成器。
-- 盤面判定は context.getCandidates(value) に委譲し、ここでは選択順と入力列だけを管理する。
local AutoPlayer = {}
AutoPlayer.__index = AutoPlayer

function AutoPlayer.new()
    return setmetatable({ targetColumn = nil, firstHoldPending = true }, AutoPlayer)
end

function AutoPlayer:reset()
    self.targetColumn = nil
    self.firstHoldPending = true
end

local function compareCandidate(a, b, cursorX)
    local aDistance = math.abs(a.column - cursorX)
    local bDistance = math.abs(b.column - cursorX)
    if aDistance ~= bDistance then return aDistance < bDistance end
    return a.column < b.column
end

local function chooseCandidate(candidates, cursorX, requireMerge)
    local selected = nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        if (not requireMerge or candidate.merge) and
            (selected == nil or compareCandidate(candidate, selected, cursorX)) then
            selected = candidate
        end
    end
    return selected
end

local function chooseConnectionCandidate(candidates, cursorX)
    local selected = nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.connectionValue ~= nil
            and (selected == nil
                or candidate.connectionValue < selected.connectionValue
                or (candidate.connectionValue == selected.connectionValue
                    and compareCandidate(candidate, selected, cursorX))) then
            selected = candidate
        end
    end
    return selected
end

function AutoPlayer:poll(_, context)
    -- 自動プレイ開始時は、まずHOLDを実行してHOLDを考慮した状態にする。
    if self.firstHoldPending then
        self.firstHoldPending = false
        return InputCommand.HOLD
    end

    if self.targetColumn == nil then
        local currentCandidates = context.getCandidates(context.nextValue)
        local candidate = chooseCandidate(currentCandidates, context.cursorX, true)

        -- 現在ブロックにマージ先がなければ、HOLD中のブロックを候補にする。
        if candidate == nil and context.holdValue ~= 0 then
            local holdCandidates = context.getCandidates(context.holdValue)
            if chooseCandidate(holdCandidates, context.cursorX, true) ~= nil then
                return InputCommand.HOLD
            end
        end

        -- 同値マージがなければ、1段階上以上のブロックへ接続できる場所を選ぶ。
        if candidate == nil then
            candidate = chooseConnectionCandidate(currentCandidates, context.cursorX)
        end

        -- 現在ブロックに接続先もない場合は、HOLD中のブロックを検討する。
        if candidate == nil and context.holdValue ~= 0 then
            local holdCandidates = context.getCandidates(context.holdValue)
            if chooseConnectionCandidate(holdCandidates, context.cursorX) ~= nil then
                return InputCommand.HOLD
            end
        end

        -- マージできない場合も、接続可能な場所から選んで進行させる。
        candidate = candidate or chooseCandidate(currentCandidates, context.cursorX, false)
        if candidate == nil then
            return nil
        end
        self.targetColumn = candidate.column
    end

    if context.cursorX < self.targetColumn then
        return InputCommand.MOVE_RIGHT
    elseif context.cursorX > self.targetColumn then
        return InputCommand.MOVE_LEFT
    end

    self.targetColumn = nil
    return InputCommand.DROP
end

_G.AutoPlayer = AutoPlayer
return AutoPlayer
