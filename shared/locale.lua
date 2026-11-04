local selected = type(GetConvar) == 'function' and tostring(GetConvar('ox:locale', 'pt-br')):lower() or 'pt-br'
selected = (selected == 'en' or selected == 'en-us') and 'en-us' or 'pt-br'
if type(lib) == 'table' and type(lib.locale) == 'function' then
  lib.locale(selected)
end
