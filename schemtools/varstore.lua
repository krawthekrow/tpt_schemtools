local Util = require('schemtools/util')
local Geom = require('schemtools/geom')
local Port = require('schemtools/port')
local Point = Geom.Point

local VariableStore = {}
function VariableStore:new()
	local o = {
		-- schematic context to be prepended when expanding variable names
		ctx_stack = {},
		vars = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function VariableStore:top_ctx()
	if #self.ctx_stack == 0 then return nil end
	return self.ctx_stack[#self.ctx_stack]
end

function VariableStore:begin_ctx(ctx)
	ctx = self:expand_var_name(ctx)
	table.insert(self.ctx_stack, ctx)
end

function VariableStore:end_ctx()
	table.remove(self.ctx_stack)
end

function VariableStore:expand_var_name(name)
	local ctx = self:top_ctx()
	if ctx == nil then return name end
	return ctx .. '.' .. name
end

function VariableStore:set_var(name, val)
	name = self:expand_var_name(name)
	if
		getmetatable(self.vars[name]) == Port and
		getmetatable(val) == Geom.Point
	then
		self.vars[name].p = val
		return
	end
	self.vars[name] = val
end

function VariableStore:get_var_raw(name)
	name = self:expand_var_name(name)
	return self.vars[name]
end

function VariableStore:get_var(name)
	local val = self:get_var_raw(name)
	assert(
		val ~= nil,
		'variable "' .. name .. '" does not exist'
	)
	if getmetatable(val) == Port then
		return val.p
	end
	return val
end

function VariableStore:translate(shift_p, translators)
	for name, val in pairs(self.vars) do
		local translation_func = translators[getmetatable(val)]
		if translation_func ~= nil then
			translation_func(val, shift_p)
		end
	end
end

function VariableStore:filter(pred)
	keys_to_remove = {}
	for name, val in pairs(self.vars) do
		if not pred(name, val) then
			table.insert(keys_to_remove, name)
		end
	end
	for name, _ in ipairs(keys_to_remove) do
		self.vars[name] = nil
	end
end

function VariableStore:merge(other_store)
	for name, val in pairs(other_store.vars) do
		name = self:expand_var_name(name)
		self.vars[name] = val
	end
end

return VariableStore
