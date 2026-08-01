-- easing.lua
-- Playdate SDK / Lua向けイージング関数
--
-- 使用例:
--   import "easing"
--   local x = Easing.step(Easing.Type.QUAD_OUT, 20, 200, 0.5)
--
-- t / v は原則として 0.0 ～ 1.0 を指定します。

local Easing = {}

-- Godot版のenum値と互換になるよう、0始まりで定義しています。
Easing.Type = {
    LINEAR = 0,
    QUAD_IN = 1,
    QUAD_OUT = 2,
    QUAD_INOUT = 3,
    CUBE_IN = 4,
    CUBE_OUT = 5,
    CUBE_INOUT = 6,
    QUART_IN = 7,
    QUART_OUT = 8,
    QUART_INOUT = 9,
    QUINT_IN = 10,
    QUINT_OUT = 11,
    QUINT_INOUT = 12,
    SMOOTH_STEP_IN = 13,
    SMOOTH_STEP_OUT = 14,
    SMOOTH_STEP_INOUT = 15,
    SMOOTHER_STEP_IN = 16,
    SMOOTHER_STEP_OUT = 17,
    SMOOTHER_STEP_INOUT = 18,
    SIN_IN = 19,
    SIN_OUT = 20,
    SIN_INOUT = 21,
    BOUNCE_IN = 22,
    BOUNCE_OUT = 23,
    BOUNCE_INOUT = 24,
    CIRC_IN = 25,
    CIRC_OUT = 26,
    CIRC_INOUT = 27,
    EXPO_IN = 28,
    EXPO_OUT = 29,
    EXPO_INOUT = 30,
    BACK_IN = 31,
    BACK_OUT = 32,
    BACK_INOUT = 33,
    ELASTIC_IN = 34,
    ELASTIC_OUT = 35,
    ELASTIC_INOUT = 36,
}

local pi = math.pi
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt
local pow = math.pow or function(a, b)
    return a ^ b
end
local asin = math.asin

-- 一次関数
function Easing.linear(t)
    return t
end

-- 二次関数
function Easing.quad_in(t)
    return t * t
end

function Easing.quad_out(t)
    return -t * (t - 2)
end

function Easing.quad_in_out(t)
    if t <= 0.5 then
        return t * t * 2
    end

    return 1 - (t - 1) * (t - 1) * 2
end

-- 三次関数
function Easing.cube_in(t)
    return t * t * t
end

function Easing.cube_out(t)
    local u = t - 1
    return 1 + u * u * u
end

function Easing.cube_in_out(t)
    if t <= 0.5 then
        return t * t * t * 4
    end

    local u = t - 1
    return 1 + u * u * u * 4
end

-- 四次関数
function Easing.quart_in(t)
    return t * t * t * t
end

function Easing.quart_out(t)
    local u = t - 1
    return 1 - u * u * u * u
end

function Easing.quart_in_out(t)
    if t <= 0.5 then
        return t * t * t * t * 8
    end

    local u = t * 2 - 2
    return (1 - u * u * u * u) / 2 + 0.5
end

-- 五次関数
function Easing.quint_in(t)
    return t * t * t * t * t
end

function Easing.quint_out(t)
    local u = t - 1
    return u * u * u * u * u + 1
end

function Easing.quint_in_out(t)
    local u = t * 2

    if u < 1 then
        return u * u * u * u * u / 2
    end

    u = u - 2
    return (u * u * u * u * u + 2) / 2
end

-- スムーズ曲線
function Easing.smooth_step_in_out(t)
    return t * t * (t * -2 + 3)
end

function Easing.smooth_step_in(t)
    return 2 * Easing.smooth_step_in_out(t / 2)
end

function Easing.smooth_step_out(t)
    return 2 * Easing.smooth_step_in_out(t / 2 + 0.5) - 1
end

