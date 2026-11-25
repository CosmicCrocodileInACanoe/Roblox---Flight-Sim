--!strict
-- Client-side aircraft audio. Reads the local flight model every frame, mixes it with
-- AudioMix and drives Sound instances. All asset IDs live in Shared/AudioConfig.
--
-- Slots with an empty or invalid ID get no Sound instance at all, so the game stays
-- silent (and error-free) until IDs are filled in. Sounds are 2D (non-positional) and
-- created on this client only, so each player hears their own aircraft.

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.AudioConfig)
local AudioMix = require(Shared.AudioMix)
local Damage = require(Shared.Damage)

local SoundController = {}
SoundController.__index = SoundController

local SILENT = 0.002

local shotFolder: Folder? = nil
local function oneShotFolder(): Folder
	if shotFolder and shotFolder.Parent then
		return shotFolder
	end
	local f = Instance.new("Folder")
	f.Name = "AircraftAudioOneShots"
	f.Parent = SoundService
	shotFolder = f
	return f
end

function SoundController.new()
	local self = setmetatable({}, SoundController) :: any
	self.fc = nil
	self.folder = nil :: Folder?
	self.groups = {} :: { [string]: SoundGroup }
	self.eq = nil :: EqualizerSoundEffect?
	self.loops = {} :: { [string]: { sound: Sound, cfg: any, volume: number, pitch: number } }
	self.oneShots = {} :: { [string]: { sound: Sound, cfg: any } }
	self.prev = nil
	self.memo = {}
	self.profile = nil
	self.voices = {} :: { [string]: { tts: Instance, cfg: any } }
	self.lastCallout = nil :: Instance?
	self.aheadSec = math.huge
	self.aheadTimer = 0
	self.atcVoice = nil :: Instance?
	self.atcClips = {} :: { any }
	self.atcTimer = 0
	return self
end

-- Text-to-speech voice for a callout slot without a recorded clip. Uses the Roblox
-- audio API (AudioTextToSpeech -> Wire -> AudioDeviceOutput). Returns nil when that API
-- isn't available, so the callout just stays silent.
local ttsBroken = false
local function makeVoice(parent: Instance, name: string, text: string, radio: boolean?): Instance?
	if ttsBroken then
		return nil
	end
	local ok, res = pcall(function()
		local tts = Instance.new("AudioTextToSpeech" :: any) :: any
		tts.Name = name
		tts.Text = text
		local out = Instance.new("AudioDeviceOutput" :: any) :: any
		out.Parent = tts
		local source: any = tts
		if radio then
			-- Thin "radio" tone: cut lows and highs. Optional; skipped if unavailable.
			pcall(function()
				local eq = Instance.new("AudioEqualizer" :: any) :: any
				eq.LowGain = -30
				eq.MidGain = 4
				eq.HighGain = -18
				eq.Parent = tts
				local w = Instance.new("Wire" :: any) :: any
				w.SourceInstance = tts
				w.TargetInstance = eq
				w.Parent = tts
				source = eq
			end)
		end
		local wire = Instance.new("Wire" :: any) :: any
		wire.SourceInstance = source
		wire.TargetInstance = out
		wire.Parent = tts
		tts.Parent = parent
		return tts
	end)
	if ok then
		return res
	end
	ttsBroken = true
	warn("[Audio] text-to-speech isn't available, voice callouts without an id stay silent: " .. tostring(res))
	return nil
end

local function playVoice(v: any, volume: number)
	local ok, err = pcall(function()
		v.Volume = volume
		v:Stop()
		v.TimePosition = 0
		v:Play()
	end)
	if not ok then
		warn("[Audio] voice callout failed: " .. tostring(err))
	end
end

local function stopAny(inst: any)
	pcall(function()
		inst:Stop()
	end)
end

local function makeGroup(parent: Instance, name: string): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = parent
	return g
end

