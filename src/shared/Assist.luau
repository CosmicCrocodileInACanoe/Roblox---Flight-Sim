--!strict
-- Flight assistance layer. Sits between the pilot's raw inputs and the FlightModel.
-- It only ever moves the same control surfaces a pilot could; it never adds forces,
-- so the aircraft remains fully physical in both modes.
--
-- Assisted: auto-trim (pitch attitude hold when the stick is neutral),
--   coordinated turns (auto-rudder), bank-angle protection, soft stall protection,
--   gentle wing levelling near wings-level, automatic ground spoilers.
-- Easy (default, aimed at younger pilots): everything Assisted does, plus wings that
--   level themselves, a 45 deg bank limit, pitch limits, a speed floor that adds power
--   when the aircraft gets slow, overspeed protection and a gentle flare helper near
--   the runway. Still only moves the pilot's own controls (surfaces and throttle).
-- Simulation: inputs pass straight through; trim is manual.

local Assist = {}

local clamp, rad, abs = math.clamp, math.rad, math.abs

export type AssistState = {
	mode: string, -- "easy" | "assisted" | "simulation"
	autoTrim: number,
	groundSpoilersArmed: boolean,
}

function Assist.new(mode: string?): AssistState
	return { mode = mode or "easy", autoTrim = 0, groundSpoilersArmed = true }
end

Assist.MODES = { "easy", "assisted", "simulation" }
Assist.LABELS = {
	easy = "Easy (self-levelling, stall and speed protection)",
	assisted = "Assisted (auto-trim, protections)",
	simulation = "Simulation (direct, manual trim)",
}

-- How much harder the airframe is to break in each mode (multiplies the damage limits).
function Assist.toughness(mode: string?): number
	return if mode == "easy" then 1.6 else 1
end

