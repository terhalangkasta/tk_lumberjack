-- client/main.lua
local sharedConfig = require 'config.shared'
local clientConfig = require 'config.client'

local RSGCore = exports['rsg-core']:GetCoreObject()

local treeObjects   = {} -- [treeId] = entity
local treeBlips     = {} -- [treeId] = blip
local treeCoordsMap = {} -- [treeId] = vec3
local treeCount     = 0

local CHECK_DIST_SQ = sharedConfig.radius.request * sharedConfig.radius.request
local BLIP_RAD_SQ   = sharedConfig.radius.blip    * sharedConfig.radius.blip

local chopTree -- forward declaration for chopOptions closure

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function dprint(...)
    if sharedConfig.debug then print('[tk_lumberjack]', ...) end
end

-- shared chop options table — reused for every tree
local chopOptions = {
    {
        icon       = 'axe',
        label      = locale('chop_label'),
        distance   = 2.5,
        drawSprite = false,
        onSelect   = function(data)
            for id, ent in pairs(treeObjects) do
                if ent == data.entity then
                    chopTree(id, ent)
                    return
                end
            end
        end,
    },
}

-- ---------------------------------------------------------------------------
-- spawn / remove
-- ---------------------------------------------------------------------------
local function SpawnTree(treeId, coords)
    if treeObjects[treeId] and DoesEntityExist(treeObjects[treeId]) then return end

    local model = sharedConfig.treeModel
    lib.requestModel(model)

    local obj = CreateObject(model, coords.x, coords.y, coords.z - 1.5, true, true, true)
    SetEntityAsMissionEntity(obj, true)
    SetModelAsNoLongerNeeded(model)

    treeObjects[treeId]   = obj
    treeCoordsMap[treeId] = vector3(coords.x, coords.y, coords.z)
    treeCount             = treeCount + 1

    exports.ox_target:addLocalEntity(obj, chopOptions)
end

local function RemoveTree(treeId)
    local ent = treeObjects[treeId]
    if ent then
        exports.ox_target:removeLocalEntity(ent)
        if DoesEntityExist(ent) then
            DeleteObject(ent)
        end
        treeObjects[treeId]   = nil
        treeCoordsMap[treeId] = nil
        treeCount             = treeCount - 1
    end

    local blip = treeBlips[treeId]
    if blip then
        RemoveBlip(blip)
        treeBlips[treeId] = nil
    end
end

-- ---------------------------------------------------------------------------
-- net events
-- ---------------------------------------------------------------------------
RegisterNetEvent('tk_lumberjack:client:syncTrees', function(list)
    if not list then return end
    for i = 1, #list do
        local t = list[i]
        SpawnTree(t.id, vector3(t.x, t.y, t.z))
    end
end)

RegisterNetEvent('tk_lumberjack:client:spawnTree', function(treeId, coords)
    SpawnTree(treeId, coords)
end)

RegisterNetEvent('tk_lumberjack:client:removeTree', function(treeId)
    RemoveTree(treeId)
end)

RegisterNetEvent('tk_lumberjack:client:toppleTree', function(treeId)
    local entity = treeObjects[treeId]
    if not (entity and DoesEntityExist(entity)) then
        RemoveTree(treeId)
        return
    end
    CreateThread(function()
        for rot = 1, 90 do
            SetEntityRotation(entity, rot * 1.0, 0.0, 0.0, 1, true)
            Wait(10)
        end
        Wait(sharedConfig.timers.toppleDelayMs)
        RemoveTree(treeId)
    end)
end)

