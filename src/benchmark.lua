--void runBenchmark(void(*callback)(), uint32_t iterations, uint32_t op_per_iteration);
local now = os.clock

local report = "Call count: %d, Arv: %s, Med: %s, Min: %s, Max: %s"

local function toStr(t, count)
  if count and count > 0 then
    return (count / t) .. "op/s"
  else
    return (1000 * t) .. "ms"
  end
end

return function(f, iterations, count)
  local toStr = function(dt) return toStr(dt, count) end
  local t = {}
  local avr = 0
  for i = 1, iterations do
    local begin = now()
    f()
    local dt = now() - begin
    t[i] = dt
    avr = avr + dt
  end
  table.sort(t)
  if iterations < 2 then
    print(toStr(t[1]))
  else
    print(report:format(
        iterations,
        toStr(avr / iterations),
        toStr(t[math.floor(#t / 2)]),
        toStr(t[1]),
        toStr(t[#t])
    ))
  end
end