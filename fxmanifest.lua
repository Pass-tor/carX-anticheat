-- CARXAC - Carx Anti-Cheat
-- Licensed under the GNU Affero General Public License v3.0

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'CARXAC'
author 'Carx Anti-Cheat'
description 'CARXAC - Carx Anti-Cheat | Control Center'
version '1.0.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/css/*.css',
    'ui/js/*.js',
    'ui/assists/**/*.*',
    'data/runtime.json'
}

shared_scripts {
    'tables/*.lua',
    'configs/carx-config.lua',
    'shared/carx-schema.lua'
}

client_scripts {
    'src/carx-client.lua',
    'src/carx-menu.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'configs/carx-webhook.lua',
    'src/carx-server.lua',
    'src/carx-control.lua'
}

exports {
    'CARXAC_CHANGE_TEMP_WHITELIST',
    'CARXAC_CHANGE_TEMP_WHHITELIST',
    'CARXAC_CHECK_TEMP_WHITELIST',
    'CARXAC_ACTION'
}

server_exports {
    'CARXAC_CHANGE_TEMP_WHITELIST',
    'CARXAC_CHANGE_TEMP_WHHITELIST',
    'CARXAC_CHECK_TEMP_WHITELIST',
    'CARXAC_ACTION',
    'CARXAC_BAN_PLAYER',
    'BanPlayer',
    'CARXAC_UNBAN_PLAYER',
    'UnbanPlayer',
    'AuthorizePedChange',
    'IsDetectionGraceActive'
}

dependencies {
    'oxmysql'
}
