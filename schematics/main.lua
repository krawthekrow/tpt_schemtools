require('schematics/stdlib')
require('schematics/testlib')

local function filt_rom_32_demo(SchemTools)
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
	port{v='reader_y', p=v('rom.io_min_y')}
	connect{p1='rom.make_reader', p2='reader_y'}
	port{v='addr_in', p=v('rom.raddr_in'):left(5)}
	filt{p=v('addr_in'), ct=ka}
	connect{p1='addr_in', p2='rom.raddr_in'}
	port_alias('data_out', 'rom.rdata_out')

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

return filt_rom_32_demo
