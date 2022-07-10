require('schem/lib/core')

function shr_1(opts)
	if opts.wordsz == nil then opts.wordsz = 29 end
	local core_num_rows = ilog2(opts.wordsz)

	array{n=core_num_rows, dy=1, f=function(i)
		chain{dx=1, f=function()
			aport{v='core_block'}
			filt{mode='set', ct=shl(1, i-1)}
			aport{v='arow'}
			filt{mode='and'}
			inwr{}

			-- fill in the DTEC later
			if i == core_num_rows then port{v='res_out'} end
			port{v='dtec_loc'}; inwr{}
			filt{mode='set'}

			inwr{}
			local shift_amt = shl(1, i-1)
			filt{mode='or', ct=shr(ka, shift_amt)}
			filt{mode='<<<', ct=bor(ka, shl(1, shift_amt))}
			if i == 1 then port{oy=-1, v='brayrow_n'} end
			adv{}
			aport{v='inslcol'}
			insl{}

			dtec{p=v('dtec_loc'), to=v('brayrow_n'), under=1}
		end}
	end}

	chain{dy=-1, p=v('arow'):n():n(), f=function()
		filt{}
		port{v='a_in', f=function(opts)
			ldtc{to=opts.p, p=v('a_in')}
		end}
	end}

	chain{dx=-1, p=v('inslcol'):n():n(), f=function()
		insl{}
		adv{}
		filt{mode='set', ct=bor(ka, 1)}
		inwr{}
		inwr{}
		aray{done=0}
		dtec{to=v('brayrow_n'), done=0}
		ssconv{t='inwr'}
		inwr{sprk=1, done=0}
		conv{from='sprk', to='inwr', ox=-1, oy=2, under=1, done=0}
		conv{from='sprk', to='inwr', ox=2, oy=1, under=1}
	end}

	schem{
		f=aray_array_e,
		p=v('core_block'):nw():w(),
		ref='araycol_ne',
		n=v('core_block'):sw().y - v('core_block'):nw().y + 1,
	}
end
