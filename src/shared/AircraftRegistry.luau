--!strict
-- All aircraft types. Milestone 1 ships one polished type; the others are listed so the
-- menu can show the roadmap, and are locked until their profiles pass the same tests.

local Registry = {}

Registry.types = {
	meridian200 = require(script.Parent.Aircraft.Meridian200),
}

Registry.order = { "meridian200" }

Registry.planned = {
	{ id = "turboprop", label = "Regional turboprop", milestone = 2 },
	{ id = "regionaljet", label = "Regional twinjet", milestone = 2 },
	{ id = "narrowbodyB", label = "Narrow-body twinjet B", milestone = 2 },
	{ id = "widebody", label = "Wide-body twinjet", milestone = 2 },
	{ id = "jumbo", label = "Four-engine jumbo", milestone = 2 },
}

function Registry.get(id: string): any
	return Registry.types[id]
end

return Registry
