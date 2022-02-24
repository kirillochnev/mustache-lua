local ffi = require("ffi")

local function readHeader()
  local end_if = "#endif"
  local str = io.open("c_api.h", "r"):read("*all"):gsub("MUSTACHE_EXPORT", ""):match("#ifdef __cplusplus.*#ifdef __cplusplus")
  local start = str:find(end_if)
  local npos = #str - #"#ifdef __cplusplus"
  return str:sub(start + #end_if, npos)
end

ffi.cdef(readHeader())

local function getLibName()
  local os_name = jit.os
  if os_name == "Windows" then
    return "./mustache.dll"
  end
  if os_name == "Linux" then
    return "./libmustache.so"
  end
  error("Unsupported OS: " + os_name)
end

local mustache = ffi.load(getLibName())

ffi.cdef("void free(void*)")
local lib = {
  _native = mustache,
  _Components = {},
  _Jobs = {}
}
local world = {}
world.__index = world

local function removeComments(str)
  return str -- TODO: impt me
end

local function getFields(def)
  return def:match("{.*}")
end

local function ptrToKey(ptr)
  return tonumber(ffi.cast("uint64_t", ptr))
end

local function getFieldsEscapeStr(fields)
  local escape_table = {"%", "'", '"', "(", ")", ".", "-", "*", "[", "]", "?", "^", "$"}
  local result = fields
  for _, char in pairs(escape_table) do
    result = result:gsub("%" .. char, "%%" .. char)
  end
  return result
end

local function getName(def, fields)
  local escape_table = {" ", "struct", "typedef", ";"}
  local name = def:gsub(getFieldsEscapeStr(fields), "")
  for _, char in pairs(escape_table) do
    name = name:gsub(char, "")
  end

  return name
end

local function parseComponentDefinition(def)
  local fields = getFields(def)
  local name = getName(def, fields)
  return {
    name = name,
    cdef = "typedef struct" .. fields .. name .. ";"
  }
end

local function makeConsructor(ctype, constructor)
  if (type(constructor) == "function") then
    return function(void_ptr) constructor(ffi.cast(ctype, void_ptr)) end
  end
end

local function makeDefaultValue(ctype, value)
  if (type(value) == "table") then
    return ctype(value)
  end
end
local function makeTypeInfo(name, ctype, constructor)
  local info = ffi.new("TypeInfo")
  info.size = ffi.sizeof(ctype)
  info.align = ffi.alignof(ctype)
  info.name = name
  info.functions.create = makeConsructor(ffi.typeof(name .. '*'), constructor)
  info.default_value = makeDefaultValue(ctype, constructor)
  info.functions.move = nil
  info.functions.copy = nil
  return info
end

local function registerComponent(def, default_value)
  def = removeComments(def)
  local info = parseComponentDefinition(def)
  ffi.cdef(info.cdef)

  local result = {
    name = info.name,
    cdef = info.cdef,
    ctype = ffi.typeof(info.name),
    ptr_type = ffi.typeof(info.name .. '*'),
    const_ptr_type = ffi.typeof(info.name .. " const *")
  }
  result.type_id = mustache.registerComponent(makeTypeInfo(result.name, result.ctype, default_value))
  lib._Components[result.type_id] = result
  lib._Components[result.ctype] = result
  lib._Components[result.name] = result
  lib._Components[result] = result
  return result
end

function lib.component(str, default_value)
  if lib._Components[str] == nil then
    registerComponent(str, default_value)
  end
  return lib._Components[str]
end

local function makeJobArgInfo(str)
  local name = str:gsub("const", ""):gsub("%*", ""):gsub(" ", "")
  if name == "Entity" then return end
  
  local ptr_pos = str:find("%*")
  local is_required = ptr_pos == nil
  local const_pos = str:find("const")
  local is_const = const_pos ~= nil
  if is_const and not is_required and ptr_pos < const_pos then
    is_const = false
  end
  
  local result = ffi.new("JobArgInfo")
  result.is_const = is_const
  result.is_required = is_required
  result.component_id = lib.component(name).type_id
  
  local type_str = (is_const and "const " or "") .. name .. "*"
  return result, name, ffi.typeof(type_str)
end



local function hasEntityArg(job)
  return (#job.args > 0) and (makeJobArgInfo(job.args[1]) == nil)
end


local function_prototype = 
[[return function(self, callback, cast_to, ffi)
  return function(_, call_args)
    VARIABLES
    FOR_BEGIN
    CALL
    FOR_END
  end
end]]

local function makeForStrs(array)
  if array then return "", "" end
  return "for i = 0, call_args.array_size - 1 do", "end"
end

local function makeVariableDeclarations(count)
  local str = "\n"
  for i = 1, count do
    str = str .. string.format("    local var%d = ffi.cast(cast_to[%d], call_args.components[%d])\n", i - 1, i, i - 1)
  end
  return str
end

local function makeCallDeclaration(job_desc, array)
  local entity_required = job_desc.entity_required
  local offset = (entity_required and 1 or 0)
  local count = job_desc.component_info_arr_size + offset
  local str = "callback(self" .. (count > 0 and ", " or "")
  
  if not array then
    str = "  " .. str
  else
    str = str .. "call_args.array_size, "
  end

  for index = 1, count do
    local var_str = "var" .. (index - 1)
    local i = index - offset
    local is_required = true
    if (not entity_required) or index > 1 then
      is_required = job_desc.component_info_arr[i - 1].is_required
    end

    if not array then
      if not is_required then
        var_str = var_str .. " and " .. var_str
      end
      var_str = var_str .. " + i"
    end
    
    str = str .. var_str .. (index < count and ", " or ")\n")
  end

  return str
end

local function makeJobEvent(callback, job)
  if callback ~= nil then
    return function(ptr, task_count, total_count, mode)
      callback(job, total_count)
    end
  end
end

local function makeJob(world, job)
  local job_desc = ffi.new("JobDescriptor")
  
  job_desc.name = name or "NoName"
  job_desc.entity_required = hasEntityArg(job)
  job_desc.component_info_arr_size = job_desc.entity_required and (#job.args - 1) or #job.args
  job_desc.component_info_arr = ffi.new("JobArgInfo[?]", job_desc.component_info_arr_size)
  if job.check_update then
    job_desc.check_update_size = #job.check_update
    job_desc.check_update = ffi.new("ComponentId[?]", #job.check_update)
    for i = 1, #job.check_update do
      job_desc.check_update[i - 1] = lib.component(job.check_update[i]).type_id
    end
  else
    job_desc.check_update_size = 0
    job_desc.check_update = nil
  end

  local index_offset = job_desc.entity_required and 1 or 0

  local cast_to = {}
  if job_desc.entity_required then
    cast_to[1] = ffi.typeof("const Entity*")
  end
  
  for i = 1 + index_offset, #job.args do
    local info, name, type_to_cast = makeJobArgInfo(job.args[i])
    job_desc.component_info_arr[i - index_offset - 1] = info
    cast_to[i] = type_to_cast
  end
  local array_function = (job.forEach == nil)
  local callback = job.forEach or job.forEachArray
  local var_decl = makeVariableDeclarations(#cast_to)
  local start, finish = makeForStrs(array_function)
  local call = makeCallDeclaration(job_desc, array_function)
  local str = function_prototype:gsub("VARIABLES", var_decl):gsub("FOR_BEGIN", start):gsub("FOR_END", finish):gsub("CALL", call)
  local new_callback = loadstring(str)()(job, callback, cast_to, ffi)  
  jit.flush(new_callback)
  job_desc.callback = new_callback
  job_desc.on_job_begin = makeJobEvent(job.onBegin, job)
  job_desc.on_job_end = makeJobEvent(job.onEnd, job)
  local native_job = ffi.gc(mustache.makeJob(job_desc), mustache.destroyJob)
  return native_job, desc, str
end

function lib.Job(job)
  if job._native_ptr == nil then
    local ptr, decs, str = makeJob(self, job)
    job._native_ptr = ptr
    job._decsriptor = desc
    job._source_code = str
    lib._Jobs[ptrToKey(ptr)] = job
  end
  return job
end

function world.run(self, job)
  mustache.runJob(lib.Job(job)._native_ptr, self._WorldPtr, mustache.kCurrentThread)
end

function world.createEntities(self, first, ...)
  local args = {...}
  local count = 1
  if type(first) == "number" then
    count = first
  else
    table.insert(args, first)
  end
  local mask = ffi.new("uint64_t")
  for i = 1, #args do
    local id = lib.component(args[i]).type_id
    mask = mask + 2 ^ (id)
  end
  local archetype = mustache.getArchetypeByBitsetMask(self._WorldPtr, mask)
  local group = ffi.new("Entity[?]", count)
  mustache.createEntityGroup(self._WorldPtr, archetype, group, count)
  return group
end


function world.assign(self, entity, component, value, ...)
  local info = lib.component(component)
  local custom_init = value ~= nil
  local ptr = mustache.assignComponent(self._WorldPtr, entity, info.type_id, custom_init)
  ptr = ffi.cast(info.ptr_type, ptr)
  if custom_init then
    ptr[0] = info.ctype(value, ...)
  end
  return ptr
end

function world.getComponent(self, entity, component, const)
  local info = lib.component(component)
  if const == false then
      local ptr = mustache.getComponent(self._WorldPtr, entity, info.type_id, false)
      return ffi.cast(info.ptr_type, ptr)
  else
      local ptr = mustache.getComponent(self._WorldPtr, entity, info.type_id, true)
      return ffi.cast(info.const_ptr_type, ptr)
  end
end

function world.getConstComponent(self, entity, component)
  return world.getComponent(self, entity, component, true)
end

function world.getMutableComponent(self, entity, component)
  return world.getComponent(self, entity, component, false)
end

function world.update(self)
  mustache.updateWorld(self._WorldPtr)
end

function world.destroyEntities(self, entities, count, now)
  if type(count) == "bool" then
    now = count
  end

  local arr
  if type(entities) == "table" then
    arr = ffi.new("Entity[?]", #entities)
    for i = 1, #entities do
      arr[i - 1] = entities[i]
    end
    count = #entities
  else
    arr = entities
    count = count or 1
  end
  if now == nil then
    now = false
  end
  mustache.destroyEntities(self._WorldPtr, arr, count, now)
end

lib.World = {
  new = function(id)
    local w = mustache.createWorld(id and id or -1)
    w = ffi.gc(w, mustache.destroyWorld)
    return setmetatable({_WorldPtr = w}, world) --ffi.metatype(res, world)
  end
}

return lib
