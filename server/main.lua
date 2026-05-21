-- server/main.lua
local sharedConfig = require 'config.shared'
local serverConfig = require 'config.server'

local RSGCore = exports['rsg-core']:GetCoreObject()
local oxmysql = exports.oxmysql

-- cache: trees[id] = { id, x, y, z, respawn_time }
local trees         = {}
-- per-tree mutex so a chop can't be confirmed twice while server is mid-process
local choppingLocks = {}
-- per-player throttle for requestTrees
local lastRequest   = {}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function dprint(...)
    if sharedConfig.debug then print('[tk_lumberjack]', ...) end
end

local function notify(src, key, kind, ...)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = locale('title'),
        description = locale(key, ...),
        type        = kind or 'info',
    })
end

-- Returns array of player ids whose ped is within `radius` of `coords`.
local function getPlayersInRadius(coords, radius)
    local result, n = {}, 0
    local r2 = radius * radius
    local players = GetPlayers()
    for i = 1, #players do
        local pid = players[i]
        local ped = GetPlayerPed(pid)
        if ped ~= 0 then
            local pc = GetEntityCoords(ped)
            local dx, dy, dz = coords.x - pc.x, coords.y - pc.y, coords.z - pc.z
            if (dx * dx + dy * dy + dz * dz) <= r2 then
                n = n + 1
                result[n] = pid
            end
        end
    end
    return result
end

local function broadcastNearby(coords, radius, event, ...)
    local nearby = getPlayersInRadius(coords, radius)
    for i = 1, #nearby do
        TriggerClientEvent(event, nearby[i], ...)
    end
end

local function buildSpawnList(now)
    now = now or os.time()
    local list, n = {}, 0
    for _, t in pairs(trees) do
        if t.respawn_time == 0 or t.respawn_time < now then
            n = n + 1
            list[n] = { id = t.id, x = t.x, y = t.y, z = t.z }
        end
    end
    return list
end

local function scheduleRespawn(treeId, delayMs)
    SetTimeout(delayMs, function()
        local t = trees[treeId]
        if not t then return end
        t.respawn_time = 0
        oxmysql:update('UPDATE lumberjack_trees SET respawn_time = ? WHERE id = ?', { 0, treeId })
        broadcastNearby(vector3(t.x, t.y, t.z), sharedConfig.radius.stream,
            'tk_lumberjack:client:spawnTree', treeId, { x = t.x, y = t.y, z = t.z })
    end)
end

