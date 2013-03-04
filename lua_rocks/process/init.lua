local cwd

if pcall(require, 'ffi') then
  local ffi = require('ffi')
  ffi.cdef [[
    void free(void *);
    char * getcwd(char *);
  ]]

  function cwd() return ffi.string(ffi.gc(ffi.C.getcwd(nil), ffi.C.free)) end
else
  function cwd() return io.popen('pwd'):lines()() end
end

local process = {
  cwd = cwd,
}

if exports then
  module.exports = process
else
  return process
end
