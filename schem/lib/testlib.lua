function filt_in(p, val)
	local id = sim.partID(p.x, p.y)
	sim.partProperty(id, sim.FIELD_CTYPE, bor(ka, val))
end

function filt_out(p)
	local id = sim.partID(p.x, p.y)
	local val = sim.partProperty(id, sim.FIELD_CTYPE)
	return bsub(val, ka)
end
