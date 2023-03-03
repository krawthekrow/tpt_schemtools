local Util = require('schemtools/util')
local Options = require('schemtools/options')
local Geom = require('schemtools/geom')
local VirtualExpression = require('schemtools/vexpr')
local Point = Geom.Point
local Rect = Geom.Rect

local Particle = {}
function Particle:new()
	local o = {
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local function decode_elem(name)
	return elem[Util.ELEM_PREFIX .. name:upper()]
end

local ELEM_GROUP_ANY = -1

local function elem_multidict_new()
	local d = {}
	d[ELEM_GROUP_ANY] = {}
	return d
end

local function elem_multidict_add(d, elem_name, val)
	local function append_to_key(t)
		if d[t] == nil then
			d[t] = {}
			for _, oval in ipairs(d[ELEM_GROUP_ANY]) do
				table.insert(d[t], oval)
			end
		end
		table.insert(d[t], val)
	end

	if elem_name == 'any' then
		for t, _ in pairs(d) do
			append_to_key(t)
		end
	elseif elem_name == 'conduct' then
		for _, t in ipairs(Util.CONDUCTORS) do
			append_to_key(t)
		end
	else
		append_to_key(decode_elem(elem_name))
	end
end

local function elem_multidict_lookup(d, t)
	if d[t] ~= nil then return d[t] end
	return d[ELEM_GROUP_ANY]
end

local function prop_id(x) return x end

local function prop_pstn_r(x)
	return x * 10 + Util.CELSIUS_BASE
end

local function prop_elem(x)
	if type(x) == 'string' then return decode_elem(x) end
	return x
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
	assert(false, 'filt mode "' .. s .. '" not recognized')
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

local PROP_TRANSLATE_RAW = {
	{'r', 'pstn', 'temp', prop_pstn_r},
	{'r', 'cray', 'tmp', prop_id},
	{'r', 'dray', 'tmp', prop_id},
	{'r', 'ldtc', 'tmp', prop_id},
	{'r', 'dtec', 'tmp2', prop_id},
	{'j', 'cray', 'tmp2', prop_id},
	{'j', 'dray', 'tmp2', prop_id},
	{'j', 'ldtc', 'life', prop_id},
	{'ct', 'any', 'ctype', prop_id},
	{'ctype', 'any', 'ctype', prop_elem},
	{'from', 'conv', 'tmp', prop_elem},
	{'to', 'conv', 'ctype', prop_elem},
	{'mode', 'filt', 'tmp', prop_filt_mode},
	{'sticky', 'frme', 'tmp', prop_frme_sticky},
	{'cap', 'pstn', 'tmp', prop_id},
}

local TranslateEntry = {}
function TranslateEntry.new(from, to, func)
	return {
		from = from,
		to = to,
		func = func,
	}
end

local function make_elem_prop_translate()
	local d = elem_multidict_new()
	for _, row in ipairs(PROP_TRANSLATE_RAW) do
		local entry = TranslateEntry.new(row[1], row[3], row[4])
		elem_multidict_add(d, row[2], entry)
	end
	return d
end
local ELEM_PROP_TRANSLATE = make_elem_prop_translate()

local function translate_props(part)
	local t = part['type']
	local translators = elem_multidict_lookup(ELEM_PROP_TRANSLATE, t)
	for _, entry in ipairs(translators) do
		if part[entry.from] ~= nil then
			part[entry.to] = entry.func(part[entry.from])
		end
	end
	return part
end

local function parse_from_to_pos(opts)
	opts = Options.opts_pt(opts, 'from', 'fromx', 'fromy', opts.p)
	opts = Options.opts_pt(opts, 'to', 'tox', 'toy', opts.from, false)
	return opts
end

local function alias_to_s_e(opts)
	opts = Options.opts_alias(opts, 's', 'tos')
	opts = Options.opts_alias(opts, 'e', 'toe')
	return opts
end

local function pre_spark(opts)
	local t = opts['type']
	if opts.sprk then
		opts.ctype = t
		opts['type'] = elem.DEFAULT_PT_SPRK
		if opts.life == nil then opts.life = 4 end
	end
	return opts
end

local function opts_rect_line(opts, rect_name, s_name, e_name, ref)
	if opts[rect_name] == nil then return opts end
	local rect = opts[rect_name]
	if getmetatable(rect) ~= Rect then return opts end
	local is_horz = rect:is_horz()
	local is_vert = rect:is_vert()
	assert(
		(is_horz and not is_vert) or (is_vert and not is_horz),
		'rect not linear'
	)
	local pt1, pt2 = nil, nil
	if is_horz then pt1, pt2 = rect:w(0), rect:e(0) end
	if is_vert then pt1, pt2 = rect:n(0), rect:s(0) end
	local dist1 = Geom.get_orth_dist(ref, pt1)
	local dist2 = Geom.get_orth_dist(ref, pt2)
	if dist1 < dist2 then
		opts[s_name], opts[e_name] = pt1, pt2
	else
		opts[s_name], opts[e_name] = pt2, pt1
	end
	return opts
end

local function opts_calc_to_line_r(opts)
	if opts.tos == nil or opts.toe == nil then return opts end
	opts.r = Geom.get_orth_dist(opts.tos, opts.toe) + 1
	return opts
end

local function resolve_to_line(opts)
	if opts.to ~= nil and getmetatable(opts.to) == Point then
		opts.tos = opts.to
	end
	opts = Options.opts_rect_line(opts, 'to', 'tos', 'toe', opts.from)
	opts = opts_calc_to_line_r(opts)
	return opts
end

local function calc_dtec_dist(from, to)
	local dp = to:sub(from)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

local function resolve_to_square(opts)
	if opts.to ~= nil then
		if getmetatable(opts.to) == Rect then
			local dist = 0
			dist = math.max(dist, calc_dtec_dist(opts.from, opts.to:nw(0)))
			dist = math.max(dist, calc_dtec_dist(opts.from, opts.to:ne(0)))
			dist = math.max(dist, calc_dtec_dist(opts.from, opts.to:sw(0)))
			dist = math.max(dist, calc_dtec_dist(opts.from, opts.to:se(0)))
			opts.r = dist
		else
			assert(getmetatable(opts.to) == Point)
			opts.r = calc_dtec_dist(opts.from, opts.to)
		end
	end
	return opts
end

local function resolve_cray_s_e(opts)
	if opts.tos ~= nil then
		opts.j = Geom.get_orth_dist(opts.from, opts.tos) - 1
	elseif opts.toe ~= nil then
		opts.j = Geom.get_orth_dist(opts.from, opts.toe) - opts.tmp
	end
	return opts
end

local function resolve_dray_s_e(opts)
	if opts.tos ~= nil then
		opts.j = Geom.get_orth_dist(opts.from, opts.tos) - opts.tmp - 1
	elseif opts.toe ~= nil then
		opts.j = Geom.get_orth_dist(opts.from, opts.toe) - opts.tmp - opts.tmp
	end
	return opts
end

local ELEM_GROUP_TO_POS = {'cray', 'dray', 'ldtc', 'dtec'}
local ELEM_GROUP_TO_LINE = {'cray', 'dray', 'ldtc'}
local ELEM_GROUP_TO_SQUARE = {'dtec'}
local ELEM_GROUP_CRAY_LIKE = {'cray', 'ldtc'}
local ELEM_GROUP_DRAY_LIKE = {'dray'}

-- func, followed by elements to apply it to
-- these will be applied in order
local PREPARE_FUNCS_RAW = {
	{parse_from_to_pos, ELEM_GROUP_TO_POS},
	{alias_to_s_e, ELEM_GROUP_CRAY_LIKE},
	{translate_props, {'any'}},
}
local RESOLVE_FUNCS_RAW = {
	{resolve_to_line, ELEM_GROUP_TO_LINE},
	{resolve_to_square, ELEM_GROUP_TO_SQUARE},
	{translate_props, {'any'}},
	{resolve_cray_s_e, ELEM_GROUP_CRAY_LIKE},
	{resolve_dray_s_e, ELEM_GROUP_DRAY_LIKE},
	{translate_props, {'any'}},
	{pre_spark, {'conduct'}},
}
local EXTRA_OPTS_RAW = {
	from = ELEM_GROUP_TO_POS,
	to = ELEM_GROUP_TO_POS,
	tos = ELEM_GROUP_TO_LINE,
	toe = ELEM_GROUP_TO_LINE,
	sprk = {'conduct'},
}

local function make_prepare_funcs()
	local d = elem_multidict_new()
	for _, row in ipairs(PREPARE_FUNCS_RAW) do
		for _, elem_name in ipairs(row[2]) do
			elem_multidict_add(d, elem_name, row[1])
		end
	end
	return d
end
local PREPARE_FUNCS = make_prepare_funcs()

local function make_resolve_funcs()
	local d = elem_multidict_new()
	for _, row in ipairs(RESOLVE_FUNCS_RAW) do
		for _, elem_name in ipairs(row[2]) do
			elem_multidict_add(d, elem_name, row[1])
		end
	end
	return d
end
local RESOLVE_FUNCS = make_resolve_funcs()

local function make_extra_opts()
	local d = elem_multidict_new()
	for extra_opt, elems in pairs(EXTRA_OPTS_RAW) do
		for _, elem_name in ipairs(elems) do
			elem_multidict_add(d, elem_name, extra_opt)
		end
	end
	return d
end
local EXTRA_OPTS = make_extra_opts()

local PROP_DEFAULTS_RAW = {
	{'filt', 'tmp', Util.FILT_MODES.NOP},
	{'aray', 'life', 1},
	{'cray', 'ctype', elem.DEFAULT_PT_SPRK},
	{'cray', 'tmp', 1},
	{'dray', 'tmp', 1},
	{'ldtc', 'tmp', 1},
}

local function make_prop_defaults()
	local d = {}
	for _, row in ipairs(PROP_DEFAULTS_RAW) do
		local t = decode_elem(row[1])
		if d[t] == nil then d[t] = {} end
		d[t][row[2]] = row[3]
	end
	return d
end
local PROP_DEFAULTS = make_prop_defaults()

local BOUNDS_CHECK_LEQ = 0
local BOUNDS_CHECK_GEQ = 1

local BoundsCheck = {}
function BoundsCheck.new(typ, prop, bound)
	return {
		typ = typ,
		prop = prop,
		bound = bound,
	}
end

local BOUNDS_CHECKS_RAW = {
	{BOUNDS_CHECK_GEQ, 'any', 'temp', 0},
	{BOUNDS_CHECK_LEQ, 'dtec', 'tmp2', 25},
	{BOUNDS_CHECK_GEQ, 'cray', 'tmp', 0},
	{BOUNDS_CHECK_GEQ, 'dray', 'tmp', 0},
	{BOUNDS_CHECK_GEQ, 'ldtc', 'tmp', 0},
	{BOUNDS_CHECK_GEQ, 'cray', 'tmp2', 0},
	{BOUNDS_CHECK_GEQ, 'dray', 'tmp2', 0},
	{BOUNDS_CHECK_GEQ, 'ldtc', 'life', 0},
}

local function make_bounds_checks()
	local d = elem_multidict_new()
	for _, row in ipairs(BOUNDS_CHECKS_RAW) do
		elem_multidict_add(d, row[2], BoundsCheck.new(row[1], row[3], row[4]))
	end
	return d
end
local BOUNDS_CHECKS = make_bounds_checks()

function Particle:config(opts)
	local prepare_funcs = elem_multidict_lookup(PREPARE_FUNCS, opts['type'])
	if prepare_funcs ~= nil then
		for _, prepare_func in ipairs(prepare_funcs) do
			opts = prepare_func(opts)
		end
	end

	for field_name, _ in pairs(Util.PART_FIELDS) do
		self[field_name] = opts[field_name]
	end
	local extra_opts = elem_multidict_lookup(EXTRA_OPTS, opts['type'])
	if extra_opts ~= nil then
		for _, extra_opt in ipairs(extra_opts) do
			self[extra_opt] = opts[extra_opt]
		end
	end
end

function Particle:from_opts(opts)
	if opts.elem_name ~= nil then
		opts['type'] = decode_elem(opts.elem_name)
	end
	local t = opts['type']

	local prop_defaults = PROP_DEFAULTS[t]
	if prop_defaults ~= nil then
		for prop, val in pairs(prop_defaults) do
			if opts[prop] == nil then
				opts[prop] = val
			end
		end
	end

	local part = Particle:new()
	part:config(opts)
	return part
end

function Particle:has_vvars()
	for k, v in pairs(self) do
		if getmetatable(v) == VirtualExpression then
			return true
		end
	end
	return false
end

local function do_bounds_check(part, bounds_check)
	local typ = bounds_check.typ
	local prop = bounds_check.prop
	local bound = bounds_check.bound
	local val = part[prop]
	if val == nil then return end
	if typ == BOUNDS_CHECK_LEQ and val <= bound then
		return
	elseif typ == BOUNDS_CHECK_GEQ and val >= bound then
		return
	else
		assert(false, 'unrecognized bounds check type')
	end
	assert(
		val >= bound,
		prop .. ' must be at least ' .. bound ..
		' but ' .. val .. ' requested'
	)
end

function Particle:resolve_vvars(vars)
	local extra_opts = elem_multidict_lookup(EXTRA_OPTS, self['type'])
	if extra_opts ~= nil then
		for _, extra_opt in ipairs(extra_opts) do
			local opt_val = self[extra_opt]
			if getmetatable(opt_val) == VirtualExpression then
				self[extra_opt] = opt_val:resolve(vars)
			end
		end
	end
end

function Particle:resolve()
	local part = self

	local resolve_funcs = elem_multidict_lookup(RESOLVE_FUNCS, part['type'])
	if resolve_funcs ~= nil then
		for _, resolve_func in ipairs(resolve_funcs) do
			part = resolve_func(part)
		end
	end

	local bounds_checks = elem_multidict_lookup(BOUNDS_CHECKS, part['type'])
	if bounds_checks ~= nil then
		for _, bounds_check in ipairs(bounds_checks) do
			do_bounds_check(part, bounds_check)
		end
	end
end

return Particle
