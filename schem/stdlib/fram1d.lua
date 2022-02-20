require('schem/stdlib/core')

function pstn_demux_e(opts)
	opts = opts_bool(opts, 'detach_pscn_placer', false)
	opts = opts_bool(opts, 'detach_apom_resetter', false)
	if opts.n == nil then opts.n = 32 end
	assert(opts.n >= 1)
	assert(opts.n <= 32)
	local num_segs = ilog2(opts.n)

	-- bit checking logic
	array{n=num_segs, dx=1, f=function(i)
		chain{dx=-1, dy=1, f=function()
			inwr{sprk=1}
			if i == 1 then port{v='arayrow_w'} end
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; schem{f=ssconv, t='inwr'}
			filt{mode='set', ct=shl(1, num_segs-i)}
			if i == 1 then port{v='addrrow_w'} end
			filt{mode='sub'}
			if i == 1 then port{v='pscnrow_w'} end
			if i == num_segs then port{v='pscnrow_e'} end
			insl{}
		end}
	end}

	local cum_piston_r = -1
	-- piston, binary section
	chain{dx=-1, p=v('pscnrow_e'):down(), f=function()
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
	end}

	-- piston front
	chain{dx=1, p=v('pstn_bin_e'):right(), f=function()
		pstn{r=0}
		port{v='pstn_head'}
	end}

	-- piston back
	chain{dx=-1, p=v('pstn_bin_w'):left(), f=function()
		port{v='pstn_target'}
		adv{}
		dmnd{}
		port{v='pstn_tail'}
	end}

	-- PSCN placer to activate PSTN where BRAY is annihilated
	local function make_pscn_placer(p, ss_to_right)
		chain{dx=1, p=p, f=function()
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
		end}
	end

	port{v='pscn_placer_wbnd', p=v('pscnrow_e'):right(2)}
	if opts.detach_pscn_placer then
		port{v='make_pscn_placer', f=function(opts)
			make_pscn_placer(findpt{ns=opts.p, ei=v('pscn_placer_wbnd')}, true)
		end}
	else
		make_pscn_placer(v('pscn_placer_wbnd'), false)
	end

	-- addr_in feed into addr row
	port{v='ldtc_target', p=findpt{n=v('pstn_target'), w=v('addrrow_w')}}
	chain{dx=1, p=v('ldtc_target'):right(), f=function()
		while not getcurs():eq(v('addrrow_w')) do
			filt{}
		end
	end}

	-- setter mechanism for APOM
	port{v='cray_target', p=findpt{n=v('pstn_target'), w=v('pscnrow_w')}}
	port{v='apom_setter_s', p=findpt{n=v('cray_target'), w=v('arayrow_w')}}
	chain{dy=-1, p=v('apom_setter_s'), f=function()
		port{v='apom_insl_s'}
		insl{} -- holds the LDTC's ID
		port{v='apom_insl_n'}
		insl{} -- holds the CRAY's ID
		pstn{r=opts.n - cum_piston_r}
		cray{r=num_segs, from=v('cray_target'), to=v('pscnrow_w')}

		port{v='apom_pstn_id_grabber_loc'}
		cray{r=1, v='apom_pstn_id_grabber', done=0}
		cray{s=v('apom_insl_n'), r=2, done=0}
		cray{r=1, v='apom_ldtc_maker', ct='ldtc', to=v('ldtc_target'), done=0}
		dray{r=2, tos=v('cray_target'), done=0}
		schem{f=ssconv, ox=1, t='pscn'}
		pscn{sprk=1}
	end}

	-- Config port for the addr_in reader.
	-- This is complicated by the fact that the LDTC is created by a CRAY
	-- through APOM. The LDTC's skip distance is configured through its
	-- life, which is set by the CRAY's life.
	port{v='addr_in', p=v('ldtc_target'):left(2), done=0, f=function(opts)
		v('apom_ldtc_maker').life = get_orth_dist(v('ldtc_target'), opts.p) - 1
	end}

	-- sparker for the APOM'ed CRAY
	chain{p=v('cray_target'):left(), f=function()
		schem{f=ssconv, t='pscn', done=0}
		pscn{sprk=1}
	end}

	-- resetter mechanism for APOM
	local function make_apom_resetter(p, is_detached)
		v('apom_pstn_id_grabber').tmp2 =
			get_orth_dist(v('apom_pstn_id_grabber_loc'), p) - 1

		if is_detached then
			port{v='retractor_sparker', p=v('pstn_target'):down()}
			-- The retractor sparker must be positioned differently if
			-- the APOM resetter is detached.
			-- NSCN must be sparked only after retraction, so don't ssconv here.
			nscn{sprk=1, p=v('retractor_sparker')}
		end

		-- actual resetter mechanism
		chain{dy=1, p=p, f=function()
			insl{} -- holds the PSTN's ID
			if is_detached then
				-- respark retractor sparker as well
				cray{r=2, s=v('retractor_sparker'), done=0}
				dray{r=2, tos=v('cray_target'), done=0}
				cray{s=v('apom_insl_s'), r=2, ct='insl', done=0}
				cray{s=p, r=1, ct='insl', done=0}
				cray{r=1, to=v('retractor_sparker'), ct='nscn'}

				cray{ct='sprk', r=1, to=v('retractor_sparker'), done=0}
				pscn{sprk=1}

				schem{f=ssconv, t='pscn', done=0}
				inwr{sprk=1}

				schem{f=ssconv, t='inwr'}
			else
				cray{r=1, to=v('pstn_target'), done=0}
				dray{r=2, tos=v('cray_target'), done=0}
				cray{s=v('apom_insl_s'), r=2, ct='insl', done=0}
				cray{s=p, r=1, ct='insl'}

				pscn{sprk=1}
				-- put the ssconv below since the earlier space is used
				-- for the retractor sparker
				schem{f=ssconv, t='pscn'}
			end
		end}
	end

	port{v='apom_resetter_nbnd', p=v('pstn_target'):down()}
	if opts.detach_apom_resetter then
		-- allow piston to be retracted later
		port{v='make_apom_resetter', f=function(opts)
			-- need to leave enough space for the resetter PSTN sparker
			make_apom_resetter(
				findpt{ew=opts.p, si=v('apom_resetter_nbnd'):down(2)}, true
			)
		end}
	else
		make_apom_resetter(v('apom_resetter_nbnd'), false)

		-- spark retractor PSTN
		chain{dy=1, p=v('pstn_target'):down(2), f=function()
			nscn{sprk=1}
			schem{f=ssconv, t='nscn', under=1}
		end}
	end
