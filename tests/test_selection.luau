--!nonstrict
-- Menu / spawn selection rules (src/shared/Selection.luau): every aircraft and airport
-- can be picked, every "Start at" list starts on a runway, routes follow the airport,
-- and every aircraft fits every runway and gate it is offered.
local Selection = require("../src/shared/Selection")
local Airports = require("../src/shared/Airports")
local Registry = require("../src/shared/AircraftRegistry")
local Units = require("../src/shared/Units")

local MODES = { "free", "airline", "sandbox" }

return { name = "Aircraft and airport selection", run = function(T)
	T.test("every unlocked aircraft in registry order is flyable", function()
		local ids = Selection.flyableAircraft(Registry)
		T.check(#ids == #Registry.order, "every aircraft type unlocked")
		for i, id in Registry.order do
			T.check(ids[i] == id, "order kept: " .. id)
		end
		local fake = { order = { "a", "b", "c" }, types = { a = { unlocked = true }, b = { unlocked = false } } }
		local f = Selection.flyableAircraft(fake)
		T.check(#f == 1 and f[1] == "a", "locked and missing types are left out")
	end)

	T.test("every Start at list begins with a runway, then gates, then approaches", function()
		local rank = { runway = 1, gate = 2, water = 2.5, approach = 3, air = 4 }
		for _, id in Registry.order do
			local cfg = Registry.get(id)
			for _, ap in Airports.order do
				for _, mode in MODES do
					for _, dest in { false, "HBR", "RDV" } do
						local list = Selection.spawnList(ap, cfg, mode, dest or nil)
						T.check(#list > 0, "never empty")
						T.check(list[1].kind == "runway", `{id} {ap} {mode}: first start is a runway`)
						T.check(Selection.defaultSpawn(ap, cfg, mode, dest or nil).id == list[1].id)
						local last = 0
						local seen = {}
						for _, s in list do
							T.check(rank[s.kind] >= last, `{id} {ap} {mode}: kinds in order`)
							last = rank[s.kind]
							T.check(not seen[s.id], "no duplicates: " .. s.id)
							seen[s.id] = true
							if s.kind == "runway" or s.kind == "gate" then
								T.check(s.airport == ap, `ground start {s.id} belongs to {ap}`)
							end
						end
					end
				end
			end
		end
	end)

	T.test("approaches: own airport in free flight, route destination in airline mode", function()
		local cfg = Registry.get("meridian200")
		for _, s in Selection.spawnList("HBR", cfg, "free", "RDV") do
			if s.kind == "approach" then
				T.check(s.airport == "HBR", "free flight approach is into the chosen airport")
			end
		end
		local n = 0
		for _, s in Selection.spawnList("HBR", cfg, "airline", "RDV") do
			if s.kind == "approach" then
				n += 1
				T.check(s.airport == "RDV", "airline approach skips to the destination")
			end
			T.check(s.kind ~= "air", "no free-air starts in airline mode")
		end
		T.check(n == 2, "both runway ends")
		local hasAir = false
		for _, s in Selection.spawnList("RDV", cfg, "sandbox") do
			hasAir = hasAir or s.kind == "air"
		end
		T.check(hasAir, "sandbox keeps the in-flight starts")
	end)

	T.test("all gates and runways of each airport are offered to every aircraft", function()
		for _, id in Registry.order do
			local cfg = Registry.get(id)
			for _, ap in Airports.order do
				T.check(Selection.runwayFits(cfg, ap), `{id} fits the {ap} runway`)
				T.check(Selection.gateFits(cfg, ap), `{id} fits {ap} gates: {tostring(Selection.gateProblem(cfg, ap))}`)
				local gates = 0
				for _, s in Selection.spawnList(ap, cfg, "free") do
					if s.kind == "gate" then
						gates += 1
					end
				end
				T.check(gates == Airports.list[ap].gates, `{id} at {ap}: all gates listed`)
			end
		end
	end)

	T.test("jumbo footprints at the gates clear neighbours, jet bridges and the taxiway", function()
		local SPM = Units.STUDS_PER_METER
		for _, ap in Airports.order do
			local l = Airports.layout(ap)
			for _, id in { "atlas400", "celestia800" } do
				local span, nose, tail = Selection.dimensions(Registry.get(id))
				-- Two of the same jumbo side by side.
				local spacing = Airports.list[ap].gateSpacingM
				T.check(spacing - span >= 7.5, `{id} wingtip clearance {spacing - span} m at {ap}`)
				for _, g in l.gates do
					local _, cross = Airports.toRunway(l, g.x, g.z)
					local lat = math.abs(cross) / SPM
					T.check(lat + tail < math.abs(l.terminalNear) / SPM - 12, `{id} tail clear of the jet bridges`)
					T.check(lat - nose > math.abs(l.apronNear) / SPM, `{id} nose stays on the apron`)
					T.check(math.abs(g.along) / SPM + span / 2 < l.apronHalfLen / SPM, `{id} wingtip stays on the apron`)
				end
			end
		end
		T.check(Selection.dimensions(Registry.get("atlas400")) > 60, "Atlas span from config")
		T.check(Selection.dimensions(Registry.get("celestia800")) > 75, "Celestia span from config")
	end)

	T.test("a too-big aircraft loses the gates and keeps the runways", function()
		local huge = { id = "test-huge", aero = { wingSpan = 120 }, geometry = { fuselage = { noseZ = -40, tailEndZ = 40 } } }
		T.check(not Selection.gateFits(huge, "HBR"), "120 m span doesn't fit 95 m stands")
		local list = Selection.spawnList("HBR", huge, "free")
		T.check(list[1].kind == "runway")
		for _, s in list do
			T.check(s.kind ~= "gate", "no gates offered")
		end
		local long = { id = "test-long", minRunwayM = 5000, aero = { wingSpan = 30 } }
		T.check(not Selection.runwayFits(long, "RDV"))
		T.check(Selection.spawnList("RDV", long, "airline", "HBR")[1].kind == "runway", "still starts on a runway")
	end)

	T.test("routes and destinations follow the departure airport", function()
		for _, ap in Airports.order do
			local routes = Selection.routesFrom(ap)
			T.check(#routes >= 1, ap .. " has a route")
			for _, r in routes do
				T.check(r.from == ap)
			end
			local airline = Selection.destinations(ap, "airline")
			T.check(#airline == #routes and airline[1] == routes[1].to, "airline: first route first")
			for _, d in airline do
				T.check(d ~= false and d ~= ap, "airline always has a real destination")
			end
			local free = Selection.destinations(ap, "free")
			T.check(#free == #routes + 1 and free[#free] == false, "free flight: destination optional")
		end
	end)

	T.test("server-side spawn resolution accepts offered ids and defaults to the first runway", function()
		for _, id in Registry.order do
			local cfg = Registry.get(id)
			for _, ap in Airports.order do
				for _, mode in MODES do
					local dest = Selection.destinations(ap, mode)[1] or nil
					local list = Selection.spawnList(ap, cfg, mode, dest)
					for _, s in list do
						T.check(Selection.resolveSpawn(s.id, ap, cfg, mode, dest).id == s.id, "accepts " .. s.id)
					end
					local first = Selection.resolveSpawn("nope", ap, cfg, mode, dest)
					T.check(first.kind == "runway" and first.airport == ap, "invalid id -> first runway")
					T.check(Selection.resolveSpawn(nil, ap, cfg, mode, dest).id == first.id, "missing id -> first runway")
				end
			end
		end
		-- a gate at the other airport is not accepted for this airport
		local cfg = Registry.get("kestrel72")
		local sp = Selection.resolveSpawn("RDV-gate1", "HBR", cfg, "free", nil)
		T.check(sp.airport == "HBR" and sp.kind == "runway", "wrong-airport gate falls back")
		-- in airline mode the free-air starts are refused
		T.check(Selection.resolveSpawn("air-cruise", "HBR", cfg, "airline", "RDV").kind == "runway")
	end)

	T.test("aircraft cards and start labels are filled in", function()
		for _, id in Registry.order do
			local c = Selection.card(Registry.get(id))
			T.check(#c.name > 0 and #c.class > 0 and #c.description > 0, id .. " text")
			T.check(c.seats and c.seats > 0, id .. " seats")
			T.check(c.cruiseKt and c.cruiseKt > 60, id .. " cruise")
			T.check(c.difficulty >= 1 and c.difficulty <= #Selection.DIFFICULTY_LABELS, id .. " difficulty")
			T.check(#c.difficultyLabel > 0)
		end
		T.check(Selection.card(Registry.get("kestrel72")).difficulty == 1, "Kestrel is among the easiest")
		T.check(Selection.card(Registry.get("meadowlark4")).difficulty == 1, "the trainer is among the easiest")
		T.check(Selection.card(Registry.get("celestia800")).difficulty == 4, "the jumbo is expert")
		for _, s in Selection.spawnList("RDV", Registry.get("meridian200"), "sandbox") do
			local label = Selection.spawnLabel(s)
			T.check(#label > 0 and not string.find(label, "?", 1, true), "label for " .. s.id .. ": " .. label)
		end
	end)
end }