function Assist.nextMode(mode: string): string
	for i, m in Assist.MODES do
		if m == mode then
			return Assist.MODES[i % #Assist.MODES + 1]
		end
	end
	return Assist.MODES[1]
end

-- Easy-mode envelope for an aircraft. Agile types (aerobatic, fighters) carry a wider
-- one in `cfg.assist`; everything else keeps the gentle airliner limits. `aerobatic`
-- also lifts the bank limit in Assisted mode so loops and rolls are possible there.
function Assist.limits(cfg: any?): any
	local a = (cfg and cfg.assist) or {}
	return {
		bank = rad(a.easyBankDeg or 45),
		pitchUp = rad(a.easyPitchUpDeg or 20),
		pitchDown = rad(a.easyPitchDownDeg or -14),
		pitchRate = rad(a.easyPitchRateDeg or 7),
		aerobatic = a.aerobatic == true,
		-- seconds of roll rate to look ahead when easing into the bank limit (slow-rolling
		-- heavy aircraft need more so they stop at the limit instead of sailing past it)
		rollLead = a.easyRollLead or 0.3,
	}
end

-- Attitude from world-up expressed in body axes.
function Assist.attitude(ux: number, uy: number, uz: number): (number, number)
	local pitch = math.asin(clamp(-uz, -1, 1))
	local bank = math.atan2(-ux, uy)
	return pitch, bank
end

-- raw: pilot controls (FlightModel.Controls shape). out: controls table written in place.
function Assist.apply(st: AssistState, raw: any, out: any, env: any, model: any, dt: number)
	-- copy everything through first
	out.pitch, out.roll, out.yaw = raw.pitch, raw.roll, raw.yaw
	out.throttle, out.flaps, out.gearDown = raw.throttle, raw.flaps, raw.gearDown
	out.brake, out.parkingBrake, out.speedbrake = raw.brake, raw.parkingBrake, raw.speedbrake
	out.reverse = raw.reverse
	out.trim = raw.trim
	out.waterDrop = raw.waterDrop == true

	if st.mode == "simulation" then
		st.autoTrim = raw.trim
		return out
	end

	local easy = st.mode == "easy"
	local lim = Assist.limits(model.cfg)
	local r = model.result
	local airborne = not r.onGround and env.agl > 3
	local pitch, bank = Assist.attitude(env.ux, env.uy, env.uz)
	local tas = math.max(r.tas, 1)

	-- Auto-trim: with the stick neutral, null the pitch rate that is not explained by a
	-- coordinated turn. Trim moves slowly; a proportional term damps immediately.
	local cosB = math.cos(bank)
	local turnPitchRate = if abs(cosB) > 0.2 then (9.81 / tas) * math.sin(bank) * math.tan(bank) else 0
	if airborne and easy then
		-- Easy: the stick asks for a pitch rate (about 7 deg/s at full deflection) inside
		-- a +20 / -14 deg attitude envelope; released, it steers back to level flight
		-- (or a gentle landing glide with the gear and flaps down).
		local qd = raw.pitch * (if raw.pitch > 0 then lim.pitchRate else lim.pitchRate * 6 / 7)
		if abs(raw.pitch) < 0.05 then
			local vs = env.vgx * env.ux + env.vgy * env.uy + env.vgz * env.uz
			-- level flight, or a gentle glide when set up to land (gear down, flaps 3+)
			-- (types with fewer flap settings count their last setting as landing flaps)
			local landing = raw.gearDown and raw.flaps >= math.min(3, #model.cfg.aero.flaps.labels)
			local target = if not landing then 0 elseif env.agl < 8 then -1.0 else -3.0
			qd = clamp((target - vs) * 0.006 - (if landing then 0 else (pitch - rad(2)) * 0.05), rad(-2.5), rad(2.5))
		end
		qd = math.min(qd, (lim.pitchUp - pitch) * 0.6)
		qd = math.max(qd, (lim.pitchDown - pitch) * 0.6)
		local err = env.wx - turnPitchRate - qd
		st.autoTrim = clamp(st.autoTrim - clamp(err * 2.5, -0.35, 0.35) * dt, -1, 1)
		out.pitch = clamp(raw.pitch * 0.3 - err * 3.0, -1, 1)
	elseif airborne and abs(raw.pitch) < 0.05 then
		local err = env.wx - turnPitchRate
		st.autoTrim = clamp(st.autoTrim - clamp(err * 2.5, -0.35, 0.35) * dt, -1, 1)
		out.pitch = clamp(out.pitch - err * 1.8, -1, 1)
	elseif not airborne then
		-- Relax toward a neutral take-off trim on the ground.
		st.autoTrim += clamp(0.15 - st.autoTrim, -0.2 * dt, 0.2 * dt)
	end
	out.trim = clamp(st.autoTrim + raw.trim, -1, 1)

	if airborne then
		-- Coordinated turns: rudder against sideslip, plus yaw-rate feed from roll.
		out.yaw = clamp(raw.yaw + r.beta * 4.0, -1, 1)

		-- Bank protection: spring back to 33 deg when released, hard stop at 60 deg.
		-- Easy: level the wings whenever the stick is released, and stop at 45 deg.
		local absBank = abs(bank)
		local bankLimit = if easy then lim.bank elseif lim.aerobatic then math.huge else rad(60)
		if abs(raw.roll) < 0.05 then
			if easy then
				out.roll = clamp(-bank * 1.7 + env.wz * 1.0, -0.65, 0.65)
			elseif lim.aerobatic then
				-- aerobatic types hold whatever attitude the pilot leaves them in
				out.roll = 0
			elseif absBank > rad(33) then
				out.roll = clamp(-math.sign(bank) * (absBank - rad(33)) * 2.5, -0.6, 0.6)
			elseif absBank < rad(8) then
				out.roll = clamp(-bank * 1.2 + env.wz * 0.8, -0.3, 0.3)
			end
		elseif absBank > bankLimit - math.max(rad(5), abs(env.wz) * lim.rollLead) and math.sign(raw.roll) == math.sign(bank) then
			-- fade the input out over the last few degrees (more for fast-rolling aircraft),
			-- then push back past the limit
			local fade = math.max(rad(5), abs(env.wz) * lim.rollLead)
			local over = (absBank - bankLimit) / fade
			out.roll = if over > 0 then -math.sign(bank) * clamp(over, 0, 0.5) else raw.roll * clamp(-over, 0, 1)
			out.roll = clamp(out.roll + env.wz * 0.5, -1, 1)
		end

		if easy then
			-- Flare helper: near the ground with the gear down, soften a steep descent.
			local vs = env.vgx * env.ux + env.vgy * env.uy + env.vgz * env.uz
			if raw.gearDown and env.agl < 25 then
				local target = if env.agl < 8 then -1.2 else -3.0
				if vs < target then
					out.pitch = math.max(out.pitch, clamp((target - vs) * 0.25, 0, 0.6))
				end
			end
			-- Speed floor and overspeed protection, through the throttle.
			local sp = model.cfg.speeds
			local kt = (r.ias or tas) * 1.943844
			local floor = if raw.flaps >= math.min(3, #model.cfg.aero.flaps.labels) then sp.vref * 1.02 else sp.vref * 1.25
			if env.agl > 12 and kt < floor then
				out.throttle = math.max(out.throttle, clamp((floor - kt) / 12, 0, 1))
			end
			if kt > sp.vmo * 0.96 then
				out.throttle = math.min(out.throttle, clamp(1 - (kt - sp.vmo * 0.96) / 10, 0, 1))
			end
		end

		-- Soft stall protection: progressively limit nose-up input near the stall angle.
		local margin = (r.stallAlpha or rad(14)) - (r.wingAlpha or 0)
		local zone = if easy then rad(5) else rad(3)
		if margin < zone then
			local limit = clamp(margin / zone, -1, 1)
			if out.pitch > limit then
				out.pitch = limit
			end
			if margin < 0 then
				out.pitch = math.min(out.pitch, -0.4)
			end
		end
	end

	-- Ground spoilers: deploy automatically on the ground with thrust at idle above 40 kt.
	if r.onGround and raw.throttle < 0.05 and r.tas > 20 and st.groundSpoilersArmed then
		out.speedbrake = 1
	end
	return out
end

return Assist
