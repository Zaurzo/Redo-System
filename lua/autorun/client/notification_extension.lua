
if notification.Add then return end

local notice_panels = {}

function notification.Add(text, length, icon, color)

    notification.AddLegacy(text, 0, length)

    local notice = notice_panels[#notice_panels]

    if icon then
        icon = Material(icon)
	    notice.Image:SetMaterial(icon)
    end

	if color then
	  	notice.Label:SetTextColor( color )
	end

    return notice

end

function notification.GetAll()

    local notices, n = {}, 0

    for k, notice in ipairs(notice_panels) do
        n = n + 1
        notices[n] = notice
    end

    return notices

end

-- Overrides

local PANEL = vgui.GetControlTable('NoticePanel')

local old_Init = PANEL.Init or function() end
local old_OnRemove = PANEL.OnRemove or function() end

function PANEL:Init(...)

    table.insert(notice_panels, self)

    return old_Init(self, ...)

end

function PANEL:OnRemove(...)
    
    table.RemoveByValue(notice_panels, self)

    return old_OnRemove(self, ...)

end