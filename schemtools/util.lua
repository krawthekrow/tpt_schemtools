local Util = {}

function Util.floordiv(x, y)
	return (x - (x % y)) / y
end

function Util.ceildiv(x, y)
	if x % y == 0 then
		return x / y
	else
		return Util.floordiv(x, y) + 1
	end
end

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
				indent .. '  [' .. dump_var_inner(k, indent .. '  ') .. '] => ' ..
				dump_var_inner(v, indent .. '  ')
		end
		xstr = xstr .. '\n' ..
			indent .. '}'
		return xstr
	end
	print(dump_var_inner(x, ''))
end

function Util.soft_assert(pred, msg)
	if not pred then
		if msg == nil then
			print('soft assert failed')
		else
			print('soft assert failed: ' .. msg)
		end
		print(debug.traceback())
	end
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

function Util.tbl_keys(tbl)
	local keys = {}
	for k, _ in pairs(tbl) do
		table.insert(keys, k)
	end
	return keys
end

function Util.custom_traceback(start_depth)
	print('debug traceback:')
	local depth = 1
	while true do
		local info = debug.getinfo(start_depth + depth, 'Sln')
		if info == nil then
			break
		end
		local source = info.short_src
		local name = info.name
		local line = info.currentline
		local output_line = '    ' .. source .. ':' .. line
		if name ~= nil then
			output_line = output_line .. ': in function ' .. name
		end
		print(output_line)
		depth = depth + 1
	end
end

function Util.wrap_with_xpcall(func, after_err)
	local function onerr(err)
		print(err)
		Util.custom_traceback(2)
		after_err()
	end
	return function(...)
		local ok, ret = xpcall(func, onerr, ...)
		return ret
	end
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

Util.CONDUCTORS = {
	elem.DEFAULT_PT_METL,
	elem.DEFAULT_PT_INWR,
	elem.DEFAULT_PT_PSCN,
	elem.DEFAULT_PT_NSCN,
	elem.DEFAULT_PT_INST,
}

Util.FRME_RANGE = 15

local function make_part_fields()
	local d = {}
	for k, v in pairs(sim) do
		if Util.str_startswith(k, Util.FIELD_PREFIX) then
			local field_name = k:sub(Util.FIELD_PREFIX:len() + 1):lower()
			d[field_name] = v
		end
	end
	return d
end
Util.PART_FIELDS = make_part_fields()

return Util
