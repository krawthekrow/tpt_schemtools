function ssconv(opts)
	opts = opts_bool(opts, 'done', true)
	opts = opts_pos(opts)
	conv{p = opts.p, from='sprk', to=opts.t, done=0}
	conv{p = opts.p, from=opts.t, to='sprk', done=opts.done}
end

function pstn_demux(opts)
	if opts.n == nil then opts.n = 32 end
	if opts.xn == nil then opts.xn = 0 end
	assert(opts.n >= 1)
	assert(opts.n <= 32)
	local num_segs = ilog2(opts.n)

	-- set up bit checking logic
	local arayy, inputp, pscn_s, pscn_e, pstn_s, pstn_e
	chain({dx=1}, function()
		for i = 1, num_segs do
			chain({dx=1, dy=-1}, function()
				if i == 1 then pscn_s = getcurs() end
				if i == num_segs then pscn_e = getcurs() end
				insl{}
				if i == 1 then inputp = getcurs() end
				filt{tmp=fsub}
				filt{tmp=fset, ct=shl(1, num_segs-i)}
				if i == 1 then arayy = getcurs().y end
				aray{done=0}
				ssconv{t='inwr'}
				inwr{sprk=1}
			end)
		end
	end)

	local retractor_target
	chain({dx=-1, p=pscn_e:add(p(2, 1))}, function()
		port('head')
		adv{}
		pstn{r=1 + opts.xn}
		local cum_r = 0
		for i = 1, num_segs do
			if i == 1 then pstn_s = getcurs() end
			if i == num_segs then pstn_e = getcurs() end
			local target_r = shl(1, i - 1)
			pstn{r=target_r - cum_r, ct='dmnd'}
			cum_r = target_r
		end
		retractor_target = getcurs()
		adv{}
		dmnd{}
	end)

	-- extend addr_in ldtc line
	local ldtc_target
	chain({dx=-1, p=inputp}, function()
		adv{}
		filt{}
		ldtc_target = getcurs()
		adv{}
		adv{}
		port('addr_in')
	end)

	-- place ss pscns in empty locations
	chain({dx=1, p=pscn_e}, function()
		adv{}
		adv{}
		pscn{sprk=1}
		adv{}
		for i = 1, 5 do
			dray{r=2, to=pscn_e:add(p(1-(i-1), 0)), done=0}
		end
		adv{}
		ssconv{t='inwr', done=0}
		inwr{sprk=1}
	end)

	local cray_target = p(ldtc_target.x, pscn_s.y)

	-- set up apom
	chain({dy=-1, x=ldtc_target.x, y=arayy}, function()
		insl{}
		local insl_s = getcurs()
		insl{}
		pstn{r=0}
		cray{r=num_segs, from=cray_target, to=pscn_s}
		cray{r=2, to=insl_s, done=0}
		cray{r=1, ct='ldtc', to=ldtc_target, done=0}
		dray{r=2, to=cray_target, done=0}
		ssconv{ox=1, t='pscn'}
		pscn{sprk=1}
	end)

	-- activate the apom'ed cray
	chain({p=cray_target}, function()
		adv{-1, 0}
		ssconv{t='pscn'}
		pscn{sprk=1}
	end)
end
