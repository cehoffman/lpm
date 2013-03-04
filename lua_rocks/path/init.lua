local sep = package.config:sub(1, 1)
local this_dir = sep .. '%.' .. sep
local back_dir = sep .. '[^' .. sep .. ']+' .. sep .. '%.%.' .. sep
local multi = sep .. '+'
local filename_capture = '([^' .. sep .. ']+)$'
local backup_dir = sep .. '[^' .. sep .. ']+$'

local function dirname(self)
  local path = self:gsub(backup_dir, '')
  return path == '' and path.sep or path
end

local path = {
  normalize = function(self)
    return self:gsub(this_dir, sep):gsub(back_dir, sep):gsub(multi, sep)
  end,
  filename = function(self) 
    return self:sub(self:find(filename_capture))
  end,
  extname = function(self)
    local start, stop = self:find('%.[^%.]+$')
    return start and self:sub(start, stop) or ''
  end
  is_root = function(self) 
    return self:gsub('%w:', '') == sep
  end
  dirname = dirname,
  parent = dirname,
  sep = sep
}



if exports then
  module.exports = path
else
  return path
end
