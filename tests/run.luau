--!nonstrict
-- Test runner for the pure (engine-independent) modules. Run from the repo root:
--   luau tests/run.luau
-- These tests do NOT start Roblox. They cover the aerodynamic model, engines, gear,
-- damage, grading, missions, airport geometry, world generation, and a 6-DOF offline
-- simulation of complete flights using the exact FlightModel the game runs.

local T = {}
local passed, failed = 0, 0
local failures = {}

function T.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

function T.check(cond: any, msg: string?)
	if not cond then
		error(msg or "check failed", 2)
	end
end

function T.near(a: number, b: number, tol: number, msg: string?)
	if math.abs(a - b) > tol then
		error(string.format("%s: expected %.4f ~= %.4f (tol %.4f)", msg or "near", a, b, tol), 2)
	end
end

function T.between(x: number, lo: number, hi: number, msg: string?)
	if not (x >= lo and x <= hi) then
		error(string.format("%s: %.4f not in [%.4f, %.4f]", msg or "between", x, lo, hi), 2)
	end
end

local suites = {
	require("./test_aero"),
	require("./test_systems"),
	require("./test_damage"),
	require("./test_world"),
	require("./test_flight"),
	require("./test_controls"),
	require("./test_audio"),
}

for _, suite in suites do
	print("\n== " .. suite.name)
	suite.run(T)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	for _, f in failures do
		print(" - " .. f)
	end
	error("tests failed")
end
