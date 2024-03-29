local Util = require('schemtools/util')

local Tester = {}
function Tester:new()
	local o = {
		active = false,
		inputs = {},
		outputs = {},
		keyframes = {},
		cursor = 1,
		subcursor = 1,
		model = nil,
		num_ticks = 0,
		stop_at = nil,
		dump_func = nil,
		dump_debug_info = true,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local Input = {}
function Input.new(p, set_func)
	return {
		p = p,
		set_func = set_func,
	}
end

local Output = {}
function Output.new(p, get_func)
	return {
		p = p,
		get_func = get_func,
	}
end

function Tester:add_input(opts)
	self.inputs[opts.name] = Input.new(opts.p, opts.f)
end

function Tester:add_output(opts)
	self.outputs[opts.name] = Output.new(opts.p, opts.f)
end

function Tester:advance_curs()
	self.cursor = self.cursor + 1
	self.subcursor = 1
end

function Tester:finish_keyframe()
	if self.cursor <= #self.keyframes then
		self:advance_curs()
	end
end

function Tester:keyframe(keyframe)
	self:finish_keyframe()
	self.keyframes[self.cursor] = keyframe
	self:advance_curs()
end

function Tester:test_case(opts)
	if opts.lat ~= nil then opts.delay = opts.lat end
	if opts.delay == nil then opts.delay = 1 end

	if self.model ~= nil then
		local outputs = nil
		if type(self.model) == 'function' then
			outputs = self.model(opts)
		else
			outputs = self.model:tick(opts)
		end
		for k, v in pairs(outputs) do
			opts[k] = v
		end
	end

	if self.cursor > #self.keyframes then
		table.insert(self.keyframes, {})
	end
	local next_keyframe = {
		delay = opts.delay,
		debug_info = opts,
	}
	for k, v in pairs(opts) do
		local input, output = self.inputs[k], self.outputs[k]
		if input ~= nil then
			self.keyframes[self.cursor][k] = v
		end
		if output ~= nil then
			next_keyframe[k] = v
		end
	end
	self:finish_keyframe()
	self.keyframes[self.cursor] = next_keyframe
end

-- the below functions are called at testing time

function Tester:start()
	if #self.keyframes == 0 then
		print('no test data supplied')
		return
	end
	self.cursor = 1
	self.subcursor = 1
	self.active = true
	tpt.set_pause(0)
	self:on_tick()
end

function Tester:stop()
	self.active = false
	tpt.set_pause(1)
end

local function compare_test_output(val, expected_val)
	if type(val) == 'table' then
		for k, v in pairs(expected_val) do
			if not compare_test_output(v, val[k]) then
				return false, k
			end
		end
		for k, _ in pairs(val) do
			if expected_val[k] == nil then
				return false, k
			end
		end
		return true, nil
	end
	return val == expected_val, nil
end

function Tester:on_tick()
	if not self.active then return end

	local keyframe = self.keyframes[self.cursor]
	local delay = 1
	if keyframe.delay ~= nil then delay = keyframe.delay end

	if self.subcursor == delay then
		for k, v in pairs(keyframe) do
			local input, output = self.inputs[k], self.outputs[k]
			if output ~= nil then
				local val = output.get_func(output.p, keyframe)
				local is_match, mismatch_key = compare_test_output(val, v)
				if not is_match then
					if self.dump_func == nil then
						if self.dump_debug_info and keyframe.debug_info ~= nil then
							print('failure debug info:')
							Util.dump_var(keyframe.debug_info)
						end
						if mismatch_key ~= nil then
							print(
								'actual output (key = ' .. mismatch_key .. '): ' ..
								val[mismatch_key]
							)
							print(
								'spec output (key = ' .. mismatch_key .. '): ' ..
								v[mismatch_key]
							)
						else
							print('actual output: ' .. val)
							print('spec output:' .. v)
						end
					else
						self.dump_func(
							self.num_ticks,
							keyframe.debug_info,
							val, v, mismatch_key
						)
					end
					assert(
						false,
						'actual output does not match spec output at tick ' ..
						self.num_ticks
					)
				end
			end
			if input ~= nil then
				input.set_func(input.p, v, keyframe)
			end
		end
	end

	self.subcursor = self.subcursor + 1
	if self.subcursor > delay then
		self:advance_curs()
	end

	if self.cursor > #self.keyframes then
		print('test complete!')
		self:stop()
		return
	end

	if self.stop_at ~= nil and self.num_ticks == self.stop_at then
		print('stopping early at tick ' .. tostring(self.num_ticks))
		self:stop()
		return
	end
	self.num_ticks = self.num_ticks + 1
end

return Tester
