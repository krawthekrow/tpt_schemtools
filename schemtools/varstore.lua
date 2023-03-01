local Util = require('schemtools/util')
local Geom = require('schemtools/geom')
local Port = require('schemtools/port')
local ArrayPort = require('schemtools/arrayport')
local Point = Geom.Point
local Rect = Geom.Rect

local VariableStore = {}
function VariableStore:new()
	local o = {
		-- schematic context to be prepended when expanding variable names
		ctx_stack = {},
		-- index suffix to be appended when referencing indexed vars
		index_stack = {},
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

function VariableStore:top_index()
	if #self.index_stack == 0 then return '' end
	return self.index_stack[#self.index_stack]
end

function VariableStore:apply_index(name)
	return name .. self:top_index()
end

function VariableStore:push_index(index)
	local new_suffix = self:top_index() .. '_' .. index
	table.insert(self.index_stack, new_suffix)
end

function VariableStore:pop_index()
	table.remove(self.index_stack)
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
		getmetatable(val) == Point
	then
		self.vars[name].p = val
		return
	end
	if
		getmetatable(self.vars[name]) == ArrayPort and
		getmetatable(val) == Rect
	then
		self.vars[name].val = val
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
	if getmetatable(val) == ArrayPort then
		return val.val
	end
	return val
end

function VariableStore:get_indexed_var(name)
	return self:get_var(self:apply_index(name))
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
