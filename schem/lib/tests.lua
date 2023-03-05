require('schem/lib/core')
require('schem/lib/testlib')

require('schem/lib/fram1d')
require('schem/lib/procedural')
require('schem/lib/vram56')
require('schem/lib/spu56')
require('schem/lib/disp56')

function shr_1_tb()
	schem{
		f=shr_1,
		v='shifter',
		x=100, y=100,
	}

	port{v='a_in', p=v('shifter.a_in'):n(2)}
	filt{p=v('a_in'), ct=bor(ka, 30)}
	connect{v='shifter.a_in', p=v('a_in')}

	port{v='res_out', p=v('shifter.res_out'):s()}
	filt{p=v('res_out')}

	tsetup{
		inputs={
			{v='a_in', f=filt_in}
		},
		outputs={
			{v='res_out', f=filt_out}
		},
		model=function(inputs)
			local shift_amt = inputs.a_in
			local res = shl(1, shift_amt)
			if shift_amt >= 29 then res = 0 end
			return {res_out = res}
		end
	}
	for i = 1, 32 do
		tc{a_in=i-1}
	end
	plot{clear={}, run_test=1}
end

function from1d_32_tb()
	local init_data = {}
	for i = 1, 32 do
		table.insert(init_data, bor(ka, i-1))
	end
	schem{
		f=from1d_32,
		x=100, y=100,
		v='rom',
		init_data=init_data,
	}
	connect{v='rom.make_reader', p=v('rom.io_nbnd')}
	port{v='addr_in', p=v('rom.raddr_in'):w(5)}
	filt{p=v('addr_in'), ct=ka}
	connect{v='rom.raddr_in', p=v('addr_in')}
	port_alias{from='rom.rdata_out', to='data_out'}

	tsetup{
		inputs={
			{v='addr_in', f=filt_in}
		},
		outputs={
			{v='data_out', f=filt_out}
		},
	}
	for i = 1, 32 do
		tc{addr_in=i-1, data_out=i-1}
	end
	plot{clear={}, run_test=1}
end

function spu56_tb()
	schem{
		f=spu56,
		x=100, y=100,
	}
	plot{clear={}, run_test=0}
end

function vram56_tb()
	local init_data = {}
	for i = 1, 64 do
		local row = {}
		for j = 1, 56 * 2 do
			table.insert(row, bor(ka, i * 128 + j))
		end
		table.insert(init_data, row)
	end
	schem{
		f=vram56,
		v='vram',
		x=100, y=100,
		init_data=init_data,
	}
	connect{v='vram.make_writer', p=v('vram.data_block'):sw(0):s(10)}
	plot{clear={}, run_test=0}
end

local DispCoreModel = {}

function DispCoreModel.createInitBuffer()
	local buffer = {}
	for i = 1, 56 do
		local row = {}
		for j = 1, 56 do
			table.insert(row, 0)
		end
		table.insert(buffer, row)
	end
	return buffer
end

