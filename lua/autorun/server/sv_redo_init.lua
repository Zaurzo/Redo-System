
AddCSLuaFile('includes/modules/notification.extension.lua')
util.AddNetworkString('Redo.SendRedoMessage')

require('redo')

local m_Entity = FindMetaTable('Entity')
local old_Remove = m_Entity.Remove

local current_undo

function m_Entity:Remove(...)
    if current_undo then
        local entities = current_undo.Redo_RemovedByFunction or {}
        current_undo.Redo_RemovedByFunction = entities

        table.insert(entities, self)
    end

    return old_Remove(self, ...)
end

hook.Add('PreUndo', 'Redo.GetEntitiesRemovedByFunction', function(undo)
    if not undo.Functions then return end

    for k, func in pairs(undo.Functions) do
        local callback = func[1]

        func[1] = function(...)
            current_undo = undo

            callback(...)

            current_undo = nil
        end
    end
end)

local function get_valid_entities(undo)
    local valid_entities = {}

    for k, ent in ipairs(undo.Entities) do
        if IsValid(ent) then
            table.insert(valid_entities, ent)
        end
    end

    for k, ent in ipairs(undo.Redo_RemovedByFunction or {}) do
        if IsValid(ent) then
            table.insert(valid_entities, ent)
        end
    end

    return valid_entities
end

hook.Add('PostUndo', 'Redo.CreateRedo', function(undo)
    local entities = get_valid_entities(undo)
    if #entities < 1 then return end

    local redo_entry = redo.Create(undo.Name)

    redo_entry:SetUndoTable(undo)
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
    local name = redo_entry:GetName()
    local owner = redo_entry:GetOwner()

    undo.Create(name)
    undo.SetPlayer(owner)
    
    for k, ent in ipairs(redone_entities) do
        undo.AddEntity(ent)
    end

    local undo_table = redo_entry:GetUndoTable()

    if undo_table then
        if undo_table.CustomUndoText then
            undo.SetCustomUndoText(undo_table.CustomUndoText)
        end
    end

    undo.Finish(nice_name)

    net.Start('Redo.SendRedoMessage')
    net.WriteString(name)
    net.WriteString(nice_name)
    net.Send(owner)
end)

local function CC_Redo(ply)
    local stack = redo.GetStack(ply)
    if not stack or stack:Size() < 1 then return end

    local redo_entry = stack:Top()

    if not redo_entry:IsPrepared() then return end
    if hook.Run('PreRedo', redo_entry) == false then return end

    local redone_entities = stack:Pop():Perform()

    hook.Run('PostRedo', redo_entry, redone_entities)
end

concommand.Add('redo', CC_Redo, nil, '', FCVAR_DONTRECORD)