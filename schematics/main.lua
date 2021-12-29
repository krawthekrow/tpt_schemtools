require('schematics/stdlib')

return function(SchemTools)
	local demux_inst = schem(function()
		pstn_demux{}
	end)
	place(demux_inst, {x=100, y=100, name='demux_1'})
	filt{p=v('demux_1.addr_in'), ct=bor(5, ka)}
	clear{w=200, h=200}
	plot{}
end
