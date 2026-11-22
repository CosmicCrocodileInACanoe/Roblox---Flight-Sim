--!strict
-- Flight assistance layer. Sits between the pilot's raw inputs and the FlightModel.
-- It only ever moves the same control surfaces a pilot could; it never adds forces,
-- so the aircraft remains fully physical in both modes.
--
-- Assisted (default): auto-trim (pitch attitude hold when the stick is neutral),
--   coordinated turns (auto-rudder), bank-angle protection, soft stall protection,
--   gentle wing levelling near wings-level, automatic ground spoilers.
-- Simulation: inputs pass straight through; trim is manual.

local Assist = {}

local clamp, rad, abs = math.clamp, math.rad, math.abs

export type AssistState = {
	mode: string, -- "assisted" | "simulation"
	autoTrim: number,
	groundSpoilersArmed: boolean,
}

function Assist.new(mode: string?): AssistState
	return { mode = mode or "assisted", autoTrim = 0, groundSpoilersArmed = true }
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

	if st.mode ~= "assisted" then
		st.autoTrim = raw.trim
		return out
	end

	local r = model.result
	local airborne = not r.onGround and env.agl > 3
	local pitch, bank = Assist.attitude(env.ux, env.uy, env.uz)
	local tas = math.max(r.tas, 1)

	-- Auto-trim: with the stick neutral, null the pitch rate that is not explained by a
	-- coordinated turn. Trim moves slowly; a proportional term damps immediately.
	local cosB = math.cos(bank)
	local turnPitchRate = if abs(cosB) > 0.2 then (9.81 / tas) * math.sin(bank) * math.tan(bank) else 0
	if airborne and abs(raw.pitch) < 0.05 then
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
		local absBank = abs(bank)
		if abs(raw.roll) < 0.05 then
			if absBank > rad(33) then
				out.roll = clamp(-math.sign(bank) * (absBank - rad(33)) * 2.5, -0.6, 0.6)
			elseif absBank < rad(8) then
				out.roll = clamp(-bank * 1.2 + env.wz * 0.8, -0.3, 0.3)
			end
		elseif absBank > rad(60) and math.sign(raw.roll) == math.sign(bank) then
			out.roll = 0
		end

		-- Soft stall protection: progressively limit nose-up input near the stall angle.
		local margin = (r.stallAlpha or rad(14)) - (r.wingAlpha or 0)
		if margin < rad(3) then
			local limit = clamp(margin / rad(3), -1, 1)
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
