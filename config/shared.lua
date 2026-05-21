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
        respawnMs        = 1 * 60 * 1000, -- 1 minute
        chopDurationMs   = 10000,
        processDurationMs= 5000,
        toppleDelayMs    = 1500,
    },
    radius = {
        request       = 250.0, -- client checks this distance moved before re-requesting
        blip          = 25.0,
        stream        = 500.0, -- server streams spawn/respawn within this distance
        chop          = 100.0, -- server broadcasts topple/respawn within this distance
        process       = 15.0,  -- server-side anti-cheat for process station
        chopAntiCheat = 15.0,  -- server-side anti-cheat for chop distance
    },
    locations = {
        processLog = vec3(-1823.79, -423.12, 159.96),
    },
}