end

local function fram1d_reader(opts)
	schem{
		f=pstn_demux_e,
		v='demux',
		detach_pscn_placer=1,
	}
	port_alias{from='demux.addr_in', to='addr_in'}
	chain{dx=1, p=v('demux.pstn_head'), f=function()
		frme{done=0}
		frme{oy=1}

		-- we're adding a frame, so the actual piston head is one further
		port{v='pstn_head'}
		port{v='data_out', oy=1}
		ldtc{r=1, j=1, done=0}
		filt{oy=1}
	end}

	port{v='make_pscn_placer', f=function(opts)
		connect{v='demux.make_pscn_placer', p=opts.p}
	end}
end

function from1d_32(opts)
	if opts.init_data == nil then
		opts.init_data = {}
		for i = 1, 32 do
			table.insert(opts.init_data, ka)
		end
	end

	port{v='data_w'}
	array{n=32, dx=1, f=function(i)
		if i == 32 then port{v='data_e'} end
		filt{ct=opts.init_data[i]}
	end}

	port{v='io_min_y', p=v('data_w'):down(2)}
	port{v='make_reader', f=function(opts)
		if opts.name == nil then opts.name = 'reader' end
		schem{
			f=fram1d_reader,
			v=opts.name,
			p=findpt{s=v('data_w'):down(), ew=opts.p},
			ref='pstn_head',
		}
		port{v=opts.name .. '_pscn_placer', p=v('data_e'):right()}
		connect{v=opts.name .. '.make_pscn_placer', p=v('data_e'):right()}
		port_alias{from=opts.name .. '.addr_in', to='raddr_in'}
		port_alias{from=opts.name .. '.data_out', to='rdata_out'}
	end}
end
