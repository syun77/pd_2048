import "game_config"

local Config <const> = GameConfig
local GameSession = {}
GameSession.__index = GameSession

function GameSession.new(state)
    return setmetatable({ state = state }, GameSession)
end

function GameSession:resetCombo()
    self.state.combo = 0
    self.state.comboBonusScore = 0
    self.state.comboDisplayFrame = 0
    self.state.comboSoundPlayed = false
end

function GameSession:addScore(value)
    local state = self.state
    state.score += value * Config.SCORE_MULTIPLIER
    if state.score > state.highScore then state.highScore = state.score end
end

function GameSession:recordMerge(value)
    local state = self.state
    state.combo += 1
    self:addScore(value)

    state.comboBonusScore = 0
    if state.combo >= 2 then
        local current = Config.COMBO_SCORE_COEFFICIENT
            * (state.combo ^ Config.COMBO_SCORE_EXPONENT)
        local previous = Config.COMBO_SCORE_COEFFICIENT
            * ((state.combo - 1) ^ Config.COMBO_SCORE_EXPONENT)
        state.comboBonusScore = math.floor(current - previous)
        self:addScore(state.comboBonusScore)
    end
end

_G.GameSession = GameSession
return GameSession
