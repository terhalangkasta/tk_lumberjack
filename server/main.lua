-- server.lua
local RSGCore = exports['rsg-core']:GetCoreObject()
local oxmysql = exports.oxmysql
local trees = {} -- cache DB rows: trees[id] = { id = id, x = x, y = y, z = z, respawn_time = n }

-- Config reference: Config.LumberjackZone.respawnTimers (ms), Config.LumberjackItems...
-- Helper notify
local function Notify(src, text, type)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Lumberjack',
        description = text,
        type = type or 'info'
    })
end

-- Fungsi helper untuk mendapatkan player terdekat
local function GetPlayersInRadius(coords, radius)
    local players = {}
    local allPlayers = GetPlayers()
    
    for _, playerId in pairs(allPlayers) do
        local playerPed = GetPlayerPed(playerId)
        if playerPed then
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(coords - playerCoords)
            
            if distance <= radius then
                table.insert(players, playerId)
            end
        end
    end
    
    return players
end

local function loadTreesFromDB()
    oxmysql:fetch('SELECT * FROM lumberjack_trees', {}, function(rows)
        if not rows then rows = {} end
        trees = {}
        for _, r in ipairs(rows) do
            trees[r.id] = {
                id = r.id,
                x = tonumber(r.x),
                y = tonumber(r.y),
                z = tonumber(r.z),
                respawn_time = tonumber(r.respawn_time) or 0
            }
        end

        -- Untuk initial load, tetap ke semua player
        local spawnList = {}
        for id, t in pairs(trees) do
            if t.respawn_time == 0 or t.respawn_time < os.time() then
                table.insert(spawnList, { id = t.id, x = t.x, y = t.y, z = t.z })
            else
                local delay = math.max(0, (t.respawn_time - os.time()) * 1000)
                SetTimeout(delay, function()
                    oxmysql:update('UPDATE lumberjack_trees SET respawn_time = ? WHERE id = ?', { 0, t.id })
                    
                    -- INI yang diubah: kirim ke player terdekat saja
                    local nearbyPlayers = GetPlayersInRadius(vector3(t.x, t.y, t.z), 500.0) -- 500 meter radius
                    for _, playerId in pairs(nearbyPlayers) do
                        TriggerClientEvent('tk_lumberjack:client:spawnTree', playerId, t.id, { x = t.x, y = t.y, z = t.z })
                    end
                end)
            end
        end

        if #spawnList > 0 then
            TriggerClientEvent('tk_lumberjack:client:syncTrees', -1, spawnList) -- Initial sync ke semua
        end
    end)
end

