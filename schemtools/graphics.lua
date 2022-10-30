local Util = require('schemtools/util')
local Geom = require('schemtools/geom')
local Point = Geom.Point

local MOUSE_CMT_LOCK_DIST = 15
local CMT_BOX_MARGIN = 8
local CMT_BOX_MARGIN_ALT = 2
local CMT_BOX_PADDING = 4

local Graphics = {}
function Graphics:new()
	local o = {
		designer = nil,
		mouse_pos = nil,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local function colToRgb(col)
	local r = bit.band(bit.rshift(col, 2 * 8), 0xFF)
	local g = bit.band(bit.rshift(col, 1 * 8), 0xFF)
	local b = bit.band(bit.rshift(col, 0 * 8), 0xFF)
	return r, g, b
end

local function getStacks()
	local function addToStacksDict(dict, partX, partY, partId)
		if dict[partY] == nil then
			dict[partY] = {}
		end
		if dict[partY][partX] == nil then
			dict[partY][partX] = {}
		end
		table.insert(dict[partY][partX], partId)
	end

	local stacks = {}
	for partId in sim.parts() do
		local partX, partY = sim.partPosition(partId)
		partX = math.floor(partX + 0.5)
		partY = math.floor(partY + 0.5)
		addToStacksDict(stacks, partX, partY, partId)
	end

	return stacks
end

function Graphics:on_mousemove(x, y, dx, dy)
	self.mouse_pos = Point:new(x, y)
end

function Graphics:on_prehud()
	if self.designer == nil then
		return
	end

	local zsx, zsy, zssz = ren.zoomScope()
	local zwx, zwy, zoom_factor, zwsz = ren.zoomWindow()
	local zsp = Point:new(zsx, zsy)
	local zwp = Point:new(zwx, zwy)
	local is_zoom_enabled = ren.zoomEnabled()
	local function fill_rect_in_zoom(x, y, w, h, r, g, b, a)
		if x + w <= zwx then return end
		if y + h <= zwy then return end
		if x >= zwx + zwsz then return end
		if y >= zwy + zwsz then return end
		if x < zwx then w = x + w - zwx; x = zwx end
		if y < zwy then h = y + h - zwy; y = zwy end
		if x + w > zwx + zwsz then w = zwx + zwsz - x end
		if y + h > zwy + zwsz then h = zwy + zwsz - y end
		gfx.fillRect(x, y, w, h, r, g, b, a)
	end

	local function is_in_zoom(p)
		return p.x >= zwx and p.y >= zwy and p.x < zwx + zwsz and p.y < zwy + zwsz
	end

	local function draw_cmt_crosshair(in_zoom, x, y, rad, highlight)
		local fill_rect_func = gfx.fillRect
		if in_zoom then fill_rect_func = fill_rect_in_zoom end

		local r, g, b, a = 0xFF, 0x00, 0x00, 0x77
		if highlight then
			r, g, b, a = 0xFF, 0xAA, 0x88, 0xFF
		end
		fill_rect_func(
			x - rad, y, 2 * rad + 1, 1,
			r, g, b, a
		)
		fill_rect_func(
			x, y - rad, 1, 2 * rad + 1,
			r, g, b, a
		)
	end

	local function for_each_cmt(f)
		for cmty, cmtRow in pairs(designer.comments) do
			for cmtx, cmt in pairs(cmtRow) do
				f(Point:new(cmtx, cmty), cmt)
			end
		end
	end

	local selected_cmt_p = nil
	local best_p_distsq = nil
	local mouse_in_zoom = false
	if self.mouse_pos ~= nil then
		mouse_in_zoom = is_zoom_enabled and is_in_zoom(self.mouse_pos)

		for_each_cmt(function(p, cmt)
			if is_zoom_enabled and not mouse_in_zoom and is_in_zoom(p) then
				-- skip comments that are hidden by the zoom window
				return
			end

			-- ref to pixel center
			local target_p
			if mouse_in_zoom then
				target_p = p:sub(zsp):mult(zoom_factor):add(zwp)
				target_p = target_p:add(Point:new(1, 1):mult((zoom_factor - 1) / 2))
			else
				target_p = p:add(Point:new(0.5, 0.5))
			end

			local distsq = self.mouse_pos:sub(target_p):lensq()
			if distsq < MOUSE_CMT_LOCK_DIST * MOUSE_CMT_LOCK_DIST then
				if best_p_distsq == nil or distsq < best_p_distsq then
					best_p_distsq = distsq
					selected_cmt_p = p
				end
			end
		end)
	end

	for_each_cmt(function(p, cmt)
		local is_target = selected_cmt_p ~= nil and p:eq(selected_cmt_p)
		if is_zoom_enabled then
			local p_in_zoom = p:sub(zsp):mult(zoom_factor):add(zwp)
			draw_cmt_crosshair(
				true,
				p_in_zoom.x + (zoom_factor - 1) / 2,
				p_in_zoom.y + (zoom_factor - 1) / 2,
				4, is_target and mouse_in_zoom
			)
		end
		-- don't show comment markers behind zoom window
		if not (is_zoom_enabled and is_in_zoom(p)) then
			draw_cmt_crosshair(false, p.x, p.y, 4, is_target and not mouse_in_zoom)
		end
	end)

	local function make_multiline(txt)
		local LINE_WIDTH_LIMIT = sim.XRES / 2 - 20
		local new_txt = nil
		local cur_line = ''
		local line_start = 1
		local line_end = nil
		local function append_line(l)
			if new_txt == nil then
				new_txt = l
			else
				new_txt = new_txt .. '\n' .. l
			end
		end
		for i = 1, #txt do
			local c = txt:sub(i, i)
			if c == ' ' or c == '\n' then
				if gfx.textSize(txt:sub(line_start, i - 1)) > LINE_WIDTH_LIMIT then
					if line_end ~= nil then
						append_line(txt:sub(line_start, line_end))
						line_start = line_end + 2
					end
				end
				line_end = i - 1
			end
			if c == '\n' then
				append_line(txt:sub(line_start, i - 1))
				line_start = i + 1
				line_end = nil
			end
		end
		if line_start <= #txt then
			append_line(txt:sub(line_start, #txt))
		end
		return new_txt
	end

	if selected_cmt_p ~= nil then
		local cmt = designer.comments[selected_cmt_p.y][selected_cmt_p.x]
		cmt = make_multiline(cmt)
		local cmtw, cmth = gfx.textSize(cmt)
		local boxw, boxh = cmtw + 2 * CMT_BOX_PADDING, cmth + 2 * CMT_BOX_PADDING - 2
		local boxp = self.mouse_pos:add(Point:new(1, 1):mult(CMT_BOX_MARGIN))
		local boxp_alt = self.mouse_pos:sub(Point:new(1, 1):mult(CMT_BOX_MARGIN_ALT))
		boxp_alt = boxp_alt:sub(Point:new(boxw, boxh))
		if self.mouse_pos.x >= sim.XRES / 2 then boxp.x = boxp_alt.x end
		if self.mouse_pos.y >= sim.YRES / 2 then boxp.y = boxp_alt.y end
		local textp = boxp:add(Point:new(1, 1):mult(CMT_BOX_PADDING))

		gfx.fillRect(
			boxp.x, boxp.y, boxw, boxh,
			0x33, 0x33, 0x33, 0xDD
		)
		gfx.drawText(
			textp.x, textp.y, cmt,
			0xEE, 0xEE, 0xEE
		)
	end
end

return Graphics
