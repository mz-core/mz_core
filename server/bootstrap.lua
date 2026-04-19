CreateThread(function()
  Wait(1000)

  if MZCoreState and MZCoreState.prepareOk and MZSeed and MZSeed.ensureDefaultOrgs then
    MZSeed.ensureDefaultOrgs()
  else
    print('[mz_core] bootstrap skipped seed because prepare did not complete')
  end

  print('[mz_core] bootstrap complete (0.1.0)')
  print('[mz_core] suporte/configuração adicional: defina seus canais e identidade do projeto antes da produção')
end)