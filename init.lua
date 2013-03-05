package.searchpath = package.searchpath or function(name, paths)
  local alt_path = package.config:sub(3, 3)
  for pat in paths:gmatch('([^' .. alt_path .. ']+)' .. alt_path .. '?') do
    local filename = pat:gsub('%?', name)
    local file = io.open(filename, 'r')
    if file then
      file:close()
      return filename
    end
  end
end

-- search for the path that led to inclusion of this file
local __filename = package.searchpath('lpm', package.path)
local sep = package.config:sub(1, 1)
local mydeps = table.concat({__filename:gsub(sep .. '?[^' .. sep .. ']+$', ''), 'lua_rocks', '?', 'init.lua'}, sep)

-- temporarily initialize loading to desired style to get dependencies
package.path = mydeps .. package.config:sub(3, 3) .. package.path

local debug = require 'debug'
local path = require 'path'
local cwd = require('process').cwd()
local require_mod

-- compatability with 5.2. Unfortunately since we really break function
-- encapsulation by modifying the calling function environment we need to use
-- this instead of the nicer and simpler _ENV. If we didn't care about
-- modifying the calling enviornment all new requires could use the _ENV method
-- for setting the module, module.exports, __filename, require, etc overrides
local setfenv = setfenv or function(fun, env)
  fun = type(fun) == 'function' and fun or debug.getinfo(fun + 1, 'f').func
  local up, name = 0
  repeat
    up = up + 1
    name = debug.getupvalue(fun, up)
  until name == '_ENV' or not name
  if name then
    debug.upvaluejoin(fun, up, function() return env end, 1)
  end
end

-- cache the metatable that all modules will share
local global_mt = { __index = _G }

local function loadmodule(code, filename, moduledir, parent)
  local module = {
    exports = {},
    children = {},
    parent = parent,
    filename = filename,
  }

  module.require = function(name)
    local mod = require_mod(name, moduledir, module)
    table.insert(module.children, mod)
    return mod.exports
  end

  -- setup module to have an environment insulated from the global environment
  -- and offers useful metadata such as filename and dirname. It follows
  -- closesly the module system in nodejs where possible
  setfenv(code, setmetatable({
    __filename = filename,
    __dirname = moduledir,
    module = module,
    exports = module.exports,
    require = module.require,
  }, global_mt))

  -- probably should use readlink to give aboslute path so symlinks don't cause
  -- multiple loadings of same file.
  if type(code) == 'function' then code() end
  package.loaded[filename] = module
  return package.loaded[filename]
end

-- modify the calling environment to match the assumptions of the new module
-- setup. The level up the stack assumes that the require is in the main chunk
-- and not whithin some other function. The level used works on 5.1.5, 5.2.1
-- and luajit 2.0.1 tested.
loadmodule(4,
  path.normalize(cwd .. path.sep .. path.filename(debug.getinfo(3, 'S').source:sub(2))),
  cwd)

-- modify this environment to have the module setup
loadmodule(2, __filename, path.dirname(__filename))

local builtin = package.loaders[1]

-- possible locations to load when assumed to be a file
local function possible_as_file(filename)
  return coroutine.wrap(function()
    coroutine.yield(filename)
    coroutine.yield(filename .. '.lua')
    coroutine.yield(filename .. '.so', true)
  end)
end

-- possible locations to load when assumed to be a folder
local function possible_as_folder(dirname)
  return coroutine.wrap(function()
    local package = loadfile(dirname .. 'package.lua')
    if package then
      package = package()
      if package and package.main then
        for filename in possible_as_file(dirname .. package.main) do
          coroutine.yield(filename)
        end
      end
    end
    coroutine.yield(dirname .. 'init.lua')
    coroutine.yield(dirname .. 'init.so', true)
  end)
end

-- combination of possible file and folder while file taking precedence
local function possible(filename)
  return coroutine.wrap(function()
    for filename, loader in possible_as_file(filename) do
      coroutine.yield(filename, loader)
    end

    for filename in possible_as_folder(filename .. path.sep) do
      coroutine.yield(filename, loader)
    end
  end)
end

--- Follow module loading scheme as used by node
-- http://nodejs.org/api/modules.html#modules_all_together
function require_mod(name, dirname, parent)
  local errors, filename = {}

  -- on all platforms / is the separator for require and it is made platform
  -- specific here
  name = name:gsub('/', path.sep)

  -- builtin modules
  if package.loaded[name] then return package.loaded[name] end
  --[[
  if name:find("^[A-Za-z_]+$") then
    local code = builtin(name)
    if type(code) == 'function' then
      package.loaded[name] = code()
      return package.loaded[name]
    else
      table.insert(errors, code)
    end
  end
  --]]
  
  -- honor the stripping of content up to first hyphen when generating name to
  -- search for in dynamic lib for module initialization function
  local clibname = "luaopen_" .. path.filename(name):lower():gsub('^[^-]+-', '')

  -- relative paths to file
  if name:find("^%.?%.?" .. path.sep) then
    for filename, clib in possible(path.normalize(dirname .. path.sep .. name)) do
      if package.loaded[filename] then return package.loaded[filename] end

      local code, msg = clib and package.loadlib(filename, clibname) or loadfile(filename)
      if code then
        return loadmodule(code, filename, path.parent(filename))
      else
        table.insert(errors, msg)
      end
    end
  end

  -- packaged modules and dependencies found inside luarocks folder
  local atroot = false
  repeat
    atroot = path.is_root(dirname)
    filename = (atroot and '' or dirname) .. path.sep .. 'lua_rocks' .. path.sep .. name
    for filename, clib in possible(filename) do
      if package.loaded[filename] then return package.loaded[filename] end

      local code, msg = clib and package.loadlib(filename, clibname) or loadfile(filename) 
      if code then
        return loadmodule(code, filename, path.parent(filename))
      else
        table.insert(errors, msg)
      end
    end
    dirname = path.parent(dirname)
  until atroot

  error(('Failed to find module %q\n  '):format(name) .. table.concat(errors, "\n  "))
end

-- Remove the temporary loaded dependencies so they can be properly loaded if
-- needed later
package.loaded['path'] = nil
package.loaded['process'] = nil

-- modify all loaed modules to be in the exports format
for k, v in pairs(package.loaded) do
  package.loaded[k] = {exports = v}
end

-- require 'semver'
-- require './test'
-- require 'rc'
-- path = require 'path'
-- print(path.parent)
