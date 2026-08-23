import "CoreLibs/graphics"

local gfx <const> = playdate.graphics
local PANEL_X <const> = 8
local PANEL_Y <const> = 4
local PANEL_WIDTH <const> = 384
local PANEL_HEIGHT <const> = 42

---@class AchievementNotificationRenderer
local AchievementNotificationRenderer = {}
AchievementNotificationRenderer.__index = AchievementNotificationRenderer

function AchievementNotificationRenderer.new(manager, englishFont)
    return setmetatable({ manager = manager, englishFont = englishFont },
        AchievementNotificationRenderer)
end

function AchievementNotificationRenderer:draw()
    local notification = self.manager:currentNotification()
    if notification == nil then return end

    local previousFont = gfx.getFont()
    local previousDrawMode = gfx.getImageDrawMode()
    local notificationFont = self.englishFont or gfx.getSystemFont()
    if notificationFont ~= nil then gfx.setFont(notificationFont) end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(PANEL_X, PANEL_Y, PANEL_WIDTH, PANEL_HEIGHT, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(PANEL_X, PANEL_Y, PANEL_WIDTH, PANEL_HEIGHT, 4)
    gfx.drawTextAligned("ACHIEVEMENT UNLOCKED", 200, 7,
        kTextAlignment.center)
    local detail = string.format("No. %02d  %s",
        notification.displayNo, notification.displayName)
    gfx.drawTextAligned(detail, 200, 23, kTextAlignment.center)
    gfx.setImageDrawMode(previousDrawMode)
    if previousFont ~= nil then gfx.setFont(previousFont) end
end

_G.AchievementNotificationRenderer = AchievementNotificationRenderer
return AchievementNotificationRenderer
