
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

-- Saving NextBot locomotion usually leads to problems/errors
-- so we just clear any of it
local function clear_locomotion(tab)
    for k, v in pairs(tab) do
        if type(v) == 'CLuaLocomotion' then
            ent_data[k] = nil
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

function RedoEntry:Paste()
    DisablePropCreateEffect = true

    local data = self:GetCreateData()
    local owner = self:GetOwner()
    
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
        return error('cannot finish redo without a player owner') 
    end

    local stack = redo_stacks[owner]

    if not stack then
        stack = util.Stack()
        redo_stacks[owner] = stack
    end

    entry:Prepare()
    stack:Push(entry)
end

hook.Add('PostUndo', 'Redo.CreateRedo', function(undo)
    local entities = undo.Entities
    if #entities < 1 or not IsTableOfEntitiesValid(entities) then return end

    local redo_entry = redo.Create(undo.Name)
    redo_entry:SetOwner(undo.Owner)

    if undo.NiceName then
        redo_entry:SetNiceName(undo.NiceName)
    end

    for k, ent in ipairs(entities) do
        if IsValid(ent) then
            redo_entry:AddEntity(ent)
        end
    end

    redo.Finish(redo_entry)
end)

concommand.Add('redo', function(ply)
    local stack = redo_stacks[ply]
    if not stack then return end

    local redo_entry = stack:Top()

    if redo_entry and hook.Run('PreRedo', redo_entry) ~= false then
        local redone_entities = stack:Pop():Paste()

        hook.Run('PostRedo', redo_entry, redone_entities)
    end
end)