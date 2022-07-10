require('schem/lib/core')

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
			local name_prefix = 'dray_deferred_' .. i .. '_' .. j
			aport{v='dray_deferred'}
			dray{r=1, v=name_prefix .. '_1', done=0}
			dray{r=1, v=name_prefix .. '_2'}
		end}
	end}

	-- The top layer of the core is shifted every frame to make
	-- them activate "earlier" relative to the DRAYs.
	local layer_shift = 3
	disp_matrix{p=v('drays_nw'):s(layer_shift), f=function(i, j)
		chain{dy=-1, f=function()
			-- We start at the position where the DRAY would be after ths shift.
			adv{}
			
			-- This INSL is deleted each frame to form the BRAY target,
			-- and then reused for the next row's ARAY sparker,
			insl{}

			-- Every frame, the FILT is temporarily pushed on top of the DRAYs.
			-- This is pmap hacking: The FILT remains in the pmap since it is
			-- only above the DRAY during the middle of each frame.
			filt{mode='and', ct=shl(1, intdiv(j - 1, 2))}

			-- This INSL is replaced with the colored INSL for the previous
			-- row each frame.
			-- It is then replaced with the data FILT for the current row
			-- just before the ARAY activates.
			insl{}

			aray{}

			port{v='sprk_target_' .. i .. '_' .. j}
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

	-- Compute positions of pistons used to shift the top layer.
	local piston_heads = {}
	chain{p=v('frame'):w(), dx=1, f=function()
		-- frame_range_cnt increases as we get closer to its PSTN, then
		-- decreases as we get further away.
		local is_getting_closer = true
		local frame_range_cnt = 1
		while true do
			if frame_range_cnt == Util.FRME_RANGE then
				-- Ensure that the pistons are at even columns so
				-- that the APOM ID holders interlace nicely with
				-- the double buffer.
				while odist(getcurs(), v('frame'):w()) % 2 ~= 0 do
					adv{-1}
				end

				loc_name = 'piston_head_' .. #piston_heads
				port{v=loc_name}
				table.insert(piston_heads, v(loc_name))
				is_getting_closer = false
			end

			if getcurs():eq(v('frame'):e()) then
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
		for _, p in pairs(piston_heads) do
			local key = odist(p, v('frame'):w())
			chain{p=p, f=function()
				opts.f(key)
			end}
		end
	end

	foreach_piston{f=function(key)
		chain{oy=-1, dy=-1, f=function()
			for i = 1, layer_shift do
				pstn{life=1}
			end
			pstn{}

			-- We pull the top layer back before the core activates.
			pstn{r=layer_shift, done=0}
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
			pstn{r=0}
			cray{v='apom_pstn_id_grabber_' .. key, done=0}
			dray{r=1, to=v('resetter_pstn_target_' .. key)}
			pscn{sprk=1, done=0}
			ssconv{t='pscn', oy=1}
		end}
	end}

	port{v='double_buffer_nw', f=function(opts)
		disp_matrix{p=opts.p, f=function(i, j)
			local name_prefix = 'dray_deferred_' .. i .. '_' .. j
			local target_name = 'dray_target_' .. i .. '_' .. j
			port{v=target_name}
			pconfig{part=v(name_prefix .. '_1'), to=v(target_name)}
			pconfig{part=v(name_prefix .. '_2'), to=v(target_name):s()}

			chain{dy=1, p=v(target_name), f=function()
				aport{v='double_buffer'}
				insl{}
				aport{v='double_buffer'}
				insl{}
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

	chain{dx=1, p=v('resetter_pstn_sparkers'):e():e(2), f=function()
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
		ssconv{t='inwr', under=1}
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

function disp56(opts)
	schem{
		f=disp56_core,
		v='core',
	}
	-- temp for testing
	connect{v='core.double_buffer_nw', p=v('core.dray_deferred'):sw():s(10)}
	connect{
		v='core.make_apom_resetters',
		p=v('core.double_buffer'):sw():s(),
	}
end
