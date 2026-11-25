--!strict
-- Every sound the game can play, in one place.
--
-- HOW TO ADD A SOUND
--   1. Find an audio asset in the Creator Store (Studio: Toolbox -> Audio, or
--      create.roblox.com/store/audio). Copy its numeric asset ID.
--   2. Paste the number into `id` below, e.g.  id = "1234567890",
--   3. Play. Nothing else needs to change.
--
-- An id can also be a list of candidates: the game checks them when you start flying and
-- uses the first one that loads (Output prints "[Audio] N sounds loaded" and names any
-- slot with no working ID). The IDs below are starter picks from the Creator Store; swap
-- in ones you like better.
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
	jetWhine = { id = { "183339994", "123172515633498", "9116932100" }, volume = 0.7, pitchMin = 0.55, pitchMax = 1.35, looped = true, group = "exterior" },
	jetRumble = { id = { "169572883", "9113060656" }, volume = 0.9, pitchMin = 0.8, pitchMax = 1.1, looped = true, group = "exterior" },
	-- Engines: propellers (turboprop) --------------------------------------------------
	propDrone = { id = { "8907185231", "142317661", "117380424798601" }, volume = 0.8, pitchMin = 0.6, pitchMax = 1.25, looped = true, group = "exterior" },
	propRumble = { id = { "117380424798601", "142317661" }, volume = 0.6, pitchMin = 0.85, pitchMax = 1.1, looped = true, group = "exterior" },
	-- Engine start (one-shot, plays once when you press the start key)
	engineStart = { id = { "4686865643" }, volume = 0.7, looped = false, group = "exterior" },

	-- Airflow and rolling --------------------------------------------------------------
	wind = { id = { "9125742111", "147722270", "9125515917" }, volume = 0.8, pitchMin = 0.7, pitchMax = 1.3, looped = true, group = "exterior" },
	runwayRoll = { id = { "9125351349" }, volume = 0.6, pitchMin = 0.8, pitchMax = 1.25, looped = true, group = "exterior" },

	-- Mechanical -----------------------------------------------------------------------
	gearMotor = { id = { "9112838396", "9118977972" }, volume = 0.5, pitchMin = 1, pitchMax = 1, looped = true, group = "exterior" },
	gearLock = { id = { "9116673068" }, volume = 0.8, looped = false, group = "exterior" }, -- clunk when gear locks up/down
	flapMotor = { id = { "9118977972", "9112838396" }, volume = 0.4, pitchMin = 1, pitchMax = 1, looped = true, group = "exterior" },

	-- Touchdown and impacts ------------------------------------------------------------
	touchdown = { id = { "9113471570" }, volume = 1.0, looped = false, group = "exterior" }, -- tyre thump; louder on hard landings
	tyreSqueal = { id = { "772085046", "444542087" }, volume = 0.8, looped = false, group = "exterior" },
	impactLight = { id = { "9116523525" }, volume = 0.9, looped = false, group = "exterior" }, -- scrapes, bumps, clipped objects
	impactHeavy = { id = { "9116546593" }, volume = 1.2, looped = false, group = "exterior" }, -- big hits, parts breaking off
	crash = { id = { "9114224800", "9114554766" }, volume = 1.5, looped = false, group = "exterior" }, -- aircraft destroyed

	-- Cockpit warnings (not muffled) ----------------------------------------------------
	-- stallWarning: about to stall (within a couple of degrees of the stall angle) and while stalled
	stallWarning = { id = { "4112829784", "9113083860" }, volume = 0.6, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	-- stickShaker: rattle while the wing is actually stalled
	stickShaker = { id = { "9114890677", "rbxasset://sounds/clickfast.wav" }, volume = 0.7, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	-- fireBell: classic fire bell while an engine burns; overspeedClacker: above Vmo
	fireBell = { id = { "130821037", "250244656" }, volume = 0.6, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	overspeedClacker = { id = { "rbxasset://sounds/clickfast.wav", "9114651987" }, volume = 0.6, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },
	-- Master warning (red: fire, a part failing or breaking off, overspeed) and master
	-- caution (amber: engine out, jammed controls, hydraulics, fuel leak, low fuel, damage)
	masterWarning = { id = { "9113086365", "9113085665" }, volume = 0.7, looped = false, group = "cockpit" },
	masterCaution = { id = { "7149373060", "2909601104" }, volume = 0.6, looped = false, group = "cockpit" },
	-- The GPWS "whoop whoop" siren. Only used when the pull-up callout is spoken by
	-- text-to-speech; the recorded pull-up clips above already contain the whoop.
	gpwsWhoop = { id = { "386179883", "224090283" }, volume = 0.8, looped = false, group = "cockpit", maxSeconds = 1.3 },
	gearWarning = { id = { "2124207508", "9113085665" }, volume = 0.5, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" },

	-- Voice callouts (one-shots, repeated while the danger lasts) -----------------------
	-- `text` is spoken with Roblox text-to-speech when the slot has no id (see
	-- useTextToSpeech below). A recorded clip in `id` always wins.
	calloutPullUp = { id = { "4119192112", "7363264916", "139545781", "71134116968565" }, volume = 1.0, looped = false, group = "cockpit", text = "Pull up! Pull up!", repeatEvery = 2.6 },
	calloutTerrain = { id = "", volume = 1.0, looped = false, group = "cockpit", text = "Terrain, terrain!", repeatEvery = 2.5 },
	calloutSinkRate = { id = "", volume = 0.9, looped = false, group = "cockpit", text = "Sink rate!", repeatEvery = 2.5 },
	calloutTooLowGear = { id = "", volume = 0.9, looped = false, group = "cockpit", text = "Too low. Gear!", repeatEvery = 3 },
	calloutBankAngle = { id = { "4896248758" }, volume = 0.9, looped = false, group = "cockpit", text = "Bank angle! Bank angle!", repeatEvery = 3 },
	calloutStall = { id = "", volume = 1.0, looped = false, group = "cockpit", text = "Stall! Stall!", repeatEvery = 2 },

	-- Pilot and automatic callouts (one each time the moment happens) ------------------
	calloutEightyKnots = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Eighty knots." },
	calloutRotate = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Rotate." },
	calloutAlt1000 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "One thousand." },
	calloutAlt500 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Five hundred." },
	calloutAlt100 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "One hundred." },
	calloutAlt50 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Fifty." },
	calloutAlt40 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Forty." },
	calloutAlt30 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Thirty." },
	calloutAlt20 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Twenty." },
	calloutAlt10 = { id = "", volume = 0.8, looped = false, group = "cockpit", text = "Ten." },

	-- Cabin and cockpit ambience ---------------------------------------------------------
	cabinChime = { id = { "154605406", "142301402" }, volume = 0.6, looped = false, group = "cockpit" }, -- climbing/descending through 10,000 ft
	cockpitAmbience = { id = "", volume = 0.25, pitchMin = 1, pitchMax = 1, looped = true, group = "cockpit" }, -- avionics fans and hum

	-- Background ATC radio chatter. Fill any of these with radio-chatter clips; they're
	-- picked at random. With none filled, made-up exchanges are spoken with text-to-speech.
	-- Clips longer than mix.atcMaxSeconds are cut off.
	atcChatter1 = { id = { "251668919" }, volume = 0.35, looped = false, group = "cockpit" },
	atcChatter2 = { id = { "676395133" }, volume = 0.35, looped = false, group = "cockpit" },
	atcChatter3 = { id = "", volume = 0.35, looped = false, group = "cockpit" },
	atcChatter4 = { id = "", volume = 0.35, looped = false, group = "cockpit" },
	atcChatter5 = { id = "", volume = 0.35, looped = false, group = "cockpit" },
}

-- Volume of spoken ATC chatter when no clips are filled in.
AudioConfig.atcVoiceVolume = 0.35

-- Speak callouts with Roblox text-to-speech when their slot has no id. Turn off to keep
-- callouts silent until recorded clips are added.
AudioConfig.useTextToSpeech = true
-- Voice for text-to-speech (see the Roblox "list of artificial voices"; "1" and "2" are valid).
AudioConfig.ttsVoiceId = "5" -- warnings and callouts: United States male #2

-- Radio voices (Roblox voice IDs: 1 British male, 2 British female, 3 US male, 4 US
-- female, 5 US male #2, 6 US female #2, 7 Australian male, 8 Australian female).
-- Controllers and pilots use different voices; each pilot also gets a small pitch shift
-- so two pilots on the same voice still sound like different people.
AudioConfig.atcControllerVoices = { "4", "3" }
AudioConfig.atcPilotVoices = { "1", "2", "6", "7", "8" }
AudioConfig.atcPilotPitch = 2.5 -- +/- semitones

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
	rainmaker = "prop",
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
	bankAngleDeg = 35, -- "bank angle" past this bank in the air
	lowFuelFraction = 0.05, -- master caution below this share of fuel capacity

	-- Pilot callouts and ambience --------------------------------------------------------
	altitudeCallouts = { 1000, 500, 100, 50, 40, 30, 20, 10 }, -- feet, on approach with gear down
	takeoffMinThrottle = 0.5, -- "eighty knots" and "rotate" only on a takeoff roll
	chimeAltFt = 10000, -- cabin chime when crossing this altitude

	-- Background ATC chatter: never constant. After an exchange ends, the next one waits
	-- atcMinGap..atcMaxGap seconds (about 3 to 5 exchanges a minute). Each exchange is
	-- cut off after atcMaxSeconds.
	atcMinGap = 5,
	atcMaxGap = 16,
	atcMaxSeconds = 15,
	atcPoolMax = 16, -- spoken exchanges kept and reused (each new one costs 2 TTS requests)
	atcLineGap = 0.6, -- s between a call and its reply
	atcQuietAfterWarning = 4, -- no chatter for this long after a warning callout
	ttsWarmInterval = 9, -- s between pre-generating voices (Roblox allows ~7 TTS requests a minute solo)
}

-- Cockpit muffle: an equaliser on the exterior group while in the cockpit view (dB).
AudioConfig.cockpitMuffle = { lowGain = 0, midGain = -6, highGain = -20, volume = 0.8 }

return AudioConfig
