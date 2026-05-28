local sharedConfig = require 'config.shared'
local clientConfig = require 'config.client'

local RSGCore = exports['rsg-core']:GetCoreObject()

-- Dynamic (DB-backed) trees ---------------------------------------------------
local treeObjects   = {}
local treeBlips     = {}
local treeCoordsMap = {}
local treeCount     = 0

-- RayFire (static map-object) trees -------------------------------------------
---@class RayfireRuntime
---@field cfg table              entry from sharedConfig.rayfire.trees
---@field blip number|nil
---@field zoneId number|nil      ox_target sphere zone id
---@field available boolean      mirrored from server state
---@field falling boolean        local lock while animation plays
local rayfireRuntime = {}

local CHECK_DIST_SQ    = sharedConfig.radius.request       * sharedConfig.radius.request
local BLIP_RAD_SQ      = sharedConfig.radius.blip          * sharedConfig.radius.blip
local RAYFIRE_SCAN_SQ  = sharedConfig.radius.rayfireScan   * sharedConfig.radius.rayfireScan
local RAYFIRE_SEARCH_R = sharedConfig.radius.rayfireSearch

local chopTree
local chopRayfire

---@param ... any
local function dprint(...)
    if sharedConfig.debug then print('[tk_lumberjack]', ...) end
end

-- ---------------------------------------------------------------------------
-- Dynamic tree handling
-- ---------------------------------------------------------------------------
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

---@param treeId number
---@param coords vector3
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

---@param treeId number
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

---@param treeId number
---@param entity number
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
-- RayFire (static) tree handling
-- ---------------------------------------------------------------------------
---@param idx integer index into sharedConfig.rayfire.trees
---@return number|nil handle
local function tryGetRayfireHandle(idx)
    local rt = rayfireRuntime[idx]
    if not rt then return nil end
    local r = rt.cfg.radius or RAYFIRE_SEARCH_R
    -- Use player position as search center
    local ped = cache.ped
    if not ped then return nil end
    local pc = GetEntityCoords(ped)
    local handle = Citizen.InvokeNative(0xB48FCED898292E52, pc, r, rt.cfg.name)
    if handle and handle ~= 0 and Citizen.InvokeNative(0x52AF537A0C5B8AAD, handle) then
        local oc = GetEntityCoords(handle)
        dprint(('rayfire[%d] found handle=%d name=%s objCoords=%.2f,%.2f,%.2f'):format(
            idx, handle, rt.cfg.name, oc.x, oc.y, oc.z))
        return handle
    end
    dprint(('rayfire[%d] NOT found name=%s'):format(idx, rt.cfg.name))
    return nil
end

---@param idx integer
local function ensureRayfireBlip(idx)
    local rt = rayfireRuntime[idx]
    if rt.blip or not rt.available then return end
    local b = clientConfig.blip
    local c = rt.cfg.coords
    local blip = N_0x554d9d53f696d002(b.type, c.x, c.y, c.z)
    SetBlipSprite(blip, b.sprite, 1)
    SetBlipScale(blip, b.scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, locale('rayfire_blip_name'))
    rt.blip = blip
end

---@param idx integer
local function clearRayfireBlip(idx)
    local rt = rayfireRuntime[idx]
    if rt and rt.blip then
        RemoveBlip(rt.blip)
        rt.blip = nil
    end
end

---@param idx integer
local function ensureRayfireZone(idx)
    local rt = rayfireRuntime[idx]
    if rt.zoneId or not rt.available then return end

    local handle = tryGetRayfireHandle(idx)
    if not handle then return end

    -- Use zoneCoords from config (actual tree position), fallback to coords (search center)
    local c = rt.cfg.zoneCoords or rt.cfg.coords
    dprint(('rayfire[%d] creating zone at %.2f,%.2f,%.2f'):format(idx, c.x, c.y, c.z))

    rt.zoneId = exports.ox_target:addSphereZone({
        coords     = c,
        radius     = 5.0,
        drawSprite = true,
        options    = {
            {
                icon     = 'axe',
                label    = locale('chop_label'),
                distance = 5.0,
                onSelect = function() chopRayfire(idx) end,
            },
        },
    })
end

---@param idx integer
local function clearRayfireZone(idx)
    local rt = rayfireRuntime[idx]
    if rt and rt.zoneId then
        exports.ox_target:removeZone(rt.zoneId)
        rt.zoneId = nil
    end
end

---@param idx integer
local function playRayfireFall(idx)
    local rt = rayfireRuntime[idx]
    if not rt or rt.falling then return end
    rt.falling = true
    CreateThread(function()
        local handle = tryGetRayfireHandle(idx)
        if not handle then
            rt.falling = false
            return
        end
        -- State 4 resets, then state 6 triggers the RayFire fall sequence
        Citizen.InvokeNative(0x5C29F698D404C5E1, handle, 4)
        Wait(500)
        Citizen.InvokeNative(0x5C29F698D404C5E1, handle, 6)
        Wait(sharedConfig.timers.rayfireFallMs)
        rt.falling = false
    end)
