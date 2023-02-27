local Geom = require('schemtools/geom')
local ArrayPort = require('schemtools/arrayport')
local Util = require('schemtools/util')
local Tester = require('schemtools/tester')
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
function Port:new(p, connect_func, cmt)
	local o = {
		p = p,
		connect_func = connect_func,
		cmt = cmt,
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
	for _, part in ipairs(parts) do
		part.x = p.x
		part.y = p.y
	end
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

-- translation functions when placing an offsetted schematic
local DEFAULT_PORT_TRANSLATORS = {
	[Port] = function(p, shift_p)
		p.p = p.p:add(shift_p)
	end,
	[ArrayPort] = function(ap, shift_p)
		ap:add_in_place(shift_p)
	end,
}

local function clone_default_port_translators()
	local translators = {}
	for typ, translator in pairs(DEFAULT_PORT_TRANSLATORS) do
		translators[typ] = translator
	end
	return translators
end

local Designer = {}
function Designer:new()
	local o = {
		stack = {},
		autogen_name_cnt = 0,
		port_translators = clone_default_port_translators(),
		tester = Tester:new(),
		comments = {},
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

function Designer:autogen_name(tag)
	local name = '__autogen_' .. tag .. '_' .. self.autogen_name_cnt
	self.autogen_name_cnt = self.autogen_name_cnt + 1
	return name
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

function Designer:get_stack_at(p)
	local schem = self:top()
	if schem.parts[p.y] == nil then return nil end
	return schem.parts[p.y][p.x]
end

function Designer:get_top_part_at(p)
	local stack = self:get_stack_at(p)
	if stack == nil then return nil end
	return stack[#stack]
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
	if opts.v == nil and opts.cmt ~= nil then opts.v = self:autogen_name('cmt') end

	local schem = self:top()
	local existing_val = self:get_var_raw(opts.v)
	if existing_val ~= nil then
		assert(
			getmetatable(existing_val) == Port,
			'variable "' .. opts.v .. '" already used for non-port'
		)
	end
	self:set_var(opts.v, Port:new(opts.p, opts.f, opts.cmt))
end

-- Create a port with the same value of an existing port.
-- Args:
-- - from: The old port's name.
-- - to: The new port's name. (default: the last component of `from`)
function Designer:port_alias(opts)
	local schem = self:top()
	local ctx, name = self:parse_full_var_name(opts.from)
	local orig = self:get_var_raw(opts.from)
	if opts.to == nil then opts.to = name end
	if getmetatable(orig) == ArrayPort then
		self:set_var(opts.to, ArrayPort:clone(orig))
		return
	end
	self:port{v=opts.to, p=orig.p, f=function(args)
		self:run_with_ctx(ctx, function()
			orig.connect_func(args)
		end)
	end}
end

function Designer:array_port(opts)
	opts = self:opts_pos(opts)
	local schem = self:top()
	local existing_val = self:get_var_raw(opts.v)
	if existing_val ~= nil then
		existing_val:expand(opts.p)
		return
	end
	self:set_var(opts.v, ArrayPort:new(opts.p))
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

function Designer:opts_alias_dp_p(opts)
	opts = self:opts_pt(opts, 'dp', 'dx', 'dy', nil, false)
	if opts ~= nil and opts.dp ~= nil then
		opts.p = opts.dp
	end
	return opts
end

function Designer:advance_curs(opts)
	local schem = self:top()
	opts = self:opts_alias_dp_p(opts)
	opts = self:opts_pt_short(opts, self:get_curs_info().adv)
	if opts.n ~= nil then
		opts.p.x = opts.p.x * opts.n
		opts.p.y = opts.p.y * opts.n
	end
	self:set_curs({ p = self:get_curs():add(opts.p) })
end

function Designer:set_curs_adv(opts)
	opts = self:opts_alias_dp_p(opts)
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

local function check_orth(from, to)
	local dp = to:sub(from)
	assert(
		dp.x == 0 or dp.y == 0 or math.abs(dp.x) == math.abs(dp.y),
		'target not in one of the ordinal directions'
	)
end

function Designer:get_orth_dist(from, to)
	check_orth(from, to)
	local dp = to:sub(from)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

function Designer:get_orth_dir(from, to)
	check_orth(from, to)
	local dp = to:sub(from)
	if dp.x > 0 then dp.x = 1 end
	if dp.x < 0 then dp.x = -1 end
	if dp.y > 0 then dp.y = 1 end
	if dp.y < 0 then dp.y = -1 end
	return dp
end

function Designer:get_dtec_dist(from, to)
	local dp = to:sub(from)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

-- custom prop names
local function custom_elem_match(t, target_type)
	if target_type == 'any' then return true end
	if target_type == 'conduct' then
		return Util.arr_contains(Util.CONDUCTORS, t)
	end
	return t == elem[Util.ELEM_PREFIX .. target_type:upper()]
end

function Designer:opts_aport(opts, aport_name, s_name, e_name, ref)
	if ref == nil then ref = self:get_curs() end
	if opts[aport_name] == nil then return opts end
	local aport = opts[aport_name]
	if getmetatable(aport) ~= ArrayPort then return opts end
	local is_horz = aport:is_horz()
	local is_vert = aport:is_vert()
	assert(
		(is_horz and not is_vert) or (is_vert and not is_horz),
		'array port not linear'
	)
	local pt1, pt2 = nil, nil
	if is_horz then pt1, pt2 = aport:w(0), aport:e(0) end
	if is_vert then pt1, pt2 = aport:n(0), aport:s(0) end
	local dist1 = self:get_orth_dist(ref, pt1)
	local dist2 = self:get_orth_dist(ref, pt2)
	if dist1 < dist2 then
		opts[s_name], opts[e_name] = pt1, pt2
	else
		opts[s_name], opts[e_name] = pt2, pt1
	end
	opts[aport_name] = nil
	return opts
end

function Designer:opts_part(opts)
	opts = self:opts_pos(opts)

	if opts.elem_name ~= nil then
		opts['type'] = decode_elem(opts.elem_name)
	end
	local t = opts['type']

	local from_to_pos_enabled = {
		elem.DEFAULT_PT_CRAY,
		elem.DEFAULT_PT_DRAY,
		elem.DEFAULT_PT_LDTC,
		elem.DEFAULT_PT_DTEC,
	}

	local function expand_aport(target_type, aport_name, s_name, e_name)
		if not custom_elem_match(t, target_type) then return end
		opts = self:opts_aport(opts, aport_name, s_name, e_name, opts.from)
	end
	expand_aport('cray', 'to', 's', 'e')
	expand_aport('dray', 'to', 'tos', 'toe')
	expand_aport('ldtc', 'to', 's', 'e')

	local do_from_to_pos = Util.arr_contains(from_to_pos_enabled, t)
	if do_from_to_pos then
		opts = self:opts_pt(opts, 'from', 'fromx', 'fromy', opts.p)
		opts = self:opts_pt(opts, 'to', 'tox', 'toy', opts.from, false)
	end

	local function calc_r(target_type, s_name, e_name)
		if opts[s_name] == nil or opts[e_name] == nil then return end
		if not custom_elem_match(t, target_type) then return end
		opts.r = self:get_orth_dist(opts[s_name], opts[e_name]) + 1
	end
	calc_r('cray', 's', 'e')
	calc_r('dray', 'tos', 'toe')
	calc_r('ldtc', 's', 'e')

	local function parse_custom(custom_prop, target_type, prop, func)
		if opts[custom_prop] == nil then return end
		if not custom_elem_match(t, target_type) then return end
		opts[prop] = func(opts[custom_prop])
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
		local j = self:get_orth_dist(opts.from, s) - 1
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dray_start(s)
		if opts.tmp == nil then opts.tmp = 1 end
		local j = self:get_orth_dist(opts.from, s) - opts.tmp - 1
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_cray_end(e)
		if opts.tmp == nil then opts.tmp = 1 end
		local j = self:get_orth_dist(opts.from, e) - opts.tmp
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dray_end(e)
		if opts.tmp == nil then opts.tmp = 1 end
		local j = self:get_orth_dist(opts.from, e) - opts.tmp - opts.tmp
		self:soft_assert(j >= 0, 'negative jump requested')
		return j
	end
	local function prop_dtec_to(to)
		return self:get_dtec_dist(opts.from, to)
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
		Util.dump_var(filt_mode_names)
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
	parse_custom('cap', 'pstn', 'tmp', prop_id)

	local function check_geq(target_type, prop_name, bound)
		if bound == nil then bound = 0 end
		if not custom_elem_match(t, target_type) then return end
		if opts[prop_name] == nil then return end
		self:soft_assert(
			opts[prop_name] >= bound,
			prop_name .. ' must be at least ' .. bound ..
			' but ' .. opts[prop_name] .. ' requested'
		)
	end
	local function check_leq(target_type, prop_name, bound)
		if bound == nil then bound = 0 end
		if not custom_elem_match(t, target_type) then return end
		if opts[prop_name] == nil then return end
		self:soft_assert(
			opts[prop_name] <= bound,
			prop_name .. ' must be at most ' .. bound ..
			' but ' .. opts[prop_name] .. ' requested'
		)
	end
	check_geq('any', 'temp', 0)
	check_leq('dtec', 'tmp2', 25)
	check_geq('cray', 'tmp', 0)
	check_geq('dray', 'tmp', 0)
	check_geq('ldtc', 'tmp', 0)
	check_geq('cray', 'tmp2', 0)
	check_geq('dray', 'tmp2', 0)
	check_geq('ldtc', 'life', 0)

	return opts
end

local function config_part(part, opts)
	for field_name, _ in pairs(PART_FIELDS) do
		local val = opts[field_name]
		if val ~= nil then
			part[field_name] = val
		end
	end
end

function Designer:pconfig(opts)
	for k, v in pairs(opts.part) do
		opts[k] = v
	end
	opts.from = Point:new(opts.part.x, opts.part.y)
	opts = self:opts_part(opts)
	config_part(opts.part, opts)
end

function Designer:part(opts)
	opts = self:opts_part(opts)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_bool(opts, 'under', false)

	local t = opts['type']

	-- custom default values
	local function default_prop(target_type, prop, val)
		if custom_elem_match(t, target_type) and opts[prop] == nil then
			opts[prop] = val
		end
	end
	default_prop('filt', 'tmp', Util.FILT_MODES.NOP)
	default_prop('aray', 'life', 1)
	default_prop('cray', 'ctype', elem.DEFAULT_PT_SPRK)
	default_prop('cray', 'tmp', 1)
	default_prop('dray', 'tmp', 1)
	default_prop('ldtc', 'tmp', 1)

	if opts.sprk then
		-- pre-spark
		assert(Util.arr_contains(Util.CONDUCTORS, t))
		opts.ctype = t
		opts['type'] = elem.DEFAULT_PT_SPRK
		if opts.life == nil then opts.life = 4 end
	end

	lazy_init_part_fields()
	local part = {}
	config_part(part, opts)

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
	opts = self:opts_bool(opts, 'keep_vars', opts.v ~= nil)
	if opts.v == nil then opts.v = self:autogen_name('schem') end
	local schem = self:top()
	self:push_curs(Point:new(0, 0))

	-- Amount to shift schematic by, if necessary.
	local shift_p = Point:new(0, 0)
	if opts.ref ~= nil then
		shift_p = opts.p:sub(child_schem.vars[opts.ref].p)
	end

	child_schem:for_each_stack(function(p, stack)
		-- Do not clone particles so that var references are
		-- maintained when a schematic is placed.
		-- Note that this makes schematics single-use only.
		schem:place_parts(p:add(shift_p), stack, opts.under)
	end)

	self:pop_curs()
	self:run_with_ctx(opts.v, function()
		for name, val in pairs(child_schem.vars) do
			local keep_var = opts.keep_vars
			if getmetatable(val) == Port and val.cmt ~= nil then
				keep_var = true
			end
			if keep_var then
				local translation_func = self.port_translators[getmetatable(val)]
				if translation_func ~= nil then
					translation_func(val, shift_p)
				end
				name = self:expand_var_name(name)
				schem.vars[name] = val
			end
		end
	end)

	if opts.done then
		self:advance_curs()
	end
end

function Designer:instantiate_schem(func, opts)
	opts = self:opts_pos(opts)
	local function call_func_with_args()
		self:set_curs({p = opts.p})
		if opts.args == nil then
			func(opts)
		else
			func(unpack(opts.args))
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
		['ne'] = Point:new(1, -1),
		['se'] = Point:new(1, 1),
		['sw'] = Point:new(-1, 1),
		['nw'] = Point:new(-1, -1),
		['ns'] = Point:new(0, 1),
		['ew'] = Point:new(1, 0),
	}
	local two_sided_dirs = {
		'ns', 'ew',
	}
	constraints = {}
	for k, v in pairs(opts) do
		if k == 'x' then
			k = 'ns'
			v = Point:new(v, 0)
		end
		if k == 'y' then
			k = 'ew'
			v = Point:new(0, v)
		end

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

function Designer:add_comment(opts)
	opts = self:opts_pos(opts)
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

	local schem = self:top()

	reload_particle_order()
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
			if field_name ~= 'x' and field_name ~= 'y' and val ~= nil then
				local field_id = sim[Util.FIELD_PREFIX .. field_name:upper()]
				sim.partProperty(id, field_id, val)
			end
		end
	end)
	reload_particle_order()

	for _, var in pairs(schem.vars) do
		if getmetatable(var) == Port and var.cmt ~= nil then
			if self.comments[var.p.y] == nil then
				self.comments[var.p.y] = {}
			end
			if self.comments[var.p.y][var.p.x] == nil then
				self.comments[var.p.y][var.p.x] = var.cmt
			else
				self.comments[var.p.y][var.p.x] = self.comments[var.p.y][var.p.x] .. '\n\n' .. var.cmt
			end
		end
	end
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
