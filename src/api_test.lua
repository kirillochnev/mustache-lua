local mustache = require("mustache")
local world = mustache.World.new()
local benchmark = require("benchmark")

mustache.component("Position{float x, y, z;}") -- no constructor
mustache.component("Rotation{float x, y, z, w;}", {x = 0, y = 0, z = 0, w = 1}) -- init with value
mustache.component("Velocity{float value;}", function(v) v.value = math.random(100) * 0.01 end) -- constructor function 

local count = 1000000
local entities
benchmark(function() entities = world:createEntities(count, "Position", "Rotation", "Velocity") end, 1)

local job = {
  args = {"Position", "const Rotation", "const Velocity"},
  forEach = function(pos, q, vel)
    local dt = 1.0 / 60.0
    local dpos = dt * vel.value
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    pos.x = pos.x + (-2.0 * (qx * qz + qw * qy)) * dpos
    pos.y = pos.y + (-2.0 * (qy * qz - qw * qx)) * dpos
    pos.z = pos.z + (-1.0 + 2.0 * (qx^2 + qy^2)) * dpos
  end
}

benchmark(function()
    world:run(job)
end, 100)
