
redo = {}

local Entity = Entity
local istable, isentity, type = istable, isentity, type
local linq, duplicator, constraint = include('redo/util.lua')

local RedoEntry = {}
RedoEntry.__index = RedoEntry

AccessorFunc(RedoEntry, 'player_owner', 'Owner')
AccessorFunc(RedoEntry, 'name', 'Name', FORCE_STRING)
AccessorFunc(RedoEntry, 'nice_name', 'NiceName', FORCE_STRING)

local filter = {
    ['PhysObj'] = true,
    ['CLuaLocomotion'] = true
}

local function filter_out_invalid_objects(_, v)
    if isentity(v) or filter[ type(v) ] then
        return not IsValid(v), nil
    end
end

local function get_restored_entities()
    local restored = {}

    for k, ent in ents.Iterator() do
        local index = ent.Redo_RestoreID

        if index then
            restored[index] = ent
        end
    end

    return restored
end

function RedoEntry:Perform()
    if not self:IsPrepared() then
        return error('cannot perform unprepared redo')
    end

    local data = self:GetCreateData()
    local owner = self:GetOwner()

    -- Clear the data of any invalid/NULL objects
    linq.MapRecursive(data, filter_out_invalid_objects)

    DisablePropCreateEffect = true
    
    local entities, constraints = duplicator.Paste(owner, data.Entities, {})

    DisablePropCreateEffect = false

    local restored = get_restored_entities()

    -- Restore constraints
    -- We do it manually as the constraints given by duplicator.Paste
    -- aren't mapped by their original creation ID.
    for _, const_data in pairs(data.Constraints) do
        local constrained_entities = {}
        local ent_data = const_data.Entity

        for i = 1, 6 do
            local ent = const_data['Ent' .. i]

            if IsValid(ent) then
                constrained_entities[ent:EntIndex()] = ent
            elseif ent_data[i] then
                local index = ent_data[i].Index

                -- Fixup constraint copy data to use restored entities
                ent = entities[index]

                if not ent then
                    local restore_id = ent_data[i].Redo_RestoreID
                    ent = restore_id and restored[restore_id] or nil
                end

                if ent then
                    ent_data[i].Entity = ent
                    constrained_entities[index] = ent
                end
            end
        end

        local consts = { duplicator.CreateConstraintFromTable(
            const_data,
            constrained_entities,
            owner
        ) }

        for k, const in ipairs(consts) do
            if const then
                constraints[const:GetCreationID()] = const
            end
        end
    end
    
    for index, ent in pairs(entities) do
        local tab = data.Entities[index]
        ent.Redo_RestoreID = tab.Redo_RestoreID

        if tab.PhysicsObjects then
            for phys_num, phys_data in pairs(tab.PhysicsObjects) do
                local phys = ent:GetPhysicsObjectNum(phys_num)

                if IsValid(phys) then
                    phys:SetVelocity(phys_data.Velocity)
                    phys:SetAngleVelocity(phys_data.AngleVelocity)
                end
            end
        end
    end

    local redone_entities = {}

    table.Add(redone_entities, entities)
    table.Add(redone_entities, constraints)

    return redone_entities
end

function RedoEntry:Prepare()
    if self:IsPrepared() then return end

    local data = self:GetCreateData()

    for ent in pairs(self.entities_to_copy) do
        if constraint.IsConstraint(ent) then
            data.Constraints[ent:GetCreationID()] = duplicator.CopyConstraint(ent)
        elseif not data.Entities[ent:EntIndex()] then
            duplicator.ForceCopy(ent, data)
        end
    end

    --PrintTable(table.GetKeys(data.Constraints))

    local id_to_entity = {}

    for index, tab in pairs(data.Entities) do
        local ent = Entity(index)
        local phys_objs = tab.PhysicsObjects or {}

        id_to_entity[index] = ent

        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)

            if phys and phys:IsValid() then
                phys_objs[i].Velocity = phys:GetVelocity()
                phys_objs[i].AngleVelocity = phys:GetAngleVelocity()
            end
        end
    end

    for id, tab in pairs(data.Constraints) do
        for i = 1, 6 do
            if tab.Entity[i] then
                local ent = tab.Entity[i].Entity
                tab.Entity[i].Redo_RestoreID = ent.Redo_RestoreID
            end
        end
    end

    -- Wait a little bit
    timer.Simple(0.1, function()
        -- Clear the data of any entity that still exists
        for index, ent in pairs(id_to_entity) do
            if IsValid(ent) then
                data.Entities[index] = nil
            end
        end

        self.is_prepared = true
    end)
end

function RedoEntry:AddEntity(ent)
    self.entities_to_copy[ent] = true
end

function RedoEntry:GetCreateData()
    return self.create_data
end

function RedoEntry:IsPrepared()
    return self.is_prepared
end

local redo_stacks = {}

function redo.Create(name)
    local entry = {}

    entry.entities_to_copy = {}
    entry.create_data = {
        Entities = {},
        Constraints = {},
        SingleConstraints = {}
    }

    entry.is_prepared = false

    setmetatable(entry, RedoEntry)

    entry:SetName(name)
    entry:SetNiceName(name)

    return entry
end

function redo.Finish(entry)
    local owner = entry:GetOwner()

    if not IsValid(owner) or not owner:IsPlayer() then
        return error('cannot finish redo entry without a player owner') 
    end

    local stack = redo_stacks[owner]

    if not stack then
        stack = util.Stack()
        redo_stacks[owner] = stack
    end

    entry:Prepare()
    stack:Push(entry)
end

function redo.GetStack(ply)
    return redo_stacks[ply]
end

hook.Add('OnEntityCreated', 'Redo.SetRestoreID', function(ent)
    ent.Redo_RestoreID = {}
end)