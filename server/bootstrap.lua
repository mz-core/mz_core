CreateThread(function()
  while not (MZCoreState and MZCoreState.prepareDone == true) do
    Wait(100)
  end

  if MZCoreState.prepareOk ~= true then
    MZCoreState.seedDone = true
    MZCoreState.seedOk = false
    MZCoreState.ready = false
    print('[mz_core] bootstrap aborted because prepare did not complete successfully')
    return
  end

  if not MZSeed or type(MZSeed.ensureDefaultOrgs) ~= 'function' then
    MZCoreState.seedDone = true
    MZCoreState.seedOk = false
    MZCoreState.ready = false
    print('[mz_core] bootstrap failed: default org seed unavailable')
    return
  end

  local ok, err = xpcall(function()
    MZSeed.ensureDefaultOrgs()
  end, debug.traceback)

  MZCoreState.seedDone = true
  MZCoreState.seedOk = ok == true
  MZCoreState.ready = MZCoreState.prepareOk == true and ok == true

  if not ok then
    print(('[mz_core] bootstrap failed: %s'):format(err))
    return
  end

  print('[mz_core] bootstrap complete (1.0.0)')
  print('[mz_core] suporte/configuracao adicional: defina seus canais e identidade do projeto antes da producao')
end)
