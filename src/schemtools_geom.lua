Geom = {}

-- treat this as immutable
local Point = {}
Geom.Point = Point
function Point:new(x, y)
	local p = {}
	setmetatable(p, self)
	self.__index = self
	p.x = x
	p.y = y
	return p
end

function Point:zero()
	return Point:new(0, 0)
end

function Point:add(op)
	return Point:new(self.x + op.x, self.y + op.y)
end

function Point:sub(op)
	return Point:new(self.x - op.x, self.y - op.y)
end

function Point:neg()
	return Point:new(-self.x, -self.y)
end

function Point:eq(op)
	return self.x == op.x and self.y == op.y
end

return Geom
