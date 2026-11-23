--!nonstrict
-- Dev helper: run the fleet, easy-mode and builder suites for the aircraft ids listed in
-- tests/generated/only.luau (written by tests/dev/one.sh). Usage: sh tests/dev/one.sh id [id...]
local Registry = require("../../src/shared/AircraftRegistry")
local only = require("../generated/only")
Registry.order = only
local T, passed, failed = {}, 0, 0
function T.test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1 else failed += 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
function T.check(c, m) if not c then error(m or "check failed", 2) end end
function T.near(a, b, tol, m) if math.abs(a - b) > tol then error(string.format("%s: %.4f vs %.4f", m or "near", a, b), 2) end end
function T.between(x, lo, hi, m) if not (x >= lo and x <= hi) then error(string.format("%s: %.4f not in [%.4f, %.4f]", m or "between", x, lo, hi), 2) end end
for _, s in { require("../test_fleet"), require("../test_easy"), require("../test_builder") } do
	s.run(T)
end
print(string.format("%d passed, %d failed", passed, failed))
