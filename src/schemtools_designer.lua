local Geom = require('schemtools_geom')
local Util = require('schemtools_util')
local Point = Geom.Point

local Cursor = {}
function Cursor.new()
	return {
		pos = Point:new(0, 0),
		adv = Point:new(0, 0),
	}
end

local Port = {}
function Port:new(p, is_local)
	local o = {
		p = p,
		is_local = is_local,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local Schematic = {}
function Schematic:new()
	local o = {
		curs_stack = { Cursor.new() },
		-- parts[y][x] is a list of particles at (x, y) in stack order
		-- in schematics, particles can take negative coordinates
		parts = {},
		vars = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Schematic:place_part(p, part, under)
	if self.parts[p.y] == nil then
		self.parts[p.y] = {}
	end
	if self.parts[p.y][p.x] == nil then
		self.parts[p.y][p.x] = {}
	end
	if under then
		table.insert(self.parts[p.y][p.x], 1, part)
	else
		table.insert(self.parts[p.y][p.x], part)
	end
end

function Schematic:for_each_part(func)
	for y, row in pairs(self.parts) do
		for x, stack in pairs(row) do
			for _, part in ipairs(stack) do
				func(Point:new(x, y), part)
			end
		end
	end
end

local Designer = {}
function Designer:new()
	local o = {
		stack = {},
	}
	setmetatable(o, self)
	self.__index = self
	o:begin_scope()
	return o
end

function Designer:top()
	return self.stack[#self.stack]
end

function Designer:set_var(name, val)
	local schem = self:top()
	if schem[name] ~= nil then
		schem[name] = val
		return
	end
	if
		getmetatable(schem.vars[name]) == Port and
		getmetatable(val) == Geom.Point
	then
		schem.vars[name].p = val
		return
	end
	schem.vars[name] = val
end

function Designer:get_var(name)
	local schem = self:top()
	if schem[name] ~= nil then
		return schem[name]
	end
	assert(
		schem.vars[name] ~= nil,
		'variable "' .. name .. '" does not exist'
	)
	if getmetatable(schem.vars[name]) == Port then
		return schem.vars[name].p
	end
	return schem.vars[name]
end

function Designer:port(name, opts)
	opts = self:opts_pos(opts)
	opts = self:opts_bool(opts, 'is_local', false)
	local schem = self:top()
	if schem.vars[name] ~= nil then
		assert(
			getmetatable(schem.vars[name]) == Port,
			'variable "' .. name .. '" already used for non-port'
		)
	end
	schem.vars[name] = Port:new(opts.p, opts.is_local)
end

function Designer:begin_scope()
	table.insert(self.stack, Schematic:new())
end

function Designer:end_scope()
	assert(#self.stack > 1, 'cannot end root scope')
	return table.remove(self.stack)
end

function Designer:run_in_scope(func)
	self:begin_scope()
	func()
	return self:end_scope()
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

function Designer:run_with_curs(opts, func)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_pos(opts, curs, false)
	opts = self:opts_pt(opts, 'dp', 'dx', 'dy')
	self:push_curs({ p = opts.dp })
	if opts.p ~= nil then self:set_curs(opts.p) end
	func()
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
	self:opts_pt(opts, 'p', 'x', 'y', ref, force)
	return opts
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

function Designer:part(opts)
	opts = self:opts_pos(opts)
	opts = self:opts_bool(opts, 'done', true)
	opts = self:opts_bool(opts, 'ss', false)

	if opts.name ~= nil then
		opts['type'] = decode_elem(opts.name)
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
	local function get_orth_dist(from, to)
		local dp = to:sub(from)
		assert(not dp:eq(Point:new(0, 0)), 'cannot target self')
		assert(
			dp.x == 0 or dp.y == 0 or math.abs(dp.x) == math.abs(dp.y),
			'target not in one of the ordinal directions'
		)
		return math.max(math.abs(dp.x), math.abs(dp.y))
	end
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
	local function prop_cray_to(to)
		if opts.from == nil then opts.from = opts.p end
		local j = get_orth_dist(opts.from, to) - 1
		assert(j >= 0)
		return j
	end
	local function prop_dray_to(to)
		if opts.from == nil then opts.from = opts.p end
		local j = get_orth_dist(opts.from, to) - opts.tmp - 1
		assert(j >= 0)
		return j
	end
	parse_custom('r', 'pstn', 'temp', prop_pstn_r)
	parse_custom('r', 'cray', 'tmp', prop_id)
	parse_custom('r', 'dray', 'tmp', prop_id)
	parse_custom('j', 'cray', 'tmp2', prop_id)
	parse_custom('j', 'dray', 'tmp2', prop_id)
	parse_custom('ct', 'any', 'ctype', prop_id)
	parse_custom('ctype', 'any', 'ctype', prop_elem)
	parse_custom('from', 'conv', 'tmp', prop_elem)
	parse_custom('to', 'conv', 'ctype', prop_elem)
	parse_custom('to', 'cray', 'tmp2', prop_cray_to)
	parse_custom('to', 'dray', 'tmp2', prop_dray_to)

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

	lazy_init_part_fields()
	local part = {}
	for field_name, _ in pairs(PART_FIELDS) do
		local val = opts[field_name]
		if val ~= nil and field_name ~= 'x' and field_name ~= 'y' then
			part[field_name] = val
		end
	end

	local schem = self:top()
	schem:place_part(opts.p, part)

	if opts.done then
		self:advance_curs()
	end
end

function Designer:place(child_schem, opts)
	opts = self:opts_pos(opts)
	-- "under=1" places particles at the bottom of stacks
	opts = self:opts_bool(opts, 'under', false)
	local schem = self:top()
	self:push_curs(Point:new(0, 0))

	child_schem:for_each_part(function(p, part)
		p = p:add(opts.p)

		-- clone part to allow schematic to be reused
		local new_part = {}
		for k, v in pairs(part) do
			new_part[k] = v
		end

		schem:place_part(p, new_part, opts.under)
	end)

	self:pop_curs()
	if opts.name ~= nil then
		for name, val in pairs(child_schem.vars) do
			local translated_val = val
			if getmetatable(val) == Port and not val.is_local then
				translated_val = Port:new(opts.p:add(val.p))
			end
			schem.vars[opts.name .. '.' .. name] = translated_val
		end
	end
end

-- Only the methods below interact with the actual simulation.

local function reload_particle_order()
	if sim.reloadParticleOrder ~= nil then
		sim.reloadParticleOrder()
	else
		assert(false, 'error: no way to reload particle order; use subframe mod or ask LBPHacker for a script')
	end
end

function Designer:plot(opts)
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

function Designer:dump_var(x)
	return Util.dump_var(x, function(x)
		if getmetatable(x) == Geom.Point then
			return '(' .. x.x .. ', ' .. x.y .. ')'
		end
		return nil
	end)
end

return Designer
