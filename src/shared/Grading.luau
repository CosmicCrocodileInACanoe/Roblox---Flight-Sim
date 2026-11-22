--!strict
-- Landing grade. Pure function so the server can compute it authoritatively and the
-- tests can pin down the scoring curve.

local Grading = {}

export type Touchdown = {
	verticalSpeedFpm: number, -- negative when descending
	centerlineOffsetM: number, -- absolute lateral offset from runway centreline
	distanceFromThresholdM: number, -- along-runway distance from the landing threshold
	bankDeg: number,
	pitchDeg: number,
	bounces: number,
	runwayLengthM: number,
	crashed: boolean,
	damagedComponents: number,
}

local function lerpScore(x: number, fullAt: number, zeroAt: number, points: number): number
	-- full points at or better than `fullAt`, linearly to zero at `zeroAt`
	if fullAt < zeroAt then
		if x <= fullAt then
			return points
		elseif x >= zeroAt then
			return 0
		end
		return points * (zeroAt - x) / (zeroAt - fullAt)
	else
		if x >= fullAt then
			return points
		elseif x <= zeroAt then
			return 0
		end
		return points * (x - zeroAt) / (fullAt - zeroAt)
	end
end

function Grading.grade(t: Touchdown): { score: number, letter: string, remarks: { string }, parts: { [string]: number } }
	local remarks = {}
	local parts = {}
	if t.crashed then
		return { score = 0, letter = "CRASH", remarks = { "Aircraft destroyed" }, parts = {} }
	end

	-- Vertical speed: 60-240 fpm is ideal. Softer floats (minor penalty), harder hurts.
	local vs = -t.verticalSpeedFpm
	local vsPts
	if vs < 0 then
		vsPts = 30
	elseif vs < 60 then
		vsPts = 34
		table.insert(remarks, "Very soft, but watch the float")
	elseif vs <= 240 then
		vsPts = 40
		table.insert(remarks, "Smooth touchdown")
	else
		vsPts = lerpScore(vs, 240, 800, 40)
		if vs > 600 then
			table.insert(remarks, "Hard landing")
		else
			table.insert(remarks, "Firm touchdown")
		end
	end
	parts.verticalSpeed = vsPts

	-- Centreline
	local cl = lerpScore(math.abs(t.centerlineOffsetM), 3, 20, 20)
	parts.centerline = cl
	if math.abs(t.centerlineOffsetM) > 10 then
		table.insert(remarks, "Off the centreline")
	end

	-- Touchdown zone: 150-600 m beyond the threshold is ideal.
	local d = t.distanceFromThresholdM
	local zone
	if d < 0 then
		zone = 0
		table.insert(remarks, "Touched down before the runway")
	elseif d < 150 then
		zone = lerpScore(d, 150, 0, 20)
	elseif d <= 600 then
		zone = 20
	else
		zone = lerpScore(d, 600, math.max(900, t.runwayLengthM * 0.5), 20)
		if d > 900 then
			table.insert(remarks, "Long landing")
		end
	end
	parts.touchdownZone = zone

	-- Attitude
	local bankPts = lerpScore(math.abs(t.bankDeg), 2, 8, 10)
	parts.bank = bankPts
	if math.abs(t.bankDeg) > 5 then
		table.insert(remarks, "Wings not level")
	end
	local pitchPts = 10
	if t.pitchDeg > 10.5 then
		pitchPts = -20
		table.insert(remarks, "Tail strike")
	elseif t.pitchDeg < -0.5 then
		pitchPts = 0
		table.insert(remarks, "Nose-first touchdown")
	end
	parts.pitch = pitchPts

	local penalty = math.min(t.bounces, 3) * 10 + math.min(t.damagedComponents, 5) * 6
	if t.bounces > 0 then
		table.insert(remarks, `Bounced {t.bounces}x`)
	end
	if t.damagedComponents > 0 then
		table.insert(remarks, `{t.damagedComponents} component(s) damaged`)
	end
	parts.penalty = -penalty

	local score = math.clamp(math.floor(vsPts + cl + zone + bankPts + pitchPts - penalty + 0.5), 0, 100)
	local letter
	if score >= 90 then
		letter = "A"
	elseif score >= 80 then
		letter = "B"
	elseif score >= 70 then
		letter = "C"
	elseif score >= 55 then
		letter = "D"
	else
		letter = "F"
	end
	return { score = score, letter = letter, remarks = remarks, parts = parts }
end

return Grading