-- ---------------------------------------------------------------------------
-- request loop (only when player moved enough)
-- ---------------------------------------------------------------------------
CreateThread(function()
    local lastCoords
    while true do
        Wait(clientConfig.requestIntervalMs)
        local ped = cache.ped
        if ped then
            local pc = GetEntityCoords(ped)
            if not lastCoords then
                lastCoords = pc
                TriggerServerEvent('tk_lumberjack:server:requestTrees')
            else
                local dx, dy, dz = pc.x - lastCoords.x, pc.y - lastCoords.y, pc.z - lastCoords.z
                if (dx * dx + dy * dy + dz * dz) > CHECK_DIST_SQ then
                    lastCoords = pc
                    TriggerServerEvent('tk_lumberjack:server:requestTrees')
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- blip loop
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if treeCount == 0 then
            Wait(clientConfig.blipIdleMs)
        else
            Wait(clientConfig.blipIntervalMs)
            local ped = cache.ped
            if ped then
                local pc = GetEntityCoords(ped)
                for id, coords in pairs(treeCoordsMap) do
                    local dx, dy, dz = pc.x - coords.x, pc.y - coords.y, pc.z - coords.z
                    local d2 = dx * dx + dy * dy + dz * dz
                    if d2 < BLIP_RAD_SQ then
                        if not treeBlips[id] then
                            local b = clientConfig.blip
                            local blip = N_0x554d9d53f696d002(b.type, coords.x, coords.y, coords.z)
                            SetBlipSprite(blip, b.sprite, 1)
                            SetBlipScale(blip, b.scale)
                            Citizen.InvokeNative(0x9CB1A1623062F402, blip, locale('blip_name', id))
                            treeBlips[id] = blip
                        end
                    elseif treeBlips[id] then
                        RemoveBlip(treeBlips[id])
                        treeBlips[id] = nil
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- chop action
-- ---------------------------------------------------------------------------
chopTree = function(treeId, entity)
    local hasAxe = lib.callback.await('tk_lumberjack:server:checkAxe', false)
    if not hasAxe then
        return lib.notify({ title = locale('title'), description = locale('no_axe'), type = 'error' })
    end

    local anim = clientConfig.chopAnim
    lib.requestAnimDict(anim.dict)
    lib.requestModel(clientConfig.models.axe)

    local ped = cache.ped
    if entity and DoesEntityExist(entity) then
        TaskTurnPedToFaceEntity(ped, entity, -1)
        Wait(800)
    end

    local axe = CreateObject(clientConfig.models.axe, GetEntityCoords(ped), true, true, true)
    SetModelAsNoLongerNeeded(clientConfig.models.axe)
    AttachEntityToEntity(
        axe, ped,
        GetEntityBoneIndexByName(ped, 'SKEL_R_Finger12'),
        0.200, 0.0, 0.5010,
        1.024, -160.0, -70.0,
        true, true, false, true, 1, true
    )

    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)

    lib.progressCircle({
        duration  = sharedConfig.timers.chopDurationMs,
        label     = locale('progress_chop'),
        position  = 'bottom',
        canCancel = false,
        disable   = { car = true, move = true, combat = true },
    })

    ClearPedTasks(ped)
    if DoesEntityExist(axe) then DeleteObject(axe) end

    TriggerServerEvent('tk_lumberjack:server:confirmChop', treeId)
end

-- ---------------------------------------------------------------------------
-- processing
-- ---------------------------------------------------------------------------
local function showProcessMenu(eventName)
    local anim = clientConfig.processAnim
    lib.requestAnimDict(anim.dict)
    lib.requestModel(clientConfig.models.woodPlane)

    local ped = cache.ped
    TaskPlayAnim(ped, anim.dict, anim.clip, 1.0, 8.0, -1, 1, 0, false, false, false)

    local obj = CreateObject(clientConfig.models.woodPlane, GetEntityCoords(ped), true, true, true)
    SetModelAsNoLongerNeeded(clientConfig.models.woodPlane)
    AttachEntityToEntity(obj, ped, GetEntityBoneIndexByName(ped, 'PH_R_Hand'),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true)

    lib.progressCircle({
        duration  = sharedConfig.timers.processDurationMs,
        label     = locale('progress_process'),
        position  = 'bottom',
        canCancel = false,
        disable   = { move = true, car = true, combat = true },
    })

    if DoesEntityExist(obj) then DeleteObject(obj) end
    ClearPedTasks(ped)
    TriggerServerEvent(eventName)
end

RegisterNetEvent('tk_lumberjack:client:openMenu', function()
    lib.registerContext({
        id      = 'lumberjack_main_menu',
        title   = locale('menu_title'),
        options = {
            {
                title       = locale('menu_wood_title'),
                description = locale('menu_wood_desc'),
                icon        = 'hammer',
                onSelect    = function() showProcessMenu('tk_lumberjack:server:processWood') end,
            },
            {
                title       = locale('menu_plank_title'),
                description = locale('menu_plank_desc'),
                icon        = 'hammer',
                onSelect    = function() showProcessMenu('tk_lumberjack:server:processPlank') end,
            },
        },
    })
    lib.showContext('lumberjack_main_menu')
end)

-- ---------------------------------------------------------------------------
-- zones
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    exports.ox_target:addBoxZone({
        coords     = sharedConfig.locations.processLog,
        size       = vec3(2.5, 2.5, 2.0),
        rotation   = 0,
        drawSprite = false,
        distance   = 2.5,
        options    = {
            {
                icon     = 'hammer',
                label    = locale('process_open'),
                onSelect = function() TriggerEvent('tk_lumberjack:client:openMenu') end,
            },
        },
    })
end)

-- ---------------------------------------------------------------------------
-- cleanup
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ent in pairs(treeObjects) do
        if DoesEntityExist(ent) then DeleteObject(ent) end
    end
    for _, blip in pairs(treeBlips) do
        if blip then RemoveBlip(blip) end
    end
    treeObjects, treeBlips, treeCoordsMap = {}, {}, {}
    treeCount = 0
end)

-- ---------------------------------------------------------------------------
-- debug command
-- ---------------------------------------------------------------------------
RegisterCommand('lumberjack_debug', function()
    local activeBlips = 0
    for _, blip in pairs(treeBlips) do
        if DoesBlipExist(blip) then activeBlips = activeBlips + 1 end
    end
    print(('[tk_lumberjack] trees=%d blips=%d requestRadius=%.1f blipRadius=%.1f'):format(
        treeCount, activeBlips, sharedConfig.radius.request, sharedConfig.radius.blip))
end, false)
