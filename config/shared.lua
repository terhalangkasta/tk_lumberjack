return {
    debug = true,
    treeModel = `p_tree_pine_ponderosa_06`,
    items = {
        requiredTool  = 'water',
        logItem       = 'water',
        twigItem      = 'water',
        processedItem = 'water',
        plankItem     = 'water',
    },
    rewards = {
        log  = { min = 1, max = 4 },
        twig = { min = 1, max = 2 },
    },
    timers = {
        respawnMs         = 1 * 60 * 1000,
        chopDurationMs    = 10000,
        processDurationMs = 5000,
        toppleDelayMs     = 1500,
        rayfireResetMs    = 100,
        rayfireFallMs     = 4000,
    },
    radius = {
        -- request:       client checks this distance moved before re-requesting
        -- blip:          dynamic-tree blip draw distance
        -- stream:        server streams spawn/respawn within this distance
        -- chop:          server broadcasts topple/respawn within this distance
        -- process:       server-side anti-cheat for process station
        -- chopAntiCheat: server-side anti-cheat for chop distance
        -- rayfireScan:   client scans nearby rayfire entries within this distance
        -- rayfireSearch: per-entry default search radius for GetRayfireMapObject
        request       = 250.0,
        blip          = 25.0,
        stream        = 500.0,
        chop          = 100.0,
        process       = 15.0,
        chopAntiCheat = 15.0,
        rayfireScan   = 200.0,
        rayfireSearch = 1500.0,
    },
    locations = {
        processLog = vec3(-1823.79, -423.12, 159.96),
    },
    rayfire = {
        -- Static destructible map objects (RayFire) registered with the script.
        -- name:    rayfire object string (from decompiled scripts / YMAPs)
        -- coords:  search center used by GetRayfireMapObject (can be player area)
        -- zoneCoords: actual tree position for ox_target zone placement
        -- radius:  optional, falls back to radius.rayfireSearch
        -- respawn: optional override of timers.respawnMs
        -- key:     stable identifier used as DB key (defaults to "name@x,y,z")
        trees = {
            {
                key       = 'des_treefall_accident_01',
                name      = 'des_treefall_accident',
                coords    = vec3(-1428.82, -173.10, 101.87),
                zoneCoords = vec3(-1402.41, -270.08, 99.94),
            },
        },
    },
}
