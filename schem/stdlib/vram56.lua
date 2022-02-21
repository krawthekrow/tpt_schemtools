require('schem/stdlib/core')

local function vram56_reader(opts)
end

local function vram56_writer(opts)
	array{n=56 * 2, dx=1, f=function(i)
		if i == 1 then port{v='write_head_nw'} end
		chain{dy=1, f=function()
			if i % 2 == 0 then
				conv{from='insl', to='filt', done=0}
				conv{from='filt', to='insl', ox=1, done=0}
				-- TODO: allow parent to place their own LDTCs to allow for
				-- double-LDTC input
				ldtc{}
				insl{}
				filt{}
				dray{}
				pscn{sprk=1}
			else
				conv{from='crmc', to='filt', done=0}
				conv{from='filt', to='crmc', ox=1, done=0}
				-- TODO: allow parent to place their own LDTCs to allow for
				-- double-LDTC input
				ldtc{}
				crmc{}
				filt{}
				aport{v='drayrow1'}
				filt{}
				aport{v='drayrow2'}
				dray{}
				ssconv{t='pscn', done=0}
				pscn{sprk=1}
			end
		end}
	end}

	chain{dx=-1, p=v('drayrow1'):w():left(), f=function()
		-- use a large block size to make room in stack for the CONV
		exponential_dray{
			blocksz=8, r=56 * 2,
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
			dray{to=v('drayrow1'):w():right((i-1) * 2 + 1), done=0}
		end
		conv{from='sprk', to='pscn', done=0}
		conv{from='pscn', to='sprk', oy=1}
		pscn{sprk=1}
		adv{}
		adv{}
		cray{to=v('drayrow1'), done=0}
		ssconv{t='pscn'}
		pscn{sprk=1}
	end}

	chain{dx=-1, p=v('drayrow2'):w():left(), f=function()
		port{v='sprkrow1_seed'}
		insl{} -- to be replaced with life=4 sparked PSCN
		exponential_dray{
			blocksz=8, r=56 * 2,
		}
		pscn{sprk=1, done=0}
		ssconv{t='pscn', oy=1}
		adv{}
		insl{} -- to be replaced with DRAY of the correct tmp2
		crmc{done=0}
		conv{from='crmc', to='pscn', ox=1, oy=-1, under=1, done=0}
		conv{from='sprk', to='crmc', ox=1, under=1}
		for i = 1, 4 do
			dray{r=2, to=v('drayrow2'):w():left():right((i-1) * 2), done=0}
		end
		conv{from='sprk', to='pscn', done=0}
		conv{from='pscn', to='sprk', oy=1}
		pscn{sprk=1}
		adv{}
		adv{}
		cray{to=v('sprkrow1_seed'), done=0}
		cray{to=v('sprkrow1_seed'), ct='pscn', done=0}
		ssconv{t='pscn'}
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
			aport{v='data_block'}
			filt{ct=opts.init_data[i][j]}
		end}
	end}

	port{v='make_writer', p=v('data_block'):sw():down(), f=function(opts)
		schem{
			f=vram56_writer,
			p=findpt{ew=opts.p, s=v('data_block'):sw()},
			ref='write_head_nw',
		}
	end}
end

