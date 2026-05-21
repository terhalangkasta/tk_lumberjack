local RSGCore = exports['rsg-core']:GetCoreObject()
local treeObjects, treeBlips, spawnedTrees, respawnTimers = {}, {}, {}, {}
local treeModel = `p_tree_pine_ponderosa_06`

-- Debug mode variable
local debugMode = false

-- Spawn pohon client-side
local function SpawnTree(treeId, coords)
    -- already exists?
    if treeObjects[treeId] and DoesEntityExist(treeObjects[treeId]) then return end

    RequestModel(treeModel)
    while not HasModelLoaded(treeModel) do Wait(0) end

    local obj = CreateObject(treeModel, coords.x, coords.y, coords.z - 1.5, true, true, true)
    -- PlaceObjectOnGroundProperly(obj)
    SetEntityAsMissionEntity(obj, true)

    treeObjects[treeId] = obj
    spawnedTrees[treeId] = true

    -- ox_target local entity so only this client can interact
    exports.ox_target:addLocalEntity(obj, {
        {
            icon = 'axe',
            label = 'Chop Tree',
            distance = 2.5,
            drawSprite = false,
            onSelect = function()
                -- run local animation then notify server
                chopTree(treeId, obj)
            end
        }
    })
end

-- Remove pohon client-side
local function RemoveTree(treeId)
    local ent = treeObjects[treeId]
    if ent and DoesEntityExist(ent) then
        DeleteObject(ent)
    end
    treeObjects[treeId] = nil
    spawnedTrees[treeId] = nil

    if treeBlips[treeId] then
        RemoveBlip(treeBlips[treeId])
        treeBlips[treeId] = nil
    end
end

-- Receive sync list from server (on join or initial load)
RegisterNetEvent('tk_lumberjack:client:syncTrees', function(list)
    -- list: array of { id, x, y, z }
    for _, t in ipairs(list or {}) do
        SpawnTree(t.id, { x = t.x, y = t.y, z = t.z })
    end
end)

-- Server asks clients to spawn a single tree
RegisterNetEvent('tk_lumberjack:client:spawnTree', function(treeId, coords)
    SpawnTree(treeId, coords)
end)

-- Server asks clients to remove a tree
RegisterNetEvent('tk_lumberjack:client:removeTree', function(treeId)
    RemoveTree(treeId)
end)

-- Request initial trees after resource start / player loaded
Citizen.CreateThread(function()
    local lastCoords = nil
    local checkDistance = Config.LumberjackZone.radiusTress or 100.0 -- jarak untuk check ulang
    local loopCount = 0
    
    if debugMode then
        print("^2[LUMBERJACK DEBUG]^7 Tree request loop started - Check distance: " .. checkDistance)
    end
    
    while true do
        loopCount = loopCount + 1
        
        if debugMode then
            print("^3[TREE REQUEST]^7 Loop #" .. loopCount .. " - Checking player position...")
        end
        
        -- Menggunakan cache.ped untuk optimasi kecil
        local ped = cache.ped
        if ped then
            if debugMode then
                print("^3[TREE REQUEST]^7 Ped found: " .. ped)
            end
            local playerCoords = GetEntityCoords(ped)
            
            if debugMode then
                print("^3[TREE REQUEST]^7 Player coords: " .. playerCoords.x .. ", " .. playerCoords.y .. ", " .. playerCoords.z)
            end
            
            -- Cek apakah player sudah pindah cukup jauh
            if not lastCoords then
                if debugMode then
                    print("^3[TREE REQUEST]^7 First time check - no lastCoords")
                    print("^2[TREE REQUEST]^7 Requesting trees for initial position")
                end
                lastCoords = playerCoords
                TriggerServerEvent('tk_lumberjack:server:requestTrees')
            else
                local distance = #(playerCoords - lastCoords)
                
                if debugMode then
                    print("^3[TREE REQUEST]^7 Distance moved: " .. string.format("%.2f", distance) .. " (threshold: " .. checkDistance .. ")")
                end
                
                if distance > checkDistance then
                    if debugMode then
                        print("^2[TREE REQUEST]^7 Player moved far enough! Requesting new trees...")
                        print("^2[TREE REQUEST]^7 Old coords: " .. lastCoords.x .. ", " .. lastCoords.y .. ", " .. lastCoords.z)
                        print("^2[TREE REQUEST]^7 New coords: " .. playerCoords.x .. ", " .. playerCoords.y .. ", " .. playerCoords.z)
                    end
                    lastCoords = playerCoords
                    TriggerServerEvent('tk_lumberjack:server:requestTrees')
                else
                    if debugMode then
                        print("^1[TREE REQUEST]^7 Player hasn't moved far enough - no request needed")
                    end
                end
            end
        else
            if debugMode then
                print("^1[TREE REQUEST]^7 No ped found in cache!")
            end
        end
        
        if debugMode then
            print("^3[TREE REQUEST]^7 Waiting 5 seconds before next check...\n")
        end
        Wait(5000) -- Check every 5 seconds
    end
end)

