MZUtils = {}

function MZUtils.jsonDecode(value, fallback)
  if not value or value == '' then return fallback end
  local ok, result = pcall(json.decode, value)
  if not ok then return fallback end
  return result
end

function MZUtils.jsonEncode(value, fallback)
  local ok, result = pcall(json.encode, value or fallback or {})
  if not ok then
    return json.encode(fallback or {})
  end
  return result
end

function MZUtils.generateCitizenId(length)
  local size = length or 8
  local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local result = ''
  for i = 1, size do
    local rand = math.random(1, #charset)
    result = result .. charset:sub(rand, rand)
  end
  return result
end

function MZUtils.tableClone(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = MZUtils.tableClone(v)
  end
  return out
end

function MZUtils.now()
  return os.time()
end

function MZUtils.generateInstanceUid(prefix)
  local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local function part(size)
    local out = {}
    for i = 1, size do
      local idx = math.random(1, #chars)
      out[#out + 1] = chars:sub(idx, idx)
    end
    return table.concat(out)
  end

  local pfx = prefix or 'MZI'
  return ('%s-%s-%s-%s'):format(pfx, part(4), part(4), part(6))
end

function MZUtils.generateItemSerial(itemName)
  local prefix = (itemName or 'ITEM'):upper():gsub('[^A-Z0-9]', '')
  prefix = prefix:sub(1, 6)
  if prefix == '' then prefix = 'ITEM' end
  return ('%s-%s'):format(prefix, MZUtils.generateCitizenId(8))
end