local Geom = require('schemtools_geom')
local Util = require('schemtools_util')
local Tester = require('schemtools_tester')
local Point = Geom.Point
local Constraints = Geom.Constraints

local Cursor = {}
function Cursor.new()
	return {
		pos = Point:new(0, 0),
		adv = Point:new(0, 0),
	}
end

local Port = {}
function Port:new(p, connect_func)
	local o = {
		p = p,
		connect_func = connect_func,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local Schematic = {}
function Schematic:new()
	local o = {
		curs_stack = { Cursor.new() },
		ctx_stack = { },
		-- parts[y][x] is a list of particles at (x, y) in stack order
		-- in schematics, particles can take negative coordinates
		parts = {},
		vars = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Schematic:place_parts(p, parts, under)
	if self.parts[p.y] == nil then
		self.parts[p.y] = {}
	end
	if self.parts[p.y][p.x] == nil then
		self.parts[p.y][p.x] = {}
	end
	if under then
		local new_stack = {}
		for _, part in ipairs(parts) do table.insert(new_stack, part) end
		for _, part in ipairs(self.parts[p.y][p.x]) do
			table.insert(new_stack, part)
		end
		self.parts[p.y][p.x] = new_stack
	else
		for _, part in ipairs(parts) do
			table.insert(self.parts[p.y][p.x], part)
		end
	end
end

function Schematic:for_each_stack(func)
	for y, row in pairs(self.parts) do
		for x, stack in pairs(row) do
			func(Point:new(x, y), stack)
		end
	end
end

function Schematic:for_each_part(func)
	self:for_each_stack(function(p, stack)
		for _, part in ipairs(stack) do
			func(p, part)
		end
	end)
end

local Designer = {}
function Designer:new()
	local o = {
		stack = {},
		autogen_instance_name_cnt = 0,
		tester = Tester:new(),
	}
	setmetatable(o, self)
	self.__index = self
	o:begin_schem()
	return o
end

function Designer:top()
	return self.stack[#self.stack]
end

function Designer:soft_assert(pred, msg)
	if not pred then
		if msg == nil then
			print('soft assert failed')
		else
			print('soft assert failed: ' .. msg)
		end
		print(debug.traceback())
	end
end

function Designer:top_ctx()
	local schem = self:top()
	if #schem.ctx_stack == 0 then return nil end
	return schem.ctx_stack[#schem.ctx_stack]
end

function Designer:expand_var_name(name)
	local ctx = self:top_ctx()
	if ctx == nil then return name end
	return ctx .. '.' .. name
end

function Designer:is_var_name_valid(name)
	return name:match('^[%a_][%w_]*$') ~= nil
end

function Designer:set_var(name, val)
	local is_valid_new_name = self:is_var_name_valid(name)
	local schem = self:top()
	if schem[name] ~= nil then
		schem[name] = val
		return
	end
	name = self:expand_var_name(name)
	assert(is_valid_new_name, 'invalid new var name "' ..  name .. '"')
	if
		getmetatable(schem.vars[name]) == Port and
		getmetatable(val) == Geom.Point
	then
		schem.vars[name].p = val
		return
	end
	schem.vars[name] = val
end

function Designer:get_var_raw(name)
	local schem = self:top()
	name = self:expand_var_name(name)
	return schem.vars[name]
end

function Designer:get_var(name)
	local schem = self:top()
	if schem[name] ~= nil then
		return schem[name]
	end
	local val = self:get_var_raw(name)
	assert(
		val ~= nil,
		'variable "' .. name .. '" does not exist'
	)
	if getmetatable(val) == Port then
		return val.p
	end
	return val
end

function Designer:begin_ctx(ctx)
	ctx = self:expand_var_name(ctx)
	table.insert(self:top().ctx_stack, ctx)
end

function Designer:end_ctx()
	table.remove(self:top().ctx_stack)
end

function Designer:run_with_ctx(ctx, func)
	if ctx == '' then
		func()
		return
	end
	self:begin_ctx(ctx)
	func()
	self:end_ctx()
end

function Designer:parse_full_var_name(full_name)
	local name = full_name:match('[^.]+$')
	if name:len() == full_name:len() then
		return '', name
	end
	local ctx = full_name:sub(1, -name:len() - 2)
	return ctx, name
end

function Designer:connect_1way(v_from, p_to, args)
	local port = self:get_var_raw(v_from)
	local ctx, _ = self:parse_full_var_name(v_from)
	if port.connect_func ~= nil then
		self:run_with_ctx(ctx, function()
			args.p = p_to
			port.connect_func(args)
		end)
	end
end

function Designer:connect(opts)
	-- 1-way connect
	if opts.v ~= nil then
		local args = opts
		if opts.args ~= nil then args = opts.args end
		self:connect_1way(opts.v, opts.p, args)
		return
	end

	local port1 = self:get_var_raw(opts.v1)
	local port2 = self:get_var_raw(opts.v2)
	local args1, args2 = opts, opts
	if opts.args1 ~= nil then args1 = opts.args1 end
	if opts.args2 ~= nil then args2 = opts.args2 end
	self:connect_1way(opts.v1, port2.p, args1)
	self:connect_1way(opts.v2, port1.p, args2)
end

function Designer:port(opts)
	opts = self:opts_pos(opts)
	local schem = self:top()
	local existing_val = self:get_var_raw(opts.v)
	if existing_val ~= nil then
		assert(
			getmetatable(existing_val) == Port,
			'variable "' .. opts.v .. '" already used for non-port'
		)
	end
	self:set_var(opts.v, Port:new(opts.p, opts.f))
end

function Designer:port_alias(opts)
	local schem = self:top()
	local ctx, _ = self:parse_full_var_name(opts.from)
	local orig = self:get_var_raw(opts.from)
	self:port{v=opts.to, p=orig.p, f=function(args)
		self:run_with_ctx(ctx, function()
			orig.connect_func(args)
		end)
	end}
end

function Designer:begin_schem()
	table.insert(self.stack, Schematic:new())
end

function Designer:end_schem()
	assert(#self.stack > 1, 'cannot end root schematic')
	return table.remove(self.stack)
end

function Designer:make_schem(func)
	self:begin_schem()
	func()
	return self:end_schem()
end

function Designer:get_curs_info()
	return self:top().curs_stack[#self:top().curs_stack]
end

function Designer:get_curs()
	return self:get_curs_info().pos
end

function Designer:set_curs(opts)
	opts = self:opts_pt_short(opts)
	self:get_curs_info().pos = opts.p
end

function Designer:advance_curs(opts)
	local schem = self:top()
	opts = self:opts_pt_short(opts, self:get_curs_info().adv)
	self:set_curs({ p = self:get_curs():add(opts.p) })
end

function Designer:set_curs_adv(opts)
	opts = self:opts_pt_short(opts)
	self:get_curs_info().adv = opts.p
end

function Designer:push_curs(opts)
	opts = self:opts_pt_short(opts)
	local curs = self:get_curs()
	table.insert(self:top().curs_stack, Cursor.new())
	self:set_curs(curs)
	self:set_curs_adv(opts)
end

function Designer:pop_curs()
	table.remove(self:top().curs_stack)
end

function Designer:run_with_curs(opts)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_pos(opts, curs, false)
	opts = self:opts_pt(opts, 'dp', 'dx', 'dy')
	self:push_curs({ p = opts.dp })
	if opts.p ~= nil then self:set_curs(opts.p) end
	opts.f()
	self:pop_curs()
	if opts.done then
		self:advance_curs()
	end
end

local PART_FIELDS = {}

local function lazy_init_part_fields()
	if #PART_FIELDS > 0 then
		return
	end
	for k, v in pairs(sim) do
		if Util.str_startswith(k, Util.FIELD_PREFIX) then
			local field_name = k:sub(Util.FIELD_PREFIX:len() + 1):lower()
			PART_FIELDS[field_name] = v
		end
	end
end

function Designer:opts_pt(opts, pname, xname, yname, ref, force)
	if force == nil then force = true end
	if ref == nil then ref = Point:zero() end
	if opts == nil then
		if force then opts = { p = ref } else opts = {} end
	end
	if opts[pname] ~= nil then
		opts[xname], opts[yname] = opts[pname].x, opts[pname].y
	end
	if opts[xname] ~= nil or opts[yname] ~= nil or force then
		if opts[xname] == nil then opts[xname] = ref.x end
		if opts[yname] == nil then opts[yname] = ref.y end
		opts[pname] = Point:new(opts[xname], opts[yname])
	end
	return opts
end

function Designer:opts_pt_short(opts, ref, force)
	if force == nil then force = true end
	if ref == nil then ref = Point:zero() end
	if opts == nil then
		if force then opts = { p = ref } else opts = {} end
	end
	if opts[1] ~= nil then opts.x = opts[1] end
	if opts[2] ~= nil then opts.y = opts[2] end
	return self:opts_pt(opts, 'p', 'x', 'y', ref, force)
end

function Designer:opts_pos(opts, force)
	local curs = self:get_curs()
	if opts == nil then opts = {} end
	if opts.ox ~= nil then opts.x = curs.x + opts.ox end
	if opts.oy ~= nil then opts.y = curs.y + opts.oy end
	return self:opts_pt_short(opts, curs, force)
end

function Designer:opts_bool(opts, name, dflt)
	if dflt == nil then dflt = false end
	if opts[name] == nil then opts[name] = dflt end
	if type(opts[name]) == 'number' then opts[name] = opts[name] == 1 end
	return opts
end

local function decode_elem(name)
	return elem[Util.ELEM_PREFIX .. name:upper()]
end

function Designer:get_orth_dist(from, to, soft_assert)
	local dp = to:sub(from)
	assert(not from:eq(to), 'source and target are the same location')
	assert(
		dp.x == 0 or dp.y == 0 or math.abs(dp.x) == math.abs(dp.y),
		'target not in one of the ordinal directions'
	)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

function Designer:get_dtec_dist(from, to)
	local dp = to:sub(from)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

function Designer:part(opts)
	opts = self:opts_pos(opts)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_bool(opts, 'ss', false)
	opts = self:opts_bool(opts, 'under', false)

	if opts.elem_name ~= nil then
		opts['type'] = decode_elem(opts.elem_name)
	end
	local t = opts['type']

	local orth_pos_enabled = {
		elem.DEFAULT_PT_CRAY,
		elem.DEFAULT_PT_DRAY,
	}

	local curs = self:get_curs()
	local do_orth_pos = Util.arr_contains(orth_pos_enabled, t)
	if do_orth_pos then
		opts = self:opts_pt(opts, 'from', 'fromx', 'fromy', curs)
		opts = self:opts_pt(opts, 'to', 'tox', 'toy', opts.from, false)
	end

	local conductors = {
		elem.DEFAULT_PT_METL,
		elem.DEFAULT_PT_INWR,
		elem.DEFAULT_PT_PSCN,
		elem.DEFAULT_PT_NSCN,
		elem.DEFAULT_PT_INST,
	}

	-- custom prop names
	local function custom_elem_match(target_type)
		if target_type == 'any' then return true end
		if target_type == 'conduct' then
			return Util.arr_contains(conductors, t)
		end
		return t == elem[Util.ELEM_PREFIX .. target_type:upper()]
	end
	local function parse_custom(custom_prop, target_type, prop, func)
		if opts[custom_prop] == nil then return end
		if custom_elem_match(target_type) then
			opts[prop] = func(opts[custom_prop])
		end
	end
	local function prop_id(x) return x end
	local function prop_pstn_r(x)
		return x * 10 + Util.CELSIUS_BASE
	end
	local function prop_elem(x)
		if type(x) == 'string' then return decode_elem(x) end
		return x
	end
	local function prop_cray_start(s)
		if opts.from == nil then opts.from = opts.p end
		local j = self:get_orth_dist(opts.from, s) - 1
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dray_start(s)
		if opts.from == nil then opts.from = opts.p end
		local j = self:get_orth_dist(opts.from, s) - opts.tmp - 1
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_cray_end(e)
		if opts.from == nil then opts.from = opts.p end
		local j = self:get_orth_dist(opts.from, e) - opts.tmp
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dray_end(e)
		if opts.from == nil then opts.from = opts.p end
		local j = self:get_orth_dist(opts.from, e) - opts.tmp - opts.tmp
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dtec_to(to)
		if opts.from == nil then opts.from = opts.p end
		local r = self:get_dtec_dist(opts.from, to)
		return r
	end
	local function prop_filt_mode(s)
		local filt_mode_names = {
			'set', 'and', 'or', 'sub',
			'<<', '>>', 'noeff', 'xor',
			'not', 'scat', '<<<', '>>>',
		}
		for i, v in ipairs(filt_mode_names) do
			if s == v then
				return i - 1
			end
		end
		self:soft_assert(false, 'filt mode "' .. s .. '" not recognized')
		print('available filt modes:')
		self:dump_var(filt_mode_names)
		return 0
	end
	local function prop_frme_sticky(x)
		if type(x) == 'number' then
			if x == 0 then x = false else x = true end
		end
		-- tmp = 0 makes FRME sticky, so invert
		if x then return 0 else return 1 end
	end
	parse_custom('r', 'pstn', 'temp', prop_pstn_r)
	parse_custom('r', 'cray', 'tmp', prop_id)
	parse_custom('r', 'dray', 'tmp', prop_id)
	parse_custom('r', 'ldtc', 'tmp', prop_id)
	parse_custom('r', 'dtec', 'tmp2', prop_id)
	parse_custom('j', 'cray', 'tmp2', prop_id)
	parse_custom('j', 'dray', 'tmp2', prop_id)
	parse_custom('j', 'ldtc', 'life', prop_id)
	parse_custom('ct', 'any', 'ctype', prop_id)
	parse_custom('ctype', 'any', 'ctype', prop_elem)
	parse_custom('from', 'conv', 'tmp', prop_elem)
	parse_custom('to', 'conv', 'ctype', prop_elem)
	parse_custom('to', 'cray', 'tmp2', prop_cray_start)
	parse_custom('s', 'cray', 'tmp2', prop_cray_start)
	parse_custom('e', 'cray', 'tmp2', prop_cray_end)
	parse_custom('to', 'dray', 'tmp2', prop_dray_start)
	parse_custom('tos', 'dray', 'tmp2', prop_dray_start)
	parse_custom('toe', 'dray', 'tmp2', prop_dray_end)
	parse_custom('to', 'ldtc', 'life', prop_cray_start)
	parse_custom('s', 'ldtc', 'life', prop_cray_start)
	parse_custom('e', 'ldtc', 'life', prop_cray_end)
	parse_custom('to', 'dtec', 'tmp2', prop_dtec_to)
	parse_custom('mode', 'filt', 'tmp', prop_filt_mode)
	parse_custom('sticky', 'frme', 'tmp', prop_frme_sticky)

	-- custom default values
	local function default_prop(target_type, prop, val)
		if custom_elem_match(target_type) and opts[prop] == nil then
			opts[prop] = val
		end
	end
	default_prop('filt', 'tmp', Util.FILT_MODES.NOP)
	default_prop('aray', 'life', 1)
	default_prop('cray', 'ctype', elem.DEFAULT_PT_SPRK)

	if opts.sprk then
		-- pre-spark
		assert(Util.arr_contains(conductors, t))
		opts.ctype = t
		opts['type'] = elem.DEFAULT_PT_SPRK
		if opts.life == nil then opts.life = 4 end
	end

	if opts.temp ~= nil then
		assert(opts.temp >= 0, 'temp must be at least 0K')
	end

	lazy_init_part_fields()
	local part = {}
	for field_name, _ in pairs(PART_FIELDS) do
		local val = opts[field_name]
		if val ~= nil and field_name ~= 'x' and field_name ~= 'y' then
			part[field_name] = val
		end
	end

	if opts.v ~= nil then self:set_var(opts.v, part) end

	local schem = self:top()
	schem:place_parts(opts.p, {part}, opts.under)

	if opts.done then
		self:advance_curs()
	end

	return part
end

function Designer:place_schem(child_schem, opts)
	opts = self:opts_pos(opts)
	opts = self:opts_bool(opts, 'done', true)
	-- "under=1" places particles at the bottom of stacks
	opts = self:opts_bool(opts, 'under', false)
	local schem = self:top()
	self:push_curs(Point:new(0, 0))

	if opts.ref ~= nil then
		opts.p = opts.p:sub(child_schem.vars[opts.ref].p)
	end

	child_schem:for_each_stack(function(p, stack)
		-- Do not clone particles so that var references are
		-- maintained when a schematic is placed.
		-- Note that this makes schematics single-use only.
		schem:place_parts(p:add(opts.p), stack, opts.under)
	end)

	self:pop_curs()
	if opts.v ~= nil then
		self:run_with_ctx(opts.v, function()
			for name, val in pairs(child_schem.vars) do
				if getmetatable(val) == Port then
					val.p = opts.p:add(val.p)
				end
				name = self:expand_var_name(name)
				schem.vars[name] = val
			end
		end)
	end

	if opts.done then
		self:advance_curs()
	end
end

function Designer:instantiate_schem(func, opts)
	local function call_func_with_args()
		if opts.args == nil then
			func(opts)
		else
			func(table.unpack(opts.args))
		end
	end
	local schem = self:make_schem(call_func_with_args)
	self:place_schem(schem, opts)
end

function Designer:solve_constraints(opts)
	local ray_dirs = {
		['n'] = Point:new(0, -1),
		['e'] = Point:new(1, 0),
		['s'] = Point:new(0, 1),
		['w'] = Point:new(-1, 0),
		['ne'] = Point:new(1, 1),
		['se'] = Point:new(-1, 1),
		['sw'] = Point:new(-1, -1),
		['nw'] = Point:new(1, -1),
		['ns'] = Point:new(0, 1),
		['ew'] = Point:new(1, 0),
	}
	local two_sided_dirs = {
		'ns', 'ew',
	}
	constraints = {}
	for k, v in pairs(opts) do
		local inclusive_suffix = 'i'
		local is_inclusive = k:sub(-#inclusive_suffix) == inclusive_suffix
		if is_inclusive then k = k:sub(1, -#inclusive_suffix - 1) end
		local dir = ray_dirs[k]
		if dir ~= nil then
			if is_inclusive then v = v:sub(dir) end
			local is_one_sided = not Util.arr_contains(two_sided_dirs, k)
			table.insert(constraints, Constraints.Ray.new(v, dir, is_one_sided))
		end
	end
	assert(
		#constraints == 2,
		'constraint satisfaction only supported for exactly two rays, ' ..
		'but ' .. #constraints .. ' ray(s) provided'
	)
	return Constraints.solve_2ray(constraints[1], constraints[2])
end

function Designer:dump_var(x)
	return Util.dump_var(x, function(x)
		if getmetatable(x) == Geom.Point then
			return '(' .. x.x .. ', ' .. x.y .. ')'
		end
		return nil
	end)
end

function Designer:test_setup(opts)
	if opts.inputs == nil then opts.inputs = {} end
	if opts.outputs == nil then opts.outputs = {} end
	if opts.tcs == nil then opts.tcs = {} end

	local function opts_io(opts)
		if opts.name == nil then
			assert(opts.v ~= nil)
			_, opts.name = self:parse_full_var_name(opts.v)
		end
		if opts.p == nil then
			assert(opts.v ~= nil)
			opts.p = self:get_var(opts.v)
		end
		return opts
	end

	for _, spec in pairs(opts.inputs) do
		self.tester:add_input(opts_io(spec))
	end
	for _, spec in pairs(opts.outputs) do
		self.tester:add_output(opts_io(spec))
	end
	for _, tc in pairs(opts.tcs) do
		self.tester:test_case(tc)
	end
end

-- Only the methods below interact with the actual simulation.

local function reload_particle_order()
	if sim.reloadParticleOrder ~= nil then
		sim.reloadParticleOrder()
	else
		assert(false, 'no way to reload particle order; use subframe mod or ask LBPHacker for a script')
	end
end

function Designer:plot_schem(opts)
	opts = self:opts_pos(opts)
	reload_particle_order()
	local schem = self:top()
	schem:for_each_part(function(p, part)
		p = p:add(opts.p)
		if p.x < 0 or p.y < 0 then
			return
		end
		local t, x, y = part['type'], p.x, p.y
		if t == elem.DEFAULT_PT_SPRK then
			sim.partCreate(-3, x, y, part.ctype)
		end
		local id = sim.partCreate(-3, x, y, t)
		for field_name, _ in pairs(PART_FIELDS) do
			local val = part[field_name]
			if val ~= nil then
				local field_id = sim[Util.FIELD_PREFIX .. field_name:upper()]
				sim.partProperty(id, field_id, val)
			end
		end
	end)
	reload_particle_order()
end

function Designer:clear(opts)
	opts = self:opts_pt_short(opts)
	if opts.w == nil then opts.w = sim.XRES end
	if opts.h == nil then opts.h = sim.YRES end
	-- crop to screen
	if opts.x < 0 then
		opts.w = opts.w + opts.x
		opts.x = 0
	end
	if opts.y < 0 then
		opts.h = opts.h + opts.y
		opts.y = 0
	end
	if opts.x + opts.w > sim.XRES then opts.w = sim.XRES - opts.x end
	if opts.y + opts.h > sim.YRES then opts.h = sim.YRES - opts.y end
	for i in sim.parts() do
		local x, y = sim.partPosition(i)
		x, y = math.floor(x), math.floor(y)
		if
			x >= opts.x and x < opts.x + opts.w and
			y >= opts.y and y < opts.y + opts.h
		then
			sim.partKill(i)
		end
	end
end

function Designer:plot(opts)
	opts = self:opts_bool(opts, 'run_test', false)
	if opts.clear ~= nil then
		self:clear(opts.clear)
	end
	self:plot_schem(opts)
	if opts.run_test then
		self.tester:start()
	end
end

return Designer
