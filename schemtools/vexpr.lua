local VirtualVariable = {}
function VirtualVariable:new(name)
	local o = {
		name = name,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local VirtualExpression = {}
function VirtualExpression:new(func, args)
	local o = {
		func = func,
		args = args,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function VirtualExpression:from_name(name)
	return VirtualExpression:new('id', { VirtualVariable:new(name) })
end

function VirtualExpression:n(n)
	return VirtualExpression:new('n', { self, n })
end
function VirtualExpression:e(n)
	return VirtualExpression:new('e', { self, n })
end
function VirtualExpression:s(n)
	return VirtualExpression:new('s', { self, n })
end
function VirtualExpression:w(n)
	return VirtualExpression:new('w', { self, n })
end

local RESOLVE_FUNCS = {
	id = function(val) return val end,
	n = function(val, n) return val:n(n) end,
	e = function(val, n) return val:e(n) end,
	s = function(val, n) return val:s(n) end,
	w = function(val, n) return val:w(n) end,
}

function VirtualExpression:resolve(varstore)
	local resolved_args = {}
	for _, arg in ipairs(self.args) do
		local arg_typ = getmetatable(arg)
		if arg_typ == VirtualExpression then
			arg = arg:resolve(vars)
		elseif arg_typ == VirtualVariable then
			arg = varstore:get_var(arg.name)
		end
		table.insert(resolved_args, arg)
	end
	return RESOLVE_FUNCS[self.func](unpack(resolved_args))
end

return VirtualExpression
