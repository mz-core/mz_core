MZOrgStaffMutationService = MZOrgStaffMutationService or {}

local ORG_TYPES = { job = true, gang = true, business = true, government = true, vip = true, event = true }
local ACTION_PERMISSION = {
  create = 'staff.orgs.create',
  basic = 'staff.orgs.edit',
  type = 'staff.orgs.edit',
  features = 'staff.orgs.features',
  appearance = 'staff.orgs.appearance',
  duty = 'staff.orgs.duty',
  archive = 'staff.orgs.archive',
  restore = 'staff.orgs.restore'
}
local ACTION_NAME = {
  create = 'org.create', basic = 'org.update', type = 'org.type.change',
  features = 'org.features.update', appearance = 'org.appearance.update',
  duty = 'org.duty_point.update',
  archive = 'org.archive', restore = 'org.restore'
}
local ACTION_TOKEN = {
  create = 'oc', basic = 'ou', type = 'ot', features = 'of',
  appearance = 'oa', duty = 'od', archive = 'ox', restore = 'or'
}
local DUTY_ORG_TYPES = { job = true, gang = true, business = true, government = true, event = true }
local APPEARANCE_FIELDS = {
  accent = true, accent2 = true, brand = true, headerIcon = true,
  badge = true, position = true, width = true
}
local FEATURE_TYPES = {
  overview = ORG_TYPES,
  members = ORG_TYPES,
  grades = { job = true, gang = true, business = true, government = true, event = true },
  bank = { job = true, gang = true, business = true, government = true },
  goals = { job = true, gang = true, business = true, government = true, event = true },
  recruitment = { job = true, gang = true, business = true, government = true, event = true },
  logs = ORG_TYPES,
  settings = ORG_TYPES
}

local function asBool(value)
  return value == true or value == 1 or tostring(value):lower() == 'true'
end

local function trim(value, maxLength)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  if maxLength and #value > maxLength then return nil end
  return value
end

local function safeText(value, minLength, maxLength, optional)
  value = trim(value, maxLength)
  if not value then return optional and nil or false end
  if #value < (minLength or 1) then return false end
  local lower = value:lower()
  if value:find('[<>]') or value:find('[{}]') or lower:find('javascript:', 1, true)
    or lower:find('data:', 1, true) or lower:find('http://', 1, true)
    or lower:find('https://', 1, true) or lower:find('url(', 1, true) then
    return false
  end
  return value
end

local function copy(value)
  if type(value) ~= 'table' then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function onlyKeys(value, allowed)
  if type(value) ~= 'table' then return false end
  for key in pairs(value) do
    if not allowed[key] then return false end
    if type(key) == 'string' and key:lower():match('^staff%.') then return false end
  end
  return true
end

local function normalizeSource(source)
  source = tonumber(source)
  return source and source > 0 and math.floor(source) or nil
end

local function actorFor(source)
  local player = MZPlayerService.getPlayer(source)
  if not player or not player.citizenid then return nil end
  local name = GetPlayerName(source)
  return {
    source = source,
    citizenid = tostring(player.citizenid),
    name = trim(name, 96) or ('ID ' .. tostring(source))
  }
end

local function hasExactPermission(source, operation)
  local permission = ACTION_PERMISSION[operation]
  return permission ~= nil and MZOrgService.hasGlobalPermission(source, permission) == true
end

local function normalizeContext(payload)
  local context = type(payload) == 'table' and payload.context or nil
  if type(context) ~= 'table' then return nil end
  local requestId = tonumber(context.requestId)
  local sessionRevision = trim(context.sessionRevision, 64)
  local contextKey = trim(context.contextKey, 96)
  local module = trim(context.module, 32)
  if not requestId or requestId <= 0 or not sessionRevision or not contextKey or not module then return nil end
  return {
    requestId = math.floor(requestId),
    sessionId = trim(context.sessionId, 64),
    sessionRevision = sessionRevision,
    contextKey = contextKey,
    module = module,
    orgCode = trim(context.orgCode, 48)
  }
end

