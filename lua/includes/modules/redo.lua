
AddCSLuaFile()

module('redo', package.seeall)

if SERVER then
    util.AddNetworkString('Redo.OnFinished')
    util.AddNetworkString('Redo.OnPerformed')
end

if CLIENT then

    local list = {}
    local ui_dirty = true

    function GetLocalList()
        return list
    end

    local function resolve_name(name, nice_name)

        local phrase = language.GetPhrase(nice_name)
        local resolved_name = phrase

        if phrase == nice_name then
            resolved_name = name
        end

        return language.GetPhrase(resolved_name)

    end

    net.Receive('Redo.OnFinished', function()

        local name, nice_name = net.ReadString(), net.ReadString()
        local entity_count = net.ReadUInt(32)
        local constraint_count = net.ReadUInt(32)

        local entry = {
            name = resolve_name(name, nice_name),
            entity_count = entity_count,
            constraint_count = constraint_count
        }

        table.insert( list, entry )

        ui_dirty = true

    end)

    net.Receive('Redo.OnPerformed', function()

        local index = net.ReadUInt(32)
        local entry = table.remove(list, index)

        hook.Run('OnPerformRedo', entry.name)

        ui_dirty = true

    end)

    -- Control panel

    CreateClientConVar('redo_tight_constraints', '1', true, true)
    CreateClientConVar('redo_restore_velocity', '1', true, true)

    local function update_panel()

        local panel = controlpanel.Get('Redo')
        if not panel:IsValid() then return end

        panel:Clear()
        panel:Help('#spawnmenu.utilities.redo.help')

        panel:CheckBox('#spawnmenu.utitilies.redo.velocity', 'redo_restore_velocity')
        panel:CheckBox('#spawnmenu.utitilies.redo.constraints', 'redo_tight_constraints')
    
        panel:Help('#spawnmenu.utilities.redo.help.constraints')

        local entry_list = vgui.Create('DListView', panel)

        entry_list:SetMultiSelect(false)
        entry_list:SetTall(500)
        entry_list:AddColumn('Name')
        entry_list:AddColumn('Entities')
        entry_list:AddColumn('Constraints')

        for k, entry in ipairs(list) do
            entry_list:AddLine(entry.name, entry.entity_count, entry.constraint_count)
        end

        function entry_list:OnRowSelected(index)
            RunConsoleCommand('redo_num', index)
        end

        panel:AddItem(entry_list)

    end

    hook.Add('PopulateToolMenu', 'Redo.ControlPanel', function()

        local function setup_panel(panel)

            function panel:Think()
                if not ui_dirty then return end

                timer.Simple(0, update_panel)

                ui_dirty = false
            end

        end

        spawnmenu.AddToolMenuOption(
            'Utilities', 
            'User', 
            'Redo', 
            '#spawnmenu.utilities.redo', 
            '', 
            '', 
            setup_panel
        )

    end)

    return

end

local RedoEntry = include('redo/entry/init.lua')

local tight_constraint_types = {}
local redo_lists = {}

function Create(name)
    return RedoEntry(name)
end

function Finish(entry)

    local owner = entry:GetOwner()

    if not IsValid(owner) or not owner:IsPlayer() then
        return error('cannot finish redo entry without a player owner') 
    end

    local list = redo_lists[owner]

    if not list then
        list = {}
        redo_lists[owner] = list
    end

    local entity_count, constraint_count = entry:Prepare()
    
    table.insert(list, entry)

    net.Start('Redo.OnFinished')
    net.WriteString(entry:GetName())
    net.WriteString(entry:GetNiceName())
    net.WriteUInt(entity_count, 32)
    net.WriteUInt(constraint_count, 32)
    net.Send(owner)

end

function Perform(ply, index)

    local list = GetList(ply)
    if not list then return end

    index = index or #list
    if index < 1 or index > #list then return end

    local entry = list[index]

    if not entry:IsPrepared() then return end
    if hook.Run('PreRedo', entry) == false then return end

    local redone_entities = entry:Perform()

    net.Start('Redo.OnPerformed')
    net.WriteUInt(index, 32)
    net.Send(ply)

    hook.Run('PostRedo', entry, redone_entities)

    table.remove(list, index)

end

function GetList(ply)
    return redo_lists[ply]
end

function RegisterTightConstraint(const_type)
    tight_constraint_types[const_type] = true
end

function IsTightConstraint(const_type)
    return tight_constraint_types[const_type] or false
end

RegisterTightConstraint('Weld')

hook.Add('OnEntityCreated', 'Redo.SetRestoreID', function(ent)
    ent.Redo_RestoreID = {}
end)