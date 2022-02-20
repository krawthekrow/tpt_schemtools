require('schem/stdlib/core')
require('schem/stdlib/fram1d')

local function spu56_rmask_demux(opts)
	-- opts.extension_map maps input bit offsets to piston extensions
	if opts.extension_map == nil then
		opts.extension_map = {}
		local i = 1
		while true do
			local extension = 2 * shl(1, i-1)
			if extension >= 56 * 2 then break end
			opts.extension_map[i-1] = 2 * shl(1, i-1)
			i = i + 1
		end
	end
	local bit_offs = Util.tbl_keys(opts.extension_map)
	local num_segs = #bit_offs

	-- bit checking logic
	array{n=num_segs, dx=1, f=function(i)
		chain{dx=-1, dy=1, f=function()
			inwr{sprk=1}
			if i == 1 then port{v='arayrow_w'} end
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; schem{f=ssconv, t='inwr'}
			filt{mode='set', ct=shl(1, bit_offs[i])}
			if i == 1 then port{v='addrrow_w'} end
			filt{mode='sub'}
			if i == 1 then port{v='pscnrow_w'} end
			if i == num_segs then port{v='pscnrow_e'} end
			insl{}
		end}
	end}

	local cum_piston_r = -1
	-- piston, binary section
	chain{dx=1, p=v('pscnrow_w'):down(), f=function()
		-- each PSTN's pushing power includes all the PSTNs in front of it,
		-- so subtract the accumulated pushing power from the target
		-- pushing power
		for i = 1, num_segs do
			if i == 1 then port{v='pstn_bin_w'} end
			if i == num_segs then port{v='pstn_bin_e'} end
			local target_r = opts.extension_map[bit_offs[i]]
			pstn{r=target_r - cum_piston_r, ct='dmnd'}
			cum_piston_r = target_r
		end
		port{v='pstn_tail'}

		setv('piston_r', cum_piston_r)
	end}

	port{v='pstn_head', p=v('pstn_bin_w'):left()}

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
	port{v='make_pscn_placer', f=function(opts)
		make_pscn_placer(findpt{ns=opts.p, ei=v('pscn_placer_wbnd')}, true)
	end}

	-- TODO: Create LDTC feed and APOM'ed CRAY.
	-- May be better to extend piston arm and place it right next
	-- to the demux instead of detaching them.
end

local function spu56_hshift_demux(opts)
	-- opts.extension_map maps input bit offsets to piston extensions
	if opts.extension_map == nil then
		opts.extension_map = {}
		local i = 1
		while true do
			local extension = 2 * shl(1, i-1)
			if extension >= 56 * 2 then break end
			opts.extension_map[i-1] = 2 * shl(1, i-1)
			i = i + 1
		end
	end
	local bit_offs = Util.tbl_keys(opts.extension_map)
	local num_segs = #bit_offs
	local extension_map = opts.extension_map

	-- bit checking logic
	array{n=num_segs, dx=1, f=function(i)
		chain{dx=-1, dy=1, f=function()
			inwr{sprk=1}
			if i == 1 then port{v='arayrow_w'} end
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; schem{f=ssconv, t='inwr'}
			filt{mode='set', ct=shl(1, bit_offs[i])}
			if i == 1 then port{v='addrrow_w'} end
			if i == num_segs then port{v='addrrow_e'} end
			filt{mode='and'}
			if i == 1 then port{v='pstnrow_w'} end
			if i == num_segs then port{v='pstnrow_e'} end
			insl{}
			insl{}
		end}
	end}

	port{v='pstn_head', p=v('pstnrow_w'):left()}
	port{v='pstn_tail', p=v('pstnrow_e'):right()}

	port{v='make_pstn_placer', f=function(opts)
		port{v='pstn_placer_e', p=findpt{ns=opts.p, w=v('pstnrow_w')}}

		chain{dx=-1, p=v('pstn_placer_e'), f=function()
			-- the PSTNs are placed in reverse
			for i = 1, num_segs do
				pstn{r=extension_map[bit_offs[num_segs - i + 1]]}
			end

			dray{r=num_segs, tos=v('pstnrow_w')}
			inwr{sprk=1}
			adv{}
			cray{
				ct='pstn', temp=Util.CELSIUS_BASE,
				r=num_segs, to=v('pstnrow_w'),
			}
			pscn{sprk=1}
		end}
	end}
