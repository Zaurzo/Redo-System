
require('redo')

if SERVER then return end

local icon_path = 'vgui/notices/redo.png'
local sound_path = 'npc/roller/mine/rmine_chirp_answer1.wav'

hook.Add('OnPerformRedo', 'OnPerformRedo', function(name)

    local text = language.GetPhrase('hint.redoneX')
    
    notification.Add(text:format(name), 5, icon_path)

    surface.PlaySound(sound_path)

end)