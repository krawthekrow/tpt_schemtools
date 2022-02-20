function ssconv(opts)
	conv{from='sprk', to=opts.t}
	conv{from=opts.t, to='sprk'}
end

function exponential_dray(opts)
	if opts.blocksz == nil then opts.blocksz = 1 end
	if opts.nblocks ~= nil then opts.n = opts.nblocks * opts.blocksz end
	if opts.n == nil then opts.n = 8 end
	local copied_sz = opts.blocksz
	while copied_sz < opts.n do
		local remainder = opts.n - copied_sz
		if remainder <= copied_sz then
			dray{r=remainder, j=copied_sz - remainder}
			return
		end
		dray{r=copied_sz}
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
				schem{f=ssconv, t='inwr'}
				inwr{sprk=1}
			end}
		else
			chain{dx=-1, f=function()
				filt{}
				if i == opts.n then port{v='last_aray'} end
				aray{}
				inwr{sprk=1}
			end}
		end
	end}

	insl{p=findpt{n=v('last_aray'), ew=v('araycol_ne'):up()}}
	-- re-spark the last outer ARAY activator manually
	schem{f=ssconv, p=v('last_aray'), t='inwr'}

	-- replace all other outer ARAY activators with the re-sparked activator
	chain{dy=1, p=v('last_aray'):down():left(), f=function()
		local respark_range = opts.n
		if opts.n % 2 == 0 then respark_range = respark_range - 1 end
		schem{f=exponential_dray, n=respark_range, blocksz=2}
		schem{f=ssconv, t='pscn', done=0}
		pscn{sprk=1}
	end}
end
