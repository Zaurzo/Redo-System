
local redo_util = {}

local istable, isentity = istable, isentity
local duplicator = duplicator

-- LINQ

local linq = {}

function linq.Map(tbl, predicate)
    for k, v in pairs(tbl) do
        local replace, replacement = predicate(k, v)

        if replace then
            tbl[k] = replacement
        end
    end
end

local function each_recursive(tbl, action, done)
    for k, v in pairs(tbl) do
        action(tbl, k, v)

        if istable(v) then
            done = done or {}

            if not done[v] then
                done[v] = true

                each_recursive(v, action, done)
            end
        end
    end

    return tbl
end

function linq.EachRecursive(tbl, action)
    return each_recursive(tbl, action)
end

function linq.MapRecursive(tbl, predicate)
    local function action(tbl, k, v)
        local replace, replacement = predicate(k, v)

        if replace then
            tbl[k] = replacement
        end
    end

    return each_recursive(tbl, action)
end

function linq.WhereRecursive(tbl, predicate)
    local values, n = {}, 0

    local function action(_, v)
        if predicate(v) then
            n = n + 1
            values[n] = v
        end
    end

    each_recursive(tbl, action)

    return values
end

-- Duplicator

local duplicator = setmetatable({}, { __index = duplicator })

function duplicator.ForceCopy(ent, output)
    local do_not_duplicate = ent.DoNotDuplicate
    local allowed = duplicator.IsAllowed(ent)

    ent.DoNotDuplicate = false

    duplicator.Allow(ent)

    local copy = duplicator.Copy(ent, output)

    if not allowed then
        duplicator.Disallow(ent)
    end

    ent.DoNotDuplicate = do_not_duplicate

    return copy
end

function duplicator.GetAllStoredEntities(data)
    local stored_entities = {}

    linq.EachRecursive(data, function(tbl, k, v)
        if isentity(v) and IsValid(v) then
            stored_entities[v:EntIndex()] = v
        end
    end)

    return stored_entities
end

function duplicator.CopyConstraint(const)
    local constraints = constraint.GetTable(const.Ent1)
    if not constraints then return end

    for k, const_data in ipairs(constraints) do
        if const_data.Constraint == const then
            return const_data
        end
    end
end

-- Constraint

local constraint = setmetatable({}, { __index = constraint })

local constraint_classes = {
    ['phys_spring'] = true,
    ['phys_slideconstraint'] = true,
    ['phys_torque'] = true
}

function constraint.IsConstraint(ent)
    if ent:IsConstraint() then
        return true
    end

    return constraint_classes[ent:GetClass()]
end

-- Misc

--[[local misc = {}

local m_Entity = FindMetaTable('Entity')
local old_Spawn = m_Entity.Spawn

local spawn_stack = util.Stack()

function m_Entity:Spawn(...)
    spawn_stack:Push(self)

    old_Spawn(self, ...)

    spawn_stack:Pop()
end

local initializer_ents

local function clear()
    initializer_ents = nil
end

hook.Add('OnEntityCreated', 'Redo.Util', function(ent)
    local root_ent = spawn_stack:Top()
    if not root_ent then return end

    initializer_ents = initializer_ents or {}

    local list = initializer_ents[root_ent] or {}
    table.insert(list, ent)

    initializer_ents[root_ent] = list

    timer.Create('RedoUtil.ClearInitializerEnts', 0, 1, clear)
end)

function misc.GetEntitiesCreatedFromInitializer(ent)
    return initializer_ents and initializer_ents[ent] or nil
end]]

return linq, duplicator, constraint, misc