function DispCoreModel:new()
	local o = {
		buffer = DispCoreModel.createInitBuffer(),
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function DispCoreModel:tick(inputs)
	local pixcol_in = inputs.pixcol_in
	local data_in = inputs.data_in
	for i = 1, 56 do
		for j = 1, 56 do
			local data_word = data_in[(i - 1) * 2 + ((j - 1) % 2) + 1]
			local shift_amt = intdiv(j - 1, 2)
			if band(shr(data_word, shift_amt), 1) == 1 then
				self.buffer[i][j] = pixcol_in
			end
		end
	end

	local pixels_out = {}
	for i = 1, 56 do
		for j = 1, 56 do
			table.insert(pixels_out, self.buffer[i][j])
			table.insert(pixels_out, self.buffer[i][j])
		end
	end
	return {pixels_out = pixels_out}
end

local function disp56_pixcol_in(p, val)
	sim.partKill(p.x, p.y)
	local id = sim.partCreate(-3, p.x, p.y, elem.DEFAULT_PT_INWR)
	sim.partProperty(id, sim.FIELD_DCOLOUR, bor(0xFF000000, val))
end

local function disp56_pixcols_in(p, val)
	for i = 1, 56 do
		for j = 1, 56 do
			local subp = p:add(get_disp_core_matrix_offset(j, i))
			disp56_pixcol_in(subp, val)
		end
	end
end

local function disp56_pixels_out(p)
	local data = {}
	for i = 1, 56 do
		for j = 1, 56 do
			local subp = p:add(get_disp_core_matrix_offset(j, i))
			local id1 = sim.partID(subp.x, subp.y)
			local id2 = sim.partID(subp.x, subp.y + 1)
			local color1 = sim.partProperty(id1, sim.FIELD_DCOLOUR)
			local color2 = sim.partProperty(id2, sim.FIELD_DCOLOUR)
			table.insert(data, band(color1, 0xFFFFFF))
			table.insert(data, band(color2, 0xFFFFFF))
		end
	end
	return data
end

local function gen_disp56_data_in(f)
	local data_in = {}
	for i = 1, 56 do
		local val1, val2 = 0, 0
		for j = 1, 56 do
			local data_bit = 0
			if f(j, i) then data_bit = 1 end
			local shift_amt = intdiv(j - 1, 2)
			if j % 2 == 1 then
				val1 = bor(val1, shl(data_bit, shift_amt))
			else
				val2 = bor(val2, shl(data_bit, shift_amt))
			end
		end
		table.insert(data_in, val1)
		table.insert(data_in, val2)
	end
	return data_in
end

local function make_disp56_render_tests()
	local seed = os.time()
	print('using seed ' .. tostring(seed))
	math.randomseed(seed)
	local random_x, random_y = math.random(56), math.random(56)

	local test_cases = {
		-- clear
		{pixcol_in=0xFFFFFF, data_in=gen_disp56_data_in(function(x, y)
			return true
		end)},

		-- square border
		{pixcol_in=0xFF0000, data_in=gen_disp56_data_in(function(x, y)
			return x == 1 or x == 56 or y == 1 or y == 56
		end)},

		-- cross
		{pixcol_in=0x0000FF, data_in=gen_disp56_data_in(function(x, y)
			return x - y == 0 or x + y == 57
		end)},

		-- halves
		{pixcol_in=0x000033, data_in=gen_disp56_data_in(function(x, y)
			return x <= 28
		end)},
		{pixcol_in=0x000066, data_in=gen_disp56_data_in(function(x, y)
			return y <= 28
		end)},
		{pixcol_in=0x000099, data_in=gen_disp56_data_in(function(x, y)
			return x > 28
		end)},
		{pixcol_in=0x0000CC, data_in=gen_disp56_data_in(function(x, y)
			return y > 28
		end)},

		-- random point
		{pixcol_in=0x0000FF, data_in=gen_disp56_data_in(function(x, y)
			return x == random_x and y == random_y
		end)},
	}

	-- random
	for i = 1, 16 do
		table.insert(test_cases, {
			pixcol_in=math.random(0x1000000) - 1,
			data_in=gen_disp56_data_in(function(x, y)
				return math.random(2) == 2
			end),
		})
	end

	return test_cases
end

function disp56_core_tb()
	schem{
		f=disp56_core,
		v='core',
		x=70, y=100,
	}
	connect{
		v='core.double_buffer_nw',
		p=v('core.pixcol_dray_matrix'):sw(0):s(9)
	}
	connect{
		v='core.make_apom_resetters',
		p=v('core.double_buffer'):sw(0):s(),
	}
	connect{
		v='core.make_side_unit',
		p=v('core.ppom_payload'):ne(0):e(2),
	}
	connect{
		v='core.reset_pscn_sparkers.make_apom_reset',
		p=v('core.double_buffer'):s(),
	}
	connect{v='core.data_in_swizzler', p=v('core.data_targets'):n(20)}

	tsetup{
		inputs={
			{name='pixcol_in', v='core.pixcol_targets', f=disp56_pixcols_in},
			{name='data_in', v='core.data_in', f=filts_in},
		},
		outputs={
			{name='pixels_out', v='core.double_buffer', f=disp56_pixels_out},
		},
		model=DispCoreModel:new(),
		dump_debug_info=false,
		tcs=make_disp56_render_tests(),
	}

	plot{clear={}, run_test=1}
end

function disp56_tb()
	schem{
		f=disp56,
		v='disp',
		x=70, y=100,
	}

	tsetup{
		inputs={
			{name='pixcol_in', v='disp.pixcol_in', f=disp56_pixcol_in},
			{name='data_in', v='disp.data_in', f=filts_in},
		},
		outputs={
			{name='pixels_out', v='disp.core.double_buffer', f=disp56_pixels_out},
		},
		model=DispCoreModel:new(),
		dump_debug_info=false,
		tcs=make_disp56_render_tests(),
	}

	plot{clear={}, run_test=1}
end
