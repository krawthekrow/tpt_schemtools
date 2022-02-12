function ssconv(opts)
	conv{from='sprk', to=opts.t}
	conv{from=opts.t, to='sprk'}
end

function pstn_demux(opts)
	opts = opts_bool(opts, 'detach_pscn_placer', false)
	if opts.n == nil then opts.n = 32 end
	assert(opts.n >= 1)
	assert(opts.n <= 32)
	local num_segs = ilog2(opts.n)

	-- bit checking logic
	array(num_segs, {dx=1}, function(i)
		chain({dx=-1, dy=1}, function()
			inwr{sprk=1}
			if i == 1 then port{v='arayrow_w'} end
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; schem{f=ssconv, t='inwr'}
			filt{tmp=fset, ct=shl(1, num_segs-i)}
			if i == 1 then port{v='addrrow_w'} end
			filt{tmp=fsub}
			if i == 1 then port{v='pscnrow_w'} end
			if i == num_segs then port{v='pscnrow_e'} end
			insl{}
		end)
	end)

	local cum_piston_r = 0
	-- piston, binary section
	chain({dx=-1, p=v('pscnrow_e'):down()}, function()
		-- each PSTN's pushing power includes all the PSTNs in front of it,
		-- so subtract the accumulated pushing power from the target
		-- pushing power
		for i = 1, num_segs do
			if i == 1 then port{v='pstn_bin_e'} end
			if i == num_segs then port{v='pstn_bin_w'} end
			local target_r = shl(1, i - 1)
			pstn{r=target_r - cum_piston_r, ct='dmnd'}
			cum_piston_r = target_r
		end
	end)

	-- piston front
	chain({dx=1, p=v('pstn_bin_e'):right()}, function()
		pstn{r=1}
		port{v='pstn_head'}
	end)

	-- piston back
	chain({dx=-1, p=v('pstn_bin_w'):left()}, function()
		port{v='pstn_target'}
		port{v='apom_pstn_id_holder', oy=1}
		adv{}
		dmnd{}
	end)

	-- PSCN placer to activate PSTN where BRAY is annihilated
	local function make_pscn_placer(p, ss_to_right)
		chain({dx=1, p=p}, function()
			pscn{sprk=1, done=0}
			if ss_to_right then
				schem{f=ssconv, t='pscn', ox=1, oy=1}
			else
				schem{f=ssconv, t='pscn', ox=-1, oy=1, under=1}
			end
			adv{}
			for i = 1, 5 do
				dray{r=2, toe=v('pscnrow_e'):left(i-1), done=0}
			end
			adv{}
			schem{f=ssconv, t='inwr', done=0}
			port{v='pscn_placer_e'}
			inwr{sprk=1}
		end)
	end

	port{v='pscn_placer_wbnd', p=v('pscnrow_e'):right(2)}
	if opts.detach_pscn_placer then
		port{v='pscn_placer', f=function(opts)
			make_pscn_placer(findpt{ns=opts.p, ei=v('pscn_placer_wbnd')}, true)
		end}
	else
		make_pscn_placer(v('pscn_placer_wbnd'), false)
	end

	-- addr_in feed into addr row
	port{v='ldtc_target', p=findpt{n=v('pstn_target'), w=v('addrrow_w')}}
	chain({dx=1, p=v('ldtc_target'):right()}, function()
		while not getcurs():eq(v('addrrow_w')) do
			filt{}
		end
	end)
	port{v='addr_in', p=v('ldtc_target'):left(2)}

	-- setter mechanism for APOM
	port{v='cray_target', p=findpt{n=v('pstn_target'), w=v('pscnrow_w')}}
	port{v='apom_setter_s', p=findpt{n=v('cray_target'), w=v('arayrow_w')}}
	chain({dy=-1, p=v('apom_setter_s')}, function()
		port{v='apom_insl_s'}
		insl{} -- holds the LDTC's ID
		port{v='apom_insl_n'}
		insl{} -- holds the CRAY's ID
		chain({p=v('apom_pstn_id_holder'), done=0}, function()
			insl{} -- holds the PSTN's ID
		end)
		pstn{r=opts.n - cum_piston_r}
		cray{r=num_segs, from=v('cray_target'), to=v('pscnrow_w')}

		cray{r=1, to=v('apom_pstn_id_holder'), done=0}
		cray{s=v('apom_insl_n'), r=2, done=0}
		cray{r=1, v='apom_ldtc_maker', ct='ldtc', to=v('ldtc_target'), done=0}
		dray{r=2, tos=v('cray_target'), done=0}
		schem{f=ssconv, ox=1, t='pscn'}
		pscn{sprk=1}
	end)

	-- Config port for the addr_in reader.
	-- This is complicated by the fact that the LDTC is created by a CRAY
	-- through APOM. The LDTC's skip distance is configured through its
	-- life, which is set by the CRAY's life.
	port{v='addr_in', p=v('ldtc_target'):left(), done=0, f=function(opts)
		v('apom_ldtc_maker').life = get_orth_dist(v('ldtc_target'), opts.p) - 1
	end}

	-- sparker for the APOM'ed CRAY
	chain({p=v('cray_target'):left()}, function()
		schem{f=ssconv, t='pscn', done=0}
		pscn{sprk=1}
	end)

	-- resetter mechanism for APOM
	chain({dy=1, p=v('apom_pstn_id_holder'):down()}, function()
		cray{r=1, to=v('pstn_target'), done=0}
		dray{r=2, tos=v('cray_target'), done=0}
		cray{s=v('apom_insl_s'), r=2, ct='insl', done=0}
		cray{s=v('apom_pstn_id_holder'), r=1, ct='insl'}
		pscn{sprk=1}
		-- put the ssconv below since the earlier space is used
		-- for the resetter PSTN sparker
		schem{f=ssconv, t='pscn'}
	end)

	-- spark resetter PSTN
	chain({dy=1, p=v('pstn_target'):down(2)}, function()
		nscn{sprk=1}
		schem{f=ssconv, t='nscn', under=1}
	end)
end

function filt_rom_32(opts)
	if opts.init_data == nil then
		opts.init_data = {}
		for i = 1, 32 do
			table.insert(opts.init_data, ka)
		end
	end
	schem{
		f=pstn_demux,
		v='demux',
		detach_pscn_placer=1,
	}
	port_alias('addr_in', 'demux.addr_in')
	chain({dx=1, p=v('demux.pstn_head')}, function()
		frme{done=0}
		frme{oy=1}

		port{v='data_w', oy=-2}
		port{v='data_out', oy=1}
		ldtc{r=1, j=1, done=0}
		filt{oy=1}
	end)
	port{v='data', p=v('data_w')}

	chain({dx=1, p=v('data_w')}, function()
		for i = 1, 32 do
			if i == 32 then port{v='data_e'} end
			filt{ct=opts.init_data[i]}
		end
	end)

	port{v='demux_pscn_placer_x', p=v('data_e'):right()}
	connect{p1='demux.pscn_placer', p2='demux_pscn_placer_x'}
end
