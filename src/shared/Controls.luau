--!strict
-- The one place key bindings live. InputController binds from this table, and the
-- Controls popup and the menu list are generated from it, so a remap is a one-line edit.
--
-- kind = "hold": the action is active while any of its keys is held.
-- kind = "press": the action fires once when one of its keys goes down.
-- keys: Enum.KeyCode names. Gamepad names (Button*, DPad*) are listed separately in the popup.
-- Start and Select belong to Roblox (its menu and gamepad UI navigation), so nothing
-- here uses them.

local Controls = {}

export type Binding = {
	action: string,
	kind: "hold" | "press",
	group: string,
	label: string,
	keys: { string },
}

Controls.GROUPS = { "Flying", "Aircraft systems", "Camera and game" }

Controls.KEYMAP = {
	-- Flying
	{ action = "pitchDown", kind = "hold", group = "Flying", label = "Pitch nose down", keys = { "W", "Up" } },
	{ action = "pitchUp", kind = "hold", group = "Flying", label = "Pitch nose up", keys = { "S", "Down" } },
	{ action = "rollLeft", kind = "hold", group = "Flying", label = "Roll left", keys = { "A", "Left" } },
	{ action = "rollRight", kind = "hold", group = "Flying", label = "Roll right", keys = { "D", "Right" } },
	{ action = "yawLeft", kind = "hold", group = "Flying", label = "Rudder / steer left", keys = { "Q", "ButtonL1" } },
	{ action = "yawRight", kind = "hold", group = "Flying", label = "Rudder / steer right", keys = { "E", "ButtonR1" } },
	{ action = "throttleUp", kind = "hold", group = "Flying", label = "Throttle up", keys = { "LeftShift" } },
	{ action = "throttleDown", kind = "hold", group = "Flying", label = "Throttle down", keys = { "LeftControl" } },
	{ action = "trimDown", kind = "hold", group = "Flying", label = "Trim nose down (Simulation)", keys = { "LeftBracket" } },
	{ action = "trimUp", kind = "hold", group = "Flying", label = "Trim nose up (Simulation)", keys = { "RightBracket" } },
	-- Aircraft systems
	{ action = "engines", kind = "press", group = "Aircraft systems", label = "Start / stop engines", keys = { "I", "ButtonY" } },
	{ action = "gear", kind = "press", group = "Aircraft systems", label = "Landing gear up / down", keys = { "G", "ButtonX" } },
	{ action = "flapsDown", kind = "press", group = "Aircraft systems", label = "Flaps down one notch", keys = { "F", "DPadDown" } },
	{ action = "flapsUp", kind = "press", group = "Aircraft systems", label = "Flaps up one notch", keys = { "V", "DPadUp" } },
	{ action = "speedbrake", kind = "press", group = "Aircraft systems", label = "Speedbrake (off / half / full)", keys = { "X", "DPadRight" } },
	{ action = "brake", kind = "hold", group = "Aircraft systems", label = "Wheel brakes", keys = { "B", "ButtonB" } },
	{ action = "parkingBrake", kind = "press", group = "Aircraft systems", label = "Parking brake", keys = { "P", "DPadLeft" } },
	{ action = "reverse", kind = "hold", group = "Aircraft systems", label = "Reverse thrust (on the ground)", keys = { "Z" } },
	{ action = "autoland", kind = "press", group = "Aircraft systems", label = "Autoland on / off (lands at the best runway nearby)", keys = { "Three" } },
	{ action = "refillWater", kind = "press", group = "Aircraft systems", label = "Refill the water tank (water bomber)", keys = { "One" } },
	{ action = "autoScoop", kind = "press", group = "Aircraft systems", label = "Auto refill: fly to the sea, scoop and climb out (water bomber)", keys = { "Two" } },
	{ action = "waterDrop", kind = "hold", group = "Aircraft systems", label = "Drop water (water bomber; skim the sea to refill)", keys = { "L" } },
	-- Camera and game
	{ action = "camera", kind = "press", group = "Camera and game", label = "Camera: chase / cockpit / tower", keys = { "C", "ButtonR3" } },
	{ action = "assist", kind = "press", group = "Camera and game", label = "Easy / Free / Assisted / Simulation mode", keys = { "T" } },
	{ action = "controls", kind = "press", group = "Camera and game", label = "Show / hide this controls list", keys = { "K" } },
	{ action = "panel", kind = "press", group = "Camera and game", label = "Show / hide on-screen buttons", keys = { "U" } },
	{ action = "minimap", kind = "press", group = "Camera and game", label = "Show / hide the map", keys = { "N" } },
	{ action = "events", kind = "press", group = "Camera and game", label = "Failures and weather events menu", keys = { "J" } },
	{ action = "hud", kind = "press", group = "Camera and game", label = "Hide / show HUD", keys = { "H" } },
	{ action = "music", kind = "press", group = "Camera and game", label = "Background music on / off", keys = { "O" } },
	{ action = "debug", kind = "press", group = "Camera and game", label = "Debug panel", keys = { "F3" } },
	{ action = "menu", kind = "press", group = "Camera and game", label = "Menu", keys = { "M", "ButtonL3" } },
	{ action = "reset", kind = "press", group = "Camera and game", label = "Reset / respawn", keys = { "R" } },
	{ action = "fixAll", kind = "press", group = "Camera and game", label = "Fix all damage (puts broken parts back)", keys = { "Y" } },
} :: { Binding }

