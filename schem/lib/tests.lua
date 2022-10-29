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
	}
	for i = 1, 32 do
		local res = shl(1, i-1)
		if i >= 30 then res = 0 end
		tc{a_in=i-1, res_out=res}
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
	connect{v='rom.make_reader', p=v('rom.io_min_y')}
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
	connect{v='vram.make_writer', p=v('vram.data_block'):sw():s(10)}
	plot{clear={}, run_test=0}
end

function disp56_tb()
	schem{
		f=disp56,
		v='disp',
		x=70, y=100,
	}
	plot{clear={w=sim.XRES/2}, run_test=0}
end
