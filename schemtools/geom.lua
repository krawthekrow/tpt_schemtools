local Geom = {}

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

Point.ZERO = Point:new(0, 0)
Point.ONE = Point:new(1, 1)

function Point:lensq()
	return self.x * self.x + self.y * self.y
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

function Point:w(n)
	if n == nil then n = 1 end
	return self:add(Point:new(-n, 0))
end

function Point:n(n)
	if n == nil then n = 1 end
	return self:add(Point:new(0, -n))
end

function Point:e(n)
	if n == nil then n = 1 end
	return self:add(Point:new(n, 0))
end

function Point:s(n)
	if n == nil then n = 1 end
	return self:add(Point:new(0, n))
end

function Point:nw(n)
	if n == nil then n = 1 end
	return self:add(Point:new(-n, -n))
end

function Point:ne(n)
	if n == nil then n = 1 end
	return self:add(Point:new(n, -n))
end

function Point:sw(n)
	if n == nil then n = 1 end
	return self:add(Point:new(-n, n))
end

function Point:se(n)
	if n == nil then n = 1 end
	return self:add(Point:new(n, n))
end

-- treat this as immutable
local Rect = {}
Geom.Rect = Rect
function Rect:new(lb, ub)
	local o = {
		lb = lb,
		ub = ub,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Rect:is_horz()
	return self:sz().y == 1
end
function Rect:is_vert()
	return self:sz().x == 1
end

function Rect:assert_horz()
	assert(self:is_horz(), 'rect is not a horizontal line')
end
function Rect:assert_vert()
	assert(self:is_vert(), 'rect is not a vertical line')
end

-- Navigation for rects is defined so that navigating from a
-- 1x1 rect is similar to navigating from a point.

function Rect:nw(n)
	return self.lb:nw(n)
end
function Rect:ne(n)
	return Point:new(self.ub.x, self.lb.y):ne(n)
end
function Rect:sw(n)
	return Point:new(self.lb.x, self.ub.y):sw(n)
end
function Rect:se(n)
	return self.ub:se(n)
end

-- Navigating off a side of width >1 should only be used when
-- the coordinate along that axis is not important. To catch bugs,
-- randomize that coordinate.

local RANDOMIZE_RECT_NAV_SRC = true
local function get_rect_nav_rand(l)
	if not RANDOMIZE_RECT_NAV_SRC then
		return 0
	end
	return math.random(l) - 1
end

function Rect:n(n)
	return self:nw(0):e(get_rect_nav_rand(self:sz().x)):n(n)
end
function Rect:s(n)
	return self:sw(0):e(get_rect_nav_rand(self:sz().x)):s(n)
end
function Rect:w(n)
	return self:nw(0):s(get_rect_nav_rand(self:sz().y)):w(n)
end
function Rect:e(n)
	return self:ne(0):s(get_rect_nav_rand(self:sz().y)):e(n)
end

function Rect:sz()
	return self.ub:sub(self.lb):add(Point.ONE)
end

function Rect:expand_to_p(p)
	return Rect:new(
		Point:new(math.min(p.x, self.lb.x), math.min(p.y, self.lb.y)),
		Point:new(math.max(p.x, self.ub.x), math.max(p.y, self.ub.y))
	)
end

function Rect:add(p)
	return Rect:new(self.lb:add(p), self.ub:add(p))
end

function Rect:sub(p)
	return Rect:new(self.lb:sub(p), self.ub:sub(p))
end

function Rect:slice(opts)
	local lbx, lby, ubx, uby = self.lb.x, self.lb.y, self.ub.x, self.ub.y
	local function resolve_x(x)
		if x >= 0 then
			return self.lb.x + x - 1
		else
			return self.ub.x + x + 1
		end
	end
	local function resolve_y(y)
		if y >= 0 then
			return self.lb.y + y - 1
		else
			return self.ub.y + y + 1
		end
	end
	if opts.x ~= nil then
		lbx = resolve_x(opts.x)
		ubx = resolve_x(opts.x)
	end
	if opts.y ~= nil then
		lby = resolve_y(opts.y)
		uby = resolve_y(opts.y)
	end
	if opts.x1 ~= nil then
		lbx = resolve_x(opts.x1)
	end
	if opts.x2 ~= nil then
		ubx = resolve_x(opts.x2)
	end
	if opts.y1 ~= nil then
		lby = resolve_y(opts.y1)
	end
	if opts.y2 ~= nil then
		uby = resolve_y(opts.y2)
	end
	return Rect:new(Point:new(lbx, lby), Point:new(ubx, uby))
end

function Rect:pad(opts)
	local lbx, lby, ubx, uby = self.lb.x, self.lb.y, self.ub.x, self.ub.y
	if opts.n ~= nil then lby = lby - 1 end
	if opts.e ~= nil then ubx = ubx + 1 end
	if opts.s ~= nil then uby = uby + 1 end
	if opts.w ~= nil then lbx = lbx - 1 end
	return Rect:new(Point:new(lbx, lby), Point:new(ubx, uby))
end

function Rect:shift(opts)
	if opts.x == nil then opts.x = 0 end
	if opts.y == nil then opts.y = 0 end
	if opts.p == nil then opts.p = Point:new(opts.x, opts.y) end
	return self:add(opts.p)
end

Geom.Constraints = {}

Geom.Constraints.Ray = {}
function Geom.Constraints.Ray.new(p, d, is_one_sided)
	return {
		p = p,
		d = d,
		is_one_sided = is_one_sided,
	}
end

local function check_ray_side(r, p)
	if not r.is_one_sided then return true end
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
	assert(check_ray_side(r1, sol), 'solution does not satisfy constraint')
	assert(check_ray_side(r2, sol), 'solution does not satisfy constraint')
	return sol
end

function Geom.is_orth(from, to)
	local dp = to:sub(from)
	return dp.x == 0 or dp.y == 0 or math.abs(dp.x) == math.abs(dp.y)
end

function Geom.assert_orth(from, to)
	assert(
		Geom.is_orth(from, to),
		'target not in one of the ordinal directions'
	)
end

function Geom.get_orth_dist(from, to)
	Geom.assert_orth(from, to)
	local dp = to:sub(from)
	return math.max(math.abs(dp.x), math.abs(dp.y))
end

function Geom.get_orth_dir(from, to)
	Geom.assert_orth(from, to)
	local dp = to:sub(from)
	if dp.x > 0 then dp.x = 1 end
	if dp.x < 0 then dp.x = -1 end
	if dp.y > 0 then dp.y = 1 end
	if dp.y < 0 then dp.y = -1 end
	return dp
end

return Geom