-- よりスムーズな曲線
function Easing.smoother_step_in_out(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

function Easing.smoother_step_in(t)
    return 2 * Easing.smoother_step_in_out(t / 2)
end

function Easing.smoother_step_out(t)
    return 2 * Easing.smoother_step_in_out(t / 2 + 0.5) - 1
end

-- SIN関数
function Easing.sine_in(t)
    return -cos(pi / 2 * t) + 1
end

function Easing.sine_out(t)
    return sin(pi / 2 * t)
end

function Easing.sine_in_out(t)
    return -cos(pi * t) / 2 + 0.5
end

-- バウンス関数
local B1 = 1 / 2.75
local B2 = 2 / 2.75
local B3 = 1.5 / 2.75
local B4 = 2.5 / 2.75
local B5 = 2.25 / 2.75
local B6 = 2.625 / 2.75

function Easing.bounce_in(t)
    local u = 1 - t

    if u < B1 then
        return 1 - 7.5625 * u * u
    end

    if u < B2 then
        return 1 - (7.5625 * (u - B3) ^ 2 + 0.75)
    end

    if u < B4 then
        return 1 - (7.5625 * (u - B5) ^ 2 + 0.9375)
    end

    return 1 - (7.5625 * (u - B6) ^ 2 + 0.984375)
end

function Easing.bounce_out(t)
    if t < B1 then
        return 7.5625 * t * t
    end

    if t < B2 then
        return 7.5625 * (t - B3) ^ 2 + 0.75
    end

    if t < B4 then
        return 7.5625 * (t - B5) ^ 2 + 0.9375
    end

    return 7.5625 * (t - B6) ^ 2 + 0.984375
end

function Easing.bounce_in_out(t)
    if t < 0.5 then
        return Easing.bounce_in(t * 2) / 2
    end

    return Easing.bounce_out(t * 2 - 1) / 2 + 0.5
end

-- 円
function Easing.circ_in(t)
    return 1 - sqrt(1 - t * t)
end

function Easing.circ_out(t)
    local u = t - 1
    return sqrt(1 - u * u)
end

function Easing.circ_in_out(t)
    if t <= 0.5 then
        return (sqrt(1 - t * t * 4) - 1) / -2
    end

    local u = t * 2 - 2
    return (sqrt(1 - u * u) + 1) / 2
end

-- 指数関数
function Easing.expo_in(t)
    if t <= 0 then
        return 0
    end

    return pow(2, 10 * (t - 1))
end

function Easing.expo_out(t)
    if t >= 1 then
        return 1
    end

    return -pow(2, -10 * t) + 1
end

function Easing.expo_in_out(t)
    if t <= 0 then
        return 0
    end

    if t >= 1 then
        return 1
    end

    if t < 0.5 then
        return pow(2, 10 * (t * 2 - 1)) / 2
    end

    return (-pow(2, -10 * (t * 2 - 1)) + 2) / 2
end

-- バック
function Easing.back_in(t)
    return t * t * (2.70158 * t - 1.70158)
end

function Easing.back_out(t)
    local u = t - 1
    return 1 - u * u * (-2.70158 * u - 1.70158)
end

function Easing.back_in_out(t)
    local u = t * 2

    if u < 1 then
        return u * u * (2.70158 * u - 1.70158) / 2
    end

    u = u - 1

    return (
        1 -
        (u - 1) *
        (u - 1) *
        (-2.70158 * (u - 1) - 1.70158)
    ) / 2 + 0.5
end

-- 弾力関数
local ELASTIC_AMPLITUDE = 1.0
local ELASTIC_PERIOD = 0.4
local ELASTIC_PHASE =
    ELASTIC_PERIOD /
    (2 * pi) *
    asin(1 / ELASTIC_AMPLITUDE)

function Easing.elastic_in(t)
    if t <= 0 then
        return 0
    end

    if t >= 1 then
        return 1
    end

    local u = t - 1

    return -(
        ELASTIC_AMPLITUDE *
        pow(2, 10 * u) *
        sin(
            (u - ELASTIC_PHASE) *
            (2 * pi) /
            ELASTIC_PERIOD
        )
    )
end

function Easing.elastic_out(t)
    if t <= 0 then
        return 0
    end

    if t >= 1 then
        return 1
    end

    return
        ELASTIC_AMPLITUDE *
        pow(2, -10 * t) *
        sin(
            (t - ELASTIC_PHASE) *
            (2 * pi) /
            ELASTIC_PERIOD
        ) +
        1
end

function Easing.elastic_in_out(t)
    if t <= 0 then
        return 0
    end

    if t >= 1 then
        return 1
    end

    local u = t - 0.5

    if t < 0.5 then
        return
            -0.5 *
            pow(2, 10 * u) *
            sin(
                (u - ELASTIC_PERIOD / 4) *
                (2 * pi) /
                ELASTIC_PERIOD
            )
    end

    return
        pow(2, -10 * u) *
        sin(
            (u - ELASTIC_PERIOD / 4) *
            (2 * pi) /
            ELASTIC_PERIOD
        ) *
        0.5 +
        1
end

local functions = {
    [Easing.Type.LINEAR] = Easing.linear,

    [Easing.Type.QUAD_IN] = Easing.quad_in,
    [Easing.Type.QUAD_OUT] = Easing.quad_out,
    [Easing.Type.QUAD_INOUT] = Easing.quad_in_out,

    [Easing.Type.CUBE_IN] = Easing.cube_in,
    [Easing.Type.CUBE_OUT] = Easing.cube_out,
    [Easing.Type.CUBE_INOUT] = Easing.cube_in_out,

    [Easing.Type.QUART_IN] = Easing.quart_in,
    [Easing.Type.QUART_OUT] = Easing.quart_out,
    [Easing.Type.QUART_INOUT] = Easing.quart_in_out,

    [Easing.Type.QUINT_IN] = Easing.quint_in,
    [Easing.Type.QUINT_OUT] = Easing.quint_out,
    [Easing.Type.QUINT_INOUT] = Easing.quint_in_out,

    [Easing.Type.SMOOTH_STEP_IN] = Easing.smooth_step_in,
    [Easing.Type.SMOOTH_STEP_OUT] = Easing.smooth_step_out,
    [Easing.Type.SMOOTH_STEP_INOUT] = Easing.smooth_step_in_out,

    [Easing.Type.SMOOTHER_STEP_IN] = Easing.smoother_step_in,
    [Easing.Type.SMOOTHER_STEP_OUT] = Easing.smoother_step_out,
    [Easing.Type.SMOOTHER_STEP_INOUT] =
        Easing.smoother_step_in_out,

    [Easing.Type.SIN_IN] = Easing.sine_in,
    [Easing.Type.SIN_OUT] = Easing.sine_out,
    [Easing.Type.SIN_INOUT] = Easing.sine_in_out,

    [Easing.Type.BOUNCE_IN] = Easing.bounce_in,
    [Easing.Type.BOUNCE_OUT] = Easing.bounce_out,
    [Easing.Type.BOUNCE_INOUT] = Easing.bounce_in_out,

    [Easing.Type.CIRC_IN] = Easing.circ_in,
    [Easing.Type.CIRC_OUT] = Easing.circ_out,
    [Easing.Type.CIRC_INOUT] = Easing.circ_in_out,

    [Easing.Type.EXPO_IN] = Easing.expo_in,
    [Easing.Type.EXPO_OUT] = Easing.expo_out,
    [Easing.Type.EXPO_INOUT] = Easing.expo_in_out,

    [Easing.Type.BACK_IN] = Easing.back_in,
    [Easing.Type.BACK_OUT] = Easing.back_out,
    [Easing.Type.BACK_INOUT] = Easing.back_in_out,

    [Easing.Type.ELASTIC_IN] = Easing.elastic_in,
    [Easing.Type.ELASTIC_OUT] = Easing.elastic_out,
    [Easing.Type.ELASTIC_INOUT] = Easing.elastic_in_out,
}

-- 種類に対応する関数を返します。
-- 未定義の種類の場合はlinearを返します。
function Easing.get_function(easing_type)
    local fn = functions[easing_type]

    if fn == nil then
        print(
            "未定義のイージング関数: " ..
            tostring(easing_type)
        )

        return Easing.linear
    end

    return fn
end

-- 0.0～1.0の進行率tをイージングして返します。
function Easing.exec(easing_type, t)
    return Easing.get_function(easing_type)(t)
end

-- startからendまでを、進行率vと指定イージングで補間します。
function Easing.step(
    easing_type,
    start_value,
    end_value,
    v
)
    if start_value == end_value then
        return start_value
    end

    if v <= 0 then
        return start_value
    end

    if v >= 1 then
        return end_value
    end

    local eased = Easing.exec(easing_type, v)

    return
        start_value +
        (end_value - start_value) *
        eased
end

-- Playdateのimport後にEasingとして参照できるよう、
-- グローバルにも公開します。
_G.Easing = Easing

return Easing