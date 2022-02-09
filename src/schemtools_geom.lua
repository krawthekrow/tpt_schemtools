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

function Point:mult(s)
	return Point:new(self.x * s, self.y * s)
end

function Point:eq(op)
	return self.x == op.x and self.y == op.y
end

function Point:left(n)
	if n == nil then n = 1 end
	return self:add(Point:new(-n, 0))
end

function Point:up(n)
	if n == nil then n = 1 end
	return self:add(Point:new(0, -n))
end

function Point:right(n)
	if n == nil then n = 1 end
	return self:add(Point:new(n, 0))
end

function Point:down(n)
	if n == nil then n = 1 end
	return self:add(Point:new(0, n))
end

Geom.Constraints = {}

Geom.Constraints.Ray = {}
function Geom.Constraints.Ray.new(p, d)
	return {
		p = p,
		d = d,
	}
end

function Geom.Constraints.check_ray(r, p)
	local diff = p:sub(r.p)
	return (
		(diff.x > 0) == (r.d.x > 0) and
		(diff.x < 0) == (r.d.x < 0) and
		(diff.y > 0) == (r.d.y > 0) and
		(diff.y < 0) == (r.d.y < 0)
	)
end

function Geom.Constraints.solve_2ray(r1, r2)
	local det = - r1.d.x * r2.d.y + r1.d.y * r2.d.x

	assert(det ~= 0, 'rays are parallel')

	local b = r1.p:sub(r2.p)
	-- "num" for numerator
	local coeff_num = r2.d.y * b.x - r2.d.x * b.y

	assert(coeff_num % det == 0, 'no integer solution')

	local coeff = math.floor(coeff_num / det + 0.5)
	local sol = r1.d:mult(coeff):add(r1.p)
	assert(Geom.Constraints.check_ray(r1, sol))
	assert(Geom.Constraints.check_ray(r2, sol))
	return sol
end

return Geom
