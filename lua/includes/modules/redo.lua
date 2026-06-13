
redo = {}

local tight_constraint_types = {}

local Entity = Entity
local istable, isentity, type = istable, isentity, type
local linq, duplicator, constraint = include('redo/util.lua')

local vector_zero, angle_zero = Vector(), Angle()

local RedoEntry = {}
RedoEntry.__index = RedoEntry

AccessorFunc(RedoEntry, 'player_owner', 'Owner')
AccessorFunc(RedoEntry, 'name', 'Name', FORCE_STRING)
AccessorFunc(RedoEntry, 'nice_name', 'NiceName', FORCE_STRING)
AccessorFunc(RedoEntry, 'undo_table', 'UndoTable')

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

    duplicator.SetLocalPos(self.paste_pos)
    duplicator.SetLocalAng(angle_zero)

    local entities, constraints = duplicator.Paste(owner, data.Entities, {})

    duplicator.SetLocalPos(vector_zero)

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
                ent_data[i].Removed = true

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

        if tight_constraint_types[const_data.Type] then
            local ent1, ent2 = const_data.Entity[1], const_data.Entity[2]

            if ent1 and ent2 then
                local parent_ent, child_ent

                -- Choose best entity to change position and angle for
                if ent1.Removed then
                    parent_ent, child_ent = ent1, ent2
                elseif ent2.Removed then
                    parent_ent, child_ent = ent2, ent1
                else
                    parent_ent, child_ent = ent1, ent2

                    local world_pos1 = ent1.Entity:GetPos()
                    local world_pos2 = ent2.Entity:GetPos()
                    local main_pos = self.paste_pos

                    if world_pos1:DistToSqr(main_pos) <= world_pos2:DistToSqr(main_pos) then
                        parent_ent, child_ent = ent2, ent1
                    end
                end

                local pos1, ang1 = LocalToWorld(
                    parent_ent.LocalPos,
                    parent_ent.LocalAng,
                    child_ent.Entity:GetPos(),
                    child_ent.Entity:GetAngles()
                )

                parent_ent.Entity:SetPos(pos1)
                parent_ent.Entity:SetAngles(ang1)
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
    local paste_pos

    for ent in pairs(self.entities_to_copy) do
        if not paste_pos then
            paste_pos = ent:GetPos()
        end

        if constraint.IsConstraint(ent) then
            data.Constraints[ent:GetCreationID()] = duplicator.CopyConstraint(ent)
        elseif not data.Entities[ent:EntIndex()] then
            duplicator.SetLocalPos(paste_pos)
            duplicator.SetLocalAng(angle_zero)

            duplicator.ForceCopy(ent, data)

            duplicator.SetLocalPos(vector_zero)
        end
    end

    self.paste_pos = paste_pos

    for index, tab in pairs(data.Entities) do
        local ent = Entity(index)

        if self.entities_to_copy[ent] then
            local phys_objs = tab.PhysicsObjects or {}

            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                local phys = ent:GetPhysicsObjectNum(i)

                if phys and phys:IsValid() then
                    phys_objs[i].Velocity = phys:GetVelocity()
                    phys_objs[i].AngleVelocity = phys:GetAngleVelocity()
                end
            end
        else
            data.Entities[index] = nil
        end
    end

    for id, tab in pairs(data.Constraints) do
        for i = 1, 6 do
            local ent_data = tab.Entity[i]

            if ent_data then
                ent_data.Redo_RestoreID = ent_data.Entity.Redo_RestoreID
            end
        end

        if tight_constraint_types[tab.Type] then
            local ent1, ent2 = tab.Entity[1], tab.Entity[2]

            ent1.LocalPos, ent1.LocalAng = WorldToLocal(
                ent1.Entity:GetPos(),
                ent1.Entity:GetAngles(),
                ent2.Entity:GetPos(),
                ent2.Entity:GetAngles()
            )

            ent2.LocalPos, ent2.LocalAng = WorldToLocal(
                ent2.Entity:GetPos(),
                ent2.Entity:GetAngles(),
                ent1.Entity:GetPos(),
                ent1.Entity:GetAngles()
            )
        end
    end

    self.is_prepared = true
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

function redo.RegisterTightConstraint(const_type)
    tight_constraint_types[const_type] = true
end

redo.RegisterTightConstraint('Weld')

hook.Add('OnEntityCreated', 'Redo.SetRestoreID', function(ent)
    ent.Redo_RestoreID = {}
end)