-- On resource start, ensure table exists then load trees
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    exports.oxmysql:query([[
        CREATE TABLE IF NOT EXISTS `lumberjack_trees` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `x` FLOAT NOT NULL,
            `y` FLOAT NOT NULL,
            `z` FLOAT NOT NULL,
            `respawn_time` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            INDEX `idx_respawn_time` (`respawn_time`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(result)
        if result and result.warningStatus == 0 then
            print('[tk_lumberjack] Table `lumberjack_trees` created successfully!')
        else
            print('[tk_lumberjack] Table `lumberjack_trees` already exists.')
        end

        -- load setelah table sudah dijamin ada
        loadTreesFromDB()
    end)
end)

-- Allow clients to request current trees (call this from client on resource start / player loaded)
RegisterNetEvent('tk_lumberjack:server:requestTrees', function()
    local src = source
    local spawnList = {}
    for id, t in pairs(trees) do
        if t.respawn_time == 0 or t.respawn_time < os.time() then
            table.insert(spawnList, { id = t.id, x = t.x, y = t.y, z = t.z })
        end
    end
    TriggerClientEvent('tk_lumberjack:client:syncTrees', src, spawnList)
end)

-- Admin create tree command
lib.addCommand('createTree', {
    help = 'Create a new tree at your position',
    params = {}, -- ga ada argumen tambahan
    restricted = { 'admin', 'god' } -- role yang bisa pakai
}, function(source, args, raw)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    if not xPlayer then return end

    local ped = GetPlayerPed(src)
    if not ped then return end
    local coords = GetEntityCoords(ped)

    oxmysql:insert('INSERT INTO lumberjack_trees (x, y, z) VALUES (?, ?, ?)', 
    { coords.x, coords.y, coords.z }, function(insertId)
        if not insertId then
            return Notify(src, "Failed to create tree.", "error")
        end

        -- update cache
        trees[insertId] = {
            id = insertId,
            x = coords.x,
            y = coords.y,
            z = coords.z,
            respawn_time = 0
        }

        -- notify all clients to spawn the tree
        TriggerClientEvent('tk_lumberjack:client:spawnTree', -1, insertId, {
            x = coords.x,
            y = coords.y,
            z = coords.z
        })

        Notify(src, ("Tree #%d created successfully!"):format(insertId), "success")
    end)
end)

-- Callback check axe (server authoritative)
lib.callback.register('tk_lumberjack:server:checkAxe', function(source)
    if type(source) ~= 'number' or source <= 0 then return false end
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return false end
    local axe = Player.Functions.GetItemByName(Config.LumberjackItems.RequiredTool)
    return axe ~= nil
end)

-- Client confirmed chop (after client animation finished)
RegisterNetEvent('tk_lumberjack:server:confirmChop', function(treeId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local t = trees[treeId]
    if not t then
        return Notify(src, "That tree can't be chopped.", "error")
    end

    -- final axe check
    local axe = Player.Functions.GetItemByName(Config.LumberjackItems.RequiredTool)
    if not axe then
        return Notify(src, "You don't have the required tool!", "error")
    end

    local treeCoords = vec3(tonumber(t.x), tonumber(t.y), tonumber(t.z))

    -- 🌲 broadcast topple hanya ke yang dekat
    local nearbyPlayers = GetPlayersInRadius(treeCoords, 100.0) -- radius bisa diatur
    for _, id in ipairs(nearbyPlayers) do
        TriggerClientEvent('tk_lumberjack:client:toppleTree', id, treeId)
    end

    -- ⏳ kasih waktu animasi roboh + delay hancur (sama kayak client)
    SetTimeout(2500, function()
        -- reward items ke player yang nebang (baru sekarang)
        local log = Config.LumberjackItems.LogItem
        local twig = Config.LumberjackItems.TwigItem
        if RSGCore.Shared.Items[log] then
            Player.Functions.AddItem(log, math.random(1, 4))
            TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[log], "add")
        end
        if RSGCore.Shared.Items[twig] then
            Player.Functions.AddItem(twig, math.random(1, 2))
            TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[twig], "add")
        end

        -- update DB respawn
        local respawnMs = Config.LumberjackZone.respawnTimers or 300000
        local respawnAt = os.time() + math.floor(respawnMs / 1000)

        oxmysql:update('UPDATE lumberjack_trees SET respawn_time = ? WHERE id = ?', { respawnAt, treeId }, function()
            if trees[treeId] then
                trees[treeId].respawn_time = respawnAt
            end

            -- schedule respawn
            SetTimeout(respawnMs, function()
                oxmysql:update('UPDATE lumberjack_trees SET respawn_time = ? WHERE id = ?', { 0, treeId })
                oxmysql:fetch('SELECT * FROM lumberjack_trees WHERE id = ?', { treeId }, function(result)
                    if result and result[1] then
                        local r = result[1]
                        trees[treeId] = { id = r.id, x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), respawn_time = 0 }

                        -- spawn lagi buat player dekat
                        local respawnNearby = GetPlayersInRadius(treeCoords, 100.0)
                        for _, id in ipairs(respawnNearby) do
                            TriggerClientEvent('tk_lumberjack:client:spawnTree', id, r.id, { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) })
                        end
                    end
                end)
            end)
        end)
    end)
end)

-- Proses Kayu Mentah → Kayu Jadi
RegisterNetEvent("tk_lumberjack:server:processWood", function(coords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if not coords or not IsPlayerNearLocation(coords, Config.LumberjackZone.processLog, 15.0) then
        Notify(src, "You are not at the wood processing station.", "error")
        return
    end

    local log = Config.LumberjckItems.LogItem
    local result = Config.LumberjckItems.ProcessedItem

    if not RSGCore.Shared.Items[log] or not RSGCore.Shared.Items[result] then return end

    local item = Player.Functions.GetItemByName(log)
    if not item or item.amount < 1 then
        Notify(src, "You don't have any raw wood.", "error")
        return
    end

    Player.Functions.RemoveItem(log, 1)
    Player.Functions.AddItem(result, 1)

    TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[log], "remove")
    TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[result], "add")
    Notify(src, "You processed raw wood into usable wood.", "success")
end)

-- Proses Kayu Mentah → Papan
RegisterNetEvent("tk_lumberjack:server:processPlank", function(coords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    if not coords or not IsPlayerNearLocation(coords, Config.LumberjackZone.processLog, 15.0) then
        Notify(src, "You are not at the plank processing station.", "error")
        return
    end

    local log = Config.LumberjckItems.LogItem
    local result = Config.LumberjckItems.PlankItem

    if not RSGCore.Shared.Items[log] or not RSGCore.Shared.Items[result] then return end

    local item = Player.Functions.GetItemByName(log)
    if not item or item.amount < 1 then
        Notify(src, "You don't have any raw wood.", "error")
        return
    end

    Player.Functions.RemoveItem(log, 1)
    Player.Functions.AddItem(result, 1)

    TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[log], "remove")
    TriggerClientEvent("rsg-inventory:client:ItemBox", src, RSGCore.Shared.Items[result], "add")
    Notify(src, "You processed raw wood into planks.", "success")
end)