end

local function spu56_rmask_hshift_demux(opts)
	chain{dx=1, f=function()
		port{v='inslcol_s'}
		insl{}
		frme{oy=-1, done=0}; frme{}
		pstn{r=0, done=0}
		port{v='rmask_demux_head'}
	end}

	schem{
		f=spu56_rmask_demux,
		v='rmask_demux',
		p=v('rmask_demux_head'),
		ref='pstn_head',
	}

	local cum_piston_r = v('rmask_demux.piston_r')

	schem{
		f=spu56_hshift_demux,
		v='hshift_demux',
		p=v('rmask_demux.pstn_tail'):left(),
		ref='pstn_head',
	}

	port{v='make_left_modules', f=function(opts)
		-- TODO: temporary configuration
		connect{v='hshift_demux.make_pstn_placer', p=opts.p}
	end}

	-- TODO: temporary position
	connect{
		v='rmask_demux.make_pscn_placer',
		p=v('hshift_demux.addrrow_e'):right()
	}
end

function spu56()
	local rowlen = 56 * 2
	array{n=rowlen, dx=1, f=function(i)
		chain{dx=-1, dy=-1, f=function()
			inwr{sprk=1}
			if i == 1 then port{v='arayrow_w'} end
			aray{done=0}
			schem{f=ssconv, t='inwr'}
			filt{mode='set'}
			if i == 1 then port{v='shiftrow1_w'} end
			filt{}
			if i == 1 then port{v='shiftrow2_w'} end
			filt{}
			if i == 1 then port{v='androw_w'} end
			filt{mode='and'}
			if i == 1 then port{v='brayrow1_w'} end
			if i == rowlen then port{v='brayrow1_e'} end
			adv{}
			adv{}
			insl{}
		end}
	end}

	-- TODO: temporary position
	schem{
		f=pstn_demux_e,
		v='lmask_demux',
		ref='pstn_head',
		p=v('brayrow1_w'):left(7),
		detach_apom_resetter=1,
	}
	-- TODO: temporary input
	port{v='lmask_in', p=v('lmask_demux.addr_in')}
	filt{p=v('lmask_in'), ct=bor(ka, 5)}

	-- only retract the piston after ARAYs have been fired
	connect{v='lmask_demux.make_apom_resetter', p=v('arayrow_w'):down()}

	chain{dx=-1, p=v('brayrow1_w'):left(), f=function()
		frme{sticky=0}
		while not getcurs():eq(v('lmask_demux.pstn_head'):left()) do
			pstn{r=0}
		end
	end}

	schem{
		f=spu56_rmask_hshift_demux,
		v='rmask_hshift_demux',
		ref='inslcol_s',
		p=v('brayrow1_e'):right(),
	}
	-- TODO: temporary position
	connect{
		v='rmask_hshift_demux.make_left_modules',
		p=v('lmask_demux.pstn_tail')
	}

	-- The BRAYs appear with the following pattern:
	-- ABCDEF...
	--  ABCDEF...
	--
	-- Even shifts require: ABCDEF...
	-- Odd shifts require:  BADCFE...
	--
	-- Target pattern for even shifts:
	--  ABCDEF...
	--  ABCDEF...
	--
	-- Target pattern for odd shifts:
	-- ABCDEF...
	--   ABCDEF...
	--
	-- Even shifts: shift top row right by one
	-- Odd shifts: shift bottom row right by one

	-- LSH mode: OR then <<<
	-- RSH mode: >>> then XOR
	chain{dx=-1, p=v('shiftrow1_w'):left(), f=function()
	end}

	chain{dx=-1, p=v('shiftrow2_w'):left(), f=function()
	end}
end

