
require('notification.extension')

local icon_path = 'vgui/notices/redo.png'
local sound_path = 'npc/roller/mine/rmine_chirp_answer1.wav'

local function resolve_name(name, nice_name)
    local phrase = language.GetPhrase(nice_name)
    local resolved_name = phrase

    if phrase == nice_name then
        resolved_name = name
    end

    return language.GetPhrase(resolved_name)
end

net.Receive('Redo.SendRedoMessage', function()
    local name = net.ReadString()
    local nice_name = net.ReadString()
    
    local text = string.format(
        language.GetPhrase('hint.redoneX'),
        resolve_name(name, nice_name)
    )
    
    notification.Add(text, 5, icon_path)

    surface.PlaySound(sound_path)
end)