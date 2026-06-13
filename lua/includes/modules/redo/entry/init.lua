
local Entity = Entity
local istable, isentity, type = istable, isentity, type
local vector_zero, angle_zero = Vector(), Angle()

local RedoEntry = {}
RedoEntry.__index = RedoEntry

AccessorFunc(RedoEntry, 'player_owner', 'Owner')
AccessorFunc(RedoEntry, 'name', 'Name', FORCE_STRING)
AccessorFunc(RedoEntry, 'nice_name', 'NiceName', FORCE_STRING)
AccessorFunc(RedoEntry, 'undo_table', 'UndoTable')

local linq, duplicator, constraint = include('util.lua')

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

        for i = 1, #ent_data do
            local tab = ent_data[i]
            local index = tab.Index
            local ent = const_data['Ent' .. i]

            if IsValid(ent) then
                constrained_entities[index] = ent
            else
                tab.Removed = true

                -- Fixup constraint copy data to use restored entities
                ent = entities[index]

                if not ent then
                    local restore_id = tab.Redo_RestoreID
                    ent = restore_id and restored[restore_id] or nil
                end

                if ent then
                    tab.Entity = ent
                    constrained_entities[index] = ent
                end
            end
        end

        local restore_positions = owner:GetInfoNum('redo_tight_constraints', 1) == 1

        -- Restore positions of tightly constrained entities
        if redo.IsTightConstraint(const_data.Type) and restore_positions then
            local ent1, ent2 = const_data.Entity[1], const_data.Entity[2]

            if ent1 and ent2 and ent1.Entity and ent2.Entity then
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

    local restore_velocity = owner:GetInfoNum('redo_restore_velocity', 1) == 1
    
    for index, ent in pairs(entities) do
        local tab = data.Entities[index]
        ent.Redo_RestoreID = tab.Redo_RestoreID

        if restore_velocity and tab.PhysicsObjects then
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

local function world_to_local_pair(ent1, ent2)

    return WorldToLocal(
        ent1.Entity:GetPos(),
        ent1.Entity:GetAngles(),
        ent2.Entity:GetPos(),
        ent2.Entity:GetAngles()
    )

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
            data.Constraints[ ent:GetCreationID() ] = duplicator.CopyConstraint(ent)
        else
            if not data.Entities[ ent:EntIndex() ] then
                duplicator.SetLocalPos(paste_pos)
                duplicator.SetLocalAng(angle_zero)

                duplicator.ForceCopy(ent, data)

                duplicator.SetLocalPos(vector_zero)
            end
        end
    end

    self.paste_pos = paste_pos

    local entity_count = 0

    for index, tab in pairs(data.Entities) do
        local ent = Entity(index)

        if self.entities_to_copy[ent] then
            entity_count = entity_count + 1
            
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

    local constraint_count = 0

    for id, tab in pairs(data.Constraints) do
        constraint_count = constraint_count + 1

        for i = 1, 6 do
            local ent_data = tab.Entity[i]

            if ent_data then
                ent_data.Redo_RestoreID = ent_data.Entity.Redo_RestoreID
            end
        end

        if redo.IsTightConstraint(tab.Type) then
            local ent1, ent2 = tab.Entity[1], tab.Entity[2]

            ent1.LocalPos, ent1.LocalAng = world_to_local_pair(ent1, ent2)
            ent2.LocalPos, ent2.LocalAng = world_to_local_pair(ent2, ent1)
        end
    end

    self.is_prepared = true

    return entity_count, constraint_count

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

local function factory(name)

    local entry = {}

    entry.entities_to_copy = {}
    entry.create_data = {
        Entities = {},
        Constraints = {},
        SingleConstraints = {}
    }

    entry.is_prepared = false

    setmetatable(entry, RedoEntry)

    if name then
        entry:SetName(name)
        entry:SetNiceName(name)
    end

    return entry

end

return factory