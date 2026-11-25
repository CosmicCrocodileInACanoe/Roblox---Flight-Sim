--!nonstrict
-- Key bindings: one table drives input and the help popup, so check it is consistent.
local Controls = require("../src/shared/Controls")

local HOLD = { pitchDown = 1, pitchUp = 1, rollLeft = 1, rollRight = 1, yawLeft = 1, yawRight = 1,
	throttleUp = 1, throttleDown = 1, trimDown = 1, trimUp = 1, brake = 1, reverse = 1, waterDrop = 1 }
local PRESS = { gear = 1, flapsDown = 1, flapsUp = 1, parkingBrake = 1, speedbrake = 1, engines = 1,
	assist = 1, camera = 1, panel = 1, hud = 1, debug = 1, menu = 1, reset = 1, fixAll = 1, controls = 1, minimap = 1, events = 1, music = 1 }
-- Keys Roblox reserves or that would fight the default player scripts.
local RESERVED = { Escape = true, Tab = true, Slash = true, Backquote = true, F9 = true, F11 = true, Space = true }

return {
	name = "Controls",
	run = function(T)
		T.test("every action has exactly one binding entry of the right kind", function()
			local seen = {}
			for _, b in Controls.KEYMAP do
				T.check(not seen[b.action], "duplicate action " .. b.action)
				seen[b.action] = true
				if b.kind == "hold" then
					T.check(HOLD[b.action], b.action .. " is not a hold action")
				else
					T.check(PRESS[b.action], b.action .. " is not a press action")
				end
				T.check(#b.keys > 0, b.action .. " has no keys")
			end
			for a in HOLD do
				T.check(seen[a], "unbound " .. a)
			end
			for a in PRESS do
				T.check(seen[a], "unbound " .. a)
			end
		end)
		T.test("no key is bound to two actions, and no reserved keys", function()
			local owner = {}
			for _, b in Controls.KEYMAP do
				for _, k in b.keys do
					T.check(owner[k] == nil, string.format("%s bound to %s and %s", k, tostring(owner[k]), b.action))
					T.check(not RESERVED[k], k .. " is reserved by Roblox")
					owner[k] = b.action
				end
			end
		end)
		T.test("every group is listed and the popup shows every binding", function()
			local groups = {}
			for _, g in Controls.GROUPS do
				groups[g] = true
			end
			for _, b in Controls.KEYMAP do
				T.check(groups[b.group], "unknown group " .. b.group)
			end
			T.check(#Controls.rows() == #Controls.KEYMAP + #Controls.EXTRAS)
			for _, r in Controls.rows() do
				T.check(r.keys ~= "", r.label .. " has no keyboard key shown")
			end
		end)
		T.test("display names are readable", function()
			T.check(Controls.displayName("LeftShift") == "Shift")
			T.check(Controls.firstKey("controls") == "K")
			local kb, gp = Controls.keyText(Controls.KEYMAP[1])
			T.check(kb == "W / Up arrow" and gp == "", kb)
		end)
	end,
}
