local Util = require('schemtools/util')
local Geom = require('schemtools/geom')
local Port = require('schemtools/port')
local VirtualExpression = require('schemtools/vexpr')
local Point = Geom.Point
local Rect = Geom.Rect

-- allows existing var paths to be mounted into schematics
local MountPoint = {}
function MountPoint:new(target, target_ctx_prefix)
	local o = {
		target = target,
		target_ctx_prefix = target_ctx_prefix,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local VariableStore = {}
function VariableStore:new()
	local o = {
		-- schematic context to be prepended when expanding variable names
		ctx_stack = {},
		-- index suffix to be appended when referencing indexed vars
		index_stack = {},
		vars = {},
		-- virtual variables, used to refer to ports that may be only
		-- defined in the future
		vvars = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function VariableStore:top_ctx()
	if #self.ctx_stack == 0 then return nil end
	return self.ctx_stack[#self.ctx_stack]
end

function VariableStore:top_ctx_prefix()
	local ctx = self:top_ctx()
	if ctx == nil then return '' end
	return ctx .. '.'
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
	return self:top_ctx_prefix() .. name
end

function VariableStore:get_var_with_mounts(name)
	local val = self.vars[name]
	if val ~= nil then
		return val
	end

	local ptr = 1
	while true do
		local match_s, _ = name:find('.', ptr, true)
		if match_s == nil then
			return nil
		end
		ptr = match_s + 1
		local mount_match = self.vars[name:sub(1, match_s - 1)]
		if mount_match ~= nil then
			name = mount_match.target_ctx_prefix .. name:sub(match_s + 1)
			return mount_match.target:get_var_with_mounts(name)
		end
	end
end

function VariableStore:set_var(name, val)
	name = self:expand_var_name(name)
	if
		getmetatable(self.vars[name]) == Port and (
			getmetatable(val) == Point or
			getmetatable(val) == Rect
		)
	then
		self.vars[name].p = val
		return
	end
	self.vars[name] = val
end

function VariableStore:get_var_raw(name)
	name = self:expand_var_name(name)
	return self:get_var_with_mounts(name)
end

function VariableStore:get_var(name)
	local val = self:get_var_raw(name)
	assert(
		val ~= nil,
		'variable "' .. name .. '" does not exist'
	)
	if getmetatable(val) == Port then
		return val.val
	end
	return val
end

function VariableStore:get_indexed_var(name)
	return self:get_var(self:apply_index(name))
end

function VariableStore:make_vvar(name)
	local existing_vvar = self.vvars[name]
	if existing_vvar ~= nil then return existing_vvar end
	local vexpr = VirtualExpression:from_name(name)
	self.vvars[name] = vexpr.args[0]
	return vexpr
end

function VariableStore:make_indexed_vvar(name)
	return self:make_vvar(self:apply_index(name))
end

function VariableStore:mount(src, dest, dest_ctx_prefix)
	self:set_var(src, MountPoint:new(dest, dest_ctx_prefix))
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
		if getmetatable(val) == MountPoint and val.target == other_store then
			val.target = self
			val.target_ctx_prefix = self:expand_var_name(val.target_ctx_prefix)
		end
		self.vars[name] = val
	end
end

return VariableStore
