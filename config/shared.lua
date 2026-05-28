return {
    debug = false,
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
        rayfireFallMs     = 4000,
    },
    radius = {
        request       = 250.0,
        blip          = 25.0,
        stream        = 500.0,
        chop          = 100.0,
        process       = 15.0,
        chopAntiCheat = 15.0,
        rayfireSearch = 1500.0,
    },
    locations = {
        processLog = vec3(-1823.79, -423.12, 159.96),
    },
    rayfire = {
        -- name:       rayfire object string (from decompiled scripts / YMAPs)
        -- coords:     search center for GetRayfireMapObject native
        -- zoneCoords: actual tree positions for ox_target zones (array)
        -- radius:     optional override for rayfireSearch
        -- respawn:    optional override for timers.respawnMs
        -- key:        stable DB key (defaults to "name@x,y,z")
        trees = {
            {
                key        = 'des_treefall_accident_01',
                name       = 'des_treefall_accident',
                coords     = vec3(-1428.82, -173.10, 101.87),
                zoneCoords = {
                    vec3(-1402.41, -270.08, 99.94),
                },
            },
        },
    },
}
