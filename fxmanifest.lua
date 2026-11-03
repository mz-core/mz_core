fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_core'
author 'Mazus'
description 'Modular FiveM core framework base'
version '1.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/*.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/prepare.lua',
  'server/cache.lua',
  'server/player/state_normalizer.lua',
  'server/identity/repository.lua',
  'server/identity/service.lua',
  'server/player/repository.lua',
  'server/player/service.lua',
  'server/player/state_observability.lua',
  'server/player/state_service.lua',
  'server/player/state_sync.lua',
  'server/player/events.lua',
  'server/player/exports.lua',
  'server/player/state_exports.lua',
  'server/player/state_staging.lua',
  'server/staff/repository.lua',
  'server/staff/service.lua',
  'server/staff/exports.lua',
  'server/logs/*.lua',
  'server/seed/*.lua',
  'server/bootstrap.lua',
  'server/main.lua'
}

client_scripts {
  'client/main.lua',
  'client/player.lua',
  'client/player_state.lua',
  'client/spawn.lua'
}

dependencies {
  'oxmysql',
  'ox_lib',
  'spawnmanager'
}
