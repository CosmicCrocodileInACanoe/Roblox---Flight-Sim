local W = require("../../src/shared/Wildfire")
local t = os.clock()
for _, s in W.sites() do print(s.id, math.floor(s.x), math.floor(s.z), math.floor(s.y)) end
print("time", os.clock() - t)
