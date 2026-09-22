-- Every bind file, loaded for its side effects. Each one owns the keys
-- its name describes, and modules/vars.lua holds what they share.
require("modules.binds.apps")
require("modules.binds.window")
require("modules.binds.workspaces")
require("modules.binds.monitor")
require("modules.binds.mouse")
require("modules.binds.media")

-- Two toggles that reshape what is already on screen rather than
-- opening anything: a floating zoom on SUPER+F, and chrome-off zen on
-- SUPER+SHIFT+F.
require("modules.binds.alt-fullscreen")
require("modules.binds.zen")
