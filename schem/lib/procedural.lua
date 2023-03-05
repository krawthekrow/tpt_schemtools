require('schem/lib/core')

function shr_1(opts)
	if opts.wordsz == nil then opts.wordsz = 29 end
	local core_num_rows = ilog2(opts.wordsz)

	array{n=core_num_rows, dy=1, f=function(i)
		chain{dx=1, f=function()
			local shift_amt = shl(1, i-1)

			aport{v='core_block'}
			filt{mode='set', ct=shl(1, i-1)}

			aport{v='acol'}
			filt{mode='and'}

			inwr{}

			if i == core_num_rows then
				port{v='res_out'}
			end
			if i == 1 then
				port{cmt=
					'Each DTEC selects the lowest row where a BRAY is present, so that ' ..
					'the final shift is the sum of all shifts in rows where the BRAY ' ..
					'is not annihilated.'
				}
			end
			dtec{to=vv('braycol'), done=0}; inwr{}

			filt{mode='set'}

			inwr{}

			filt{mode='or', ct=shr(ka, shift_amt)}

			filt{mode='<<<', ct=bor(ka, shl(1, shift_amt))}

			aport{v='braycol'}
			adv{}

			aport{v='inslcol'}
			insl{}
		end}
	end}

	chain{dy=-1, p=v('acol'):n(), f=function()
		filt{}
		port{v='a_in', f=function(opts)
			ldtc{to=opts.p, p=v('a_in')}
		end}
	end}

	chain{dx=-1, p=v('inslcol'):n(), f=function()
		insl{}
		adv{}
		filt{mode='set', ct=bor(ka, 1)}
		inwr{}
		inwr{}

		aray{done=0}
		dtec{to=v('braycol'), done=0}
		ssconv{t='inwr'}

		inwr{sprk=1, done=0}
		conv{from='sprk', to='inwr', ox=-1, oy=2, under=1, done=0}
		conv{from='sprk', to='inwr', ox=2, oy=1, under=1}
	end}

	schem{
		f=aray_array_e,
		p=v('core_block'):nw(0),
		ref='logic_nw',
		n=v('core_block'):sz().y,
	}
end
