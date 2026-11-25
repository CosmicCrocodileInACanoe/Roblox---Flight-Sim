local T = {}
function T.test(n, f) local ok, e = pcall(f); print((ok and "  ok   " or "  FAIL ") .. n .. (ok and "" or ("\n       " .. tostring(e)))) end
function T.check(c, m) if not c then error(m or "check failed", 2) end end
function T.near(a, b, t, m) if math.abs(a - b) > t then error(string.format("%s: %.4f vs %.4f", m or "near", a, b), 2) end end
function T.between(x, lo, hi, m) if not (x >= lo and x <= hi) then error(string.format("%s: %.4f not in [%.4f, %.4f]", m or "between", x, lo, hi), 2) end end
require("../test_firefighting").run(T)
