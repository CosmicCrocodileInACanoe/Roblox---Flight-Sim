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
	kestrel72 = req("Kestrel72"),
	meridian200 = req("Meridian200"),
	atlas400 = req("Atlas400"),
	celestia800 = req("Celestia800"),
	-- Stunts-mode placeholder; not in `order`, so the airliner fleet checks skip it.
	stunt = req("Stunt"),
}

-- Smallest to largest; the menu shows them in this order.
Registry.order = { "kestrel72", "meridian200", "atlas400", "celestia800" }

Registry.planned = {
	{ id = "regionaljet", label = "Regional twinjet", milestone = 3 },
	{ id = "widebodytwin", label = "Wide-body twinjet", milestone = 3 },
}

-- The aircraft Stunts mode always uses: the fleet's own aerobatic plane when it is
-- registered, otherwise the placeholder racer.
Registry.stuntAircraftId = if Registry.types.sprite then "sprite" else "stunt"

function Registry.get(id: string): any
	return Registry.types[id]
end

return Registry
