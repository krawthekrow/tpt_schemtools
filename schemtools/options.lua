local Geom = require('schemtools/geom')
local Point = Geom.Point

local Options = {}

function Options.opts_pt(opts, pname, xname, yname, ref, force)
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

function Options.opts_alias_dp_p(opts)
	opts = Options.opts_pt(opts, 'dp', 'dx', 'dy', nil, false)
	if opts ~= nil and opts.dp ~= nil then
		opts.p = opts.dp
	end
	return opts
end

function Options.opts_pt_short(opts, ref, force)
	if force == nil then force = true end
	if ref == nil then ref = Point:zero() end
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

return Options
