--!strict
-- Every sound the game can play, in one place.
--
-- HOW TO ADD A SOUND
--   1. Find an audio asset in the Creator Store (Studio: Toolbox -> Audio, or
--      create.roblox.com/store/audio). Copy its numeric asset ID.
--   2. Paste the number into `id` below, e.g.  id = "1234567890",
--   3. Play. Nothing else needs to change.
--
-- An empty id ("") means "no sound for this slot": the game stays silent there and never
-- errors. You can fill the slots in any order. Looping slots should be seamless loops;
-- one-shot slots should start immediately (no leading silence).
--
-- volume    : loudness at full effect (0..10, Roblox Sound.Volume; most sounds sit at 0.3..1)
-- pitchMin  : playback speed at the low end of the effect (idle, slow), loops only
-- pitchMax  : playback speed at the high end (full thrust, fast), loops only
-- group     : "exterior" sounds are muffled in the cockpit view, "cockpit" sounds are not

local AudioConfig = {}

AudioConfig.masterVolume = 1.0

AudioConfig.sounds = {
	-- Engines: jets (turbofan) -------------------------------------------------------
	jetWhine = { id = "", volume = 0.7, pitchMin = 0.55, pitchMax = 1.35, looped = true, group = "exterior" },
	jetRumble = { id = "", volume = 0.9, pitchMin = 0.8, pitchMax = 1.1, looped = true, group = "exterior" },
	-- Engines: propellers (turboprop) --------------------------------------------------
	propDrone = { id = "", volume = 0.8, pitchMin = 0.6, pitchMax = 1.25, looped = true, group = "exterior" },
	propRumble = { id = "", volume = 0.6, pitchMin = 0.85, pitchMax = 1.1, looped = true, group = "exterior" },
	-- Engine start (one-shot, plays once when you press the start key)
	engineStart = { id = "", volume = 0.7, looped = false, group = "exterior" },

	-- Airflow and rolling --------------------------------------------------------------
	wind = { id = "", volume = 0.8, pitchMin = 0.7, pitchMax = 1.3, looped = true, group = "exterior" },
	runwayRoll = { id = "", volume = 0.6, pitchMin = 0.8, pitchMax = 1.25, looped = true, group = "exterior" },

	-- Mechanical -----------------------------------------------------------------------
	gearMotor = { id = "", volume = 0.5, pitchMin = 1, pitchMax = 1, looped = true, group = "exterior" },
	gearLock = { id = "", volume = 0.8, looped = false, group = "exterior" }, -- clunk when gear locks up/down
	flapMotor = { id = "", volume = 0.4, pitchMin = 1, pitchMax = 1, looped = true, group = "exterior" },

	-- Touchdown and impacts ------------------------------------------------------------
	touchdown = { id = "", volume = 1.0, looped = false, group = "exterior" }, -- tyre thump; louder on hard landings
	tyreSqueal = { id = "", volume = 0.8, looped = false, group = "exterior" },
	impactLight = { id = "", volume = 0.9, looped = false, group = "exterior" }, -- scrapes, bumps, clipped objects
	impactHeavy = { id = "", volume = 1.2, looped = false, group = "exterior" }, -- big hits, parts breaking off
	crash = { id = "", volume = 1.5, looped = false, group = "exterior" }, -- aircraft destroyed

	-- Cockpit warnings (not muffled) ----------------------------------------------------
	-- stallWarning: about to stall (within a couple of degrees of the stall angle) and while stalled
	stallWarning = { id = "", volume = 0.6, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	-- stickShaker: rattle while the wing is actually stalled
	stickShaker = { id = "", volume = 0.7, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	gearWarning = { id = "", volume = 0.5, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },

	-- Voice callouts (one-shots, repeated while the danger lasts) -----------------------
	-- `text` is spoken with Roblox text-to-speech when the slot has no id (see
	-- useTextToSpeech below). A recorded clip in `id` always wins.
	calloutPullUp = { id = "", volume = 1.0, looped = false, group = "cockpit", text = "Whoop whoop. Pull up!", repeatEvery = 2.2 },
	calloutTerrain = { id = "", volume = 1.0, looped = false, group = "cockpit", text = "Terrain, terrain!", repeatEvery = 2.5 },
	calloutSinkRate = { id = "", volume = 0.9, looped = false, group = "cockpit", text = "Sink rate!", repeatEvery = 2.5 },
	calloutTooLowGear = { id = "", volume = 0.9, looped = false, group = "cockpit", text = "Too low. Gear!", repeatEvery = 3 },
	calloutStall = { id = "", volume = 1.0, looped = false, group = "cockpit", text = "Stall! Stall!", repeatEvery = 2 },
}

-- Speak callouts with Roblox text-to-speech when their slot has no id. Turn off to keep
-- callouts silent until recorded clips are added.
AudioConfig.useTextToSpeech = true

-- Which engine sounds each aircraft uses. Unknown aircraft use "jet".
AudioConfig.profiles = {
	jet = { whine = "jetWhine", rumble = "jetRumble" },
	prop = { whine = "propDrone", rumble = "propRumble" },
}
-- (an aircraft config's own soundProfile wins; this table covers older configs)
AudioConfig.aircraftProfile = {
	bumble = "prop",
	meadowlark4 = "prop",
	sprite = "prop",
	ridgehopper = "prop",
	puffin = "prop",
	breezetwin = "prop",
	silverline8 = "jet",
	swiftletj3 = "jet",
	vectorx1 = "jet",
	nightjart2 = "jet",
	kestrel72 = "prop",
	meridian200 = "jet",
	hauler4 = "prop",
	atlas400 = "jet",
	arrowstar = "jet",
	celestia800 = "jet",
}
AudioConfig.defaultProfile = "jet"

-- Mixing ------------------------------------------------------------------------------
AudioConfig.mix = {
	windFullKts = 320, -- wind is at full volume at this indicated airspeed
	rollFullKts = 150, -- runway rolling noise is at full volume at this ground speed
	squealMinKts = 40, -- tyres only squeal on touchdown above this ground speed
	firmLandingFpm = 600, -- touchdown thump reaches full volume at this sink rate
	impactLightDv = 5, -- m/s local velocity change for a light impact sound
	impactHeavyDv = 15, -- m/s for a heavy one
	impactCooldown = 0.25, -- s between impact sounds
	gearWarningFt = 1000, -- gear horn below this radio altitude...
	gearWarningThrottle = 0.3, -- ...when the throttle is below this...
	gearWarningFlap = 4, -- ...or the flaps are at or past this notch (1 = up)
	warningsOutside = 0.6, -- warning volume in the chase/tower views
	towerFalloffStuds = 300, -- tower view: exterior sounds fade beyond this distance
	smoothing = 8, -- loop volume/pitch follow rate (1/s); higher is snappier

	-- Ground proximity warnings (GPWS) --------------------------------------------------
	gpwsMinFt = 50, -- no terrain callouts below this height (flare and touchdown)
	gpwsMaxFt = 2500, -- sink rate checks only below this height
	sinkRateBaseFpm = 1000, -- "sink rate" when descending faster than base + perFt * height
	sinkRatePerFt = 0.6,
	pullUpSinkFactor = 1.4, -- "pull up" at this multiple of the sink rate limit
	pullUpBelowSec = 8, -- "pull up" when the ground below is this many seconds away
	terrainAheadSec = 25, -- "terrain" when the flight path meets ground within this time
	pullUpAheadSec = 12, -- "pull up" when it's this close
	lookAheadMaxStuds = 6000, -- how far ahead the terrain check looks
	tooLowGearFt = 500, -- "too low, gear" below this height with the gear up
}

-- Cockpit muffle: an equaliser on the exterior group while in the cockpit view (dB).
AudioConfig.cockpitMuffle = { lowGain = 0, midGain = -6, highGain = -20, volume = 0.8 }

return AudioConfig
