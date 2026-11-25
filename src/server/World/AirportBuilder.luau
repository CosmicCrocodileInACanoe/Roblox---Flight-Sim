--!strict
-- Builds a complete airport from the shared layout: runway with markings, lighting,
-- PAPI and approach lights, parallel taxiway and connectors, apron with gate stands,
-- terminal, tower, hangar, windsock and signage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Airports = require(Shared.Airports)
local Units = require(Shared.Units)
local Geometry = require(script.Parent.Geometry)

local SPM = Units.STUDS_PER_METER
local AirportBuilder = {}

-- Weathered, real-world surface colours: runway asphalt is a dark warm grey, taxiways
-- are older and lighter, apron concrete is a pale warm grey, airfield grass is mown and
-- a little dry, and paint is never pure white.
local ASPHALT = Color3.fromRGB(48, 49, 52)
local TAXI = Color3.fromRGB(78, 78, 80)
local SHOULDER = Color3.fromRGB(92, 90, 86)
local RUBBER = Color3.fromRGB(26, 26, 28) -- tyre deposits in the touchdown zones
local CONCRETE = Color3.fromRGB(168, 166, 158)
local GRASS = Color3.fromRGB(104, 128, 66)
local WHITE = Color3.fromRGB(232, 232, 226)
local YELLOW = Color3.fromRGB(226, 182, 46)

