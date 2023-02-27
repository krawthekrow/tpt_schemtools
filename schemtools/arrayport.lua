local ArrayPort = {}
function ArrayPort:new(p)
	local o = {
		minx = p.x,
		maxx = p.x,
		miny = p.y,
		maxy = p.y,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function ArrayPort:clone(old)
	local o = {}
	for k, v in pairs(old) do o[k] = v end
	setmetatable(o, self)
	self.__index = self
	return o
end

function ArrayPort:is_horz() return self.miny == self.maxy end
function ArrayPort:is_vert() return self.minx == self.maxx end
function ArrayPort:check_horz()
	assert(self:is_horz(), 'array port is not a horizontal line')
end
function ArrayPort:check_vert()
	assert(self:is_vert(), 'array port is not a vertical line')
end

-- Always specify navigation steps explicitly for array ports
-- to reduce confusion. Navigation is defined so that navigating
-- from a 1x1 array port is similar to navigating from a point.

function ArrayPort:nw(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return Point:new(self.minx, self.miny):nw(n)
end
function ArrayPort:ne(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return Point:new(self.maxx, self.miny):ne(n)
end
function ArrayPort:sw(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return Point:new(self.minx, self.maxy):sw(n)
end
function ArrayPort:se(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return Point:new(self.maxx, self.maxy):se(n)
end

-- Navigating off a side of width >1 should only be used when
-- the coordinate along that axis is not important. To catch bugs,
-- randomize that coordinate.

function ArrayPort:n(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return self:nw(0):e(math.random(self:sz().x) - 1):n(n)
end
function ArrayPort:s(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return self:sw(0):e(math.random(self:sz().x) - 1):s(n)
end
function ArrayPort:w(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return self:nw(0):s(math.random(self:sz().y) - 1):w(n)
end
function ArrayPort:e(n)
	assert(n ~= nil, 'array port nav step must be explicit')
	return self:ne(0):s(math.random(self:sz().y) - 1):e(n)
end

function ArrayPort:ln(n)
	self:check_vert()
	return self:n(n)
end
function ArrayPort:ls(n)
	self:check_vert()
	return self:s(n)
end
function ArrayPort:lw(n)
	self:check_horz()
	return self:w(n)
end
function ArrayPort:le(n)
	self:check_horz()
	return self:e(n)
end

function ArrayPort:x() self:check_vert(); return self.minx end
function ArrayPort:y() self:check_horz(); return self.miny end

function ArrayPort:sz()
	return Point:new(
		self.maxx - self.minx + 1,
		self.maxy - self.miny + 1
	)
end

function ArrayPort:expand(p)
	self.minx = math.min(self.minx, p.x)
	self.maxx = math.max(self.maxx, p.x)
	self.miny = math.min(self.miny, p.y)
	self.maxy = math.max(self.maxy, p.y)
end

function ArrayPort:translate(p)
	self.minx = self.minx + p.x
	self.maxx = self.maxx + p.x
	self.miny = self.miny + p.y
	self.maxy = self.maxy + p.y
end

return ArrayPort
