require('schem/lib/core')

-- The top layer of the core is shifted every frame to make
-- them activate "earlier" relative to the DRAYs.
local LAYER_SHIFT = 3

-- Horizontal pixel color propagation uses an exponential
-- DRAY mechanism. These DRAYs are APOMed so that the
-- propagation happens before the layer shift. Each stage
-- consists of:
-- - Creating the column of DRAYs from an ID holder row.
-- - DRAYing the pixel colors.
-- - Transferring the DRAY IDs back to the ID holders.
local NUM_HORZ_PROP_STAGES = 5

-- Type of particle used to hold pixel colors in the screen.
local PIXCOL_TYPE = 'inwr'

local Range = {}
function Range.new(from, to)
	return {from=from, to=to}
end

local function disp56_core(opts)
	port{v='drays_nw'}

	local function disp_matrix(opts)
		opts = opts_pos(opts)
		array{n=56, dy=2, p=opts.p, f=function(i)
			if i % 2 == 1 then
				adv{dx=1}
			end
			array{n=56, dx=2, f=function(j)
				opts.f(i, j)
			end}
		end}
	end

	-- Place the DRAYs first since they belong to the lower layer.
	disp_matrix{p=v('drays_nw'), f=function(i, j)
		chain{dy=-1, f=function()
			-- These DRAYs duplicate an INSL downwards.
			-- Their tmp2s will be configured later once the double buffer
			-- position is known.
			aport{v='dray_deferred'}
			dray{r=1, iv='dray_deferred_1', done=0}
			dray{r=1, iv='dray_deferred_2'}
		end}
	end}

	disp_matrix{p=v('drays_nw'):s(LAYER_SHIFT):s(), f=function(i, j)
		local col_index = (i-1) % 2 + (j-1) * 2 + 1

		chain{dy=-1, f=function()
			if i >= 55 then
				-- Seeds for the reset phase.
				--
				-- Although the lower four rows of the matrix are already
				-- the correct particle types, we need the resetters lower
				-- in order to prevent the upper row of resetter DRAYs from
				-- getting activated by remnant PSCNs (the ones used by the
				-- last row to conditionally copy the pixcols).
				chain{oy=1, dy=1, f=function()
					-- Range of particles to reset during the reset phase.
					aport{v='reset_col_' .. col_index}

					-- Same FILT as in the rest of the core matrix. See below.
					filt{mode='and', ct=shl(1, intdiv(j - 1, 2))}

					if i == 56 then
						-- Range of particles to reset during the reset phase.
						aport{v='reset_col_' .. col_index}

						-- Reset row 55's resetter sparkers.
						conv{from='sprk', to='pscn'}
					end
				end, done=0}
			end

			-- This holds the pixcol that gets copied down.
			aport{v='pixcol_row_' .. i}
			aport{v='pixcol_matrix'}
			insl{}

			-- This is the position where the DRAY would be after the shift.
			if i >= 55 then
				-- These serve as seeds to duplicate back over the entire
				-- core matrix once we're done, for resetting.
				aray{}
			else
				-- Apart from the last two rows, this space would
				-- be filled by the next row's ARAY, so we skip this.
				adv{}
			end

			-- This INSL is deleted each frame to form the BRAY target,
			-- and then reused for the next row's ARAY sparker.
			aport{v='bray_targets'}
			aport{v='bray_targets_row_' .. i}
			insl{}

			-- Every frame, the FILT is temporarily pushed on top of the DRAYs.
			-- This is pmap hacking: The FILT remains in the pmap since it is
			-- only above the DRAY during the middle of each frame.
			filt{mode='and', ct=shl(1, intdiv(j - 1, 2))}

			-- Range of particles to reset during the reset phase.
			aport{v='reset_col_' .. col_index}

			-- This spot gets replaced with the data FILT just before the ARAY
			-- activates.
			aport{v='data_targets'}
			if i <= 2 then
				insl{}
			else
				-- Apart from the first two rows, this space is shared with the
				-- pixcol for the previous row, so we skip this.
				adv{}
			end

			aray{}

			aport{v='sprk_targets'}
			aport{v='sprk_targets_row_' .. i}
			port{iv='sprk_target'}
			if i == 1 then
				-- This INSL is replaced with a sparker for the ARAY each frame.
				-- We only do this for the top row, because in the other rows
				-- this role is shared with the BRAY target from the previous row.
				insl{}

				aport{v='frame'}
				frme{}
			end

			-- Fill up the top to make a flat, pushable block.
			if i == 2 then
				local col_n = findpt{
					n=v('sprk_target_2_' .. j),
					ew=v('sprk_target_1_' .. j),
				}
				array{to=col_n, f=function() insl{} end}

				chain{p=col_n:n(), f=function()
					aport{v='frame'}
					frme{}
				end}
			end
		end}
	end}

	-- After everything is over, the reset phase duplicates a seed over
	-- the entire matrix, column by column, to ensure that we don't have
	-- any FILTs on the top layer where there shouldn't be.
	-- The presence of unwanted FILTs interferes with CRAY operation and
	-- causes them to get stacked under the hidden DRAYs.
	for i = 1, 56 * 2 do
		chain{dy=1, p=v('reset_col_' .. i):ls(1), f=function()
			local is_row_55 = i % 2 == 1

			local specs = get_exponential_dray_configs{
				blocksz=4, to=v('reset_col_' .. i),
			}
			schem{oy=-LAYER_SHIFT, f=function()
				for j = 1, #specs - 1 do
					dray{r=specs[j].r, j=specs[j].j, done=0}
				end
			end, under=1, done=0}
			if is_row_55 then
				aport{v='row_55_resetters'}
				-- The row 55 DRAYs get copied over during horz pixcol prop.
				-- This exposes the DRAY spec so the pixcol propagator maker
				-- can set the seed so that the DRAYs get copied over with
				-- the right particles.
				setv('row_55_resetter_spec', specs[#specs])
			end
			dray{r=specs[#specs].r, j=specs[#specs].j}

			-- Record how large the top layer is to set the PSTN tmps.
			aport{v='top_layer_lb'}

			-- TODO: These need to be resparked.
			pscn{sprk=1}

			if is_row_55 then
				insl{}
				insl{}
				-- Reset the last row's resetter sparkers.
				conv{from='sprk', to='pscn'}
			end
		end}
	end

	-- Compute positions of pistons used to shift the top layer.
	setv('piston_heads', {})
	chain{p=v('frame'):lw(0), dx=1, f=function()
		-- frame_range_cnt increases as we get closer to its PSTN, then
		-- decreases as we get further away.
		local is_getting_closer = true
		local frame_range_cnt = 1
		while true do
			if frame_range_cnt == Util.FRME_RANGE then
				-- Ensure that the pistons are at even columns so
				-- that the APOM ID holders interlace nicely with
				-- the double buffer.
				while odist(getcurs(), v('frame'):lw(0)) % 2 ~= 0 do
					adv{-1}
				end

				loc_name = 'piston_head_' .. #v('piston_heads')
				table.insert(v('piston_heads'), getcurs())
				is_getting_closer = false
			end

			if getcurs():eq(v('frame'):le(0)) then
				break
			end

			if not is_getting_closer and frame_range_cnt == 1 then
				-- End of current PSTN range. Start a new one.
				is_getting_closer = true
			elseif is_getting_closer then
				frame_range_cnt = frame_range_cnt + 1
			else
				frame_range_cnt = frame_range_cnt - 1
			end

			adv{}
		end
	end}

	local function foreach_piston(opts)
		for _, p in pairs(v('piston_heads')) do
			local key = odist(p, v('frame'):lw(0))
			chain{p=p, f=function()
				opts.f(key)
			end}
		end
	end

	foreach_piston{f=function(key)
		chain{oy=-1, dy=-1, f=function()
			local piston_cap = odist(
				v('top_layer_lb'):sw(0), v('frame'):lw(0)
			) + 1

			for i = 1, LAYER_SHIFT do
				pstn{life=1}
			end
			pstn{}

			-- We pull the top layer back before the core activates.
			aport{v='retractor_pstn'}
			pstn{r=LAYER_SHIFT, cap=piston_cap, done=0}
			chain{ox=1, f=function()
				nscn{sprk=1, done=0}
				ssconv{t='nscn', oy=1}
			end}

			-- We restore the top layer only after the core is done.
			-- To ensure this happens after the core is done, use APOM
			-- to move the PSTN's ID to below the double buffer.
			port{v='resetter_pstn_target_' .. key}
			chain{ox=1, f=function()
				conv{from='sprk', to='pscn', oy=-1, done=0}
				-- The sparker needs to be re-sparked with life=3 since the PSTN
				-- only activates after it is re-sparked.
				aport{v='resetter_pstn_sparkers'}
				port{v='resetter_pstn_sparker_' .. key}
				pscn{}
			end}

			-- Setter mechanism for APOM.

			-- This PSTN's range gets added to the rest of the piston.
			-- It's already at LAYER_SHIFT, so no additional range needed.
			pstn{r=0, cap=piston_cap}

			cray{v='apom_pstn_id_grabber_' .. key, done=0}
			dray{r=1, to=v('resetter_pstn_target_' .. key)}

			pscn{sprk=1, done=0}
			ssconv{t='pscn', oy=1}
		end}
	end}

	port{v='double_buffer_nw', f=function(opts)
		disp_matrix{p=opts.p, f=function(i, j)
			-- Copy the pixel colors into the double buffer.
			port{iv='dray_target'}
			pconfig{
				part=v(iname('dray_deferred_1')),
				to=iv('dray_target')
			}
			pconfig{
				part=v(iname('dray_deferred_2')),
				to=iv('dray_target'):s()
			}

			-- Placeholders to show where the double buffer is.
			chain{dy=1, p=iv('dray_target'), f=function()
				aport{v='double_buffer'}
				part{elem_name=PIXCOL_TYPE}
				aport{v='double_buffer'}
				part{elem_name=PIXCOL_TYPE}
			end}
		end}

		-- ID holders for APOM.
		-- These are placed in between the half-pixels in the double buffer.
		foreach_piston{f=function(key)
			local holder_loc = findpt{
				s=v('resetter_pstn_target_' .. key),
				ew=opts.p,
			}
			pconfig{part=v('apom_pstn_id_grabber_' .. key), to=holder_loc}
			chain{p=holder_loc, f=function()
				port{v='apom_id_holder_' .. key}
				insl{}
			end}
		end}
	end}

	chain{dx=1, p=v('resetter_pstn_sparkers'):le(2), f=function()
		port{v='sparker_sparker_loc'}
		chain{f=function()
			foreach_piston{f=function(key)
				cray{
					life=3,
					p=v('sparker_sparker_loc'),
					to=v('resetter_pstn_sparker_' .. key),
					done=0,
				}
			end}
		end}
		inwr{sprk=1, done=0}
		ssconv{t='inwr', ox=-1, oy=1}
	end}

	-- Resetter mechanisms for APOM.
	port{v='make_apom_resetters', f=function(opts)
		foreach_piston{f=function(key)
			local resetter_loc = findpt{
				s=v('resetter_pstn_target_' .. key),
				ew=opts.p,
			}
			chain{dy=1, p=resetter_loc, f=function()
				cray{to=v('resetter_pstn_target_' .. key), done=0}
				cray{ct='insl', to=v('apom_id_holder_' .. key)}
				pscn{sprk=1, done=0}
				ssconv{t='pscn', oy=-1}
			end}
		end}
	end}
end

-- Propagate a single pixcol to the entire matrix
local function make_pixcol_propagator()
	local piston_heads = v('core.piston_heads')

	-- Horizontal propagation
	local horz_prop_s = v('core.pixcol_matrix'):ne(0):e()
	local horz_prop_e = v('core.pixcol_matrix'):se(0):e()
	local num_horz_prop_rows = intdiv(
		odist(horz_prop_e:s(), horz_prop_s) + 1, 2
	)
	array{from=horz_prop_s, to=horz_prop_e:s(), dy=2, f=function(i)
		chain{dx=1, f=function()
			for j = 1, 4 do
				aport{v='horz_prop_pixcol_matrix'}
				if i ~= num_horz_prop_rows then
					-- Fill out the spaces in between, to block diagonal BRAYs.
					insl{oy=1, done=0}
				end
				if j % 2 == 0 and i == num_horz_prop_rows then
					-- The last row needs to copy in resetter DRAYs.
					local spec = v('core.row_55_resetter_spec')
					dray{r=spec.r, j=spec.j}
				else
					aport{v='horz_prop_pixcol_matrix_col_' .. j}
					insl{}
				end
			end

			aport{v='horz_prop_dray_targets'}
			adv{}

			pscn{sprk=1, done=0}
			ssconv{t='pscn', oy=-1}
		end}
	end}

	-- Propagate the horizontal propagation DRAYs downwards.
	local vert_prop_s = findpt{
		-- The DRAYs need to update before the retraction.
		e=v('core.retractor_pstn'):n(1),
		n=v('horz_prop_dray_targets'):ln(0),
	}
	local exponential_dray_extras = {}
	array{n=NUM_HORZ_PROP_STAGES, from=vert_prop_s, dy=-1, f=function(i)
		local stage_num = NUM_HORZ_PROP_STAGES - i + 1
		local target_s = v('horz_prop_dray_targets'):ls(0)
		-- Each stage relies on two initial seed DRAYs.
		configs = get_exponential_dray_configs{
			blocksz=2 * 2, s=getcurs():s(), e=target_s
		}
		for j, spec in ipairs(configs) do
			if j == #configs then
				-- The last DRAY will be DRAYed in between stages since
				-- the top layer DRAY space is shared with the propagation
				-- buffer for the previous stage.
				exponential_dray_extras[stage_num] = spec
				-- These need to be de-sparked at the end to prevent them
				-- from conducting to the pixcol seeds.
				aport{v='pixcol_seeds_despark_targets'}
				aport{v='vert_prop_dray_targets'}
				port{v='vert_prop_dray_target_' .. stage_num}
				insl{}
			else
				dray{r=spec.r, j=spec.j, done=0}
			end
		end
	end}

	-- Fill the remaining spaces to prevent IDs from getting messed up
	-- during the DRAY propagation.
	local vert_prop_filler_n = v('vert_prop_dray_targets'):ls(1)
	local vert_prop_filler_s = v('horz_prop_dray_targets'):ln(1)
	array{
		from=vert_prop_filler_s, to=vert_prop_filler_n, dy=-2,
		f=function()
			insl{oy=-1}
		end
	}
	-- The FILTs fill the entire column.
	-- We use FILTs so that the horizontal propagation DRAYs can be
	-- all cleared with a single CRAY.
	local vert_prop_filt_filler_s = v('horz_prop_dray_targets'):ls(0)
	array{
		from=vert_prop_filt_filler_s, to=vert_prop_filler_n, dy=-2,
		f=function()
			filt{oy=-1}
		end
	}

	-- Vertical pixel color propagation
	local pixcol_vert_prop_seeds = {}
	array{
		from=v('horz_prop_pixcol_matrix'):nw(0),
		to=v('horz_prop_pixcol_matrix'):ne(0),
		f=function(i)
			-- The pixcols must be vertically propagated before the DRAYs
			-- used for horizontal propagation get updated.
			local vert_prop_base = findpt{
				w=v('vert_prop_dray_targets'):ln(0),
				n=getcurs()
			}
			chain{p=vert_prop_base, f=function()
				aport{v='vert_prop_base'}

				-- Stagger the DRAYs.
				if i % 2 == 0 then
					port{v='vert_prop_dray_' .. i, oy=-1}
				else
					port{v='vert_prop_dray_' .. i}
				end

				-- Fill out the spaces between the DRAYs and the
				-- horizontal pixcol propagation seeds.
				local placeholders_n = vert_prop_base:s()
				local placeholders_s = findpt{
					ei=v('horz_prop_pixcol_matrix'):nw(0),
					si=v('vert_prop_dray_' .. i),
				}:n()
				local placeholders_range = odist(
					placeholders_n, placeholders_s
				) + 1
				soft_assert(placeholders_range % 2 == 0, 'expect range to be even')
				local num_placeholders = intdiv(placeholders_range, 2)
				local seed_index = (i + num_placeholders % 2) % 2 + 1
				array{
					dy=2,
					from=placeholders_n,
					to=placeholders_s,
					f=function(j)
						if j == seed_index then
							table.insert(pixcol_vert_prop_seeds, getcurs())
						end
						insl{done=0}
						-- Fill out the spaces in between, to block diagonal BRAYs.
						if i % 2 == 0 and j == 1 then
							insl{oy=-1, done=0}
						end
						insl{oy=1}
					end
				}

				-- Do the pixcol vert prop.
				chain{dy=-1, p=v('vert_prop_dray_' .. i), f=function()
					local exp_dray_to = v('horz_prop_pixcol_matrix_col_' .. i):ls(0)
					exponential_dray{blocksz=2 * 2, s=getcurs():s(), e=exp_dray_to}
					if i % 2 == 1 then
						aport{v='vert_prop_sparker_targets_low'}
					else
						aport{v='vert_prop_sparker_targets_high'}
						-- De-spark the lower sparkers to prevent them from
						-- conducting to the pixcol seeds.
						conv{from='sprk', to='insl', done=0}
					end
					-- These will need to be sparked externally with life=3 CRAY,
					-- so give them placeholders for now.
					insl{}
				end}
			end}
		end
	}
	-- Include initial DRAY vert prop stage sparker for resparking
	-- along with the pixcol vert prop sparkers.
	chain{p=v('vert_prop_dray_targets'):ln(1), f=function()
		aport{v='vert_prop_sparker_targets_low'}
		-- This needs to be de-sparked late to prevent it from conducting
		-- to the pixcol seeds in the next frame.
		aport{v='pixcol_seeds_despark_targets'}
		insl{}
	end}

	-- A column of sparks need to be de-sparked to prevent them
	-- from conducting to the pixcol seeds in the next frame.
	chain{dy=1, p=v('horz_prop_dray_targets'):ls(1), f=function()
		-- Re-create them twice to preserve ID order.
		cray{to=v('pixcol_seeds_despark_targets'), done=0}
		cray{ct='insl', to=v('pixcol_seeds_despark_targets'), done=0}
		cray{to=v('pixcol_seeds_despark_targets'), done=0}
		cray{ct='insl', to=v('pixcol_seeds_despark_targets')}

		pscn{sprk=1, done=0}
		ssconv{t='pscn', under=1}
	end}

	-- Staging pixcols for the vertical pixcol propagation seeds,
	-- copied in diagonally.
	local highest_seed_staging = nil
	for i = 1, 4 do
		local seed_staging = findpt{
			ns=v('vert_prop_dray_targets'):e(2),
			ne=pixcol_vert_prop_seeds[i],
		}
		chain{p=seed_staging, dx=1, dy=-1, f=function()
			aport{v='pixcol_vert_prop_seed_staging'}
			part{elem_name=PIXCOL_TYPE}
			if (
				highest_seed_staging == nil or
				seed_staging.y < highest_seed_staging.y
			) then
				highest_seed_staging = seed_staging
			end

			dray{to=pixcol_vert_prop_seeds[i]}

			-- Place the sparkers for the staging pixcol propagators.
			-- These must be copied in row by row to ensure that the DRAYs
			-- are only activated once in the correct direction.
			-- Later on, the sparkers will be cleared at the same time as
			-- one of the right-side APOM sparker columns.
			chain{dx=1, f=function()
				local sparker_target_name =
					'pixcol_staging_copy_sparker_target_' .. i
				aport{v='pixcol_staging_copy_sparker_targets'}
				port{v=sparker_target_name}; adv{}
				adv{}
				aport{v='pixcol_staging_copy_sparker_seeds'}
				pscn{sprk=1}
				adv{}
				dray{r=2}
				aport{v='pixcol_staging_copy_sparker_prop_sparkers'}
				inwr{sprk=1}
			end}
		end}
	end

	-- Args:
	-- - p: horz ref for top of resparkers
	port{v='make_pixcol_staging_copy_sparker_resparkers', f=function(opts)
		local num_resparkers = 0
		local make_resparker = function(
			p, sparks_ap, spark_type
		)
			chain{dy=1, p=p, f=function()
				cray{to=sparks_ap, done=0}
				cray{ct=spark_type, to=sparks_ap, done=0}
				ssconv{t='pscn'}

				cray{life=4, to=sparks_ap, done=0}
				pscn{sprk=1}

				aport{v='pixcol_staging_copy_sparker_resparker_sparkers'}
				port{
					v='pixcol_staging_copy_sparker_resparker_sparker_' ..
						(num_resparkers + 1)
				}
				inwr{sprk=1}

				num_resparkers = num_resparkers + 1
			end}
		end
		make_resparker(
			findpt{
				ew=opts.p, s=v('pixcol_staging_copy_sparker_seeds'):ls(0)
			}, v('pixcol_staging_copy_sparker_seeds'), 'pscn'
		)
		make_resparker(
			findpt{
				ew=opts.p, s=v('pixcol_staging_copy_sparker_prop_sparkers'):ls(0)
			}, v('pixcol_staging_copy_sparker_prop_sparkers'), 'inwr'
		)
		-- TODO: temporary position
		chain{
			dx=1,
			p=v('pixcol_staging_copy_sparker_resparker_sparkers'):le(5),
			f=function()
				for i = 1, num_resparkers do
					local respark_target =
						v('pixcol_staging_copy_sparker_resparker_sparker_' .. i)
					cray{to=respark_target, done=0}
					cray{ct='inwr', to=respark_target, done=0}
				end
				conv{from='sprk', to='pscn'}

				-- Due to space constraints, this will be de-sparked again
				-- by the PPOM pusher's CONV, and then sparked by conduction.
				pscn{sprk=1}

				-- The newly de-sparked INWRs will be sparked by conduction.
			end
		}
	end}

	setv('pixcol_vert_prop_seed_staging_seed', highest_seed_staging)
	-- TODO: Temporary color for testing
	pconfig{part=pmap(highest_seed_staging), dcolour=0xff00ffff}

	-- Propagate the staging pixcols
	chain{
		dy=-1, p=v('pixcol_vert_prop_seed_staging'):ln(1),
		f=function()
			stacked_dray{
				s=v('pixcol_vert_prop_seed_staging_seed'):s(),
				e=v('pixcol_vert_prop_seed_staging'):ls(0),
				done=0,
			}
			-- Protect seed pixcols from getting sparked.
			conv{from='sprk', to='pscn', done=0}
			insl{done=0}
			insl{done=0, ox=-1}
			insl{done=0, ox=-1, oy=1}
			conv{from='pscn', to='sprk', ox=1}

			-- upper bound for vertprop mechanism
			port{v='vert_prop_ub'}
			pscn{sprk=1}
		end
	}

	-- TODO: Temporary location for testing
	-- Initialize vert prop sparkers. These include sparkers for both
	-- the initial DRAY vert prop stage and the pixcol vert prop.
	chain{dx=1, p=v('vert_prop_sparker_targets_high'):le(15), f=function()
		local targets_e = v('vert_prop_sparker_targets_high'):le(0)
		-- Be careful to preserve particle IDs, since the sparkers are
		-- stacked on top of other particles.
		cray{to=targets_e:w(2), done=0}
		cray{to=targets_e, done=0}
		cray{ct='pscn', to=targets_e, done=0}
		cray{ct='pscn', to=targets_e:w(2)}

		cray{s=targets_e, r=2, life=3, done=0}
		pscn{sprk=1, done=0}
		conv{from='sprk', to='pscn', ox=-1, done=0}
		conv{from='pscn', to='sprk', ox=1}

		inwr{sprk=1}

		port{v='vert_prop_sparker_sparker_e'}
		ssconv{t='inwr'}
	end}

	chain{
		dx=1,
		p=findpt{
			e=v('vert_prop_sparker_targets_low'):le(0),
			s=v('vert_prop_sparker_sparker_e'):e(),
		},
		f=function()
			local targets_e = v('vert_prop_sparker_targets_low'):le(0)
			cray{to=targets_e, done=0}
			cray{to=targets_e:w(2), done=0}
			cray{to=targets_e:w(4)}

			cray{ct='pscn', s=targets_e, r=3, done=0}
			cray{s=targets_e, r=3, life=3, done=0}
			pscn{sprk=1, done=0}
			conv{from='sprk', to='pscn', ox=-1, done=0}
			conv{from='pscn', to='sprk', ox=1}

			inwr{sprk=1}

			ssconv{t='inwr'}
		end
	}

	-- Left side of DRAY/CRAY APOM mechanism:
	-- - Move the CRAY ID holders to a temporary staging area so that
	--   they're to the left of the APOM setup mechanism.
	-- - Place the last DRAY of each DRAY propagator.
	-- - Grab IDs for the horizontal propagation DRAYs.
	local aapom_id_grabbers_n = findpt{
		w=v('vert_prop_dray_targets'):ln(0),
		n=v('horz_prop_pixcol_matrix'):nw(0):w(),
	}
	array{
		n=NUM_HORZ_PROP_STAGES, from=aapom_id_grabbers_n, dy=1,
		f=function(i)
			chain{dx=-1, f=function()
				port{v='apom_cray_id_holder_staging_' .. i}
				adv{}

				local dray_spec = exponential_dray_extras[i]
				dray{r=dray_spec.r, j=dray_spec.j}

				-- Copy the last DRAY propagator DRAY.
				-- This does not affect the free stack.
				dray{to=v('vert_prop_dray_target_' .. i), done=0}
				-- Push the horizontal propagator DRAYs onto the free stack.
				cray{v='horz_prop_dray_id_grabber_' .. i, done=0}
				-- Transfer the CRAY ID to its staging location.
				cray{v='apom_cray_id_grabber_' .. i, done=0}
				cray{ct='insl', to=v('apom_cray_id_holder_staging_' .. i)}

				aport{v='apom_left_sparkers'}
				port{v='apom_left_sparker_' .. i}
				conv{from='sprk', to='insl', ox=1}
				adv{}

				aport{v='apom_left_sparker_seeds'}
				pscn{sprk=1}

				adv{}

				dray{r=2, toe=v('apom_left_sparker_' .. i), done=0}
				dray{r=2, v='apom_right_sparker_1_' .. i, done=0}
				dray{r=2, v='apom_right_sparker_2_' .. i}

				aport{v='apom_left_sparker_seed_prop_sparkers'}
				inwr{sprk=1, done=0}
			end}
		end
	}

	-- Right side of DRAY/CRAY APOM mechanism
	array{
		n=NUM_HORZ_PROP_STAGES, dy=1,
		from=v('vert_prop_dray_targets'):ln(0):e(2),
		f=function(i)
			chain{dx=1, f=function()
				-- The CRAY is placed into the same spot as the DRAY
				-- propagator DRAYs, reusing the sparker.
				local cray_target = v('vert_prop_dray_target_' .. i)
				cray{
					from=cray_target,
					j=odist(cray_target, v('horz_prop_dray_targets'):ln(1)),
					r=56,
				}

				-- Push the DRAY propagator ID onto the free stack.
				cray{to=v('vert_prop_dray_target_' .. i), done=0}
				-- Transfer the CRAY ID to the CRAY.
				cray{to=v('apom_cray_id_holder_staging_' .. i), done=0}
				dray{to=cray_target}

				aport{v='apom_right_sparkers_1'}
				pconfig{part=v('apom_right_sparker_1_' .. i), toe=getcurs()}
				conv{from='sprk', to='insl', ox=-1}

				-- The horizontal propagation DRAYs must update before the CRAY.
				for j = 1, 56 do
					aport{v='horz_prop_dray_id_holders'}
					aport{v='horz_prop_dray_id_holders_row_' .. i}
					insl{}
				end
				pconfig{
					part=v('horz_prop_dray_id_grabber_' .. i),
					to=v('horz_prop_dray_id_holders_row_' .. i),
				}

				port{v='apom_cray_id_holder_' .. i}
				pconfig{
					part=v('apom_cray_id_grabber_' .. i),
					to=v('apom_cray_id_holder_' .. i),
				}
				-- CRAY ID holder. When this ID updates, the CRAY deletes the
				-- horizontal propagation DRAYs and pushes their IDs on the
				-- free stack.
				insl{}

				-- Staging for the DRAY propagator sparkers.
				if i == NUM_HORZ_PROP_STAGES then
					-- There is nothing left to spark after the last one.
					insl{}
				else
					aport{v='apom_right_sparker_seeds'}
					pscn{sprk=1}
				end
				adv{}

				-- Transfer the CRAY ID back to its ID holder.
				dray{to=cray_target, done=0}
				cray{ct='insl', to=v('apom_cray_id_holder_' .. i), done=0}
				-- Pop horizontal propagation DRAY IDs from the free stack
				-- and give them back to their ID holders.
				-- Note that this reverses the ID order of the ID holders.
				-- This does not affect functionality, even across reloads.
				cray{
					ct='insl', to=v('horz_prop_dray_id_holders_row_' .. i),
					done=0,
				}
				-- Pop the DRAY propagator ID from the free stack, and create
				-- the sparker for the next step.
				dray{r=2, to=v('vert_prop_dray_target_' .. i):e()}

				aport{v='apom_right_sparkers_2'}
				pconfig{part=v('apom_right_sparker_2_' .. i), toe=getcurs()}
				conv{from='sprk', to='insl', ox=-1}
			end}
		end
	}

	connect{
		v='make_pixcol_staging_copy_sparker_resparkers',
		p=v('horz_prop_dray_id_holders'):sw(0):s(),
	}

	-- We need to respark several columns of sparks.
	-- For compactness, we spark the INWRs all at the same time with a
	-- single life=3 CRAY. To avoid having to de-spark them, we turn them
	-- into INSLs after they are used, and turn them back into INWRs just
	-- before we spark them. This intermediate step is necessary to avoid
	-- de-sparking the PSCNs after re-sparking them.
	local num_apom_resparkers = 0
	local make_apom_resparker = function(ap, spark_type)
		chain{dy=-1, p=ap:ln(2), f=function()
			cray{life=3, to=ap, done=0}
			conv{from='sprk', to='insl'}

			cray{to=ap, done=0}
			cray{ct=spark_type, to=ap, done=0}
			ssconv{t='pscn', done=0}
			port{v='apom_resparker_sprk_target_' .. (num_apom_resparkers + 1)}
			insl{done=0}
			conv{from='insl', to='inwr', ox=1}

			pscn{sprk=1}

			num_apom_resparkers = num_apom_resparkers + 1
		end}
	end
	make_apom_resparker(v('apom_left_sparker_seeds'), 'pscn')
	make_apom_resparker(v('apom_left_sparker_seed_prop_sparkers'), 'inwr')
	make_apom_resparker(v('apom_right_sparker_seeds'), 'pscn')

	chain{
		dx=1, p=v('apom_resparker_sprk_target_' .. num_apom_resparkers):e(2),
		f=function()
			for i = 1, num_apom_resparkers do
				cray{life=3, to=v('apom_resparker_sprk_target_' .. i), done=0}
			end
			ssconv{t='inwr'}

			inwr{sprk=1}
		end
	}

	-- Clear the sparkers, so that new ones can be DRAYed in.
	chain{dy=1, p=v('apom_left_sparkers'):ls(1), f=function()
		cray{to=v('apom_left_sparkers')}
		pscn{sprk=1, done=0}; ssconv{t='pscn', oy=-1}
	end}
	chain{dy=1, p=v('apom_right_sparkers_1'):ls(1), f=function()
		cray{to=v('apom_right_sparkers_1'), done=0}
		cray{to=v('pixcol_staging_copy_sparker_targets')}
		pscn{sprk=1, done=0}; ssconv{t='pscn', oy=-1}
	end}
	chain{dy=1, p=v('apom_right_sparkers_2'):ls(1), f=function()
		cray{to=v('apom_right_sparkers_2')}
		pscn{sprk=1, done=0}; ssconv{t='pscn', oy=-1}
	end}

	local horz_prop_dray_configs = get_exponential_dray_configs{
		blocksz=2 * 2,
		s=findpt{
			e=v('core.pixcol_matrix'):ne(0),
			ns=v('horz_prop_dray_targets'):w(1),
		},
		e=v('core.pixcol_matrix'):nw(0),
		skip_curs_check=true,
	}

	-- Setup the seed for the first DRAY propagation.
	chain{dy=-1, p=v('vert_prop_dray_targets'):ln(2), f=function()
		filt{}

		local dray_config = horz_prop_dray_configs[1]
		dray{r=dray_config.r, j=dray_config.j}

		stacked_dray{
			r=2,
			s=v('vert_prop_dray_target_1'):s(),
			e=v('vert_prop_dray_target_1'):s(4),
		}

		pscn{sprk=1, done=0}
		ssconv{t='pscn', oy=1}
	end}

	port{v='stage_2_seed_1_target', p=v('vert_prop_dray_target_2'):s(2)}
	port{v='stage_2_seed_2_target', p=v('vert_prop_dray_target_2'):s(4)}
	port{v='stage_3_seed_1_target', p=v('vert_prop_dray_target_3'):s(1)}
	port{v='stage_3_seed_2_target', p=v('vert_prop_dray_target_3'):s(3)}
	port{v='stage_4_seed_1_target', p=v('vert_prop_dray_target_4'):s(2)}
	port{v='stage_4_seed_2_target', p=v('vert_prop_dray_target_4'):s(4)}
	port{v='stage_5_seed_1_target', p=v('vert_prop_dray_target_5'):s(1)}
	port{v='stage_5_seed_2_target', p=v('vert_prop_dray_target_5'):s(3)}

	local function make_seed_placer_pair(
		p, stage1, seed1, stage2, seed2
	)
		chain{p=p, dx=-1, f=function()
			local dray_config_1 = horz_prop_dray_configs[stage1]
			dray{r=dray_config_1.r, j=dray_config_1.j}
			local placer_target_name_1 =
				'stage_' .. stage1 .. '_seed_' .. seed1 .. '_placer_target'
			port{v=placer_target_name_1}; adv{}
			pscn{sprk=1, done=0}; ssconv{t='pscn', ox=-1}

			local dray_config_2 = horz_prop_dray_configs[stage2]
			dray{r=dray_config_2.r, j=dray_config_2.j}
			local placer_target_name_2 =
				'stage_' .. stage2 .. '_seed_' .. seed2 .. '_placer_target'
			port{v=placer_target_name_2}; adv{}
			pscn{sprk=1, done=0}; ssconv{t='pscn', under=1}
			adv{}
		end}
	end

	local stage_2_seed_1_placer_e = findpt{
		w=v('stage_2_seed_1_target'),
		ns=piston_heads[#piston_heads]:w(),
	}
	local stage_3_seed_2_placer_e = findpt{
		w=v('stage_3_seed_2_target'),
		s=stage_2_seed_1_placer_e,
	}
	-- TODO: Temporary position for testing
	local stage_4_seed_1_placer_e = findpt{
		w=v('stage_4_seed_1_target'),
		ns=v('core.pixcol_matrix'):nw(0):w(10),
	}
	local stage_5_seed_2_placer_e = findpt{
		w=v('stage_5_seed_2_target'),
		s=stage_4_seed_1_placer_e,
	}
	make_seed_placer_pair(stage_2_seed_1_placer_e, 2, 1, 3, 1)
	make_seed_placer_pair(stage_3_seed_2_placer_e, 3, 2, 2, 2)
	make_seed_placer_pair(stage_4_seed_1_placer_e, 4, 1, 5, 1)
	make_seed_placer_pair(stage_5_seed_2_placer_e, 5, 2, 4, 2)

	local function make_placer_apom_setter(
		p, stage1, seed1, stage2, seed2
	)
		chain{p=p, dy=-1, f=function()
			local id_holder_name_1 =
				'stage_' .. stage1 .. '_seed_' .. seed1 .. '_placer_id_holder'
			local id_holder_name_2 =
				'stage_' .. stage2 .. '_seed_' .. seed2 .. '_placer_id_holder'
			local placer_target_name_1 =
				'stage_' .. stage1 .. '_seed_' .. seed1 .. '_placer_target'
			local placer_target_name_2 =
				'stage_' .. stage2 .. '_seed_' .. seed2 .. '_placer_target'
			port{v=id_holder_name_2}
			insl{}
			port{v=id_holder_name_1}
			insl{}

			dray{
				from=v(placer_target_name_1),
				to=v('stage_' .. stage1 .. '_seed_' .. seed1 .. '_target'),
			}
			cray{
				s=v(id_holder_name_1),
				e=v(id_holder_name_2),
				done=0
			}
			dray{to=v(placer_target_name_2), done=0}
			dray{to=v(placer_target_name_1)}

			pscn{sprk=1, done=0}; ssconv{t='pscn', oy=1}
		end}
	end

	local function make_placer_apom_resetter(
		p, stage1, seed1, stage2, seed2
	)
		chain{p=p, dy=1, f=function()
			local id_holder_name_1 =
				'stage_' .. stage1 .. '_seed_' .. seed1 .. '_placer_id_holder'
			local id_holder_name_2 =
				'stage_' .. stage2 .. '_seed_' .. seed2 .. '_placer_id_holder'
			local placer_target_name_1 =
				'stage_' .. stage1 .. '_seed_' .. seed1 .. '_placer_target'
			local placer_target_name_2 =
				'stage_' .. stage2 .. '_seed_' .. seed2 .. '_placer_target'

			cray{to=v(placer_target_name_1), done=0}
			cray{to=v(placer_target_name_2), done=0}
			cray{ct='insl', s=v(id_holder_name_2), e=v(id_holder_name_1)}

			ssconv{t='pscn', oy=-1, done=0}
			pscn{sprk=1}
		end}
	end

	local function make_placer_apom(
		pset, preset, stage1, seed1, stage2, seed2
	)
		make_placer_apom_setter(pset, stage1, seed1, stage2, seed2)
		make_placer_apom_resetter(preset, stage1, seed1, stage2, seed2)
	end

	-- Set up APOM for the placers
	make_placer_apom(
		findpt{
				n=v('stage_3_seed_2_placer_target'),
				w=v('vert_prop_dray_target_3'),
		},
		findpt{
				s=v('stage_3_seed_2_placer_target'),
				ew=v('core.double_buffer'):sw(0):s(),
		},
		2, 1, 3, 2
	)
	make_placer_apom(
		findpt{
				n=v('stage_3_seed_1_placer_target'),
				w=v('vert_prop_dray_target_3'),
		},
		findpt{
				s=v('stage_2_seed_2_placer_target'),
				ew=v('core.double_buffer'):sw(0):s(),
		},
		2, 2, 3, 1
	)
	make_placer_apom(
		findpt{
				n=v('stage_5_seed_2_placer_target'),
				w=v('vert_prop_dray_target_5'),
		},
		findpt{
				s=v('stage_5_seed_2_placer_target'),
				ew=v('core.data_targets'):sw(0):s():n(LAYER_SHIFT),
		},
		4, 1, 5, 2
	)
	make_placer_apom(
		findpt{
				n=v('stage_5_seed_1_placer_target'),
				w=v('vert_prop_dray_target_5'),
		},
		findpt{
				s=v('stage_4_seed_2_placer_target'),
				ew=v('core.data_targets'):sw(0):s():n(LAYER_SHIFT),
		},
		4, 2, 5, 1
	)
end

function disp56(opts)
	schem{
		f=disp56_core,
		v='core',
	}

	-- TODO: temporary location
	connect{v='core.double_buffer_nw', p=v('core.dray_deferred'):sw(0):s(9)}
	connect{
		v='core.make_apom_resetters',
		p=v('core.double_buffer'):sw(0):s(),
	}

	-- Initial screen area.
	array{
		n=56 * 2,
		from=v('core.double_buffer'):ne(0):e(),
		to=v('core.double_buffer'):se(0):e(),
		f=function(i)
			array{n=56 * 2, dx=1, f=function(j)
				aport{v='screen_row_' .. i}
				part{elem_name=PIXCOL_TYPE}
			end}
		end
	}

	-- Expand the double buffer into full screen.
	array{
		from=v('core.double_buffer'):nw(0):w(),
		to=v('core.double_buffer'):sw(0):w(),
		f=function()
			dray{}
		end
	}

	-- Propagating the data FILTs only happens after the layer shift,
	-- so we need to account for it in positioning.
	local data_prop_from =
		v('core.data_targets'):nw(0):n(LAYER_SHIFT):w()
	local data_prop_to =
		v('core.data_targets'):sw(0):n(LAYER_SHIFT):w():s()
	local ldtc_positions = {}
	array{dy=2, from=data_prop_from, to=data_prop_to, f=function(i)
		chain{dx=-1, f=function()
			if i % 2 == 1 then
				filt{}
			end
			for j = 1, 2 do
				adv{}

				filt{mode='set', done=0}
				local data_index = (i-1) * 2 + (3-j)
				ldtc_positions[data_index] = getcurs()
				ldtc{v='data_reader_' .. data_index, ox=1, oy=-1}
			end
			if i % 2 == 0 then
				adv{}
			end

			local exp_dray_to = findpt{
				e=getcurs(),
				ns=v('core.data_targets'):ne(0),
			}
			exponential_dray{blocksz=2 * 2, s=getcurs():e(), e=exp_dray_to}
			aport{v='data_prop_sparkers'}
			pscn{sprk=1}
		end}
	end}

	chain{
		dy=1, p=v('data_prop_sparkers'):ls(2), f=function()
			cray{ct='insl', to=v('data_prop_sparkers'), done=0}
			cray{ct='pscn', to=v('data_prop_sparkers')}

			cray{to=v('data_prop_sparkers'), done=0}
			pscn{sprk=1, done=0}
			ssconv{t='pscn', oy=-1}

			inwr{sprk=1, done=0}
			ssconv{t='inwr', oy=1}
		end
	}

	-- Propagate sparkers for the second row.
	-- This reuses the DRAYs from the first row's data FILT propagation.
	chain{
		dx=-1, p=v('core.sprk_targets'):nw(0):n(LAYER_SHIFT):s(2):w(2),
		f=function()
			ssconv{t='inwr', done=0}; inwr{sprk=1}
			adv{}
			ssconv{t='inwr', done=0}; inwr{sprk=1}
		end,
	}

	-- Propagate sparkers for the first row.
	chain{
		dx=-1, p=v('core.sprk_targets'):nw(0):n(LAYER_SHIFT):w(),
		f=function()
			-- Add INSLs above to block stray BRAYs from the core matrix.
			ssconv{t='inwr', done=0}; inwr{sprk=1, done=0}; insl{oy=-1}
			filt{}
			ssconv{t='inwr', done=0}; inwr{sprk=1, done=0}; insl{oy=-1}
			filt{}

			local exp_dray_to = findpt{
				e=getcurs(),
				ns=v('core.sprk_targets'):ne(0),
			}
			exponential_dray{blocksz=2 * 2, s=getcurs():e(), e=exp_dray_to}

			port{v='row_1_sprk_prop_dray_sparker'}
			pscn{sprk=1, done=0}
		end,
	}

	-- The input port for the draw pattern.
	-- The port needs to reorder FILTs for detection by the LDTCs.
	-- It does so by using an intermediate ARAY-DTEC stage, with
	-- the DTECs offset and set to different ranges to capture
	-- the correct FILT data.
	-- Args:
	-- - p: Horizontal reference for bottom of input port
	port{v='data_in_swizzler', f=function(opts)
		local staging_positions = {}
		-- ARAY offset required, assuming first offset is 0
		local rel_offsets = {}
		local max_offset = 0
		for i = 1, 56 * 2 do
			table.insert(staging_positions, findpt{
				ew=opts.p,
				ne=ldtc_positions[i],
			})
			table.insert(rel_offsets,
				odist(staging_positions[i], staging_positions[1]) + 1 - i
			)
			if rel_offsets[i] > max_offset then
				max_offset = rel_offsets[i]
			end
		end
		for i = 1, 56 * 2 do
			chain{dx=1, dy=-1, p=staging_positions[i], f=function()
				pconfig{part=v('data_reader_' .. i), to=getcurs()}
				filt{}
				dtec{r=max_offset - rel_offsets[i] + 1}
			end}
		end
		array{
			n=56 * 2, dx=1,
			from=staging_positions[1]:n(3):e(3):e(max_offset),
			f=function(i)
				chain{dx=1, dy=-1, f=function()
					aport{v='data_in'}
					-- TODO: temporary data for now
					-- local temp_data = 0x2aaaaaaa
					-- if i % 2 == 0 then
					-- 	temp_data = bxor(temp_data, 0x0fffffff)
					-- end
					local temp_data = 0x3fffffff
					filt{mode='set', ct=temp_data}
					aray{}
					inwr{sprk=1, done=0}; ssconv{t='inwr', ox=-1, oy=1}
				end}
			end
		}
	end}

	-- The last row doesn't need any data, but it does need the
	-- INSLs cleared to make way for the BRAYs.
	chain{
		dx=-1, p=v('core.bray_targets'):sw(0):n(LAYER_SHIFT):w(),
		f=function()
			cray{r=56 * 2, s=v('core.bray_targets'):sw(0):n(LAYER_SHIFT)}
			pscn{sprk=1, done=0}; ssconv{t='pscn', ox=1}
		end
	}

	make_pixcol_propagator()

	chain{
		dx=1, p=findpt{
			e=v('row_1_sprk_prop_dray_sparker'),
			ns=v('horz_prop_dray_targets'):e(1),
		}:e(10), -- TODO: temporary offset
		f=function()
			cray{to=v('row_1_sprk_prop_dray_sparker'), done=0}
			cray{ct='pscn', to=v('row_1_sprk_prop_dray_sparker')}

			pscn{sprk=1, done=0}
			ssconv{t='pscn', ox=-1}
		end
	}

	-- Copy in PSCNs wherever the BRAY gets annihilated.
	-- These will spark the DRAYs used to write to the screen buffer.

	-- Three stacks of five DRAYs, minus one to invert.
	local num_seeds = ceildiv(56, 14)

	array{
		n=56, dy=2, p=findpt{
			e=v('core.bray_targets'):ne(0):n(LAYER_SHIFT),
			ns=v('horz_prop_dray_targets'):e(2),
		},
		f=function(i)
			chain{dx=1, f=function()
				if i % 2 == 1 then
					-- Block diagonal BRAYs. This ensures that the set of IDs
					-- containing the blocker and the BRAY target placeholders
					-- will be preserved, to ensure that pixcols don't get
					-- sparked by the DRAY sparkers.
					local blocker_insl_w_pos = findpt{
						ns=v('core.bray_targets'):nw(0):w(),
						w=getcurs(),
					}
					local blocker_insl_e_pos = findpt{
						ns=v('core.bray_targets'):ne(0):e(),
						w=getcurs(),
					}
					insl{p=blocker_insl_w_pos, done=0}
					if i < 55 then
						insl{p=blocker_insl_w_pos:s(), done=0}
					end
					-- This row's blockers get removed when the data FILTs get
					-- copied in, so we need to re-create them.
					cray{ct='insl', to=blocker_insl_w_pos, done=0}
				end
				local invert_s = findpt{
					ns=v('core.bray_targets'):ne(0),
					w=getcurs(),
				}
				local invert_e = findpt{
					ns=v('core.bray_targets'):nw(0),
					w=getcurs(),
				}
				-- Invert, so that we write the pixcol where bits are set
				if i == 56 then
					-- The last row does not have FILTs, so we need to include
					-- those spots in the fill.
					cray{ct='insl', s=invert_s, r=56 * 2}
				else
					cray{ct='insl', s=invert_s, r=56}
				end

				for j = 1, num_seeds do
					aport{v='core_sparker_seeds_col_' .. j}
					pscn{sprk=1}
					adv{}
				end

				-- replicate sprk pattern across three stacks
				local rep_len = num_seeds * 2
				local rep_s =
					v('core.bray_targets_row_' .. i):le(1):n(LAYER_SHIFT)
				local rep_e =
					v('core.bray_targets_row_' .. i):lw(0):n(LAYER_SHIFT)
				stacked_dray{
					r=num_seeds * 2,
					s=rep_s, e=rep_s:w(rep_len * 5 - 1),
				}
				inwr{sprk=1, done=0}; ssconv{t='inwr', under=1}

				stacked_dray{
					r=num_seeds * 2, off=2,
					s=rep_s:w(rep_len * 5), e=rep_s:w(rep_len * 10 - 1),
				}
				inwr{sprk=1, done=0}; ssconv{t='inwr', under=1}

				stacked_dray{
					r=num_seeds * 2, off=4,
					s=rep_s:w(rep_len * 10), e=rep_e,
				}
				aport{v='sprk_filler_sparkers'}
				inwr{sprk=1, done=0}
				ssconv{t='inwr', under=1}
			end}
		end
	}

	for i = 1, num_seeds do
		-- Respark the core sparker seeds. This comes before the
		-- seed propagation, so we must spark them with life=3 sparks.
		chain{
			dy=-1, p=v('core_sparker_seeds_col_' .. i):ln(2), 
			f=function()
				-- There is one seed every two spaces, so make sure we
				-- spark the right number.
				local num_targets = ceildiv(
					v('core_sparker_seeds_col_' .. i):sz().y, 2
				)
				cray{
					life=3, r=num_targets,
					s=v('core_sparker_seeds_col_' .. i):ln(0)
				}

				cray{ct='insl', to=v('core_sparker_seeds_col_' .. i), done=0}
				cray{ct='pscn', to=v('core_sparker_seeds_col_' .. i), done=0}
				ssconv{t='pscn', done=0}
				if i ~= 1 then
					-- Ensure the resparker CRAYs only touch the particles
					-- that need resparking. This is necessary to ensure
					-- that IDs are preserved, since these sparkers are
					-- stacked on top of other particles.
					filt{ox=-1, done=0}
				end
				-- This will be resparked before the lower CRAY updates.
				aport{v='core_sparker_seeds_sparkers'}
				inwr{sprk=1}

				pscn{sprk=1}
			end
		}
	end

	-- Respark the sparkers.
	chain{
		-- TODO: temporary position
		dx=1, p=v('core_sparker_seeds_sparkers'):le(3),
		f=function()
			local respark_s = v('core_sparker_seeds_sparkers'):le(0)
			-- Do this twice to ensure that IDs are preserved
			-- (the IDs flip each time). This is necessary since
			-- the targets are stacked on top of other particles.
			cray{r=num_seeds, s=respark_s, done=0}
			cray{ct='inwr', r=num_seeds, s=respark_s, done=0}
			cray{r=num_seeds, s=respark_s, done=0}
			cray{ct='inwr', r=num_seeds, s=respark_s}

			cray{life=3, r=num_seeds, s=respark_s, done=0}
			ssconv{t='pscn', ox=1, oy=1, done=0}
			pscn{sprk=1}

			inwr{sprk=1, done=0}
			ssconv{t='inwr', ox=1, oy=1}
		end
	}

	-- After DRAYs have fired, replace their sparker slots with
	-- sparkers for the next row's ARAYs.
	-- We don't need to do this for the last two rows, since there
	-- are no more ARAYs to fire.
	-- However, for the second-last row, we do want to replace
	-- any SPRK-ed PSCNs to prevent firing PSCN-BRAYs.
	array{
		n=56 - 1, dy=2, p=v('sprk_filler_sparkers'):ln(0):se(),
		f=function(i)
			chain{dx=1, f=function()
				local is_last_row = (i == 56 - 1)
				aport{v='aray_sparker_placer'}
				if not is_last_row then
					aport{v='aray_sparker_placer', oy=1}
				end

				-- Delete whatever is currently there.
				-- This ignores the FILTs on every other column.
				cray{
					r=56,
					from=getcurs():n():s(LAYER_SHIFT),
					s=v('core.bray_targets_row_' .. i):le(0),
					done=is_last_row,
				}
				if not is_last_row then
					insl{oy=1}
				end

				pscn{sprk=1, done=is_last_row}
				if not is_last_row then
					filt{oy=1}
				end

				conv{from='sprk', to='pscn', done=0}
				if is_last_row then
					conv{from='pscn', to='sprk'}
				else
					conv{from='pscn', to='sprk', oy=1}
				end

				-- Place down INWRs.
				local repl_type = 'inwr'
				if is_last_row then
					repl_type = 'insl'
				end
				cray{
					ct=repl_type, r=56,
					from=getcurs():n():s(LAYER_SHIFT),
					s=v('core.bray_targets_row_' .. i):le(0),
					done=is_last_row,
				}
				if not is_last_row then
					insl{oy=1}
				end

				pscn{sprk=1, done=is_last_row}
				if not is_last_row then
					filt{oy=1}
				end

				conv{from='sprk', to='pscn', done=0}
				if is_last_row then
					conv{from='pscn', to='sprk'}
				else
					conv{from='pscn', to='sprk', oy=1}
				end

				-- Spark the INWRs.
				if not is_last_row then
					cray{
						life=3, r=56,
						from=getcurs():n():s(LAYER_SHIFT),
						s=v('core.bray_targets_row_' .. i):le(0),
						done=is_last_row,
					}
					insl{oy=1}
				end

				aport{v='aray_sparker_placer'}

				if not is_last_row then
					aport{v='aray_sparker_placer', oy=1}
					aport{v='aray_sparker_sparker_sparkers'}
					inwr{sprk=1, done=is_last_row}
					filt{oy=1}
				end
			end}
		end
	}

	chain{dy=1, p=v('aray_sparker_sparker_sparkers'):ls(3), f=function()
		cray{r=56 - 2, s=v('aray_sparker_sparker_sparkers'):ls(0), done=0}
		cray{ct='inwr', r=56 - 2, s=v('aray_sparker_sparker_sparkers'):ls(0)}

		cray{r=56 - 2, s=v('aray_sparker_sparker_sparkers'):ls(0), done=0}
		pscn{sprk=1, done=0}
		ssconv{t='pscn', oy=-1}

		inwr{sprk=1}

		ssconv{t='inwr'}
	end}

	-- PPOM mechanism for the ARAY sparker placers.
	array{
		from=v('aray_sparker_placer'):nw(0):n(),
		to=v('aray_sparker_placer'):ne(0):n(),
		f=function() frme{} end,
	}

	chain{p=v('aray_sparker_placer'):sw(0):s(), f=function()
		port{v='aray_sparker_placer_pusher_id_holder'}
		insl{}
	end}

	chain{dy=-1, p=v('aray_sparker_placer'):nw(0):n(2), f=function()
		pstn{life=1}

		pstn{}

		pstn{ct='dmnd', cap=2 * 56, done=0}
		nscn{sprk=1, ox=1, done=0}
		ssconv{t='nscn', ox=1, under=1}

		port{v='aray_sparker_placer_pusher_target'}
		-- This will be sparked with life=3 CRAY.
		port{v='aray_sparker_placer_pusher_sparker', ox=-1}
		conv{from='sprk', to='pscn', ox=-1, done=0}
		pscn{sprk=1, ox=-1}

		-- APOM setter for the pusher
		pstn{ct='dmnd', r=0, cap=2 * 56}

		cray{to=v('aray_sparker_placer_pusher_id_holder'), done=0}
		dray{to=v('aray_sparker_placer_pusher_target'), done=0}
		ssconv{t='pscn', done=0}
		dmnd{}

		pscn{sprk=1, done=0}
	end}

	chain{
		dx=1, p=v('aray_sparker_placer_pusher_sparker'):e(4), f=function()
			cray{life=3, to=v('aray_sparker_placer_pusher_sparker'), done=0}
			ssconv{t='inwr'}

			inwr{sprk=1}
		end
	}

	chain{
		dy=1, p=findpt{
			s=v('aray_sparker_placer_pusher_id_holder'),
			e=v('sprk_filler_sparkers'):ls(1),
		},
		f=function()
			cray{to=v('aray_sparker_placer_pusher_target'), done=0}
			cray{ct='insl', to=v('aray_sparker_placer_pusher_id_holder')}

			pscn{sprk=1, done=0}
			ssconv{t='pscn', ox=1, oy=-1}
		end
	}

	connect{v='data_in_swizzler', p=v('vert_prop_ub'):n()}
end
