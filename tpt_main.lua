local SCHEMTOOLS_MAIN = 'schemtools_main'
local DEFAULT_SCHEMTOOLS_PATH = 'schemtools'

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
	schemtools_path = nil,
}

-- 'path' takes the path to the schemtools project directory
-- (i.e. where this file is located). Let me know if there's
-- a way to get this automatically.
function SchemTools:new(path)
	if path == nil then path = DEFAULT_SCHEMTOOLS_PATH end
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.schemtools_path = sanitize_path(path)
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

local function wrap_with_xpcall(func, after_err)
	local function onerr(err)
		print(debug.traceback(err, 2))
		after_err()
	end
	return function(...)
		local ok, ret = xpcall(func, onerr, ...)
		return ret
	end
end

function SchemTools:register_trigger(opts)
	-- default key is Return/Enter
	if opts.key == nil then opts.key = 13 end
	if opts.reload_tools == nil then opts.reload_tools = false end
	if opts.reload == nil then
		opts.reload = (opts.reload_entry ~= nil)
	end
	if opts.reload and opts.reload_prefix == nil then
		opts.reload_prefix = ''
	end
	if opts.use_shortcuts == nil then opts.use_shortcuts = true end

	local function reload_tools()
		if opts.use_shortcuts and self.Main ~= nil then
			self.Main.Shortcuts.teardown_globals()
		end
		unload_modules('schemtools_')
		self.Main = nil
		self.Main =
			require_with_path(self.schemtools_path .. 'src', SCHEMTOOLS_MAIN)
	end

	local designer = nil
	local function on_key(key)
		if key ~= opts.key then return end
		if opts.reload_tools then
			reload_tools()
		end
		if opts.use_shortcuts then
			designer = self.Main.Designer:new()
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
			schematic_func(self.Main)
		end
	end
	event.register(event.keypress, wrap_with_xpcall(on_key))

	local function on_tick()
		if designer ~= nil then
			designer.tester:on_tick()
		end
	end
	event.register(event.tick, wrap_with_xpcall(on_tick, function()
		if designer ~= nil then
			designer.tester:stop()
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
