CreateThread(function()
  print(('[mz_core][bootstrap] waiting prepare prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s'):format(
    tostring(MZCoreState and MZCoreState.prepareDone),
    tostring(MZCoreState and MZCoreState.prepareOk),
    tostring(MZCoreState and MZCoreState.seedDone),
    tostring(MZCoreState and MZCoreState.seedOk),
    tostring(MZCoreState and MZCoreState.ready)
  ))

  local lastStatusAt = GetGameTimer()

  while not (MZCoreState and MZCoreState.prepareDone == true) do
    if GetGameTimer() - lastStatusAt >= 5000 then
      lastStatusAt = GetGameTimer()
      print(('[mz_core][bootstrap] still waiting prepare prepareStage=%s prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s'):format(
        tostring(MZCoreState and MZCoreState.prepareStage),
        tostring(MZCoreState and MZCoreState.prepareDone),
        tostring(MZCoreState and MZCoreState.prepareOk),
        tostring(MZCoreState and MZCoreState.seedDone),
        tostring(MZCoreState and MZCoreState.seedOk),
        tostring(MZCoreState and MZCoreState.ready)
      ))
    end

    Wait(100)
  end

  if MZCoreState.prepareOk ~= true then
    MZCoreState.seedDone = true
    MZCoreState.seedOk = false
    MZCoreState.ready = false
    print(('[mz_core][bootstrap] aborted prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s prepareStage=%s prepareMarker=%s prepareEnteredXpcall=%s prepareError=%s'):format(
      tostring(MZCoreState.prepareDone),
      tostring(MZCoreState.prepareOk),
      tostring(MZCoreState.seedDone),
      tostring(MZCoreState.seedOk),
      tostring(MZCoreState.ready),
      tostring(MZCoreState.prepareStage),
      tostring(MZCoreState.prepareMarker),
      tostring(MZCoreState.prepareEnteredXpcall),
      tostring(MZCoreState.prepareError)
    ))
    return
  end

  print(('[mz_core][bootstrap] prepare ok prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s'):format(
    tostring(MZCoreState.prepareDone),
    tostring(MZCoreState.prepareOk),
    tostring(MZCoreState.seedDone),
    tostring(MZCoreState.seedOk),
    tostring(MZCoreState.ready)
  ))

  if not MZSeed or type(MZSeed.ensureDefaultOrgs) ~= 'function' then
    MZCoreState.seedDone = true
    MZCoreState.seedOk = false
    MZCoreState.ready = false
    print(('[mz_core][bootstrap] seed failed: default org seed unavailable prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s'):format(
      tostring(MZCoreState.prepareDone),
      tostring(MZCoreState.prepareOk),
      tostring(MZCoreState.seedDone),
      tostring(MZCoreState.seedOk),
      tostring(MZCoreState.ready)
    ))
    return
  end

  print('[mz_core][bootstrap] seed start')

  local ok, err = xpcall(function()
    MZSeed.ensureDefaultOrgs()
  end, debug.traceback)

  MZCoreState.seedDone = true
  MZCoreState.seedOk = ok == true
  MZCoreState.ready = MZCoreState.prepareOk == true and ok == true

  if not ok then
    print(('[mz_core][bootstrap] seed failed stage=%s error=%s'):format(
      tostring(MZCoreState.seedStage),
      tostring(err)
    ))
    print(('[mz_core][bootstrap] final state prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s seedStage=%s'):format(
      tostring(MZCoreState.prepareDone),
      tostring(MZCoreState.prepareOk),
      tostring(MZCoreState.seedDone),
      tostring(MZCoreState.seedOk),
      tostring(MZCoreState.ready),
      tostring(MZCoreState.seedStage)
    ))
    return
  end

  print(('[mz_core][bootstrap] complete prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s seedStage=%s'):format(
    tostring(MZCoreState.prepareDone),
    tostring(MZCoreState.prepareOk),
    tostring(MZCoreState.seedDone),
    tostring(MZCoreState.seedOk),
    tostring(MZCoreState.ready),
    tostring(MZCoreState.seedStage)
  ))
  print('[mz_core] bootstrap complete (1.0.0)')
  print('[mz_core] suporte/configuracao adicional: defina seus canais e identidade do projeto antes da producao')
end)
