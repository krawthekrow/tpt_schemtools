function filt_in(p, val)
	local id = sim.partID(p.x, p.y)
	sim.partProperty(id, sim.FIELD_CTYPE, bor(ka, val))
end

function filts_in(p, val)
	for i, v in ipairs(val) do
		filt_in(p:e(i - 1), v)
	end
end

function filt_out(p)
	local id = sim.partID(p.x, p.y)
	local val = sim.partProperty(id, sim.FIELD_CTYPE)
	return bsub(val, ka)
end
