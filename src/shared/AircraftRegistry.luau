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
	bumble = req("Bumble"),
	puffin = req("Puffin"),
	breezetwin = req("BreezeTwin"),
	ridgehopper = req("Ridgehopper"),
	silverline8 = req("Silverline8"),
	vectorx1 = req("VectorX1"),
	nightjart2 = req("NightjarT2"),
	swiftletj3 = req("SwiftletJ3"),
	kestrel72 = req("Kestrel72"),
	meridian200 = req("Meridian200"),
	hauler4 = req("Hauler4"),
	atlas400 = req("Atlas400"),
	arrowstar = req("Arrowstar"),
	celestia800 = req("Celestia800"),
}

-- Smallest to largest; the menu shows them in this order.
Registry.order = { "bumble", "meadowlark4", "sprite", "ridgehopper", "puffin", "breezetwin", "silverline8", "swiftletj3", "vectorx1", "nightjart2", "kestrel72", "meridian200", "hauler4", "atlas400", "arrowstar", "celestia800" }

Registry.planned = {
	{ id = "regionaljet", label = "Regional twinjet", milestone = 3 },
	{ id = "widebodytwin", label = "Wide-body twinjet", milestone = 3 },
}

function Registry.get(id: string): any
	return Registry.types[id]
end

return Registry
