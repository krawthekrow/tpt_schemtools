require('schem/lib/core')
require('schem/lib/fram1d')

local function build_extension_map(start_off)
	local extension_map = {}
	local i = 1
	while true do
		local extension = 2 * shl(1, i-1)
		if extension >= 56 * 2 then break end
		extension_map[start_off + i-1] = extension
		i = i + 1
	end
	return extension_map
end

local function spu56_rmask_demux(opts)
	-- opts.extension_map maps input bit offsets to piston extensions
	if opts.extension_map == nil then
		opts.extension_map = build_extension_map(0)
	end
	local bit_offs = Util.tbl_keys(opts.extension_map)
	local num_segs = #bit_offs

	-- bit checking logic
	array{n=num_segs, dx=1, f=function(i)
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
	chain{dx=1, p=v('pscnrow'):w():down(), f=function()
		-- each PSTN's pushing power includes all the PSTNs in front of it,
		-- so subtract the accumulated pushing power from the target
		-- pushing power
		for i = 1, num_segs do
			aport{v='pstn_bin'}
			local target_r = opts.extension_map[bit_offs[i]]
			local pstn_r = target_r - cum_piston_r
			if i == 1 then setv('first_pstn_r', pstn_r) end
			pstn{r=pstn_r, ct='dmnd'}
			cum_piston_r = target_r
		end
		port{v='pstn_tail'}

		setv('piston_r', cum_piston_r)
	end}

	-- PSCN placer to activate PSTN where BRAY is annihilated
	local function make_pscn_placer(p)
		chain{dx=1, p=p, f=function()
			ssconv{t='pscn', oy=1, under=1, done=0}
			pscn{sprk=1}
			pscn{sprk=1}
			adv{}
			stacked_dray{off=1, r=2, to=v('pscnrow')}
			ssconv{t='inwr', done=0}
			port{v='pscn_placer_e'}
			inwr{sprk=1}
		end}
	end

	port{v='pscn_placer_wbnd', p=v('pscnrow'):e():right(2)}
	port{v='make_pscn_placer', f=function(opts)
		make_pscn_placer(findpt{ns=opts.p, ei=v('pscn_placer_wbnd')})
	end}

	-- set up APOM'ed CRAY sparker
	chain{dx=-1, p=v('pscnrow'):w():left(), f=function()
		port{v='cray_target'}
		adv{}
		ssconv{t='pscn', done=0}
		port{v='apom_wbnd'}
		pscn{sprk=1}
	end}

	-- set up addr_in feed
	port{v='ldtc_target', p=findpt{n=v('cray_target'), w=v('addrrow'):w()}}
	array{
		from=v('addrrow'):w():left(), to=v('ldtc_target'):right(),
		f=function() filt{} end,
	}

	-- setter mechanism for APOM
	port{v='apom_setter_s', p=findpt{w=v('arayrow'):w(), n=v('ldtc_target')}}
	chain{dy=-1, p=v('apom_setter_s'), f=function()
		aport{v='apom_insl'}
		insl{} -- holds the LDTC's ID
		aport{v='apom_insl'}
		insl{} -- holds the CRAY's ID
		cray{from=v('cray_target'), to=v('pscnrow')}

		cray{to=v('apom_insl'), done=0}
		cray{v='apom_ldtc_maker', ct='ldtc', to=v('ldtc_target'), done=0}
		dray{to=v('cray_target'), done=0}
		ssconv{t='pscn'}
		pscn{sprk=1}
	end}

	-- resetter mechanism
	port{
		v='apom_resetter_n',
		p=findpt{s=v('cray_target'), ew=v('pstn_bin'):w():down()}
	}
	chain{dy=1, p=v('apom_resetter_n'), f=function()
		-- leave space to DRAY over the CRAY
		adv{}
		dray{to=v('cray_target'), done=0}
		cray{to=v('ldtc_target'), done=0}
		cray{to=v('apom_insl'), ct='insl'}
		ssconv{t='pscn', done=0}
		pscn{sprk=1}
	end}

	port{v='pstn_head', p=v('pstn_bin'):w():left()}
end

local function spu56_hshift_demux(opts)
	opts = opts_bool(opts, 'omit_bray_blocker', false)
	-- opts.extension_map maps input bit offsets to piston extensions
	if opts.extension_map == nil then
		opts.extension_map = build_extension_map(0)
	end
	local bit_offs = Util.tbl_keys(opts.extension_map)
	local num_segs = #bit_offs
	local extension_map = opts.extension_map

	-- bit checking logic
	array{n=num_segs, dx=1, f=function(i)
		chain{dx=-1, dy=1, f=function()
			inwr{sprk=1}
			aport{v='arayrow'}
			-- we want the BRAY to persist to the next frame so that the
			-- resetter CRAY always deletes the same number of particles
			aray{life=2, done=0}; ssconv{t='inwr'}
			aport{v='addrrow'}
			filt{mode='set'}
			aport{v='androw'}
			filt{mode='and', ct=shl(1, bit_offs[i])}
			aport{v='pstnrow'}
			insl{}
			aport{v='bray_blocker'}
			if not opts.omit_bray_blocker then insl{} end
		end}
	end}

	port{v='pstn_head', p=v('pstnrow'):w():left()}
	port{v='pstn_tail', p=v('pstnrow'):e():right()}

	-- The PSTN placer has three steps:
	-- Clearing step: PSTNs from the previous frame are cleared.
	-- Inverting step: r=0 PSTNs are placed in empty spaces while BRAYs
	-- are deleted.
	-- Filling step: binary-r PSTNs are placed in the now empty spaces
	-- (previously BRAYs).
	port{v='make_pstn_placer', f=function(opts)
		port{v='pstn_placer_e', p=findpt{ns=opts.p, w=v('pstnrow'):w()}}

		chain{dx=-1, p=v('pstn_placer_e'), f=function()
			-- the PSTNs are placed in reverse
			for i = 1, num_segs do
				aport{v='filler_template'}
				pstn{r=extension_map[bit_offs[num_segs - i + 1]]}
			end

			dray{to=v('pstnrow'), done=0}
			ssconv{t='inwr', oy=1}
			port{v='pstn_filler_w'}
			inwr{sprk=1}
		end}

		chain{dx=-1, p=v('pstn_filler_w'), f=function()
			cray{
				ct='pstn', temp=Util.CELSIUS_BASE,
				to=v('pstnrow'),
				under=1, done=0,
			}
			ssconv{t='pscn', oy=1}
			port{v='pstn_inverter_w'}
			pscn{sprk=1}

			dmnd{}
			port{v='cray_target'}
			port{
				v='resetter_apom_s',
				p=findpt{n=v('cray_target'), w=v('arayrow'):w()}
			}
			chain{dy=-1, p=v('resetter_apom_s'), done=0, f=function()
				port{v='apom_cray_id_holder'}
				insl{}
				cray{from=v('cray_target'), to=v('pstnrow')}
				cray{to=v('apom_cray_id_holder'), done=0}
				dray{to=v('cray_target'), done=0}
				ssconv{t='pscn'}
				pscn{sprk=1}
			end}
			chain{dy=1, oy=1, f=function()
				adv{}
				dray{to=v('cray_target'), done=0}
				cray{ct='insl', to=v('apom_cray_id_holder'), done=0}
				ssconv{t='pscn'}
				pscn{sprk=1}
			end}
			ssconv{t='pscn', done=0}
			port{v='pstn_placer_w'}
			pscn{sprk=1}
		end}
	end}
end

local function spu56_rmask_hshift_demux(opts)
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
	--   ABCDEF...
	-- ABCDEF...
	--
	-- Optionally offset the BRAY rows by adding two INSLs to the
	-- piston head's second row and changing extension by two.
	--
	-- In total, this setup carries out four steps:
	-- 1. Retract the piston fully to reset.
	-- 2. Extend the rmask.
	-- 3. After the ARAYs fire, extend the piston all the way.
	-- 4. Retract according to hshift.

	port{v='brayrow_e'}
	chain{dx=1, p=v('brayrow_e'):right(), f=function()
		port{v='opt_insl_w'}
		insl{}
		port{v='opt_insl_e'}
		insl{}
		frme{oy=-1, done=0}; frme{}
		pstn{r=0}
		port{v='rmask_demux_head'}
		port{v='opt_pstn'}
		pstn{r=0, ct='dmnd', done=0} -- to be optionally replaced by r=2 PSTN
	end}

	schem{
		f=spu56_rmask_demux,
		v='rmask_demux',
		p=v('rmask_demux_head'),
		ref='pstn_head',
	}
	local cum_piston_r = v('rmask_demux.piston_r')

	-- sparker for optional offset PSTN
	-- will be resparked by the APOM mechanism from rmask_demux
	pscn{sprk=1, p=v('opt_pstn'):down(2)}

	-- Bottom row starts offset right by one, and may end up offset left
	-- by two using two INSLs for alignment. This means that we might
	-- need to push three pixels more than the row length, or two INSLs
	-- extra.
	local max_extension = 56 * 2 + 3
	local max_load = 56 * 2 + 2
	chain{dx=1, p=v('rmask_demux.pstn_tail'), f=function()
		port{v='extender_pstn_target'}
		port{v='extender_sparker', oy=-1}
		pscn{sprk=1, p=v('extender_sparker'), done=0}
		-- TODO: manual temporary position
		-- APOM setter for the extender PSTN
		chain{dy=-1, oy=-6, f=function()
			-- push as far as possible, including possible offset by three
			pstn{r=max_extension - cum_piston_r, cap=max_load, ct='dmnd'}
			cum_piston_r = max_extension
			cray{v='extender_pstn_id_grabber', done=0}
			dray{to=v('extender_pstn_target'), done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
		end}

		port{v='retractor_pstn_target'}
		-- APOM setter for the retractor PSTN
		chain{dx=1, dy=-1, ox=1, oy=-1, f=function()
			port{v='retractor_pstn_id_holder'}
			insl{}
			adv{} -- make space for temporary FILT feed into hshift addr_in
			-- retract as far as possible, using extension from the extender
			pstn{r=0, ct='crmc', cap=max_load}
			cray{to=v('retractor_pstn_id_holder'), done=0}
			dray{to=v('retractor_pstn_target'), done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
		end}

		-- cancel the lmask piston extensions so that hshift extension
		-- reflects the value sent into hshift_demux
		while true do
			if cum_piston_r <= 27 then
				port{v='hshift_demux_head'}
				pstn{r=-cum_piston_r}
				cum_piston_r = 0
				break
			end
			pstn{r=-27}
			cum_piston_r = cum_piston_r - 27
		end
	end}

	schem{
		f=spu56_hshift_demux,
		v='hshift_demux',
		p=v('hshift_demux_head'),
		ref='pstn_head',
	}
	-- TODO: temporarily share addr_in for rmask and hshift
	array{
		from=v('rmask_demux.addrrow'):e():right(),
		to=v('hshift_demux.addrrow'):w():left(),
		f=function() filt{} end,
	}

	-- APOM to perform the hshift retraction
	chain{dx=1, p=v('hshift_demux.pstn_tail'), f=function()
		-- INSL is necessary to block the CONV from the PSCN placer
		port{v='hshift_pstn_target'}; insl{done=0}
		port{v='conv_blocker_id_holder', ox=-1, oy=1}
		nscn{sprk=1, oy=2, done=0}
		setv('hshift_pstn_r', -cum_piston_r)
		-- APOM setter for the hshift PSTN
		chain{dx=1, dy=-1, ox=2, oy=-2, f=function()
			pstn{r=v('hshift_pstn_r'), ct='crmc', cap=max_load}
			-- move the INSL to conv_blocker_id_holder
			cray{r=2, to=v('hshift_pstn_target'), ct='insl', done=0}
			cray{v='hshift_pstn_id_grabber', done=0}
			dray{to=v('hshift_pstn_target'), done=0}
			-- prevent resparker from resparking ARAY activators
			ssconv{t='pscn', ox=2}
			pscn{sprk=1}
		end}
		cum_piston_r = 0

		dmnd{}
	end}

	-- APOM resetters for hshift, extender and retractor PSTNs
	-- connect position should be ARAY row
	port{v='make_apom_resetter', f=function(opts)
		-- TODO: temporary positions

		-- this needs to be after piston has been extended
		setv(
			'apom_hshift_pstn_ne',
			findpt{ew=opts.p:down(), sw=v('hshift_pstn_target')}
		)
		chain{dx=-1, dy=1, p=v('apom_hshift_pstn_ne'), f=function()
			port{v='hshift_pstn_id_holder'}
			insl{}
			pconfig{
				part=v('hshift_pstn_id_grabber'),
				to=v('hshift_pstn_id_holder')
			}
			cray{to=v('hshift_pstn_target'), done=0}
			cray{to=v('hshift_pstn_id_holder'), ct='insl', done=0}
			-- move the INSL back
			cray{r=2, to=v('conv_blocker_id_holder'), ct='insl', done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
		end}

		-- this needs to be after the lmask PSTN has retracted
		setv(
			'apom_extender_pstn_n',
			findpt{ew=opts.p:down(), s=v('extender_pstn_target')}
		)
		chain{dy=1, p=v('apom_extender_pstn_n'), f=function()
			port{v='extender_pstn_id_holder'}
			insl{}
			pconfig{
				part=v('extender_pstn_id_grabber'),
				to=v('extender_pstn_id_holder')
			}
			cray{to=v('extender_pstn_target'), done=0}
			cray{to=v('extender_pstn_id_holder'), ct='insl', done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
		end}

		-- This needs to be before lmask/rmask extends.
		-- The PSTN can only be cleared after the hshift step since
		-- it is necessary to form a contiguous piston.
		setv(
			'apom_retractor_pstn_n',
			findpt{ew=opts.p:down(2), sw=v('retractor_pstn_target')}
		)
		chain{dx=-1, dy=1, p=v('apom_retractor_pstn_n'), f=function()
			cray{to=v('retractor_pstn_target'), done=0}
			cray{to=v('retractor_pstn_id_holder'), ct='insl', done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
		end}
	end}

	-- leave it to parent to make pscn placer, in order to combine
	-- with the pscn placer for the lmask demux
	port_alias{from='rmask_demux.pscnrow', to='rmask_pscnrow'}
	port{v='pscn_placer_wbnd', p=v('hshift_demux.androw'):e():right()}

	-- TODO: reset opt_pstn

	port{v='make_left_modules', f=function(opts)
		connect{
			v='hshift_demux.make_pstn_placer', p=opts.p,
		}
		port_alias{from='hshift_demux.filler_template'}

		-- optionally offset BRAY rows
		chain{dx=-1, p=v('hshift_demux.pstn_placer_w'):left(), f=function()
			local offset_amount = 2
			pstn{
				r=v('rmask_demux.first_pstn_r') - (offset_amount + 1),
				ct='dmnd'
			}
			pstn{r=offset_amount + 1, ct='dmnd'}
			cray{s=v('opt_insl_w'), e=v('opt_insl_e'), done=0}
			dray{r=2, tos=v('opt_pstn'), done=0}
			ssconv{t='pscn'}
			pscn{sprk=1}
			dmnd{}
		end}
	end}
end

function spu56()
	local rowlen = 56 * 2
	array{n=rowlen, dx=1, f=function(i)
		chain{dx=-1, dy=-1, f=function()
			inwr{sprk=1}
			aport{v='arayrow'}
			aray{done=0}
			ssconv{t='inwr'}
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

	chain{dx=-1, p=v('brayrow1_w'):left(), f=function()
		-- leave space as we may need to offset the bottom row left by three
		adv{n=3}
		-- prevent retraction from pulling BRAYs along with it
		crmc{}
		pstn{r=0}
		port{v='lmask_demux_pstn_head'}
		-- extend three extra to cover offset space
		pstn{r=3+1, ct='dmnd', done=0}
		pscn{sprk=1, oy=-1, done=0}
		ssconv{t='pscn', ox=1, under=1}
	end}

	schem{
		f=pstn_demux_e,
		v='lmask_demux',
		ref='pstn_head',
		p=v('lmask_demux_pstn_head'),
		extension_map=build_extension_map(0),
		detach_apom_resetter=1,
		detach_pscn_placer=1,
		omit_front_pstn=1,
		omit_back_dmnd=1,
	}
	-- TODO: temporary input
	port{v='lmask_in', p=v('lmask_demux.addr_in')}
	filt{p=v('lmask_in'), ct=bor(ka, 5)}

	-- only pull back the CRMC
	pconfig{part=v('lmask_demux.resetter_pstn'), cap=1}
	-- only retract the piston after the ARAYs have been fired
	connect{v='lmask_demux.make_apom_resetter', p=v('arayrow'):w():down()}
	-- compensate for offset space
	pconfig{
		part=v('lmask_demux.pstn_bin_1'),
		r=v('lmask_demux.pstn_bin_r_1') - (3+1),
	}

	schem{
		f=spu56_rmask_hshift_demux,
		v='rmask_hshift_demux',
		ref='brayrow_e',
		p=v('brayrow1_e'),
	}
	connect{
		v='rmask_hshift_demux.make_left_modules',
		p=v('lmask_demux.pstn_tail')
	}
	connect{
		v='rmask_hshift_demux.make_apom_resetter',
		p=v('arayrow'):w(),
	}
	-- block the lmask PSTN from here instead
	dmnd{p=v('rmask_hshift_demux.filler_template'):w():left()}

	-- combined PSCN placer for both lmask and rmask demuxes
	chain{dx=1, p=v('rmask_hshift_demux.pscn_placer_wbnd'), f=function()
		conv{from='sprk', to='pscn', oy=1, under=1, done=0}
		pscn{sprk=1}
		ssconv{t='pscn', oy=1, under=1, done=0}
		pscn{sprk=1}
		pscn{sprk=1}
		adv{}
		stacked_dray{
			off=1, r=3, to=v('rmask_hshift_demux.rmask_pscnrow'), done=0
		}
		stacked_dray{off=1, r=3, to=v('lmask_demux.pscnrow')}
		inwr{sprk=1}
	end}

	-- LSH mode: OR then <<<
	-- RSH mode: >>> then XOR
	chain{dx=-1, p=v('shiftrow1_w'):left(), f=function()
	end}

	chain{dx=-1, p=v('shiftrow2_w'):left(), f=function()
	end}
end