local function safeToken(value, maxLength)
  value = tostring(value or ''):gsub('[^%w:_-]', '_')
  if #value > maxLength then value = value:sub(1, maxLength) end
  return value
end

local function auditIdFor(operation, source, context)
  return ('mzorg:%s:%s:%s:%s'):format(
    ACTION_TOKEN[operation], tostring(source), safeToken(context.sessionRevision, 52), safeToken(context.requestId, 12)
  ):sub(1, 96)
end

local function orgDto(row)
  if not row then return nil end
  return {
    id = tonumber(row.id) or row.id,
    code = row.code,
    name = row.name,
    type = row.type_code,
    typeName = row.type_name,
    active = asBool(row.active),
    status = asBool(row.active) and 'active' or 'archived',
    organizationRevision = tonumber(row.revision) or 1,
    isPublic = asBool(row.is_public),
    requiresWhitelist = asBool(row.requires_whitelist),
    hasSalary = asBool(row.has_salary),
    hasSharedAccount = asBool(row.has_shared_account),
    hasStorage = asBool(row.has_storage),
    config = MZUtils.jsonDecode(row.config_json, {}) or {},
    createdAt = row.created_at,
    updatedAt = row.updated_at
  }
end

local function existingResult(auditId, action, orgCode)
  local audit = MZOrgStaffMutationRepository.getAuditById(auditId)
  if not audit or audit.action ~= action or audit.org_code ~= orgCode then return nil end
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return nil end
  return {
    auditId = auditId,
    organization = orgDto(org),
    idempotent = true
  }
end

local function auditJson(auditId, action, actor, orgCode, before, after, reason, context)
  return MZUtils.jsonEncode({
    auditId = auditId,
    actor = { source = actor.source, citizenid = actor.citizenid, name = actor.name },
    organization = orgCode,
    action = action,
    before = before,
    after = after,
    reason = reason,
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    session = { id = context.sessionId, revision = context.sessionRevision },
    requestId = context.requestId,
    context = { key = context.contextKey, module = context.module, orgCode = context.orgCode }
  })
end

local function emitChanged(operation, actor, org, auditId)
  TriggerEvent('mz_core:internal:organizationChanged', {
    action = ACTION_NAME[operation],
    orgCode = org.code,
    organizationRevision = tonumber(org.revision) or 1,
    active = asBool(org.active),
    auditId = auditId,
    actorSource = actor.source
  })

  for _, member in ipairs(MZOrgRepository.listMembersForOrg(org.id) or {}) do
    local online = MZPlayerService.getPlayerByCitizenId(member.citizenid)
    if online and online.source then
      MZOrgService.loadPlayerOrgs(online.source)
      TriggerClientEvent('mz_core:client:playerLoaded', online.source, online)
    end
  end
end

local function featureAllowed(name, orgType)
  return FEATURE_TYPES[name] and FEATURE_TYPES[name][orgType] == true
end

local function validateFeatures(features, orgType, flags)
  if type(features) ~= 'table' then return false, 'invalid_features' end
  local result = {}
  for name, value in pairs(features) do
    if not featureAllowed(name, orgType) then return false, FEATURE_TYPES[name] and 'feature_not_applicable' or 'unknown_feature' end
    if type(value) ~= 'boolean' then return false, 'invalid_feature_value' end
    if name == 'bank' and value == true and flags.hasSharedAccount ~= true then return false, 'feature_dependency_unavailable' end
    result[name] = value
  end
  return true, result
end

