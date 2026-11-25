local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
local cfg = Registry.get("rainmaker")
local floatY = math.huge
for _, hp in cfg.hullPoints do if hp[5] == "float" then floatY = math.min(floatY, hp[2]) end end
local w = Sim.new(cfg, { enginesRunning = true, flaps = 4, gearDown = false, y = 60, z = 1000, speed = (cfg.speeds.vref + 5) * U.MPS_PER_KT, water = true })
w.ctl.gearDown = false
w.ctl.flaps = 4
w.ctl.throttle = 0.35
for i = 1, 60 * 120 do
	w:prepareEnv()
	local p, b = w:attitude()
	local h = w.py + floatY
	local vsT = if h > 8 then -2.5 else -0.8
	local pitchT = math.clamp((vsT - w.vy) * 2 + 3, -6, 9)
	w.ctl.pitch = math.clamp((pitchT - p) * 0.1 - w.env.wx, -1, 1)
	w.ctl.roll = math.clamp(-b * 0.05, -1, 1)
	if h < 4 then w.ctl.throttle = 0 end
	w:frame()
	if i % 300 == 0 then print(string.format("t%.0f h %.1f p %.1f vy %.2f kt %.0f gs %.1f thr %.2f floats %s wet %s", w.time, h, p, w.vy, w.model.result.ias*U.KTS_PER_MPS, w:groundSpeed(), w.model.result.thrust, tostring(w.model.result.onFloats), tostring(w.model.result.inWater))) end
end
