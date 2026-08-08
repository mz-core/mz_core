local function exportContext(context, defaultReason)
  context = type(context) == 'table' and context or {}
  return {
    internal = false,
    invokingResource = GetInvokingResource(),
    reason = type(context.reason) == 'string' and context.reason or defaultReason,
    actorSource = tonumber(context.actorSource),
    item = type(context.item) == 'string' and context.item or nil,
    cause = type(context.cause) == 'string' and context.cause:sub(1, 48) or nil,
    operationId = type(context.operationId) == 'string' and context.operationId:sub(1, 96) or nil,
    administrative = context.administrative == true,
    reviveHealth = tonumber(context.reviveHealth),
    reviveArmor = tonumber(context.reviveArmor),
    respawnHealth = tonumber(context.respawnHealth),
    respawnArmor = tonumber(context.respawnArmor),
    expectedRevision = tonumber(context.expectedRevision),
    requestedAt = os.time()
  }
end

local function runtimeStateReaderAllowed(resource)
  local readers = Config and Config.PlayerStates and Config.PlayerStates.authorization
    and Config.PlayerStates.authorization.stateReaders or {}
  for _, candidate in ipairs(type(readers) == 'table' and readers or {}) do
    if candidate == resource then return true end
  end
  return false
end

exports('GetPlayerState', function(source)
  return MZPlayerStateService.getState(source)
end)

exports('GetPlayerStateRuntimeIdentity', function(source)
  if not runtimeStateReaderAllowed(GetInvokingResource()) then
    return false, { code = 'not_authorized' }
  end
  return MZPlayerStateService.getRuntimeIdentity(source)
end)

exports('GetStatus', function(source, statusName)
  return MZPlayerStateService.getStatus(source, statusName)
end)

exports('SetStatus', function(source, statusName, value, context)
  return MZPlayerStateService.setStatus(source, statusName, value, exportContext(context, 'set_status'))
end)

exports('AddStatus', function(source, statusName, amount, context)
  return MZPlayerStateService.addStatus(source, statusName, amount, exportContext(context, 'add_status'))
end)

exports('RemoveStatus', function(source, statusName, amount, context)
  return MZPlayerStateService.removeStatus(source, statusName, amount, exportContext(context, 'remove_status'))
end)

exports('ApplyStatusPatch', function(source, patch, context)
  return MZPlayerStateService.applyStatusPatch(source, patch, exportContext(context, 'status_patch'))
end)

exports('ApplyPlayerHealthDamage', function(source, amount, context)
  return MZPlayerStateService.applyHealthDamage(source, amount, exportContext(context, 'health_damage'))
end)

exports('ApplyPlayerHealing', function(source, amount, context)
  return MZPlayerStateService.applyHealing(source, amount, exportContext(context, 'health_healing'))
end)

exports('GetDeathState', function(source)
  return MZPlayerStateService.getDeathState(source)
end)

exports('MarkPlayerDowned', function(source, context)
  return MZPlayerStateService.markDowned(source, exportContext(context, 'mark_downed'))
end)

exports('MarkPlayerDead', function(source, context)
  return MZPlayerStateService.markDead(source, exportContext(context, 'mark_dead'))
end)

exports('RevivePlayer', function(source, context)
  return MZPlayerStateService.revive(source, exportContext(context, 'revive'))
end)

exports('BeginPlayerRespawn', function(source, context)
  return MZPlayerStateService.beginRespawn(source, exportContext(context, 'begin_respawn'))
end)

exports('CompletePlayerRespawn', function(source, context)
  return MZPlayerStateService.completeRespawn(source, exportContext(context, 'complete_respawn'))
end)

exports('AbortPlayerRespawn', function(source, context)
  return MZPlayerStateService.abortRespawn(source, exportContext(context, 'abort_respawn'))
end)

exports('GetPlayerStateIdentity', function(source)
  return MZPlayerStateService.getSyncIdentity(source)
end)

exports('SetPlayerDeathDeadline', function(source, deadlineKind, deadline, context)
  return MZPlayerStateService.setDeathDeadline(
    source,
    deadlineKind,
    deadline,
    exportContext(context, 'set_death_deadline')
  )
end)

exports('CanPlayerPerformAction', function(source, action)
  return MZPlayerStateService.canPerformAction(source, action)
end)

exports('FlushPlayerState', function(source, reason, force)
  return MZPlayerStateService.flush(source, reason, force == true, exportContext(nil, 'manual_flush'))
end)
