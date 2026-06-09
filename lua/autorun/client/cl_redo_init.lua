
require('notification.extension')

local icon_path = 'vgui/notices/redo.png'
local sound_path = 'npc/roller/mine/rmine_chirp_answer1.wav'

net.Receive('Redo.SendRedoMessage', function()
    local nice_name = language.GetPhrase(net.ReadString())
    local text = 'Redone "' .. nice_name .. '"'
    
    notification.Add(text, 5, icon_path)

    surface.PlaySound(sound_path)
end)