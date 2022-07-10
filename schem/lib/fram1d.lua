require('schem/lib/core')

function pstn_demux_e(opts)
	opts = opts_bool(opts, 'detach_pscn_placer', false)
	opts = opts_bool(opts, 'detach_apom_resetter', false)
	opts = opts_bool(opts, 'omit_front_pstn', false)
	opts = opts_bool(opts, 'omit_back_dmnd', false)
	if opts.n == nil then opts.n = 32 end

	-- opts.extension_map maps input bit offsets to piston extensions
	if opts.extension_map == nil then
		opts.extension_map = {}
		local i = 1
		while true do
			local extension = shl(1, i-1)
			if extension >= opts.n then break end
			opts.extension_map[i-1] = extension
			i = i + 1
		end
	end
	local bit_offs = Util.tbl_keys(opts.extension_map)
	local num_segs = #bit_offs

	local max_extension = 0
	for _, extension in pairs(opts.extension_map) do
		max_extension = max_extension + extension
	end

	-- bit checking logic
	array{n=num_segs, dx=-1, f=function(i)
		chain{dx=-1, dy=1, f=function()
			inwr{sprk=1}
			aport{v='arayrow'}
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; ssconv{t='inwr'}
			filt{mode='set', ct=shl(1, bit_offs[i])}
			aport{v='addrrow'}
			filt{mode='sub'}
			aport{v='pscnrow'}
			insl{}
		end}
	end}

	local cum_piston_r = -1
	-- piston, binary section
	chain{dx=-1, p=v('pscnrow'):e():s(), f=function()
		-- each PSTN's pushing power includes all the PSTNs in front of it,
		-- so subtract the accumulated pushing power from the target
		-- pushing power
		for i = 1, num_segs do
			aport{v='pstn_bin'}
			local target_r = opts.extension_map[bit_offs[i]]
			local pstn_r = target_r - cum_piston_r
			setv('pstn_bin_r_' .. i, pstn_r)
			pstn{r=pstn_r, ct='dmnd', v='pstn_bin_' .. i}
			cum_piston_r = target_r
		end
	end}

	-- piston front
	chain{dx=1, p=v('pstn_bin'):e():e(), f=function()
		if not opts.omit_front_pstn then
			pstn{r=0}
		end
		port{v='pstn_head'}
	end}

	-- piston back
	chain{dx=-1, p=v('pstn_bin'):w():w(), f=function()
		port{v='pstn_target'}
		adv{}
		if not opts.omit_back_dmnd then
			dmnd{}
		end
		port{v='pstn_tail'}
	end}

	-- PSCN placer to activate PSTN where BRAY is annihilated
	local function make_pscn_placer(p, ss_to_right)
		chain{dx=1, p=p, f=function()
			pscn{sprk=1, done=0}
			if ss_to_right then
				ssconv{t='pscn', ox=1, oy=1}
			else
				ssconv{t='pscn', ox=-1, oy=1, under=1}
			end
			adv{}
			stacked_dray{off=1, r=1, to=v('pscnrow')}
			ssconv{t='inwr', done=0}
			port{v='pscn_placer_e'}
			inwr{sprk=1}
		end}
	end

	port{v='pscn_placer_wbnd', p=v('pscnrow'):e():e(2)}
	if opts.detach_pscn_placer then
		port{v='make_pscn_placer', f=function(opts)
			make_pscn_placer(findpt{ns=opts.p, ei=v('pscn_placer_wbnd')}, true)
		end}
	else
		make_pscn_placer(v('pscn_placer_wbnd'), false)
	end

	-- addr_in feed into addr row
	port{v='ldtc_target', p=findpt{n=v('pstn_target'), w=v('addrrow'):w()}}
	array{
		from=v('ldtc_target'):e(), to=v('addrrow'):w():w(),
		f=function() filt{} end
	}

	-- setter mechanism for APOM
	port{v='cray_target', p=findpt{n=v('pstn_target'), w=v('pscnrow'):w()}}
	port{v='apom_setter_s', p=findpt{n=v('cray_target'), w=v('arayrow'):w()}}
	chain{dy=-1, p=v('apom_setter_s'), f=function()
		aport{v='apom_insl'}
		insl{} -- holds the LDTC's ID
		aport{v='apom_insl'}
		insl{} -- holds the CRAY's ID
		pstn{r=max_extension - cum_piston_r, v='resetter_pstn'}
		cray{r=num_segs, from=v('cray_target'), to=v('pscnrow'):w()}

		cray{v='apom_pstn_id_grabber', done=0}
		cray{to=v('apom_insl'), done=0}
		cray{v='apom_ldtc_maker', ct='ldtc', to=v('ldtc_target'), done=0}
		dray{r=2, tos=v('cray_target'), done=0}
		ssconv{ox=1, t='pscn'}
		pscn{sprk=1}
	end}

	-- Config port for the addr_in reader.
	-- This is complicated by the fact that the LDTC is created by a CRAY
	-- through APOM. The LDTC's skip distance is configured through its
	-- life, which is set by the CRAY's life.
	port{v='addr_in', p=v('ldtc_target'):w(2), done=0, f=function(opts)
		v('apom_ldtc_maker').life = odist(v('ldtc_target'), opts.p) - 1
	end}

	-- sparker for the APOM'ed CRAY
	chain{p=v('cray_target'):w(), f=function()
		ssconv{t='pscn', done=0}
		pscn{sprk=1}
	end}

	-- resetter mechanism for APOM
	local function make_apom_resetter(p, is_detached)
		pconfig{part=v('apom_pstn_id_grabber'), to=p}

		if is_detached then
			port{v='retractor_sparker', p=v('pstn_target'):s()}
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
				cray{to=v('apom_insl'), ct='insl', done=0}
				cray{to=p, ct='insl', done=0}
				cray{to=v('retractor_sparker'), ct='nscn'}

				cray{ct='sprk', to=v('retractor_sparker'), done=0}
				pscn{sprk=1}

				ssconv{t='pscn', done=0}
				inwr{sprk=1}

				ssconv{t='inwr'}
			else
				cray{to=v('pstn_target'), done=0}
				dray{r=2, tos=v('cray_target'), done=0}
				cray{to=v('apom_insl'), ct='insl', done=0}
				cray{to=p, ct='insl'}

				pscn{sprk=1}
				-- put the ssconv below since the earlier space is used
				-- for the retractor sparker
				ssconv{t='pscn'}
			end
		end}
	end

	port{v='apom_resetter_nbnd', p=v('pstn_target'):s()}
	if opts.detach_apom_resetter then
		-- allow piston to be retracted later
		port{v='make_apom_resetter', f=function(opts)
			-- need to leave enough space for the resetter PSTN sparker
			make_apom_resetter(
				findpt{ew=opts.p, si=v('apom_resetter_nbnd'):s(2)}, true
			)
		end}
	else
		make_apom_resetter(v('apom_resetter_nbnd'), false)

		-- spark retractor PSTN
		chain{dy=1, p=v('pstn_target'):s(2), f=function()
			nscn{sprk=1}
			ssconv{t='nscn', under=1}
		end}
	end
