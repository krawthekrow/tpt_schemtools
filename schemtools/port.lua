local Port = {}
function Port:new(val, connect_func, cmt)
	local o = {
		val = val,
		connect_func = connect_func,
		cmt = cmt,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

return Port
