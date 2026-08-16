import "CoreLibs/graphics"
import "app"

local app = App.new()

function playdate.update()
    app:update()
    app:draw()
end

-- システムメニューからホームへ戻る直前にNORMALを中断保存する.
function playdate.gameWillTerminate()
    app:autoSuspendNormal()
end

-- 低バッテリーによるスリープへ入る直前にNORMALを中断保存する.
function playdate.deviceWillSleep()
    app:autoSuspendNormal()
end