function SoundController:attach(fc: any)
	self:detach()
	self.fc = fc
	local aircraftId = fc.model:GetAttribute("AircraftId") :: string?
	self.profile = AudioMix.profileFor(AudioConfig, aircraftId, fc.cfg)

	local ok, err = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "AircraftAudio"
		self.groups.exterior = makeGroup(folder, "Exterior")
		self.groups.cockpit = makeGroup(folder, "Cockpit")
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = AudioConfig.cockpitMuffle.lowGain
		eq.MidGain = AudioConfig.cockpitMuffle.midGain
		eq.HighGain = AudioConfig.cockpitMuffle.highGain
		eq.Enabled = false
		eq.Parent = self.groups.exterior
		self.eq = eq

		for slot, sc in AudioConfig.sounds do
			local url = AudioMix.assetUrl(sc.id)
			if not url then
				if sc.text and AudioConfig.useTextToSpeech then
					local v = makeVoice(folder, slot, sc.text)
					if v then
						self.voices[slot] = { tts = v, cfg = sc }
					end
				end
				continue
			end
			local s = Instance.new("Sound")
			s.Name = slot
			s.SoundId = url
			s.Looped = sc.looped == true
			s.Volume = 0
			s.SoundGroup = self.groups[sc.group] or self.groups.exterior
			s.Parent = folder
			if sc.looped then
				self.loops[slot] = { sound = s, cfg = sc, volume = 0, pitch = AudioMix.pitch(sc, 0) }
			else
				self.oneShots[slot] = { sound = s, cfg = sc }
			end
		end
		for slot, o in self.oneShots do
			if string.sub(slot, 1, 10) == "atcChatter" then
				table.insert(self.atcClips, o)
			end
		end
		if #self.atcClips == 0 and AudioConfig.useTextToSpeech then
			self.atcVoice = makeVoice(folder, "AtcVoice", "", true)
		end
		self.atcTimer = AudioMix.atcDelay(math.random(), AudioConfig.mix)
		folder.Parent = SoundService
		self.folder = folder
	end)
	if not ok then
		warn("[Audio] could not set up sounds, continuing silently: " .. tostring(err))
	end
end

function SoundController:detach()
	if self.folder then
		self.folder:Destroy()
	end
	self.folder = nil
	self.groups = {}
	self.eq = nil
	self.loops = {}
	self.oneShots = {}
	self.voices = {}
	self.lastCallout = nil
	self.atcVoice = nil
	self.atcClips = {}
	self.atcTimer = 0
	self.aheadSec = math.huge
	self.aheadTimer = 0
	self.prev = nil
	self.memo = {}
	self.fc = nil
end

-- Seconds until the flight path meets the ground (math.huge when clear).
local function terrainAhead(fc: any, maxStuds: number): number
	local core = fc.model.PrimaryPart
	if not core then
		return math.huge
	end
	local v = core.AssemblyLinearVelocity
	local speed = v.Magnitude
	if speed < 20 then
		return math.huge
	end
	local dist = math.min(maxStuds, speed * 40)
	local hit = Workspace:Raycast(core.Position, v.Unit * dist, fc.rayParams)
	if hit then
		return (hit.Position - core.Position).Magnitude / speed
	end
	return math.huge
end

