-- expected directory structure for default settings:
--
-- <your powder toy directory>
-- ├── powder
-- ├── autorun.lua
-- └── schemtools
--     ├── schem
--     │   ├── main.lua (entry point for your schematic)
--     │   └── ...
--     ├── schemtools
--     │   ├── main.lua (entry point for schemtools lib)
--     │   └── ...
--     └── tpt_main.lua (this file)

local DEFAULT_SCHEMTOOLS_PATH = 'schemtools'
local SCHEMTOOLS_PREFIX = 'schemtools/'
local SCHEMTOOLS_ENTRY = 'schemtools/main'
local DEFAULT_RELOAD_KEY = 13 -- Return/Enter
local DEFAULT_CMT_KEY = 97 -- 'A' key

local function str_startswith(str, prefix)
	return str:sub(1, #prefix) == prefix
end

local function sanitize_path(path)
	if path:sub(path:len()) ~= '/' then
		path = path .. '/'
	end
	if not str_startswith(path, './') and not str_startswith(path, '/') then
		path = './' .. path
	end
	return path
end

SchemTools = {
}

function SchemTools:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self
	return o
end

local function unload_modules(prefix)
	for name, _ in pairs(package.loaded) do
		if str_startswith(name, prefix) then
			package.loaded[name] = nil
		end
	end
end

local function require_with_path(path, mod_name)
	local oldpath = package.path
	if path ~= nil then
		path = sanitize_path(path)
		package.path = path .. '?.lua;' .. package.path
	end
	local module = require(mod_name)
	package.path = oldpath
	return module
end

function SchemTools:register_trigger(opts)
	if opts.key == nil then opts.key = DEFAULT_RELOAD_KEY end
	if opts.cmt_key == nil then opts.cmt_key = DEFAULT_CMT_KEY end
	if opts.reload_tools == nil then opts.reload_tools = false end
	if opts.reload == nil then
		opts.reload = (opts.reload_entry ~= nil)
	end
	if opts.reload and opts.reload_prefix == nil then
		opts.reload_prefix = ''
	end
	if opts.use_shortcuts == nil then opts.use_shortcuts = true end
	if opts.schemtools_path == nil then
		opts.schemtools_path = DEFAULT_SCHEMTOOLS_PATH
	end
	opts.schemtools_path = sanitize_path(opts.schemtools_path)

	local designer = nil
	local graphics = nil
	local function reload_tools()
		if opts.use_shortcuts and self.Main ~= nil then
			self.Main.Shortcuts.teardown_globals()
		end
		unload_modules(SCHEMTOOLS_PREFIX)
		self.Main = nil
		self.Main = require_with_path(
			opts.schemtools_path, SCHEMTOOLS_ENTRY
		)
	end
	reload_tools()

	local function wrap_with_xpcall(...)
		return self.Main.Util.wrap_with_xpcall(...)
	end
	local err_ctx = self.Main.Util.make_err_ctx()

	local function trigger_reload()
		if opts.reload_tools then
			reload_tools()
		end
		designer = self.Main.Designer:new()
		designer.err_ctx = err_ctx
		graphics = self.Main.Graphics:new()
		graphics.designer = designer
		graphics.cmt_key = opts.cmt_key
		if opts.use_shortcuts then
			self.Main.Shortcuts.init(designer)
		end
		if opts.reload then
			if opts.reload_prefix == nil then
				package.loaded[opts.reload_entry] = nil
			else
				unload_modules(opts.reload_prefix)
			end
			local schematic_func =
				require_with_path(opts.reload_path, opts.reload_entry)
			print()
			print('=============== STARTING NEW RUN ===============')
			self.Main.Util.clear_err_ctx(err_ctx)
			wrap_with_xpcall(schematic_func, {err_ctx = err_ctx})(self.Main)
		end
	end

	local function on_key_down(key, scan, is_repeat, shift, ctrl, alt)
		if is_repeat then return end
		if key == opts.key and not shift and not ctrl and not alt then
			trigger_reload()
			return false
		end
		if graphics ~= nil then
			return graphics:on_key_down(key, shift, ctrl, alt)
		end
	end
	event.register(event.keypress, wrap_with_xpcall(on_key_down))

	local function on_key_up(key, scan, is_repeat, shift, ctrl, alt)
		if is_repeat then return end
		if graphics ~= nil then
			return graphics:on_key_up(key, shift, ctrl, alt)
		end
	end
	event.register(event.keyrelease, wrap_with_xpcall(on_key_up))

	local function on_tick()
		if designer ~= nil then
			designer.tester:on_tick()
		end
	end
	event.register(event.tick, wrap_with_xpcall(on_tick, {
		after_err=function()
			if designer ~= nil then
				designer.tester:stop()
			end
		end
	}))

	-- Graphics

	local graphics_event = event.tick
	if event.prehuddraw ~= nil then
		-- If prehuddraw (from subframe mod) is supported, use it
		-- to draw in the zoom window below the game's HUD.
		graphics_event = event.prehuddraw
	end
	event.register(graphics_event, wrap_with_xpcall(function()
		if graphics ~= nil then
			graphics:on_prehud()
		end
	end))
	event.register(event.mousemove, wrap_with_xpcall(function(x, y, dx, dy)
		if graphics ~= nil then
			graphics:on_mousemove(x, y, dx, dy)
		end
	end))
end

function SchemTools:register_default_trigger()
	self:register_trigger{
		reload_tools = true,
		reload_path = 'schemtools',
		reload_prefix = 'schem/',
		reload_entry = 'schem/main',
	}
end
