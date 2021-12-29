local Util = require('schemtools_util')
local Geom = require('schemtools_geom')

local Shortcuts = {
	globals = {},
}

function Shortcuts.set_global(k, v)
	assert(
		Shortcuts.globals[k] == nil,
		'internal error: global "' .. k .. '" previously defined'
	)
	assert(
		_G[k] == nil,
		'unable to set up shortcuts: global "' .. k .. '" already exists'
	)
	Shortcuts.globals[k] = true
	_G[k] = v
end

function Shortcuts.init(designer)
	Shortcuts.set_global('designer', designer)

	local function make_part(elem_name)
		local function part(opts)
			opts.name = elem_name
			designer:part(opts)
		end
		return part
	end
	for k, _ in pairs(elem) do
		if Util.str_startswith(k, Util.ELEM_PREFIX) then
			local elem_name = k:sub(Util.ELEM_PREFIX:len() + 1):lower()
			Shortcuts.set_global(elem_name, make_part(elem_name))
		end
	end

	local function expose_designer_method(name, internal_name)
		if internal_name == nil then internal_name = name end
		local function func(...)
			return designer[internal_name](designer, ...)
		end
		Shortcuts.set_global(name, func)
	end
	local designer_methods_to_expose = {
		'opts_bool',
		'opts_pos',
		'port',
		'part',
		'place',
		'clear',
		'plot',
	}
	for _, method in ipairs(designer_methods_to_expose) do
		expose_designer_method(method)
	end

	local function schem(func)
		designer:begin_scope()
		func()
		return designer:end_scope()
	end
	expose_designer_method('schem', 'run_in_scope')
	expose_designer_method('v', 'get_var')
	expose_designer_method('setv', 'set_var')
	expose_designer_method('adv', 'advance_curs')
	expose_designer_method('cursmode', 'set_curs_adv')
	expose_designer_method('getcurs', 'get_curs')
	expose_designer_method('setcurs', 'set_curs')
	expose_designer_method('pushc', 'push_curs')
	expose_designer_method('popc', 'pop_curs')
	expose_designer_method('chain', 'run_with_curs')

	for name, val in pairs(Util.FILT_MODES) do
		Shortcuts.set_global('f' .. name:lower(), val)
	end

	local function ilog2(x)
		local i = 0
		while true do
			if 2^i >= x then return i end
			i = i + 1
		end
	end
	Shortcuts.set_global('ilog2', ilog2)
	Shortcuts.set_global('shl', bit.lshift)
	Shortcuts.set_global('shr', bit.rshift)
	Shortcuts.set_global('band', bit.band)
	Shortcuts.set_global('bor', bit.bor)
	Shortcuts.set_global('bxor', bit.bxor)
	Shortcuts.set_global('bnot', bit.bnot)
	Shortcuts.set_global('ka', 0x20000000)

	Shortcuts.set_global('dump', Util.dump_var)

	local function make_point(x, y)
		return Geom.Point:new(x, y)
	end
	Shortcuts.set_global('p', make_point)
end

function Shortcuts.teardown_globals()
	for k, _ in pairs(Shortcuts.globals) do
		_G[k] = nil
	end
end

return Shortcuts
