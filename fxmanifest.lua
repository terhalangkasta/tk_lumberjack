fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'tk_lumberjack'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'config/client.lua',
    'config/server.lua',
    'config/shared.lua',
    'locales/*.json',
}

dependencies {
    'rsg-core',
    'ox_lib',
    'oxmysql',
}

lua54 'yes'
ox_lib 'locale'