local function normalizeAppearance(values)
  if type(values) ~= 'table' then return false, 'invalid_appearance' end
  local result = {}
  for field, value in pairs(values) do
    if not APPEARANCE_FIELDS[field] then return false, 'unknown_appearance_field' end
    if field == 'accent' or field == 'accent2' then
      if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then return false, 'invalid_color' end
      result[field] = value:upper()
    elseif field == 'position' then
      if value ~= 'left' and value ~= 'right' and value ~= 'center' then return false, 'invalid_position' end
      result[field] = value
    elseif field == 'width' then
      value = tonumber(value)
      if not value or value ~= math.floor(value) or value < 320 or value > 640 then return false, 'invalid_width' end
      result[field] = value
    elseif field == 'headerIcon' then
      value = trim(value, 32)
      if not value or not value:match('^[a-z0-9][a-z0-9_-]*$') then return false, 'invalid_icon' end
      result[field] = value
    else
      value = safeText(value, 1, field == 'badge' and 16 or 48, false)
      if not value then return false, 'invalid_appearance_text' end
      result[field] = value
    end
  end
  return true, result
end

local function normalizeDutyPoint(value, orgType)
  if DUTY_ORG_TYPES[tostring(orgType or '')] ~= true then return false, 'invalid_duty_type' end
  if type(value) ~= 'table'
    or not onlyKeys(value, { enabled = true, coords = true, radius = true, drawDistance = true, label = true }) then
    return false, 'invalid_duty_point'
  end
  if type(value.enabled) ~= 'boolean' then return false, 'invalid_duty_point' end
  if value.enabled == false then return true, nil end

  if type(value.coords) ~= 'table' or not onlyKeys(value.coords, { x = true, y = true, z = true }) then
    return false, 'invalid_coords'
  end
  local x, y, z = tonumber(value.coords.x), tonumber(value.coords.y), tonumber(value.coords.z)
  local function finite(number)
    return number ~= nil and number == number and number ~= math.huge and number ~= -math.huge
  end
  if not finite(x) or not finite(y) or not finite(z)
    or x < -10000.0 or x > 10000.0 or y < -10000.0 or y > 10000.0
    or z < -1000.0 or z > 3000.0 then
    return false, 'invalid_coords'
  end
  local radius = tonumber(value.radius)
  if not finite(radius) or radius < 1.0 or radius > 5.0 then return false, 'invalid_radius' end
  local drawDistance = tonumber(value.drawDistance)
  if not finite(drawDistance) or drawDistance < 5.0 or drawDistance > 50.0
    or drawDistance < radius then
    return false, 'invalid_draw_distance'
  end
  local label = safeText(value.label, 2, 64, false)
  if not label then return false, 'invalid_label' end
  return true, {
    enabled = true,
    coords = { x = x, y = y, z = z },
    radius = radius,
    drawDistance = drawDistance,
    label = label
  }
end

local function mergeDomain(config, domain, patch, remove, resetAll)
  config = copy(type(config) == 'table' and config or {})
  local current = {}
  if not resetAll then current = copy(type(config[domain]) == 'table' and config[domain] or {}) end
  for _, key in ipairs(type(remove) == 'table' and remove or {}) do current[key] = nil end
  for key, value in pairs(type(patch) == 'table' and patch or {}) do current[key] = value end
  config[domain] = current
  return config
end

local function prepare(source, operation, payload, orgCode)
  source = normalizeSource(source)
  payload = type(payload) == 'table' and payload or {}
  if not source then return nil, 'invalid_source' end
  local actor = actorFor(source)
  if not actor then return nil, 'player_not_loaded' end
  if not hasExactPermission(source, operation) then return nil, 'forbidden' end
  local context = normalizeContext(payload)
  if not context then return nil, 'invalid_context' end
  if orgCode and context.orgCode ~= orgCode then return nil, 'context_mismatch' end
  local action = ACTION_NAME[operation]
  local auditId = auditIdFor(operation, source, context)
  local duplicate = orgCode and existingResult(auditId, action, orgCode) or nil
  return { source = source, actor = actor, context = context, action = action, auditId = auditId, duplicate = duplicate }
end

local function revisionGuard(row, payload)
  local expected = tonumber(payload.organizationRevision)
  if not expected or expected < 1 then return nil, 'invalid_revision' end
  if tonumber(row.revision) ~= math.floor(expected) then return nil, 'conflict' end
  return math.floor(expected)
end

local function finalize(operation, prepared, row, before, reason)
  local after = orgDto(row)
  emitChanged(operation, prepared.actor, row, prepared.auditId)
  return true, {
    auditId = prepared.auditId,
    organization = after,
    before = before,
    after = after,
    idempotent = false
  }
