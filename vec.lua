local ffi = require 'ffi'
local tds = require 'tds.env'
local elem = require 'tds.elem'
local C = tds.C

-- vec-independent temporary buffers
local val__ = C.tds_elem_new()
ffi.gc(val__, C.tds_elem_free)

local vec = {}
local NULL = not jit and ffi.C.NULL or nil

local mt = {}

function mt:insert(...)
   local lkey, lval
   if select('#', ...) == 1 then
      lkey, lval = #self+1, select(1, ...)
   elseif select('#', ...) == 2 then
      lkey, lval = select(1, ...), select(2, ...)
   else
      error('[key] value expected')
   end
   assert(self)
   assert(type(lkey) == 'number' and lkey > 0, 'positive number expected as key')
   if lval then
      elem.set(val__, lval)
   else
      C.tds_elem_set_nil(val__)
   end
   if C.tds_vec_insert(self, lkey-1, val__) == 1 then
      error('out of memory')
   end
end

function mt:remove(lkey)
   lkey = lkey or #self
   assert(self)
   assert(type(lkey) == 'number' and lkey > 0, 'positive number expected as key')
   C.tds_vec_remove(self, lkey-1)
end

function mt:resize(size)
   assert(type(size) == 'number' and size > 0, 'size must be a positive number')
   C.tds_vec_resize(self, size)
end

function vec:__new(...) -- beware of the :
   local self = C.tds_vec_new()
   if self == NULL then
      error('unable to allocate vec')
   end
   self = ffi.cast('tds_vec&', self)
   ffi.gc(self, C.tds_vec_free)
   if select('#', ...) > 0 then
      for key=1,select('#', ...) do
         local val = select(key, ...)
         self[key] = val
      end
   end
   return self
end

function vec:__newindex(lkey, lval)
   assert(self)
   assert(type(lkey) == 'number' and lkey > 0, 'positive number expected as key')
   if lval then
      elem.set(val__, lval)
   else
      C.tds_elem_set_nil(val__)
   end
   if C.tds_vec_set(self, lkey-1, val__) == 1 then
      error('out of memory')
   end
end

function vec:__index(lkey)
   local lval
   assert(self)
   if type(lkey) == 'number' then
      assert(lkey > 0, 'positive number expected as key')
      C.tds_vec_get(self, lkey-1, val__)
      if C.tds_elem_isnil(val__) == 0 then
         lval = elem.get(val__)
      end
   else
      local method = rawget(mt, lkey)
      if method then
         return method
      else
         error('invalid key: number or "insert" or "remove" or "resize" expected')
      end
   end
   return lval
end

function vec:__len()
   assert(self)
   return tonumber(C.tds_vec_size(self))
end

function vec:__ipairs()
   assert(self)
   local k = 0
   return function()
      k = k + 1
      if k <= C.tds_vec_size(self) then
         return k, self[k]
      end
   end
end

vec.__pairs = vec.__ipairs

ffi.metatype('tds_vec', vec)

if pcall(require, 'torch') and torch.metatype then

   function vec:__write(f)
      f:writeLong(#self)
      for k,v in ipairs(self) do
         f:writeObject(v)
      end
   end

   function vec:__read(f)
      local n = f:readLong()
      for k=1,n do
         local v = f:readObject()
         self[k] = v
      end
   end

   vec.__factory = vec.__new
   vec.__version = 0

   torch.metatype('tds_vec', vec, 'tds_vec&')

end

function vec:__tostring()
   local str = {}
   table.insert(str, string.format('tds_vec[%d]{', #self))
   for k,v in ipairs(self) do
      local kstr = string.format("%5d : ", tostring(k))
      local vstr = tostring(v) or type(v)
      local sp = string.rep(' ', #kstr)
      local i = 0
      vstr = vstr:gsub(
         '([^\n]+)',
         function(line)
            i = i + 1
            if i == 1 then
               return kstr .. line
            else
               return sp .. line
            end
         end
      )
      table.insert(str, vstr)
      if k == 20 then
         table.insert(str, '...')
         break
      end
   end
   table.insert(str, '}')
   return table.concat(str, '\n')
end

-- table constructor
local vec_ctr = {}
setmetatable(
   vec_ctr,
   {
      __index = vec,
      __newindex = vec,
      __call = vec.__new
   }
)
tds.vec = vec_ctr

return vec_ctr
