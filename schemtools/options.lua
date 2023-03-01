local Geom = require('schemtools/geom')
local Point = Geom.Point
local Rect = Geom.Rect

local Options = {}

function Options.opts_alias(opts, from, to)
	if opts == nil then return opts end
	if opts[from] == nil then return opts end
	opts[to] = opts[from]
	return opts
end

function Options.opts_pt(opts, pname, xname, yname, ref, force)
	if force == nil then force = true end
	if ref == nil then ref = Point.ZERO end
	if opts == nil then
		if force then opts = { [pname] = ref } else opts = {} end
	end
	if opts[pname] ~= nil and getmetatable(opts[pname]) ~= Point then
		return opts
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

function Options.opts_alias_dp_p(opts)
	opts = Options.opts_pt(opts, 'dp', 'dx', 'dy', nil, false)
	opts = Options.opts_alias(opts, 'dp', 'p')
	return opts
end

function Options.opts_pt_short(opts, ref, force)
	if force == nil then force = true end
	if ref == nil then ref = Point.ZERO end
	if opts == nil then
		if force then opts = { p = ref } else opts = {} end
	end
	if opts.ox ~= nil then opts.x = ref.x + opts.ox end
	if opts.oy ~= nil then opts.y = ref.y + opts.oy end
	if opts[1] ~= nil then opts.x = opts[1] end
	if opts[2] ~= nil then opts.y = opts[2] end
	return Options.opts_pt(opts, 'p', 'x', 'y', ref, force)
end

function Options.opts_bool(opts, name, dflt)
	if dflt == nil then dflt = false end
	if opts[name] == nil then opts[name] = dflt end
	if type(opts[name]) == 'number' then opts[name] = opts[name] == 1 end
	return opts
end

function Options.opts_rect_line(opts, rect_name, s_name, e_name, ref)
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

return Options
