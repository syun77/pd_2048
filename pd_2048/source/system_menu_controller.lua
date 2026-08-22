---@class SystemMenuController システムメニューコントローラー.
---@field menu playdate.menu システムメニュー.
local SystemMenuController = {}
SystemMenuController.__index = SystemMenuController

-- 生成.
---@param menu playdate.menu システムメニュー.
---@return SystemMenuController システムメニューコントローラー.
function SystemMenuController.new(menu)
    return setmetatable({ menu = menu }, SystemMenuController)
end

-- アイテムの登録.
---@param items table[]|nil アイテムリスト. nilの場合はメニューを空にする.
function SystemMenuController:setItems(items)
    self.menu:removeAllMenuItems()
    for _, item in ipairs(items or {}) do
        if item.type == "options" then
            self.menu:addOptionsMenuItem(
                item.title, item.options, item.value, item.callback)
        elseif item.type == "checkmark" then
            self.menu:addCheckmarkMenuItem(item.title, item.value == true, item.callback)
        else
            self.menu:addMenuItem(item.title, item.callback)
        end
    end
end

_G.SystemMenuController = SystemMenuController
return SystemMenuController
