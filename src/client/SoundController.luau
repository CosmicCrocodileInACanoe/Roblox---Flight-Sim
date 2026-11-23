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
	return self
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
	self.prev = nil
	self.memo = {}
	self.fc = nil
end

local function snapshot(fc: any): any
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
	local snap = snapshot(fc)

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
	for _, ev in AudioMix.events(snap, self.prev, mix, self.memo) do
		local o = self.oneShots[ev.slot]
		if o then
			local s = o.sound:Clone()
			s.Volume = ev.gain * o.cfg.volume * master
			s.Parent = oneShotFolder()
			s:Play()
			s.Ended:Once(function()
				s:Destroy()
			end)
			Debris:AddItem(s, 30) -- fallback if Ended never fires (asset failed to load)
		end
	end

	self.prev = snap
end

return SoundController
