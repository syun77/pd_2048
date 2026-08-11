local SystemMenuController = {}
SystemMenuController.__index = SystemMenuController

function SystemMenuController.new(menu)
    return setmetatable({ menu = menu }, SystemMenuController)
end

function SystemMenuController:setItems(items)
    self.menu:removeAllMenuItems()
    for _, item in ipairs(items or {}) do
        if item.type == "checkmark" then
            self.menu:addCheckmarkMenuItem(item.title, item.value == true, item.callback)
        else
            self.menu:addMenuItem(item.title, item.callback)
        end
    end
end

_G.SystemMenuController = SystemMenuController
return SystemMenuController