-- ---------------------------------------------------------------------------
-- DB load
-- ---------------------------------------------------------------------------
local function loadTreesFromDB()
    oxmysql:fetch('SELECT id, x, y, z, respawn_time FROM lumberjack_trees', {}, function(rows)
        rows  = rows or {}
        trees = {}
        local now = os.time()

        for i = 1, #rows do
            local r  = rows[i]
            local rt = tonumber(r.respawn_time) or 0
            trees[r.id] = {
                id           = r.id,
                x            = tonumber(r.x),
                y            = tonumber(r.y),
                z            = tonumber(r.z),
                respawn_time = rt,
            }
            if rt ~= 0 and rt > now then
                scheduleRespawn(r.id, (rt - now) * 1000)
            end
        end

        dprint(('loaded %d trees from DB'):format(#rows))
    end)
end

-- ---------------------------------------------------------------------------
-- resource start: ensure schema, then load
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    oxmysql:query([[
        CREATE TABLE IF NOT EXISTS `lumberjack_trees` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `x`  FLOAT NOT NULL,
            `y`  FLOAT NOT NULL,
            `z`  FLOAT NOT NULL,
            `respawn_time` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            INDEX `idx_respawn_time` (`respawn_time`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        loadTreesFromDB()
    end)
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)

-- ---------------------------------------------------------------------------
-- requestTrees (throttled)
-- ---------------------------------------------------------------------------
RegisterNetEvent('tk_lumberjack:server:requestTrees', function()
    local src = source
    local now = GetGameTimer()
    if lastRequest[src] and (now - lastRequest[src]) < serverConfig.requestCooldownMs then
        return
    end
    lastRequest[src] = now
    TriggerClientEvent('tk_lumberjack:client:syncTrees', src, buildSpawnList())
end)

-- ---------------------------------------------------------------------------
-- admin: createTree
-- ---------------------------------------------------------------------------
lib.addCommand('createTree', {
    help       = 'Create a new tree at your position',
    params     = {},
    restricted = serverConfig.adminGroups,
}, function(source)
    local src = source
    if not RSGCore.Functions.GetPlayer(src) then return end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local coords = GetEntityCoords(ped)

    oxmysql:insert('INSERT INTO lumberjack_trees (x, y, z) VALUES (?, ?, ?)',
        { coords.x, coords.y, coords.z }, function(insertId)
            if not insertId then
                return notify(src, 'tree_create_failed', 'error')
            end

            trees[insertId] = {
                id = insertId, x = coords.x, y = coords.y, z = coords.z, respawn_time = 0,
            }

            broadcastNearby(coords, sharedConfig.radius.stream,
                'tk_lumberjack:client:spawnTree', insertId,
                { x = coords.x, y = coords.y, z = coords.z })

            notify(src, 'tree_created', 'success', insertId)
        end)
end)

-- ---------------------------------------------------------------------------
-- callbacks
-- ---------------------------------------------------------------------------
lib.callback.register('tk_lumberjack:server:checkAxe', function(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.GetItemByName(sharedConfig.items.requiredTool) ~= nil
end)

-- ---------------------------------------------------------------------------
-- chop confirm
-- ---------------------------------------------------------------------------
RegisterNetEvent('tk_lumberjack:server:confirmChop', function(treeId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local t = trees[treeId]
    if not t or (t.respawn_time ~= 0 and t.respawn_time > os.time()) then
        return notify(src, 'tree_unavailable', 'error')
    end

    if choppingLocks[treeId] then return end
    choppingLocks[treeId] = true

    if not Player.Functions.GetItemByName(sharedConfig.items.requiredTool) then
        choppingLocks[treeId] = nil
        return notify(src, 'no_tool', 'error')
    end

    -- distance sanity check
    local ped = GetPlayerPed(src)
    if ped ~= 0 then
        local pc = GetEntityCoords(ped)
        local dx, dy, dz = t.x - pc.x, t.y - pc.y, t.z - pc.z
        local maxDist = sharedConfig.radius.chopAntiCheat
        if (dx * dx + dy * dy + dz * dz) > (maxDist * maxDist) then
            choppingLocks[treeId] = nil
            return notify(src, 'tree_too_far', 'error')
        end
    end

    local treeCoords = vec3(t.x, t.y, t.z)
    broadcastNearby(treeCoords, sharedConfig.radius.chop, 'tk_lumberjack:client:toppleTree', treeId)

    SetTimeout(2500, function()
        local logItem  = sharedConfig.items.logItem
        local twigItem = sharedConfig.items.twigItem
        local logR     = sharedConfig.rewards.log
        local twigR    = sharedConfig.rewards.twig

        if RSGCore.Shared.Items[logItem] then
            Player.Functions.AddItem(logItem, math.random(logR.min, logR.max))
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[logItem], 'add')
        end
        if RSGCore.Shared.Items[twigItem] then
            Player.Functions.AddItem(twigItem, math.random(twigR.min, twigR.max))
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[twigItem], 'add')
        end

        local respawnMs = sharedConfig.timers.respawnMs
        local respawnAt = os.time() + math.floor(respawnMs / 1000)

        if trees[treeId] then trees[treeId].respawn_time = respawnAt end

        oxmysql:update('UPDATE lumberjack_trees SET respawn_time = ? WHERE id = ?',
            { respawnAt, treeId }, function()
                scheduleRespawn(treeId, respawnMs)
                choppingLocks[treeId] = nil
            end)
    end)
end)

-- ---------------------------------------------------------------------------
-- processing (shared handler)
-- ---------------------------------------------------------------------------
local function processItem(src, fromItem, toItem, successKey)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local pc        = GetEntityCoords(ped)
    local sp        = sharedConfig.locations.processLog
    local maxDist   = sharedConfig.radius.process
    local dx, dy, dz= sp.x - pc.x, sp.y - pc.y, sp.z - pc.z
    if (dx * dx + dy * dy + dz * dz) > (maxDist * maxDist) then
        return notify(src, 'not_at_station', 'error')
    end

    if not RSGCore.Shared.Items[fromItem] or not RSGCore.Shared.Items[toItem] then return end

    local item = Player.Functions.GetItemByName(fromItem)
    if not item or item.amount < 1 then
        return notify(src, 'no_raw_wood', 'error')
    end

    Player.Functions.RemoveItem(fromItem, 1)
    Player.Functions.AddItem(toItem, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[fromItem], 'remove')
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[toItem], 'add')
    notify(src, successKey, 'success')
end

RegisterNetEvent('tk_lumberjack:server:processWood', function()
    processItem(source, sharedConfig.items.logItem, sharedConfig.items.processedItem, 'processed_wood')
end)

RegisterNetEvent('tk_lumberjack:server:processPlank', function()
    processItem(source, sharedConfig.items.logItem, sharedConfig.items.plankItem, 'processed_plank')
end)
