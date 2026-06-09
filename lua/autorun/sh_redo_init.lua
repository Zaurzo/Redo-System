
require('notification.extension')

if SERVER then
    require('redo')

    util.AddNetworkString('Redo.SendRedoMessage')

    hook.Add('PostRedo', 'PostRedo', function(redo_entry, redone_entities)
        local nice_name = redo_entry:GetNiceName()
        local owner = redo_entry:GetOwner()

        undo.Create(redo_entry:GetName())
        undo.SetPlayer(owner)
        
        for k, ent in ipairs(redone_entities) do
            undo.AddEntity(ent)
        end

        undo.Finish(nice_name)

        net.Start('Redo.SendRedoMessage')
        net.WriteString(nice_name)
        net.Send(owner)
    end)
else
    local icon_path = 'vgui/notices/redo.png'
    local sound_path = 'npc/roller/mine/rmine_chirp_answer1.wav'

    net.Receive('Redo.SendRedoMessage', function()
        local nice_name = language.GetPhrase(net.ReadString())
        local text = 'Redone "' .. nice_name .. '"'

        surface.PlaySound(sound_path)
        
        notification.Add(text, 5, icon_path)
    end)
end