end

function MZOrgStaffMutationService.create(source, payload)
  if not onlyKeys(payload, { code = true, name = true, type = true, active = true, public = true, features = true, appearance = true, reason = true, context = true }) then
    return false, 'unknown_field'
  end
  local code = trim(payload.code, 48)
  code = code and code:lower() or nil
  if not code or not code:match('^[a-z0-9][a-z0-9_-]*$') or #code < 2 then return false, 'invalid_code' end
  -- Criacao usa o contexto global staff:create: a organizacao ainda nao existe
  -- e, por contrato, nao ha orgCode selecionado no envelope contextual.
  local prepared, err = prepare(source, 'create', payload, nil)
  if not prepared then return false, err end
  local duplicate = existingResult(prepared.auditId, prepared.action, code)
  if duplicate then return true, duplicate end
  if MZOrgRepository.getOrgByCode(code) then return false, 'org_already_exists' end

  local orgType = trim(payload.type, 32)
  orgType = orgType and orgType:lower() or nil
  if not ORG_TYPES[orgType] then return false, 'invalid_type' end
  local name = safeText(payload.name, 2, 120, false)
  local reason = safeText(payload.reason, 3, 255, false)
  if not name then return false, 'invalid_name' end
  if not reason then return false, 'invalid_reason' end
  if type(payload.active) ~= 'boolean' then return false, 'invalid_state' end
  if not onlyKeys(payload.public or {}, { displayName = true, description = true, metadata = true }) then return false, 'invalid_public_config' end
  local public = copy(payload.public or {})
  public.displayName = safeText(public.displayName, 2, 48, true)
  public.description = safeText(public.description, 1, 160, true)
  if type(public.metadata) ~= 'table' or not onlyKeys(public.metadata, { category = true, locale = true }) then return false, 'invalid_metadata' end
  for key, value in pairs(public.metadata) do
    public.metadata[key] = safeText(value, 1, key == 'locale' and 16 or 48, true)
    if value ~= nil and not public.metadata[key] then return false, 'invalid_metadata' end
  end
  local appearanceOk, appearance = normalizeAppearance(payload.appearance or {})
  if not appearanceOk then return false, appearance end
  if not public.displayName and not appearance.brand then return false, 'display_name_required' end

  local template = MZOrgService.getCreationTemplate(orgType)
  local typeRow = MZOrgRepository.getOrgTypeByCode(orgType)
  if not template or not typeRow then return false, 'invalid_type' end
  local flags = {
    hasSalary = template.has_salary == true,
    hasSharedAccount = template.has_shared_account == true or template.requires_shared_account == true,
    hasStorage = template.has_storage == true
  }
  local featuresOk, features = validateFeatures(payload.features or {}, orgType, flags)
  if not featuresOk then return false, features end
  local config = {
    public = public,
    features = features,
    ui = appearance,
    lifecycle = {},
    created_from_template = orgType,
    created_by = prepared.actor.citizenid,
    created_reason = reason
  }
  if payload.active == false then
    config.lifecycle.archivedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
    config.lifecycle.archivedBy = prepared.actor.citizenid
    config.lifecycle.archivedReason = reason
  end
  local afterAudit = {
    code = code, name = name, type = orgType, active = payload.active,
    public = public, features = features, appearance = appearance
  }
  local auditJsonValue = auditJson(prepared.auditId, prepared.action, prepared.actor, code, nil, afterAudit, reason, prepared.context)
  local transactionOk, committed = pcall(MZOrgStaffMutationRepository.createWithAudit, {
    type_id = typeRow.id, type_code = orgType, code = code, name = name,
    is_public = false, has_salary = flags.hasSalary, has_shared_account = flags.hasSharedAccount,
    has_storage = flags.hasStorage, active = payload.active, config_json = MZUtils.jsonEncode(config),
    action = prepared.action, actor = prepared.actor.citizenid, audit_id = prepared.auditId, audit_json = auditJsonValue
  }, template)
  if not transactionOk or not committed then
    local raced = existingResult(prepared.auditId, prepared.action, code)
    if raced then return true, raced end
    if MZOrgRepository.getOrgByCode(code) then return false, 'org_already_exists' end
    return false, 'audit_transaction_failed'
  end
  local row = MZOrgRepository.getOrgByCode(code)
  if not row or not MZOrgStaffMutationRepository.getAuditById(prepared.auditId) then return false, 'audit_transaction_failed' end
  return finalize('create', prepared, row, nil, reason)
