require '../../init'
local path = require 'path'
local errors = {}

setmetatable(_G, {
  __gc = function()
    for err in errors do print('Failed: ' .. err) end
  end,
})

local function test(name)
  return function(test)
    local ok, msg = pcall(test)
    io.stdout:write(ok and '.' or 'F')
    if not ok then table.insert(errors, {name = name, msg = msg}) end
  end
end

local function assert_equal(a, b)
  if a ~= b then
    error(("\n\tgot: %q\n\texpected: %q"):format(tostring(a), tostring(b)))
  end
end

test 'get parent of directory' (function()
  assert_equal(path.parent('/some/path'), '/some')
end)

test 'get parent directory of /' (function()
  assert_equal(path.parent('/'), '/')
end)

test 'get parent directory of /path' (function()
  assert_equal(path.parent('/path'), '/')
end)

if #errors > 0 then print '\n' end
for _, err in pairs(errors) do print('Failed: ' .. err.name .. ': ' .. err.msg) end