-- Blip loop (optional, spawns blip for each known tree when near)
CreateThread(function()
    local blipLoopCount = 0
    
    if debugMode then
        print("^2[LUMBERJACK DEBUG]^7 Tree blip loop started")
    end
    
    while true do
        Wait(1000)
        blipLoopCount = blipLoopCount + 1
        
        -- Debug setiap 10 detik untuk menghindari spam (hanya jika debug mode aktif)
        local showDebug = debugMode and (blipLoopCount % 10 == 0)
        if showDebug then
            print("^4[TREE BLIPS]^7 Blip loop #" .. blipLoopCount)
        end
        
        -- Menggunakan cache.ped dan pengecekan yang lebih efisien
        local ped = cache.ped
        if not ped then 
            if showDebug then
                print("^1[TREE BLIPS]^7 No ped found in cache - waiting...")
            end
            Wait(1000)
            goto continue
        end
        
        local pCoords = GetEntityCoords(ped)
        local radiusBlip = Config.LumberjackZone.radiusBlip or 100.0
        
        if showDebug then
            print("^4[TREE BLIPS]^7 Player coords: " .. pCoords.x .. ", " .. pCoords.y .. ", " .. pCoords.z)
            print("^4[TREE BLIPS]^7 Blip radius: " .. radiusBlip)
            print("^4[TREE BLIPS]^7 Total trees to check: " .. #treeObjects)
        end
        
        local blipsCreated = 0
        local blipsRemoved = 0
        local treesInRange = 0

        for id, ent in pairs(treeObjects) do
            local coords = GetEntityCoords(ent)
            local dist = #(pCoords - coords)
            
            if dist < radiusBlip then
                treesInRange = treesInRange + 1
                if not treeBlips[id] then
                    local blip = N_0x554d9d53f696d002(1664425300, coords.x, coords.y, coords.z)
                    SetBlipSprite(blip, 1904459580, 1)
                    SetBlipScale(blip, 0.2)
                    Citizen.InvokeNative(0x9CB1A1623062F402, blip, ('Tree #%d'):format(id))
                    treeBlips[id] = blip
                    blipsCreated = blipsCreated + 1
                    
                    if showDebug then
                        print("^2[TREE BLIPS]^7 Created blip for tree #" .. id .. " (dist: " .. string.format("%.2f", dist) .. ")")
                    end
                end
            else
                if treeBlips[id] then
                    RemoveBlip(treeBlips[id])
                    treeBlips[id] = nil
                    blipsRemoved = blipsRemoved + 1
                    
                    if showDebug then
                        print("^1[TREE BLIPS]^7 Removed blip for tree #" .. id .. " (dist: " .. string.format("%.2f", dist) .. ")")
                    end
                end
            end
        end
        
        if showDebug then
            print("^4[TREE BLIPS]^7 Trees in range: " .. treesInRange)
            print("^4[TREE BLIPS]^7 Blips created this loop: " .. blipsCreated)
            print("^4[TREE BLIPS]^7 Blips removed this loop: " .. blipsRemoved)
            print("^4[TREE BLIPS]^7 Total active blips: " .. #treeBlips)
            print("^4[TREE BLIPS]^7 ===============================\n")
        end
        
        ::continue::
    end
end)

-- Debug command untuk melihat status saat ini
RegisterCommand('lumberjack_debug', function()
    print("^5=== LUMBERJACK DEBUG STATUS ===^7")
    
    local ped = cache.ped
    if ped then
        local coords = GetEntityCoords(ped)
        print("^2Player Ped:^7 " .. ped)
        print("^2Player Coords:^7 " .. coords.x .. ", " .. coords.y .. ", " .. coords.z)
    else
        print("^1No ped found in cache!^7")
    end
    
    print("^2Total Trees:^7 " .. #treeObjects)
    print("^2Total Blips:^7 " .. #treeBlips)
    print("^2Check Distance:^7 " .. (Config.LumberjackZone.radiusTress or 100.0))
    print("^2Blip Radius:^7 " .. (Config.LumberjackZone.radiusBlip or 100.0))
    
    -- List active blips
    local activeBlips = 0
    for id, blip in pairs(treeBlips) do
        if DoesBlipExist(blip) then
            activeBlips = activeBlips + 1
        end
    end
    print("^2Active Blips:^7 " .. activeBlips)
    print("^5==============================^7")
end, false)

-- Debug command untuk toggle debug mode
RegisterCommand('lumberjack_toggle_debug', function()
    debugMode = not debugMode
    if debugMode then
        print("^2[LUMBERJACK]^7 Debug mode enabled")
    else
        print("^1[LUMBERJACK]^7 Debug mode disabled")
    end
end, false)

-- 🌲 Event: pohon tumbang sinkron
RegisterNetEvent('tk_lumberjack:client:toppleTree', function(treeId)
    local entity = treeObjects[treeId]
    if entity and DoesEntityExist(entity) then
        CreateThread(function()
            local rot = 1.01
            while rot < 90 do
                Wait(10)
                rot = rot + 1
                SetEntityRotation(entity, rot, 0.0, 0.0, 1, true)
            end
            -- delay dikit biar kelihatan tumbang dulu
            Wait(1500)
            RemoveTree(treeId)
        end)
    else
        -- fallback kalau entity udah ga ada
        RemoveTree(treeId)
    end
end)

-- ✂️ chopTree: hapus bagian topple & delete entity, biar server yang broadcast
function chopTree(treeId, entity)
    local hasAxe = lib.callback.await('tk_lumberjack:server:checkAxe', false)
    if not hasAxe then
        return lib.notify({ title = 'Lumberjack', description = "You don't have an axe!", type = 'error' })
    end

    -- animasi & progress bar (sama kayak sebelumnya)...
    local dict, anim = "amb_work@world_human_tree_chop@male_a@idle_b", "idle_f"
    local axeModel = `p_axe02x`

    RequestAnimDict(dict) while not HasAnimDictLoaded(dict) do Wait(0) end
    RequestModel(axeModel) while not HasModelLoaded(axeModel) do Wait(0) end

    if entity and DoesEntityExist(entity) then
        TaskTurnPedToFaceEntity(PlayerPedId(), entity, -1)
        Wait(800)
    end

    local axe = CreateObject(axeModel, GetEntityCoords(PlayerPedId()), true, true, true)
    AttachEntityToEntity(
        axe, 
        PlayerPedId(), 
        GetEntityBoneIndexByName(PlayerPedId(), "SKEL_R_Finger12"),
        0.200, 0.0, 0.5010, 
        1.024, -160.0, -70.0, 
        true, true, false, true, 1, true
    )

    TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)

    lib.progressCircle({
        duration = 10000,
        label = 'Chopping Tree...',
        position = 'bottom',
        canCancel = false,
        disable = { car = true, move = true, combat = true }
    })

    ClearPedTasks(PlayerPedId())
    if DoesEntityExist(axe) then DeleteObject(axe) end

    -- 🔔 minta server confirm (reward + sync)
    TriggerServerEvent('tk_lumberjack:server:confirmChop', treeId)
end

-- Processing menu / zones (same as before)
local function showProcessMenu(eventName)
    local dict, anim = "amb_work@world_human_wood_plane@working@male_a@base", "base"
    local toolModel = `p_woodplane01x`

    RequestAnimDict(dict) while not HasAnimDictLoaded(dict) do Wait(0) end
    RequestModel(toolModel) while not HasModelLoaded(toolModel) do Wait(0) end

    TaskPlayAnim(PlayerPedId(), dict, anim, 1.0, 8.0, -1, 1, 0, false, false, false)

    local obj = CreateObject(toolModel, GetEntityCoords(PlayerPedId()), true, true, true)
    AttachEntityToEntity(obj, PlayerPedId(), GetEntityBoneIndexByName(PlayerPedId(), "PH_R_Hand"),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true)

    lib.progressCircle({
        duration = 5000,
        label = 'Processing...',
        position = 'bottom',
        canCancel = false,
        disable = { move = true, car = true, combat = true }
    })

    DeleteObject(obj)
    ClearPedTasks(PlayerPedId())
    TriggerServerEvent(eventName, GetEntityCoords(PlayerPedId()))
end

RegisterNetEvent('tk_lumberjack:client:openMenu', function()
    lib.registerContext({
        id = 'lumberjack_main_menu',
        title = 'Lumberjack Processing',
        options = {
            { title = 'Process Kayu', description = 'Ubah kayu mentah menjadi bahan', icon = 'hammer',
              onSelect = function() showProcessMenu('tk_lumberjack:server:processWood') end },
            { title = 'Process Papan', description = 'Ubah kayu menjadi papan', icon = 'hammer',
              onSelect = function() showProcessMenu('tk_lumberjack:server:processPlank') end }
        }
    })
    lib.showContext('lumberjack_main_menu')
end)

-- Zones: info & process (ox_target box zones)
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    exports.ox_target:addBoxZone({
        coords = Config.LumberjackZone.processLog,
        size = vec3(2.5, 2.5, 2.0),
        rotation = 0,
        drawSprite = false,
        distance = 2.5,
        options = {
            { icon = 'hammer', label = 'Open Processing Menu', onSelect = function()
                TriggerEvent('tk_lumberjack:client:openMenu')
            end }
        }
    })
end)

-- Cleanup
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id, ent in pairs(treeObjects) do
        if DoesEntityExist(ent) then DeleteObject(ent) end
    end
    for id, b in pairs(treeBlips) do
        if b then RemoveBlip(b) end
    end
    treeObjects, treeBlips, spawnedTrees, respawnTimers = {}, {}, {}, {}
end)