end

local function fram1d_reader(opts)
	schem{
		f=pstn_demux_e,
		v='demux',
		detach_pscn_placer=1,
	}
	port_alias{from='demux.addr_in'}
	chain{dx=1, p=v('demux.pstn_head'), f=function()
		frme{done=0}
		frme{oy=1}

		-- we're adding a frame, so the actual piston head is one further
		port{v='pstn_head'}
		port{v='data_out', oy=1}
		ldtc{j=1, done=0}
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

	array{n=32, dx=1, f=function(i)
		aport{v='data_block'}
		filt{ct=opts.init_data[i]}
	end}

	port{v='io_min_y', p=v('data_block'):w():s(2)}
	port{v='make_reader', f=function(opts)
		if opts.name == nil then opts.name = 'reader' end
		schem{
			f=fram1d_reader,
			v=opts.name,
			p=findpt{s=v('data_block'):w():s(), ew=opts.p},
			ref='pstn_head',
		}
		port{v=opts.name .. '_pscn_placer', p=v('data_block'):e():e()}
		connect{
			v=opts.name .. '.make_pscn_placer',
			p=v('data_block'):e():e()
		}
		port_alias{from=opts.name .. '.addr_in', to='raddr_in'}
		port_alias{from=opts.name .. '.data_out', to='rdata_out'}
	end}
end
