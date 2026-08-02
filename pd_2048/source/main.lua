import "CoreLibs/graphics"
import "app"

local app = App.new()

function playdate.update()
    app:update()
    app:draw()
end