end

local function loadEditable(source, operation, payload, requireActive)
  local code = trim(payload.orgCode, 48)
  code = code and code:lower() or nil
  if not code or not code:match('^[a-z0-9][a-z0-9_-]*$') then return nil, 'invalid_org' end
  local prepared, err = prepare(source, operation, payload, code)
  if not prepared then return nil, err end
  if prepared.duplicate then return { duplicate = prepared.duplicate } end
  local row = MZOrgRepository.getOrgByCode(code)
  if not row or not ORG_TYPES[tostring(row.type_code or '')] then return nil, 'org_not_found' end
  if requireActive == true and not asBool(row.active) then return nil, 'org_archived' end
  if requireActive == false and asBool(row.active) then return nil, 'org_already_active' end
  local revision, revisionError = revisionGuard(row, payload)
  if not revision then return nil, revisionError end
  return { code = code, prepared = prepared, row = row, revision = revision, config = MZUtils.jsonDecode(row.config_json, {}) or {} }
end

local function commitUpdate(operation, loaded, nextConfig, before, afterAudit, reason, extra)
  local data = {
    code = loaded.code,
    expected_revision = loaded.revision,
    config_json = MZUtils.jsonEncode(nextConfig),
    action = loaded.prepared.action,
    actor = loaded.prepared.actor.citizenid,
    audit_id = loaded.prepared.auditId,
    audit_json = auditJson(loaded.prepared.auditId, loaded.prepared.action, loaded.prepared.actor, loaded.code, before, afterAudit, reason, loaded.prepared.context)
  }
  for key, value in pairs(extra or {}) do data[key] = value end
  local transactionOk, committed = pcall(MZOrgStaffMutationRepository.updateWithAudit, operation, data)
  if not transactionOk or not committed then
    local duplicate = existingResult(loaded.prepared.auditId, loaded.prepared.action, loaded.code)
    if duplicate then return true, duplicate end
    local current = MZOrgRepository.getOrgByCode(loaded.code)
    if current and tonumber(current.revision) ~= loaded.revision then return false, 'conflict' end
    return false, 'audit_transaction_failed'
  end
  local row = MZOrgRepository.getOrgByCode(loaded.code)
  return finalize(operation, loaded.prepared, row, before, reason)
end

