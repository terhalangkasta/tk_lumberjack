Config = {}

-- Bahasa (gunakan Language.translate[Config.lang])
Config.lang = 'en'

-- Lokasi Zona Kerja
Config.LumberjackZone = {
    processLog = vec3(-1823.79, -423.12, 159.96),
    respawnTimers = 1 * 60 * 1000, -- 1 minute
    radiusBlip = 25.0, -- radius blip for Spawned Tree
    radiusTress = 250.0, -- radius for Spawn Tree
}

Config.LumberjackItems = {
    RequiredTool    = "water",
    LogItem         = "water",
    TwigItem        = "water",
    ProcessedItem   = "water",
    PlankItem       = "water"
}