local function snapshot(fc: any, aheadSec: number): any
	local fm = fc.fm
	local t = fc.telemetry or {}
	local n1, starting, rev = 0, false, 0
	local count = math.max(1, #fm.engines)
	for i, e in fm.engines do
		local comp = fc.cfg.engines[i] and fc.cfg.engines[i].component
		if comp == nil or Damage.isAttached(fm.damage, comp) then
			n1 += e.n1
			starting = starting or e.starting
			rev = math.max(rev, e.reverser)
		end
	end
	local detached = 0
	for _, c in fm.damage.components do
		if c.state == "detached" then
			detached += 1
		end
	end
	return {
		n1 = n1 / count,
		anyStarting = starting,
		reverser = rev,
		throttle = t.throttle or 0,
		ias = t.ias or 0,
		gs = t.gs or 0,
		onGround = t.onGround == true,
		gearExt = fm.gearExtension,
		flapPos = fm.flapPos,
		speedbrake = fm.speedbrakePos or 0,
		stallWarning = t.stallWarning == true,
		stall = t.stall == true,
		terrainAheadSec = aheadSec,
		altFt = t.altFt,
		rotateKts = fc.cfg.speeds and fc.cfg.speeds.rotate,
		raFt = t.raFt or 1e4,
		vsFpm = t.vsFpm or 0,
		crashed = fc.crashed == true,
		touchdownCount = fm.touchdownCount,
		touchdownVsFpm = (fc.touchdownFlash and fc.touchdownFlash.vsFpm) or 0,
		impactCount = fc.impactCount or 0,
		impactDv = fc.impactDv or 0,
		detachedCount = detached,
		time = fc.time or 0,
	}
end

-- cameraMode: "chase" | "cockpit" | "tower"
function SoundController:update(dt: number, cameraMode: string?)
	local fc = self.fc
	if not fc or not self.folder then
		return
	end
	local ok, err = pcall(function()
		self:_update(dt, cameraMode)
	end)
	if not ok then
		warn("[Audio] update failed, muting this flight: " .. tostring(err))
		self:detach()
	end
end

function SoundController:_update(dt: number, cameraMode: string?)
	local fc = self.fc
	local mix = AudioConfig.mix
	local master = AudioConfig.masterVolume
	self.aheadTimer -= dt
	if self.aheadTimer <= 0 then
		self.aheadTimer = 0.2
		self.aheadSec = terrainAhead(fc, mix.lookAheadMaxStuds)
	end
	local snap = snapshot(fc, self.aheadSec)

	-- View-dependent mix: cockpit muffles the outside, tower fades with distance.
	local inCockpit = cameraMode == "cockpit"
	local exteriorVol = 1
	if inCockpit then
		exteriorVol = AudioConfig.cockpitMuffle.volume
	elseif cameraMode == "tower" then
		local cam = Workspace.CurrentCamera
		local core = fc.model.PrimaryPart
		if cam and core then
			local d = (cam.CFrame.Position - core.Position).Magnitude
			exteriorVol = math.clamp(mix.towerFalloffStuds / math.max(d, 1), 0.05, 1)
		end
	end
	if self.eq then
		self.eq.Enabled = inCockpit
	end
	if self.groups.exterior then
		self.groups.exterior.Volume = exteriorVol
	end
	if self.groups.cockpit then
		self.groups.cockpit.Volume = if inCockpit then 1 else mix.warningsOutside
	end

	-- Loops
	local targets = AudioMix.loops(snap, self.prev, dt, self.profile, mix)
	local k = 1 - math.exp(-mix.smoothing * dt)
	for slot, l in self.loops do
		local tgt = targets[slot]
		local level = if tgt then tgt.level else 0
		local effect = if tgt then tgt.effect else 0
		local wantVol = level * l.cfg.volume * master
		l.volume += (wantVol - l.volume) * k
		l.pitch += (AudioMix.pitch(l.cfg, effect) - l.pitch) * k
		local s = l.sound
		if l.volume < SILENT and wantVol < SILENT then
			if s.IsPlaying then
				s:Pause()
			end
			s.Volume = 0
		else
			s.Volume = l.volume
			s.PlaybackSpeed = math.max(0.05, l.pitch)
			if not s.IsPlaying then
				s:Resume()
			end
		end
	end

	-- One-shots: play a copy so overlapping hits don't cut each other off. Copies live
	-- outside the aircraft's folder so a crash keeps sounding after the aircraft is gone.
	local cockpitVol = if inCockpit then 1 else mix.warningsOutside
	for _, ev in AudioMix.events(snap, self.prev, mix, self.memo, AudioConfig.sounds) do
		local isCallout = string.sub(ev.slot, 1, 7) == "callout"
		if isCallout and self.lastCallout then
			stopAny(self.lastCallout) -- one voice at a time
			self.lastCallout = nil
		end
		local voice = self.voices[ev.slot]
		if voice then
			playVoice(voice.tts, ev.gain * voice.cfg.volume * master * cockpitVol)
			self.lastCallout = voice.tts
			continue
		end
		local o = self.oneShots[ev.slot]
		if o then
			local s = o.sound:Clone()
			s.Volume = ev.gain * o.cfg.volume * master
			s.Parent = oneShotFolder()
			if isCallout then
				self.lastCallout = s
			end
			s:Play()
			s.Ended:Once(function()
				s:Destroy()
			end)
			Debris:AddItem(s, 30) -- fallback if Ended never fires (asset failed to load)
		end
	end

	self:_atc(dt, snap, cockpitVol)
	self.prev = snap
end

-- Background ATC: one transmission every atcMinGap..atcMaxGap seconds, cut at atcMaxSeconds.
function SoundController:_atc(dt: number, snap: any, cockpitVol: number)
	local mix = AudioConfig.mix
	if snap.crashed or (#self.atcClips == 0 and not self.atcVoice) then
		return
	end
	self.atcTimer -= dt
	if self.atcTimer > 0 then
		return
	end
	-- Hold off while a warning is talking; try again shortly.
	if snap.time - (self.memo.lastCalloutTime or -math.huge) < mix.atcQuietAfterWarning then
		self.atcTimer = 2
		return
	end
	self.atcTimer = AudioMix.atcDelay(math.random(), mix)
	local maxSec = mix.atcMaxSeconds
	if #self.atcClips > 0 then
		local o = self.atcClips[math.random(1, #self.atcClips)]
		local s = o.sound:Clone()
		s.Volume = o.cfg.volume * AudioConfig.masterVolume
		s.Parent = oneShotFolder()
		s:Play()
		task.delay(maxSec, function()
			s:Destroy()
		end)
	elseif self.atcVoice then
		local v: any = self.atcVoice
		local ok = pcall(function()
			v.Text = AudioMix.atcPhrase(math.random)
		end)
		if ok then
			playVoice(v, AudioConfig.atcVoiceVolume * AudioConfig.masterVolume * cockpitVol)
			task.delay(maxSec, function()
				stopAny(v)
			end)
		end
	end
end

return SoundController
