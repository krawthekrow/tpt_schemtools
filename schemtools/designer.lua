local Util = require('schemtools/util')
local Options = require('schemtools/options')
local Geom = require('schemtools/geom')
local Port = require('schemtools/port')
local Particle = require('schemtools/particle')
local VariableStore = require('schemtools/varstore')
local Tester = require('schemtools/tester')
local Point = Geom.Point
local Rect = Geom.Rect
local Constraints = Geom.Constraints

local Cursor = {}
function Cursor.new()
	return {
		pos = Point:new(0, 0),
		adv = Point:new(0, 0),
	}
end

local Schematic = {}
function Schematic:new()
	local o = {
		curs_stack = { Cursor.new() },
		-- parts[y][x] is a list of particles at (x, y) in stack order
		-- in schematics, particles can take negative coordinates
		parts = {},
		-- For performance, track particles that need to be resolved
		-- and only resolve those when placing schematics. Note that
		-- resolving a particle should still be idempotent.
		unresolved_parts = {},
		varstore = VariableStore:new(),
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
		p.val = p.val:add(shift_p)
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

function Designer:autogen_name(tag)
	local name = '__autogen_' .. tag .. '_' .. self.autogen_name_cnt
	self.autogen_name_cnt = self.autogen_name_cnt + 1
	return name
end

function Designer:is_var_name_valid(name)
	return name:match('^[%a_][%w_]*$') ~= nil
end

function Designer:set_var(name, val)
	local schem = self:top()
	if schem[name] ~= nil then
		schem[name] = val
		return
	end

	local is_valid_new_name = self:is_var_name_valid(name)
	assert(is_valid_new_name, 'invalid new var name "' ..  name .. '"')

	schem.varstore:set_var(name, val)
end

function Designer:get_var_raw(name)
	local schem = self:top()
	return schem.varstore:get_var_raw(name)
end

function Designer:get_var(name)
	local schem = self:top()
	if schem[name] ~= nil then
		return schem[name]
	end

	return schem.varstore:get_var(name)
end

function Designer:get_indexed_var(name)
	return self:top().varstore:get_indexed_var(name)
end

function Designer:apply_index(name)
	return self:top().varstore:apply_index(name)
end

function Designer:push_index(index)
	self:top().varstore:push_index(index)
end

function Designer:pop_index()
	self:top().varstore:pop_index()
end

function Designer:run_with_ctx(ctx, func)
	if ctx == '' then
		func()
		return
	end

	local schem = self:top()
	schem.varstore:begin_ctx(ctx)
	func()
	schem.varstore:end_ctx()
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
	if opts.v == nil and opts.cmt ~= nil then
		opts.v = self:autogen_name('cmt')
	end
	if opts.iv ~= nil then
		opts.v = self:apply_index(opts.iv)
	end
	if opts.val == nil then
		opts.val = opts.p
	end

	local schem = self:top()
	local existing_val = self:get_var_raw(opts.v)
	-- ports should only be defined once
	assert(
		existing_val == nil,
		'variable "' .. opts.v .. '" already in use'
	)
	self:set_var(opts.v, Port:new(opts.val, opts.f, opts.cmt))
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
	local connect_func = nil
	if orig.connect_func ~= nil then
		connect_func = function(args)
			self:run_with_ctx(ctx, function()
				orig.connect_func(args)
			end)
		end
	end
	self:port{v=opts.to, val=orig.val, f=connect_func}
end

function Designer:array_port(opts)
	opts = self:opts_pos(opts)
	local schem = self:top()
	local existing_val = self:get_var_raw(opts.v)
	if existing_val ~= nil then
		existing_val:expand(opts.p)
		return
	end
	assert(
		opts.f == nil and opts.cmt == nil,
		'f/cmt not supported on array ports yet'
	)
	local port = Port:new(Rect:new(opts.p, opts.p), opts.f, opts.cmt)
	self:set_var(opts.v, port)
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
	return Options.opts_alias_dp_p(opts)
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

function Designer:opts_pt(opts, pname, xname, yname, ref, force)
	return Options.opts_pt(opts, pname, xname, yname, ref, force)
end

function Designer:opts_pt_short(opts, ref, force)
	return Options.opts_pt_short(opts, ref, force)
end

function Designer:opts_pos(opts, force)
	local curs = self:get_curs()
	return self:opts_pt_short(opts, curs, force)
end

function Designer:opts_bool(opts, name, dflt)
	return Options.opts_bool(opts, name, dflt)
end

function Designer:opts_rect_line(opts, rect_name, s_name, e_name, ref)
	if ref == nil then ref = self:get_curs() end
	return Options.opts_rect_line(opts, rect_name, s_name, e_name, ref)
end

function Designer:get_orth_dist(from, to)
	return Geom.get_orth_dist(from, to)
end

function Designer:get_orth_dir(from, to)
	Geom.assert_orth(from, to)
	local dp = to:sub(from)
	if dp.x > 0 then dp.x = 1 end
	if dp.x < 0 then dp.x = -1 end
	if dp.y > 0 then dp.y = 1 end
	if dp.y < 0 then dp.y = -1 end
	return dp
end

function Designer:resolve_parts(schem)
	for _, part in ipairs(schem.unresolved_parts) do
		part:resolve()
	end
	schem.unresolved_parts = {}
end

function Designer:pconfig(opts)
	for k, v in pairs(opts.part) do
		opts[k] = v
	end
	opts.from = Point:new(opts.part.x, opts.part.y)
	opts.part:config(opts)
	table.insert(self:top().unresolved_parts, opts.part)
end

function Designer:part(opts)
	opts = self:opts_pos(opts)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_bool(opts, 'under', false)
	if opts.iv ~= nil then
		opts.v = self:apply_index(opts.iv)
	end

	local part = Particle:from_opts(opts)
	table.insert(self:top().unresolved_parts, part)

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

	self:resolve_parts(child_schem)

	-- Amount to shift schematic by, if necessary.
	local shift_p = Point:new(0, 0)
	if opts.ref ~= nil then
		shift_p = opts.p:sub(child_schem.varstore:get_var(opts.ref))
	end

	child_schem:for_each_stack(function(p, stack)
		-- Do not clone particles so that var references are
		-- maintained when a schematic is placed.
		-- Note that this makes schematics single-use only.
		schem:place_parts(p:add(shift_p), stack, opts.under)
	end)

	self:pop_curs()
	self:run_with_ctx(opts.v, function()
		child_schem.varstore:filter(function(name, val)
			if opts.keep_vars then
				return true
			end
			if getmetatable(val) == Port and val.cmt ~= nil then
				return true
			end
			return false
		end)
		child_schem.varstore:translate(shift_p, self.port_translators)
		schem.varstore:merge(child_schem.varstore)
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
	self:resolve_parts(schem)
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
		for field_name, _ in pairs(Util.PART_FIELDS) do
			local val = part[field_name]
			if field_name ~= 'x' and field_name ~= 'y' and val ~= nil then
				local field_id = sim[Util.FIELD_PREFIX .. field_name:upper()]
				sim.partProperty(id, field_id, val)
			end
		end
	end)
	reload_particle_order()

	for _, var in pairs(schem.varstore.vars) do
		if getmetatable(var) == Port and var.cmt ~= nil then
			local p = var.val
			if self.comments[p.y] == nil then
				self.comments[p.y] = {}
			end
			if self.comments[p.y][p.x] == nil then
				self.comments[p.y][p.x] = var.cmt
			else
				self.comments[p.y][p.x] = self.comments[p.y][p.x] .. '\n\n' .. var.cmt
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
