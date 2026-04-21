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
  'server/player/*.lua',
  'server/orgs/*.lua',
  'server/vehicles/repository.lua',
  'server/vehicles/service.lua',
  'server/vehicles/events.lua',
  'server/vehicles/exports.lua',
  'server/vehicles/commands.lua',
  'server/vehicles/debug.lua',
  'server/inventory/*.lua',
  'server/accounts/*.lua',
  'server/logs/*.lua',
  'server/bridges/*.lua',
  'server/seed/*.lua',
  'server/bootstrap.lua',
  'server/main.lua'
}

client_scripts {
  'client/main.lua',
  'client/player.lua',
  'client/spawn.lua',
  'client/orgs.lua',
  'client/vehicles.lua',
  'client/inventory.lua'
}

dependencies {
  'oxmysql',
  'ox_lib'
}
