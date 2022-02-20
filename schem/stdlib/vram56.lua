require('schem/stdlib/core')

local function vram56_reader(opts)
end

local function vram56_writer(opts)
	local ldtcs = {}
	array{n=56 * 2, dx=1, f=function(i)
		if i == 1 then port{v='write_head_nw'} end
		chain{dy=1, f=function()
			if i % 2 == 0 then
				conv{from='insl', to='filt', done=0}
				conv{from='filt', to='insl', ox=1, done=0}
				table.insert(ldtcs, ldtc{})
				insl{}
				filt{}
				dray{}
				pscn{sprk=1}
			else
				conv{from='crmc', to='filt', done=0}
				conv{from='filt', to='crmc', ox=1, done=0}
				table.insert(ldtcs, ldtc{})
				crmc{}
				filt{}
				if i == 1 then port{v='drayrow1_w'} end
				filt{}
				if i == 1 then port{v='drayrow2_w'} end
				dray{}
				schem{f=ssconv, t='pscn', done=0}
				pscn{sprk=1}
			end
		end}
	end}
	setv('ldtcs', ldtcs)

	chain{dx=-1, p=v('drayrow1_w'):left(), f=function()
		-- use a large block size to make room in stack for the CONV
		schem{
			f=exponential_dray,
			blocksz=8, n=56 * 2,
			done=0,
		}
		conv{from='sprk', to='inwr', done=0}
		-- split up the ssconv to prevent overstacking
		conv{from='inwr', to='sprk', oy=1}
		inwr{sprk=1}
		adv{}
		adv{}
		insl{} -- to be replaced with DRAY of the correct tmp2
		for i = 1, 4 do
			dray{r=1, to=v('drayrow1_w'):right((i-1) * 2 + 1), done=0}
		end
		conv{from='sprk', to='pscn', done=0}
		conv{from='pscn', to='sprk', oy=1}
		pscn{sprk=1}
		adv{}
		adv{}
		cray{r=56, s=v('drayrow1_w'), done=0}
		schem{f=ssconv, t='pscn'}
		pscn{sprk=1}
	end}

	chain{dx=-1, p=v('drayrow2_w'):left(), f=function()
		port{v='sprkrow1_seed'}
		insl{} -- to be replaced with life=4 sparked PSCN
		schem{
			f=exponential_dray,
			blocksz=8, n=56 * 2
		}
		pscn{sprk=1, done=0}
		schem{f=ssconv, t='pscn', oy=1}
		adv{}
		insl{} -- to be replaced with DRAY of the correct tmp2
		crmc{done=0}
		conv{from='crmc', to='pscn', ox=1, oy=-1, under=1, done=0}
		conv{from='sprk', to='crmc', ox=1, under=1}
		for i = 1, 4 do
			dray{r=2, to=v('drayrow2_w'):left():right((i-1) * 2), done=0}
		end
		conv{from='sprk', to='pscn', done=0}
		conv{from='pscn', to='sprk', oy=1}
		pscn{sprk=1}
		adv{}
		adv{}
		cray{r=1, to=v('sprkrow1_seed'), done=0}
		cray{r=1, to=v('sprkrow1_seed'), ct='pscn', done=0}
		schem{f=ssconv, t='pscn'}
		pscn{sprk=1}
	end}
end

function vram56(opts)
	if opts.n == nil then opts.n = 64 end
	if opts.init_data == nil then
		opts.init_data = {}
		for i = 1, opts.n do
			local entry = {}
			for j = 1, 56 * 2 do
				table.insert(entry, ka)
			end
			table.insert(opts.init_data, entry)
		end
	end

	array{n=opts.n, dy=1, f=function(i)
		array{n=56 * 2, dx=1, f=function(j)
			if j == 1 and i == opts.n then
				port{v='data_sw'}
			end
			filt{ct=opts.init_data[i][j]}
		end}
	end}

	port{v='make_writer', p=v('data_sw'):down(), f=function(opts)
		schem{
			f=vram56_writer,
			p=findpt{ew=opts.p, s=v('data_sw')},
			ref='write_head_nw',
		}
	end}
end