end

---@param idx integer
local function resetRayfire(idx)
    local rt = rayfireRuntime[idx]
    if not rt then return end
    local handle = tryGetRayfireHandle(idx)
    if handle then
        -- State 4 = reset to default
        Citizen.InvokeNative(0x5C29F698D404C5E1, handle, 4)
    end
end

---@param idx integer
---@param available boolean
local function setRayfireAvailability(idx, available)
    local rt = rayfireRuntime[idx]
    if not rt then return end
    rt.available = available
    if available then
        resetRayfire(idx)
    else
        clearRayfireBlip(idx)
        clearRayfireZone(idx)
    end
end

---@param idx integer
chopRayfire = function(idx)
    local rt = rayfireRuntime[idx]
    if not rt or not rt.available or rt.falling then
        return lib.notify({ title = locale('title'), description = locale('rayfire_unavailable'), type = 'error' })
    end

    local hasAxe = lib.callback.await('tk_lumberjack:server:checkAxe', false)
    if not hasAxe then
        return lib.notify({ title = locale('title'), description = locale('no_axe'), type = 'error' })
    end

    local anim = clientConfig.chopAnim
    lib.requestAnimDict(anim.dict)
    lib.requestModel(clientConfig.models.axe)

    local ped = cache.ped
    local c = rt.cfg.coords
    SetEntityHeading(ped, GetHeadingFromVector_2d(c.x - GetEntityCoords(ped).x, c.y - GetEntityCoords(ped).y))
    Wait(400)

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

    TriggerServerEvent('tk_lumberjack:server:confirmRayfireChop', idx)
end

RegisterNetEvent('tk_lumberjack:client:syncRayfire', function(states)
    if type(states) ~= 'table' then return end
    for idx, available in pairs(states) do
        setRayfireAvailability(idx, available)
    end
end)

RegisterNetEvent('tk_lumberjack:client:rayfireFall', function(idx)
    setRayfireAvailability(idx, false)
    playRayfireFall(idx)
end)

RegisterNetEvent('tk_lumberjack:client:rayfireRespawn', function(idx)
    setRayfireAvailability(idx, true)
end)

CreateThread(function()
    local entries = sharedConfig.rayfire and sharedConfig.rayfire.trees or {}
    for i = 1, #entries do
        rayfireRuntime[i] = {
            cfg       = entries[i],
            blip      = nil,
            zoneId    = nil,
            available = true,
            falling   = false,
        }
    end

    if next(rayfireRuntime) == nil then return end

    -- request initial state once player ped exists
    while not cache.ped do Wait(500) end
    local states = lib.callback.await('tk_lumberjack:server:getRayfireStates', false)
    if type(states) == 'table' then
        for idx, available in pairs(states) do
            setRayfireAvailability(idx, available)
        end
    end

    while true do
        Wait(clientConfig.rayfireScanMs or 1000)
        local ped = cache.ped
        if ped then
            for idx, rt in pairs(rayfireRuntime) do
                if rt.available then
                    if tryGetRayfireHandle(idx) then
                        ensureRayfireBlip(idx)
                        ensureRayfireZone(idx)
                    end
                else
                    clearRayfireBlip(idx)
                    clearRayfireZone(idx)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Processing
-- ---------------------------------------------------------------------------
---@param eventName string
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

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ent in pairs(treeObjects) do
        if DoesEntityExist(ent) then DeleteObject(ent) end
    end
    for _, blip in pairs(treeBlips) do
        if blip then RemoveBlip(blip) end
    end
    for idx, _ in pairs(rayfireRuntime) do
        clearRayfireBlip(idx)
        clearRayfireZone(idx)
    end
    treeObjects, treeBlips, treeCoordsMap = {}, {}, {}
    treeCount    = 0
    rayfireRuntime = {}
end)

RegisterCommand('lumberjack_debug', function()
    local activeBlips = 0
    for _, blip in pairs(treeBlips) do
        if DoesBlipExist(blip) then activeBlips = activeBlips + 1 end
    end
    local rayfireCount, rayfireBlips = 0, 0
    for _, rt in pairs(rayfireRuntime) do
        rayfireCount = rayfireCount + 1
        if rt.blip and DoesBlipExist(rt.blip) then rayfireBlips = rayfireBlips + 1 end
    end
    print(('[tk_lumberjack] trees=%d blips=%d rayfire=%d rayfireBlips=%d requestRadius=%.1f blipRadius=%.1f'):format(
        treeCount, activeBlips, rayfireCount, rayfireBlips,
        sharedConfig.radius.request, sharedConfig.radius.blip))
end, false)

RegisterCommand('rayfire_mypos', function()
    local pc = GetEntityCoords(cache.ped)
    print(('[tk_lumberjack] Your position: vec3(%.2f, %.2f, %.2f)'):format(pc.x, pc.y, pc.z))
end, false)
