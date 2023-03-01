local Geom = require('schemtools/geom')
local Rect = Geom.Rect

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

function Port:is_array()
	return getmetatable(self.val) == Rect
end
function Port:assert_array()
	assert(self:is_array(), 'expected array port')
end

function Port:expand(p)
	self:assert_array()
	self.val = self.val:expand_to_p(p)
end

return Port
