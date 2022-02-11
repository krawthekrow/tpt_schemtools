require('schematics/stdlib')

return function(SchemTools)
	schem{
		f=pstn_demux,
		v='demux_1',
		x=100, y=100,
		detach_pscn_placer=1,
	}
	port{v='addr_in', p=v('demux_1.addr_in'):left(5)}
	filt{p=v('addr_in'), ct=bor(5, ka)}
	connect{p1='addr_in', p2='demux_1.addr_in'}
	chain({dx=1, p=v('demux_1.pstn_head')}, function()
		frme{done=0}
		frme{oy=1}

		port{v='data_w', oy=-2}
		ldtc{r=1, j=1, done=0}
		filt{oy=1}
	end)

	chain({dx=1, p=v('data_w')}, function()
		for i = 1, 32 do
			if i == 32 then port{v='data_e'} end
			filt{ct=bor(ka, i)}
		end
	end)

	port{v='demux_pscn_placer_x', p=v('data_e'):right()}
	connect{p1='demux_1.pscn_placer', p2='demux_pscn_placer_x'}

	-- connect{p1='demux_1.pscn_placer', p2='demux_1.pstn_head'}
	-- port{v='demux_head', p=findpt{
	-- 	e=v('demux_1.pstn_head'), ns=v('demux_1.pscn_placer_e')
	-- }}
	clear{w=200, h=200}
	plot{}
end
