--!strict
-- All aircraft types. Each one must pass the offline fleet tests (tests/test_fleet.luau).

local Registry = {}

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent.Aircraft[name])
	end
	return (require :: any)("./Aircraft/" .. name)
end

Registry.types = {
	meadowlark4 = req("Meadowlark4"),
	sprite = req("Sprite"),
	puffin = req("Puffin"),
	silverline8 = req("Silverline8"),
	kestrel72 = req("Kestrel72"),
	meridian200 = req("Meridian200"),
	atlas400 = req("Atlas400"),
	celestia800 = req("Celestia800"),
}

-- Smallest to largest; the menu shows them in this order.
Registry.order = { "meadowlark4", "sprite", "puffin", "silverline8", "kestrel72", "meridian200", "atlas400", "celestia800" }

Registry.planned = {
	{ id = "regionaljet", label = "Regional twinjet", milestone = 3 },
	{ id = "widebodytwin", label = "Wide-body twinjet", milestone = 3 },
}

function Registry.get(id: string): any
	return Registry.types[id]
end

return Registry
