local Geom = require('schemtools/geom')
local Rect = Geom.Rect

local ArrayPort = {}
function ArrayPort:new(val)
	local o = {
		val = val,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function ArrayPort:from_p(p)
	return ArrayPort:new(Rect:new(p, p))
end

function ArrayPort:expand(p)
	self.val = self.val:expand_to_p(p)
end

return ArrayPort
