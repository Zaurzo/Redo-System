
local Entity = Entity
local istable, isentity, type = istable, isentity, type

redo = {}

local RedoEntry = {}
RedoEntry.__index = RedoEntry

AccessorFunc(RedoEntry, 'player_owner', 'Owner')
AccessorFunc(RedoEntry, 'name', 'Name', FORCE_STRING)
AccessorFunc(RedoEntry, 'nice_name', 'NiceName', FORCE_STRING)

local function get_constraint_data(const)
    local constraints = constraint.GetTable(const.Ent1)
    if not constraints then return end

    for k, const_data in ipairs(constraints) do
        if const_data.Constraint == const then
            return const_data
        end
    end
end

local function force_copy(ent)
    local do_not_duplicate = ent.DoNotDuplicate
    local allowed = duplicator.IsAllowed(ent)

    ent.DoNotDuplicate = false

    duplicator.Allow(ent)

    local copy = duplicator.Copy(ent)

    if not allowed then
        duplicator.Disallow(ent)
    end

    ent.DoNotDuplicate = do_not_duplicate

    return copy
end

local filter = {
    ['PhysObj'] = true,
    ['CLuaLocomotion'] = true
}

local function filter_out_invalid_objects(tab, done)
    for k, v in pairs(tab) do
        if isentity(v) or filter[ type(v) ] then
            if not IsValid(v) then
                tab[k] = nil
            end
            
            continue
        end

        if istable(v) then
            done = done or {}

            if not done[v] then
                done[v] = true

                filter_out_invalid_objects(v, done)
            end
        end
    end
end

function RedoEntry:Perform()
    if not self:IsPrepared() then
        return error('cannot perform unprepared redo')
    end

    local data = self:GetCreateData()
    local owner = self:GetOwner()

    DisablePropCreateEffect = true

    filter_out_invalid_objects(data)
    
    local entities, constraints = duplicator.Paste(
        owner, 
        data.entities, 
        data.constraints
    )

    DisablePropCreateEffect = false

    for k, const_data in pairs(data.single_constraints) do
        local constrained_entities = {}

        for i = 1, 6 do
            local ent = const_data['Ent' .. i]

            if IsValid(ent) then
                constrained_entities[ent:EntIndex()] = ent
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
        local tab = data.entities[index]

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
        if ent:IsConstraint() then
            data.single_constraints[ent:GetCreationID()] = get_constraint_data(ent)
        end

        if not data.entities[ent:EntIndex()] then
            local copy = force_copy(ent)

            table.Merge(data.entities, copy.Entities)
            table.Merge(data.constraints, copy.Constraints)
        end
    end

    for index, tab in pairs(data.entities) do
        local ent = Entity(index)
        local phys_objs = tab.PhysicsObjects or {}

        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)

            if phys and phys:IsValid() then
                phys_objs[i].Velocity = phys:GetVelocity()
                phys_objs[i].AngleVelocity = phys:GetAngleVelocity()
            end
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
        entities = {},
        constraints = {},
        single_constraints = {}
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