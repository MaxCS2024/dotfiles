local vars = require("modules.vars")
local mainMod = vars.mainMod

-- A tiled window shrinks while it's carried: see modules/lift.lua.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