function AirportBuilder.build(id: string, parent: Instance): Model
	local l = Airports.layout(id)
	local ap = Airports.list[id]
	local model = Instance.new("Model")
	model.Name = "Airport_" .. id
	model:SetAttribute("AirportId", id)
	model.Parent = parent

	-- Runway frame: origin at runway centre (pavement top), X along heading, Z to the right.
	local origin = Vector3.new(l.cx, l.y, l.cz)
	local along = Vector3.new(l.ax, 0, l.az)
	local right = Vector3.new(l.rx, 0, l.rz)
	local frame = CFrame.fromMatrix(origin, along, Vector3.yAxis, right)
	-- fromMatrix(pos, X, Y, Z): X = along, Y = up, Z = right. (Right-handed check: X x Y = Z.)
	if along:Cross(Vector3.yAxis):Dot(right) < 0 then
		frame = CFrame.fromMatrix(origin, along, Vector3.yAxis, -right)
		-- keep lateral sign consistent below by flipping
		right = -right
	end
	local function at(a: number, lat: number, y: number?): CFrame
		return frame * CFrame.new(a, y or 0, lat)
	end
	-- Convert layout lateral (relative to +right) into this frame's Z.
	local latSign = if right:Dot(Vector3.new(l.rx, 0, l.rz)) > 0 then 1 else -1
	local function lat(v: number): number
		return v * latSign
	end

	local side = l.side
	local hl, hw = l.halfLen, l.halfWidth

	-- Ground slab (grass) under the whole airport.
	local farLat = math.abs(l.terminalFar) + 500
	Geometry.tiledRect(frame, -hl - 900, hl + 900, lat(-side * (hw + 700)), lat(side * farLat), -0.6, 4, {
		Name = "Grass", Color = GRASS, Material = Enum.Material.Grass,
	}, model)

	-- Runway pavement (top at y).
	Geometry.tiledRect(frame, -hl - 60, hl + 60, lat(-hw), lat(hw), 0, 2, {
		Name = "Runway", Color = ASPHALT, Material = Enum.Material.Asphalt,
	}, model)
	-- Shoulders
	for _, s in { -1, 1 } do
		Geometry.tiledRect(frame, -hl, hl, lat(s * hw), lat(s * (hw + 7.5 * SPM)), -0.15, 1.7, {
			Name = "Shoulder", Color = SHOULDER, Material = Enum.Material.Pavement,
		}, model)
	end

	local markings = Instance.new("Folder")
	markings.Name = "Markings"
	markings.Parent = model
	local function mark(a0: number, a1: number, l0: number, l1: number, color: Color3?)
		Geometry.tiledRect(frame, a0, a1, lat(l0), lat(l1), 0.06, 0.1, {
			Name = "Marking", Color = color or WHITE, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		}, markings)
	end

	-- Centreline dashes: 36 m stripe, 24 m gap.
	local a = -hl + 120 * SPM
	while a < hl - 120 * SPM do
		mark(a, a + 36 * SPM, -0.45 * SPM, 0.45 * SPM)
		a += 60 * SPM
	end
	-- Edge lines
	for _, s in { -1, 1 } do
		mark(-hl, hl, s * (hw - 1.2 * SPM), s * (hw - 0.3 * SPM))
	end

	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model
	local function light(cf: CFrame, color: Color3, size: number?)
		local s = size or 1.4
		Geometry.decal({
			Name = "Light", Size = Vector3.new(s, s * 0.6, s), CFrame = cf,
			Color = color, Material = Enum.Material.Neon, Parent = lights,
		})
	end

	-- Per runway end: threshold bars, numbers, touchdown/aiming markings, lights, PAPI, ALS.
	for k, e in l.ends do
		local dir = if k == 1 then 1 else -1 -- along-axis direction of landing for this end
		local th = -dir * hl -- threshold along-position
		-- Tyre rubber deposits: dark, worn smears where the main wheels touch down, densest
		-- around the aiming point and fading out down the runway and towards the edges.
		-- One layer of non-overlapping patches (no z-fighting), darkness = along x across.
		local bands = { { 0, 0.16, 1 }, { 0.16, 0.34, 0.55 } } -- lateral fraction of half-width, weight
		for seg = 0, 11 do
			local d0, d1 = 90 + seg * 62, 90 + (seg + 1) * 62
			local mid = (d0 + d1) / 2
			local alongW = math.clamp(1 - math.abs(mid - 330) / 520, 0.15, 1)
			local k0 = if dir > 0 then 0.37 else 0.71
			local r0, r1 = th + dir * d0 * SPM, th + dir * d1 * SPM
			for _, bd in bands do
				local k = alongW * bd[3] * (0.85 + 0.3 * math.noise(seg * 0.7 + 0.3, bd[1] * 3.1 + 0.2, k0))
				local color = ASPHALT:Lerp(RUBBER, math.clamp(k, 0, 1))
				local lanes = if bd[1] == 0 then { { -bd[2], bd[2] } } else { { -bd[2], -bd[1] }, { bd[1], bd[2] } }
				for _, ln in lanes do
					Geometry.tiledRect(frame, math.min(r0, r1), math.max(r0, r1), lat(hw * ln[1]), lat(hw * ln[2]), 0.03, 0.05, {
						Name = "TyreMarks", Color = color, Material = Enum.Material.Asphalt,
						CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
					}, markings)
				end
			end
		end
		-- threshold "piano keys"
		for i = -6, 6 do
			if i ~= 0 then
				local lc = i * 3 * SPM
				local a0 = th + dir * 6 * SPM
				local a1 = th + dir * 36 * SPM
				mark(math.min(a0, a1), math.max(a0, a1), lc - 0.9 * SPM, lc + 0.9 * SPM)
			end
		end
		-- runway designator
		local numA = th + dir * 60 * SPM
		local numCF = at(numA, 0, 0.08)
		local look = Vector3.new(l.ax, 0, l.az) * dir
		Geometry.groundText(CFrame.lookAt(numCF.Position, numCF.Position + look), 16 * SPM, 20 * SPM, e.ident, WHITE, markings)
		-- aiming point (300 m) and touchdown zone bars
		for _, s in { -1, 1 } do
			local a0, a1 = th + dir * 300 * SPM, th + dir * 345 * SPM
			mark(math.min(a0, a1), math.max(a0, a1), s * 6 * SPM, s * 10 * SPM)
			for _, d in { 150, 450, 600 } do
				local b0, b1 = th + dir * d * SPM, th + dir * (d + 22) * SPM
				mark(math.min(b0, b1), math.max(b0, b1), s * 6 * SPM, s * 8 * SPM)
			end
		end
		-- threshold (green, facing approach) and end (red) light rows
		for i = -8, 8 do
			light(at(th - dir * 1.0, i * (hw / 8), 0.3), Color3.fromRGB(60, 255, 90))
		end
		-- PAPI: 4 boxes on the left of the landing direction, 300 m past the threshold.
		local leftLat = -dir * (hw + 15 * SPM) -- left of landing direction
		for i = 1, 4 do
			local box = Geometry.decal({
				Name = "PAPI", Size = Vector3.new(2.2, 1.6, 2.2),
				CFrame = at(th + dir * 300 * SPM, leftLat - dir * (i - 1) * 9 * SPM, 1.4),
				Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, Parent = lights,
			})
			box:SetAttribute("PapiIndex", i)
			box:SetAttribute("PapiAngle", 3.5 - (i - 1) * (1 / 3)) -- 3.50, 3.17, 2.83, 2.50 deg
		end
		-- Approach lighting: 900 m of centreline bars, crossbar at 300 m.
		for d = 30, 900, 30 do
			local aa = th - dir * d * SPM
			local width = if d == 300 then 30 * SPM else 5 * SPM
			Geometry.decal({
				Name = "ALS", Size = Vector3.new(1.2, 0.8, width),
				CFrame = at(aa, 0, 1.5), Color = Color3.fromRGB(255, 250, 225),
				Material = Enum.Material.Neon, Parent = lights,
			})
			Geometry.decal({
				Name = "ALSPost", Size = Vector3.new(0.5, 6, 0.5), CFrame = at(aa, 0, -2.0),
				Color = Color3.fromRGB(200, 200, 200), Parent = lights,
			})
		end
	end
	-- Edge lights every 60 m
	a = -hl
	while a <= hl do
		for _, s in { -1, 1 } do
			light(at(a, lat(s * (hw + 1.5 * SPM)), 0.4), Color3.fromRGB(255, 246, 220), 1.1)
		end
		a += 60 * SPM
	end

	-- Taxiways -----------------------------------------------------------------
	local taxiW = 23 * SPM
	local tlat = l.taxiOffset
	Geometry.tiledRect(frame, -hl, hl, lat(tlat - taxiW / 2), lat(tlat + taxiW / 2), -0.05, 1.8, {
		Name = "Taxiway", Color = TAXI, Material = Enum.Material.Asphalt,
	}, model)
	-- taxiway centreline (yellow)
	mark(-hl, hl, tlat - 0.25 * SPM, tlat + 0.25 * SPM, YELLOW)
	-- connectors from runway edge to apron
	for _, ca in l.connectors do
		local l0 = side * hw
		local l1 = l.apronNear
		if math.abs(ca) > l.apronHalfLen then
			l1 = tlat + side * taxiW / 2
		end
		Geometry.tiledRect(frame, ca - taxiW / 2, ca + taxiW / 2, lat(math.min(l0, l1)), lat(math.max(l0, l1)), -0.05, 1.8, {
			Name = "Connector", Color = TAXI, Material = Enum.Material.Asphalt,
		}, model)
		mark(ca - 0.25 * SPM, ca + 0.25 * SPM, math.min(l0, l1), math.max(l0, l1), YELLOW)
		-- holding position: double yellow bars + sign
		local hold = side * (hw + 75 * SPM)
		mark(ca - taxiW / 2, ca + taxiW / 2, hold - 0.5 * SPM, hold + 0.5 * SPM, YELLOW)
		local sign = Geometry.part({
			Name = "HoldSign", Size = Vector3.new(2, 4, 12),
			CFrame = at(ca - taxiW * 0.8, lat(hold + side * 4), 3), Color = Color3.fromRGB(200, 20, 20),
			CanCollide = false, CanQuery = false, Parent = model,
		})
		Geometry.signText(sign, Enum.NormalId.Left, `{l.ends[1].ident}-{l.ends[2].ident}`, WHITE)
		Geometry.signText(sign, Enum.NormalId.Right, `{l.ends[1].ident}-{l.ends[2].ident}`, WHITE)
	end

	-- Apron and gates ------------------------------------------------------------
	Geometry.tiledRect(frame, -l.apronHalfLen, l.apronHalfLen, lat(math.min(l.apronNear, l.apronFar)), lat(math.max(l.apronNear, l.apronFar)), -0.02, 1.8, {
		Name = "Apron", Color = CONCRETE, Material = Enum.Material.Pavement,
	}, model)
	for i, gt in l.gates do
		local gateLat = side * 340 * SPM
		-- lead-in line from the taxiway to the stand, stop bar near the terminal
		mark(gt.along - 0.25 * SPM, gt.along + 0.25 * SPM, math.min(tlat, gateLat + side * 20 * SPM), math.max(tlat, gateLat + side * 20 * SPM), YELLOW)
		local stop = gateLat + side * 22 * SPM
		mark(gt.along - 3 * SPM, gt.along + 3 * SPM, stop - 0.4 * SPM, stop + 0.4 * SPM, YELLOW)
		local numCF = at(gt.along + 6 * SPM, lat(gateLat), 0.08)
		Geometry.groundText(CFrame.lookAt(numCF.Position, numCF.Position + Vector3.new(l.rx, 0, l.rz) * side), 7 * SPM, 7 * SPM, tostring(i), YELLOW, markings)
	end

	-- Terminal building --------------------------------------------------------
	local tNear, tFar = math.min(l.terminalNear, l.terminalFar), math.max(l.terminalNear, l.terminalFar)
	local tDepth = tFar - tNear
	local tMid = (tNear + tFar) / 2
	local tHeight = 22 * SPM
	local function block(name: string, a0: number, a1: number, l0: number, l1: number, y0: number, y1: number, color: Color3, mat: Enum.Material, props: any?)
		local p = {
			Name = name,
			Size = Vector3.new(math.abs(a1 - a0), y1 - y0, math.abs(l1 - l0)),
			CFrame = at((a0 + a1) / 2, lat((l0 + l1) / 2), (y0 + y1) / 2),
			Color = color, Material = mat, Parent = model,
		}
		if props then
			for k, v in props do
				p[k] = v
			end
		end
		return Geometry.part(p)
	end
	local half = l.terminalHalfLen
	local segs = math.ceil(half * 2 / 1900)
	for s = 0, segs - 1 do
		local a0 = -half + s * (2 * half / segs)
		local a1 = a0 + 2 * half / segs
		block("Terminal", a0, a1, tNear, tFar, 0, tHeight, Color3.fromRGB(206, 204, 198), Enum.Material.Concrete)
		block("Facade", a0, a1, tNear - side * 0.6, tNear, 2, tHeight - 6, Color3.fromRGB(70, 98, 118), Enum.Material.Glass, { Reflectance = 0.35, Transparency = 0.05 })
		-- curtain-wall mullions: a dark aluminium sill and head along the glass
		block("FacadeFrame", a0, a1, tNear - side * 0.9, tNear - side * 0.5, 2, 3.2, Color3.fromRGB(64, 66, 70), Enum.Material.Metal)
		block("FacadeFrame", a0, a1, tNear - side * 0.9, tNear - side * 0.5, tHeight - 7.2, tHeight - 6, Color3.fromRGB(64, 66, 70), Enum.Material.Metal)
		block("Roof", a0 - 10, a1 + 10, tNear - side * 12, tFar + side * 4, tHeight, tHeight + 4, Color3.fromRGB(176, 178, 180), Enum.Material.CorrodedMetal)
	end
	-- Terminal name sign on the roof edge
	local signPart = block("TerminalSign", -half * 0.4, half * 0.4, tNear - side * 1.2, tNear - side * 0.8, tHeight + 4, tHeight + 24, Color3.fromRGB(30, 60, 110), Enum.Material.SmoothPlastic)
	Geometry.signText(signPart, if latSign * side > 0 then Enum.NormalId.Back else Enum.NormalId.Front, ap.name, WHITE, Color3.fromRGB(30, 60, 110))
	Geometry.signText(signPart, if latSign * side > 0 then Enum.NormalId.Front else Enum.NormalId.Back, ap.name, WHITE, Color3.fromRGB(30, 60, 110))
	-- Gate jet-bridge stubs (short, kept clear of the parking spot)
	for _, gt in l.gates do
		block("JetBridge", gt.along - 2 * SPM, gt.along + 2 * SPM, tNear - side * 12 * SPM, tNear, 12, 12 + 3.5 * SPM, Color3.fromRGB(190, 192, 196), Enum.Material.Metal)
	end
	-- Landside parking
	Geometry.tiledRect(frame, -half, half, lat(tFar), lat(tFar + side * 120 * SPM), -0.3, 1, {
		Name = "Parking", Color = Color3.fromRGB(66, 66, 68), Material = Enum.Material.Asphalt,
	}, model)

	-- Control tower
	local towerA = half + 120 * SPM
	local towerL = tMid
	local shaft = Geometry.part({
		ClassName = "Part", Name = "TowerShaft", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(45 * SPM, 7 * SPM, 7 * SPM),
		CFrame = at(towerA, lat(towerL), 22.5 * SPM) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(212, 210, 204), Material = Enum.Material.Concrete, Parent = model,
	})
	shaft:SetAttribute("Landmark", "Tower")
	Geometry.part({
		ClassName = "Part", Name = "TowerCab", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5 * SPM, 13 * SPM, 13 * SPM),
		CFrame = at(towerA, lat(towerL), 47.5 * SPM) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(52, 86, 100), Material = Enum.Material.Glass, Reflectance = 0.4, Parent = model,
	})
	Geometry.part({
		ClassName = "Part", Name = "TowerRoof", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2 * SPM, 14.5 * SPM, 14.5 * SPM),
		CFrame = at(towerA, lat(towerL), 50.6 * SPM) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal, Parent = model,
	})
	Geometry.decal({
		Name = "TowerBeacon", Size = Vector3.new(2, 2, 2), CFrame = at(towerA, lat(towerL), 52 * SPM),
		Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, Parent = model,
	})

	-- Hangar
	local hA = -half - 220 * SPM
	block("Hangar", hA - 45 * SPM, hA + 45 * SPM, tNear, tNear + side * 70 * SPM, 0, 24 * SPM, Color3.fromRGB(152, 158, 162), Enum.Material.CorrodedMetal)
	block("HangarDoor", hA - 40 * SPM, hA + 40 * SPM, tNear - side * 0.5, tNear, 0, 21 * SPM, Color3.fromRGB(126, 132, 138), Enum.Material.Metal)

	-- Windsock on the far side of the runway
	local wsA = -hl * 0.55
	local wsL = -side * (hw + 60 * SPM)
	Geometry.part({
		Name = "WindsockPole", Size = Vector3.new(0.8, 9 * SPM, 0.8), CFrame = at(wsA, lat(wsL), 4.5 * SPM),
		Color = Color3.fromRGB(230, 230, 230), Material = Enum.Material.Metal, Parent = model,
	})
	local sock = Geometry.decal({
		ClassName = "Part", Name = "Windsock", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4 * SPM, 1.2 * SPM, 1.2 * SPM),
		CFrame = at(wsA, lat(wsL), 9 * SPM), Color = Color3.fromRGB(255, 120, 20), Parent = model,
	})
	sock:SetAttribute("Windsock", true)
	sock:SetAttribute("PivotX", sock.Position.X)
	sock:SetAttribute("PivotY", sock.Position.Y)
	sock:SetAttribute("PivotZ", sock.Position.Z)

	return model
end

return AirportBuilder
