# Mustache-lua

This is binding of [mustache](https://github.com/kirillochnev/mustache)
library to LuaJit.

## How to use

### How to define component
```lua

-- you can provide no constructor
mustache.component("Position{float x, y, z;}")

-- Or you can make component with default value
mustache.component("Rotation{float x, y, z, w;}", {x = 0, y = 0, z = 0, w = 1})

-- You also can use constructor function that will be called every time component is assign
mustache.component("Velocity{float value;}", function(v) v.value = math.random(100) * 0.01 end)
```

### How to create a world

```lua
local world = mustache.World.new(id) -- id is optional
```

### How to create an entity

```
--- create 1 entity without components
entity = world:createEntities(1)

--- create N entities with next components: Position, Rotation, Velocity
entities = world:createEntities(N, "Position", "Rotation", "Velocity")

```

### How to destroy an entity

```lua

--- destroy 1 entity
world:destroyEntities(entity)

--- destroy all(3) entities in a table
world:destroyEntities({e0, e1, e2})

```

### How to make and run a job
```lua
local job = {
    name = "Name of the job",
    -- string names of components, with optional modifiers: '*' (for optional components), 'const' (for non-mutable)
    args = {
        "Position", -- required mutable component
         "const Rotation*", -- const optional component
         "const Velocity" }, -- const required component
    
    
    forEach = function(self, pos, rot, vel)
        -- this function will be called for each entity with 'Position' and 'Velocity' components
        -- value of rot may be nil
    end
}

--- after creating a job, you can run it like below:

world:run(job)
```

## How fast is it

This binding has very good single-threaded performance, only slightly slower than similar C++ code,
see [performance](https://github.com/kirillochnev/mustache#performance) at mustache library
