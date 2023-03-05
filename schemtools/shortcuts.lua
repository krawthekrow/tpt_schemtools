local Util = require('schemtools/util')
local Geom = require('schemtools/geom')
local Point = Geom.Point

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
			opts.elem_name = elem_name
			return designer:part(opts)
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
		'opts_rect_line',
		'port',
		'port_alias',
		'connect',
		'part',
		'place',
		'clear',
		'plot',
		'get_dtec_dist',
		'pconfig',
	}
	for _, method in ipairs(designer_methods_to_expose) do
		expose_designer_method(method)
	end

	expose_designer_method('dump', 'dump_var')
	expose_designer_method('v', 'get_var')
	expose_designer_method('iv', 'get_indexed_var')
	expose_designer_method('vv', 'make_vvar')
	expose_designer_method('ivv', 'make_indexed_vvar')
	expose_designer_method('setv', 'set_var')
	expose_designer_method('adv', 'advance_curs')
	expose_designer_method('cursmode', 'set_curs_adv')
	expose_designer_method('getcurs', 'get_curs')
	expose_designer_method('setcurs', 'set_curs')
	expose_designer_method('pushc', 'push_curs')
	expose_designer_method('popc', 'pop_curs')
	expose_designer_method('pushi', 'push_index')
	expose_designer_method('popi', 'pop_index')
	expose_designer_method('chain', 'run_with_curs')
	expose_designer_method('findpt', 'solve_constraints')
	expose_designer_method('tsetup', 'test_setup')
	expose_designer_method('aport', 'array_port')
	expose_designer_method('odist', 'get_orth_dist')
	expose_designer_method('odir', 'get_orth_dir')
	expose_designer_method('pmap', 'get_top_part_at')
	expose_designer_method('cmt', 'add_comment')

	local function array(opts)
		opts = designer:opts_pos(opts)
		opts = designer:opts_pt(opts, 'dp', 'dx', 'dy', nil, false)
		if opts.r ~= nil then
			if opts.r:is_vert() then
				if opts.dp == nil then
					opts.dp = Point:new(0, 1)
				end
				if opts.dp.y > 0 then
					opts.from = opts.r:n(0)
					opts.to = opts.r:s(0)
				else
					opts.from = opts.r:s(0)
					opts.to = opts.r:n(0)
				end
			elseif opts.r:is_horz() then
				if opts.dp == nil then
					opts.dp = Point:new(1, 0)
				end
				if opts.dp.x > 0 then
					opts.from = opts.r:w(0)
					opts.to = opts.r:e(0)
				else
					opts.from = opts.r:e(0)
					opts.to = opts.r:w(0)
				end
			else
				assert(false, 'array r not a line')
			end
		end
		if opts.from ~= nil then opts.p = opts.from end
		if opts.to ~= nil then
			if opts.dp == nil then
				opts.dp = designer:get_orth_dir(opts.p, opts.to)
			end
			opts.n = designer:get_orth_dist(opts.p, opts.to) + 1

			-- allow striding
			local dplen = designer:get_orth_dist(Point.ZERO, opts.dp)
			if dplen ~= 0 then
				opts.n = Util.ceildiv(opts.n, dplen)
			end
		end
		local func = opts.f
		opts.f = function()
			for i = 1, opts.n do
				designer:push_index(i)
				designer:run_with_curs{dx=0, dy=0, f=function()
					func(i)
				end}
				designer:pop_index(i)
			end
		end
		designer:run_with_curs(opts)
	end
	Shortcuts.set_global('array', array)

	local function apply_index(name)
		return designer:apply_index(name)
	end
	Shortcuts.set_global('iname', apply_index)

	local function schem(opts)
		designer:instantiate_schem(opts.f, opts)
	end
	Shortcuts.set_global('schem', schem)

	local function test_case(opts)
		designer.tester:test_case(opts)
	end
	Shortcuts.set_global('tc', test_case)

	local function ilog2(x)
		local i = 0
		while true do
			if 2^i >= x then return i end
			i = i + 1
		end
	end
	local function bsub(x, y)
		return bit.band(x, bit.bnot(y))
	end
	Shortcuts.set_global('intdiv', Util.floordiv)
	Shortcuts.set_global('floordiv', Util.floordiv)
	Shortcuts.set_global('ceildiv', Util.ceildiv)
	Shortcuts.set_global('ilog2', ilog2)
	Shortcuts.set_global('shl', bit.lshift)
	Shortcuts.set_global('shr', bit.rshift)
	Shortcuts.set_global('band', bit.band)
	Shortcuts.set_global('bor', bit.bor)
	Shortcuts.set_global('bxor', bit.bxor)
	Shortcuts.set_global('bnot', bit.bnot)
	Shortcuts.set_global('bsub', bsub)
	Shortcuts.set_global('ka', 0x20000000)

	local function make_point(x, y)
		return Point:new(x, y)
	end
	Shortcuts.set_global('p', make_point)

	Shortcuts.set_global('Util', Util)
	Shortcuts.set_global('Point', Point)
end

function Shortcuts.teardown_globals()
	for k, _ in pairs(Shortcuts.globals) do
		_G[k] = nil
	end
end

return Shortcuts
