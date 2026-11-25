local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
local cfg = Registry.get("rainmaker")
local floatY = math.huge
for _, hp in cfg.hullPoints do if hp[5] == "float" then floatY = math.min(floatY, hp[2]) end end
local s = Sim.new(cfg, { enginesRunning = true, flaps = 3, gearDown = false, y = -floatY + 0.05, water = true })
s.ctl.gearDown = false
s.ctl.flaps = 3
for i = 1, 60 * 8 do
	s:frame()
	if i % 60 == 0 then local p, b = s:attitude(); print(string.format("t%.0f y %.2f p %.1f b %.1f vy %.2f floats %s wet %s", s.time, s.py, p, b, s.vy, tostring(s.model.result.onFloats), tostring(s.model.result.inWater))) end
end
s:prepareEnv()
for i, hp in cfg.hullPoints do print(i, hp[4], hp[5], string.format("%.2f", s.env.hullDepth[i])) end
