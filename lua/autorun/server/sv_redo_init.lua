
AddCSLuaFile('includes/modules/notification.extension.lua')
util.AddNetworkString('Redo.SendRedoMessage')

require('redo')

local function get_valid_entities(entities)
    local valid_entities = {}

    for k, ent in ipairs(entities) do
        if IsValid(ent) then
            table.insert(valid_entities, ent)
        end
    end

    return valid_entities
end

hook.Add('PostUndo', 'Redo.CreateRedo', function(undo)
    local entities = get_valid_entities(undo.Entities)
    if #entities < 1 then return end

    local redo_entry = redo.Create(undo.Name)
    redo_entry:SetOwner(undo.Owner)

    if #entities == 1 then
        redo_entry:SetNiceName(entities[1]:GetClass())
    else
        if undo.NiceText and string.find(undo.NiceText, '#undo.duplication') then
            redo_entry:SetName('undo.duplication')
        end
    end

    for k, ent in ipairs(entities) do
        if IsValid(ent) then
            redo_entry:AddEntity(ent)
        end
    end

    redo.Finish(redo_entry)
end)

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
    net.WriteString(redo_entry:GetName())
    net.WriteString(nice_name)
    net.Send(owner)
end)

local function CC_Redo(ply)
    local stack = redo.GetStack(ply)
    if not stack or stack:Size() < 1 then return end

    local redo_entry = stack:Top()
    if hook.Run('PreRedo', redo_entry) == false then return end

    local redone_entities = stack:Pop():Perform()

    hook.Run('PostRedo', redo_entry, redone_entities)
end

concommand.Add('redo', CC_Redo, nil, '', FCVAR_DONTRECORD)
concommand.Add('gmod_redo', CC_Redo, nil, '', FCVAR_DONTRECORD)