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

return Port
