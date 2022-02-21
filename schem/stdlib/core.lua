function ssconv(opts)
	opts.f = function(opts)
		conv{from='sprk', to=opts.t, done=0}
		conv{from=opts.t, to='sprk'}
	end
	schem(opts)
end

function stacked_dray(opts)
	opts = opts_bool(opts, 'done', true)
	opts = opts_aport(opts, 'to', 's', 'e')
	if opts.off == nil then opts.off = 0 end
	local cover_range = get_orth_dist(opts.s, opts.e) + 1
	local d = get_orth_dir(opts.s, opts.e)
	local num_covered = 0
	while true do
		local target = opts.s:add(d:mult(num_covered - opts.off))
		if num_covered + opts.r >= cover_range then
			dray{
				r=cover_range - num_covered + opts.off,
				to=target,
				done=opts.done
			}
			return
		end
		dray{r=opts.r + opts.off, to=target, done=0}
		num_covered = num_covered + opts.r
	end
end

function exponential_dray(opts)
	opts = opts_bool(opts, 'done', true)
	opts = opts_aport(opts, 'to', 's', 'e')
	if opts.s ~= nil then
		assert(
			get_orth_dist(getcurs(), opts.s) == 1,
			'effect range must start next to DRAY'
		)
	end
	if opts.e ~= nil then opts.r = get_orth_dist(opts.s, opts.e) + 1 end
	if opts.blocksz == nil then opts.blocksz = 1 end
	if opts.nblocks ~= nil then opts.r = opts.nblocks * opts.blocksz end
	if opts.r == nil then opts.r = 8 end
	local copied_sz = opts.blocksz
	while copied_sz < opts.r do
		local remainder = opts.r - copied_sz
		if remainder <= copied_sz then
			dray{r=remainder, j=copied_sz - remainder, done=opts.done}
			return
		end
		dray{r=copied_sz, done=0}
		copied_sz = copied_sz * 2
	end
end

function aray_array_e(opts)
	if opts.n == nil then opts.n = 8 end

	array{n=opts.n, dy=1, f=function(i)
		if i == 1 then port{v='araycol_ne'} end
		if (opts.n - i) % 2 == 1 then
			chain{dx=-1, f=function()
				aray{done=0}
				-- all inner ARAY activators are re-sparked immediately
				ssconv{t='inwr'}
				inwr{sprk=1}
			end}
		else
			chain{dx=-1, f=function()
				filt{}
				if i == opts.n then port{v='last_aray'} end
				aray{}
				aport{v='outer_sprkcol'}
				inwr{sprk=1}
			end}
		end
	end}

	insl{p=findpt{n=v('last_aray'), ew=v('araycol_ne'):up()}}
	-- re-spark the last outer ARAY activator manually
	ssconv{p=v('last_aray'), t='inwr'}

	-- replace all other outer ARAY activators with the re-sparked activator
	chain{dy=1, p=v('last_aray'):down():left(), f=function()
		local respark_range = opts.n
		if opts.n % 2 == 0 then respark_range = respark_range - 1 end
		exponential_dray{to=v('outer_sprkcol'), blocksz=2}
		ssconv{t='pscn', done=0}
		pscn{sprk=1}
	end}
end