function MZOrgStaffMutationService.updateBasic(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, name = true, public = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'basic', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  local name = payload.name ~= nil and safeText(payload.name, 2, 120, false) or loaded.row.name
  if not name then return false, 'invalid_name' end
  if not onlyKeys(payload.public or {}, { displayName = true, description = true, metadata = true }) then return false, 'invalid_public_config' end
  local public = copy(type(loaded.config.public) == 'table' and loaded.config.public or {})
  for key, value in pairs(payload.public or {}) do
    if key == 'metadata' then
      if type(value) ~= 'table' or not onlyKeys(value, { category = true, locale = true }) then return false, 'invalid_metadata' end
      public.metadata = copy(type(public.metadata) == 'table' and public.metadata or {})
      for metadataKey, metadataValue in pairs(value) do
        local normalized = safeText(metadataValue, 1, metadataKey == 'locale' and 16 or 48, true)
        if metadataValue ~= nil and trim(metadataValue) and not normalized then return false, 'invalid_metadata' end
        public.metadata[metadataKey] = normalized
      end
    else
      local normalized = safeText(value, key == 'displayName' and 2 or 1, key == 'displayName' and 48 or 160, true)
      if value ~= nil and trim(value) and not normalized then return false, 'invalid_public_config' end
      public[key] = normalized
    end
  end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.public = public
  local before = { name = loaded.row.name, public = loaded.config.public }
  return commitUpdate('basic', loaded, nextConfig, before, { name = name, public = public }, reason, { name = name })
end

function MZOrgStaffMutationService.changeType(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, targetType = true, dropIncompatible = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'type', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  local targetType = trim(payload.targetType, 32)
  targetType = targetType and targetType:lower() or nil
  if not ORG_TYPES[targetType] then return false, 'invalid_type' end
  if targetType == loaded.row.type_code then return false, 'same_type' end
  local typeRow = MZOrgRepository.getOrgTypeByCode(targetType)
  if not typeRow then return false, 'invalid_type' end
  local nextConfig = copy(loaded.config)
  local incompatible = {}
  for name in pairs(type(nextConfig.features) == 'table' and nextConfig.features or {}) do
    if not featureAllowed(name, targetType) then incompatible[#incompatible + 1] = name end
  end
  if type(nextConfig.ui) == 'table' and nextConfig.ui.profile ~= nil then incompatible[#incompatible + 1] = 'ui.profile' end
  if nextConfig.dutyPoint ~= nil and DUTY_ORG_TYPES[targetType] ~= true then
    incompatible[#incompatible + 1] = 'dutyPoint'
  end
  if #incompatible > 0 and payload.dropIncompatible ~= true then return false, 'incompatible_overrides' end
  if payload.dropIncompatible == true then
    for name in pairs(type(nextConfig.features) == 'table' and nextConfig.features or {}) do
      if not featureAllowed(name, targetType) then nextConfig.features[name] = nil end
    end
    if type(nextConfig.ui) == 'table' then nextConfig.ui.profile = nil end
    if DUTY_ORG_TYPES[targetType] ~= true then nextConfig.dutyPoint = nil end
  end
  local flags = { hasSharedAccount = asBool(loaded.row.has_shared_account) }
  local featuresOk, features = validateFeatures(type(nextConfig.features) == 'table' and nextConfig.features or {}, targetType, flags)
  if not featuresOk then return false, features end
  nextConfig.features = features
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local before = {
    type = loaded.row.type_code,
    features = loaded.config.features,
    ui = loaded.config.ui,
    dutyPoint = loaded.config.dutyPoint
  }
  return commitUpdate('type', loaded, nextConfig, before, {
    type = targetType,
    features = features,
    ui = nextConfig.ui,
    dutyPoint = nextConfig.dutyPoint
  }, reason, { type_id = typeRow.id })
end

function MZOrgStaffMutationService.updateFeatures(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, overrides = true, remove = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'features', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  local flags = { hasSharedAccount = asBool(loaded.row.has_shared_account) }
  local valid, overrides = validateFeatures(payload.overrides or {}, loaded.row.type_code, flags)
  if not valid then return false, overrides end
  local current = copy(type(loaded.config.features) == 'table' and loaded.config.features or {})
  for _, name in ipairs(type(payload.remove) == 'table' and payload.remove or {}) do
    if FEATURE_TYPES[name] == nil then return false, 'unknown_feature' end
    current[name] = nil
  end
  for name, value in pairs(overrides) do current[name] = value end
  local finalOk, finalFeatures = validateFeatures(current, loaded.row.type_code, flags)
  if not finalOk then return false, finalFeatures end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.features = finalFeatures
  return commitUpdate('features', loaded, nextConfig, { features = loaded.config.features }, { features = finalFeatures }, reason)
end

function MZOrgStaffMutationService.updateAppearance(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, overrides = true, remove = true, resetAll = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'appearance', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  local valid, overrides = normalizeAppearance(payload.overrides or {})
  if not valid then return false, overrides end
  local remove = type(payload.remove) == 'table' and payload.remove or {}
  for _, field in ipairs(remove) do if not APPEARANCE_FIELDS[field] then return false, 'unknown_appearance_field' end end
  local current = payload.resetAll == true and {} or copy(type(loaded.config.ui) == 'table' and loaded.config.ui or {})
  if payload.resetAll == true then current.icon = nil end
  for _, field in ipairs(remove) do
    current[field] = nil
    if field == 'headerIcon' then current.icon = nil end
  end
  for field, value in pairs(overrides) do current[field] = value end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.ui = current
  return commitUpdate('appearance', loaded, nextConfig, { ui = loaded.config.ui }, { ui = current }, reason)
end

function MZOrgStaffMutationService.updateDutyPoint(source, payload)
  if not onlyKeys(payload, {
    orgCode = true, organizationRevision = true, dutyPoint = true,
    reason = true, context = true
  }) then
    return false, 'unknown_field'
  end
  local loaded, err = loadEditable(source, 'duty', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  local valid, dutyPoint = normalizeDutyPoint(payload.dutyPoint, loaded.row.type_code)
  if not valid then return false, dutyPoint end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.dutyPoint = dutyPoint
  return commitUpdate(
    'duty',
    loaded,
    nextConfig,
    { dutyPoint = loaded.config.dutyPoint },
    { dutyPoint = dutyPoint },
    reason
  )
end

function MZOrgStaffMutationService.archive(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, confirmCode = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'archive', payload, true)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  if trim(payload.confirmCode, 48) ~= loaded.code then return false, 'strong_confirmation_failed' end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.lifecycle = copy(type(nextConfig.lifecycle) == 'table' and nextConfig.lifecycle or {})
  nextConfig.lifecycle.archivedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  nextConfig.lifecycle.archivedBy = loaded.prepared.actor.citizenid
  nextConfig.lifecycle.archivedReason = reason
  local before = { active = true, lifecycle = loaded.config.lifecycle }
  return commitUpdate('archive', loaded, nextConfig, before, { active = false, lifecycle = nextConfig.lifecycle }, reason)
end

function MZOrgStaffMutationService.restore(source, payload)
  if not onlyKeys(payload, { orgCode = true, organizationRevision = true, reason = true, context = true }) then return false, 'unknown_field' end
  local loaded, err = loadEditable(source, 'restore', payload, false)
  if not loaded then return false, err end
  if loaded.duplicate then return true, loaded.duplicate end
  if not ORG_TYPES[loaded.row.type_code] or not MZOrgRepository.getOrgTypeByCode(loaded.row.type_code) then return false, 'invalid_type' end
  local flags = { hasSharedAccount = asBool(loaded.row.has_shared_account) }
  local featuresOk = validateFeatures(type(loaded.config.features) == 'table' and loaded.config.features or {}, loaded.row.type_code, flags)
  if featuresOk ~= true then return false, 'invalid_features' end
  local appearanceOk = normalizeAppearance((function()
    local values = {}
    for field in pairs(APPEARANCE_FIELDS) do
      if type(loaded.config.ui) == 'table' and loaded.config.ui[field] ~= nil then values[field] = loaded.config.ui[field] end
    end
    return values
  end)())
  if appearanceOk ~= true then return false, 'invalid_appearance' end
  if loaded.config.dutyPoint ~= nil then
    local dutyPointOk = normalizeDutyPoint(loaded.config.dutyPoint, loaded.row.type_code)
    if dutyPointOk ~= true then return false, 'invalid_duty_point' end
  end
  local reason = safeText(payload.reason, 3, 255, false)
  if not reason then return false, 'invalid_reason' end
  local nextConfig = copy(loaded.config)
  nextConfig.lifecycle = copy(type(nextConfig.lifecycle) == 'table' and nextConfig.lifecycle or {})
  nextConfig.lifecycle.restoredAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  nextConfig.lifecycle.restoredBy = loaded.prepared.actor.citizenid
  nextConfig.lifecycle.restoredReason = reason
  local before = { active = false, lifecycle = loaded.config.lifecycle }
  return commitUpdate('restore', loaded, nextConfig, before, { active = true, lifecycle = nextConfig.lifecycle }, reason)
end
