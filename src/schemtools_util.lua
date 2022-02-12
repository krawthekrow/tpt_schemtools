local Util = {}

function Util.invert_table(tbl)
	local invtbl = {}
	for k, v in pairs(tbl) do
		invtbl[v] = k
	end
	return invtbl
end

function Util.escape_str(s)
	local escape_map = {
		['\a'] = '\\a',
		['\b'] = '\\b',
		['\f'] = '\\f',
		['\n'] = '\\n',
		['\r'] = '\\r',
		['\t'] = '\\t',
		['\v'] = '\\v',
		['\\'] = '\\\\',
	}
	return s:gsub('[%c\\]', escape_map)
end

function Util.dump_var(x, custom_dump)
	local tbl_cache = {}
	local function dump_var_inner(x, indent)
		if type(x) == 'string' then
			return '"' .. Util.escape_str(x) .. '"'
		end
		if type(x) ~= 'table' then
			return tostring(x)
		end
		if tbl_cache[tostring(x)] ~= nil then
			return '*' .. tostring(x)
		end
		if custom_dump ~= nil then
			local custom_res = custom_dump(x)
			if custom_res ~= nil then
				return custom_res
			end
		end
		local xstr = tostring(x) .. ' {'
		for k, v in pairs(x) do
			xstr = xstr .. '\n' ..
				indent .. '  [' .. k .. '] => ' .. dump_var_inner(v, indent .. '  ')
		end
		xstr = xstr .. '\n' ..
			indent .. '}'
		return xstr
	end
	print(dump_var_inner(x, ''))
end

function Util.str_split(str, delimiter)
  local result = {}
  local from = 1
  local delim_from, delim_to = str:find(delimiter, from)
  while delim_from do
    table.insert(result, str:sub(from, delim_from-1))
    from = delim_to + 1
    delim_from, delim_to = str:find(delimiter, from)
  end
  table.insert(result, str:sub(from))
  return result
end

function Util.str_startswith(str, prefix)
	return str:sub(1, #prefix) == prefix
end

function Util.arr_contains(arr, x)
	for _, v in ipairs(arr) do
		if v == x then
			return true
		end
	end
	return false
end

-- tpt specific

Util.ELEM_PREFIX = 'DEFAULT_PT_'
Util.FIELD_PREFIX = 'FIELD_'
Util.CELSIUS_BASE = 273.15

Util.FILT_MODES = {
	SET = 0,
	AND = 1,
	OR = 2,
	SUB = 3,
	SHL = 4,
	SHR = 5,
	NOP = 6,
	XOR = 7,
	NOT = 8,
	QSCAT = 9,
	SHLV = 10,
	SHRV = 11,
}

return Util
