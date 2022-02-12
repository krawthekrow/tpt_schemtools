local Util = require('schemtools_util')

local Tester = {}
function Tester:new()
	local o = {
		active = false,
		inputs = {},
		outputs = {},
		keyframes = {},
		cursor = 1,
		subcursor = 1,
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
	self.cursor = 1
	self.subcursor = 1
	self.active = true
	tpt.set_pause(0)
end

function Tester:stop()
	self.active = false
	tpt.set_pause(1)
end

function Tester:on_tick()
	if not self.active then return end
	if self.cursor > #self.keyframes then
		print('test complete!')
		self:stop()
		return
	end
	local keyframe = self.keyframes[self.cursor]
	local delay = 1
	if keyframe.delay ~= nil then delay = keyframe.delay end

	if self.subcursor == delay then
		for k, v in pairs(keyframe) do
			local input, output = self.inputs[k], self.outputs[k]
			if output ~= nil then
				local val = output.get_func(output.p, keyframe)
				if val ~= v and keyframe.debug_info ~= nil then
					print('failure debug info:')
					Util.dump_var(keyframe.debug_info)
				end
				assert(
					val == v,
					'actual output ' .. val .. ' does not match spec output ' .. v
				)
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
end

return Tester