-- Mouse and analogue inputs that are not key bindings, shown in the popup only.
Controls.EXTRAS = {
	{ group = "Camera and game", keys = "Right mouse drag", label = "Look around" },
	{ group = "Camera and game", keys = "Mouse wheel", label = "Camera distance" },
	{ group = "Flying", keys = "Left stick / triggers", label = "Gamepad: pitch and roll / throttle" },
	{ group = "Flying", keys = "On-screen stick and buttons", label = "Mouse or touch: drag the stick and throttle, tap the buttons" },
}

local DISPLAY = {
	LeftShift = "Shift", RightShift = "Right Shift", LeftControl = "Ctrl", RightControl = "Right Ctrl",
	LeftAlt = "Alt", LeftBracket = "[", RightBracket = "]", Space = "Space",
	Up = "Up arrow", Down = "Down arrow", Left = "Left arrow", Right = "Right arrow",
	Comma = ",", Period = ".", Slash = "/", Semicolon = ";", Quote = "'", Minus = "-", Equals = "=",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonX = "X button", ButtonY = "Y button", ButtonB = "B button",
	ButtonA = "A button", ButtonL3 = "Left stick click", ButtonR3 = "Right stick click",
	DPadUp = "D-pad up", DPadDown = "D-pad down", DPadLeft = "D-pad left", DPadRight = "D-pad right",
}

function Controls.isGamepadKey(name: string): boolean
	return string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 10) == "Thumbstick"
end

function Controls.displayName(name: string): string
	return DISPLAY[name] or name
end

-- Human-readable key text for one binding: keyboard keys, then gamepad keys.
function Controls.keyText(b: Binding): (string, string)
	local kb, gp = {}, {}
	for _, k in b.keys do
		table.insert(if Controls.isGamepadKey(k) then gp else kb, Controls.displayName(k))
	end
	return table.concat(kb, " / "), table.concat(gp, " / ")
end

-- Rows for display, grouped in GROUPS order: { group, keys, gamepad, label }.
function Controls.rows(): { { group: string, keys: string, gamepad: string, label: string } }
	local out = {}
	for _, g in Controls.GROUPS do
		for _, b in Controls.KEYMAP do
			if b.group == g then
				local kb, gp = Controls.keyText(b)
				table.insert(out, { group = g, keys = kb, gamepad = gp, label = b.label })
			end
		end
		for _, e in Controls.EXTRAS do
			if e.group == g then
				table.insert(out, { group = g, keys = e.keys, gamepad = "", label = e.label })
			end
		end
	end
	return out
end

-- The key name bound to an action, for hints such as "Press K for controls".
function Controls.firstKey(action: string): string?
	for _, b in Controls.KEYMAP do
		if b.action == action then
			for _, k in b.keys do
				if not Controls.isGamepadKey(k) then
					return Controls.displayName(k)
				end
			end
		end
	end
	return nil
end

return Controls
