--!strict
-- Emergency calls (see Shared/Rescue). The owning client reports a crash or a ditching
-- with ReportEmergency(model, situation); the server checks it against the aircraft it
-- knows about and tells every client to send the responders (fire trucks, ambulances and
-- police on land; rescue boats, helicopters and a ferry at sea). Each client builds and
-- drives the vehicles itself (client/EmergencyController), so they cost the server
-- nothing and move smoothly. Fix all, Reset, a new flight or leaving sends them home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rescue = require(Shared.Rescue)
local Registry = require(Shared.AircraftRegistry)
local Crash = require(Shared.Crash)
local WorldGen = require(Shared.WorldGen)

local EmergencyService = {}

export type Hooks = {
	remotes: Folder,
	getAircraft: (Player) -> Model?,
	notify: (Player, string) -> (),
}

type Incident = {
	id: string,
	ownerUserId: number,
	situation: string,
	pos: Vector3,
	aircraftId: string,
	passengers: number,
	started: number, -- os.clock()
}

local LIFETIME = 240 -- s; responders go home after this anyway
local hooks: Hooks
local incidents: { [Player]: Incident } = {}
local lastCall: { [Player]: number } = {}
local counter = 0

local function payload(inc: Incident): any
	return {
		id = inc.id,
		ownerUserId = inc.ownerUserId,
		situation = inc.situation,
		pos = inc.pos,
		aircraftId = inc.aircraftId,
		passengers = inc.passengers,
		age = os.clock() - inc.started,
	}
end

function EmergencyService.clear(p: Player)
	local inc = incidents[p]
	if not inc then
		return
	end
	incidents[p] = nil
	local r = hooks and hooks.remotes:FindFirstChild("EmergencyClear") :: RemoteEvent?
	if r then
		r:FireAllClients(inc.id)
	end
end

local function onReport(p: Player, model: any, situation: any)
	if typeof(model) ~= "Instance" or model ~= hooks.getAircraft(p) or type(situation) ~= "string" or not Rescue.SITUATIONS[situation] then
		return
	end
	local m = model :: Model
	local core = m.PrimaryPart
	if not core then
		return
	end
	local now = os.clock()
	if now - (lastCall[p] or -math.huge) < 3 then
		return
	end
	if Crash.justRepaired(m:GetAttribute("RepairedAt"), now) then
		return -- sent before Fix all put it back together
	end
	local existing = incidents[p]
	if existing and existing.situation == situation then
		return -- already on their way
	end
	local pos = core.Position
	local overSea = WorldGen.meshHeight(pos.X, pos.Z) < WorldGen.SEA_LEVEL - 1
	local cfg = Registry.get(m:GetAttribute("AircraftId") :: string)
	if not cfg then
		return
	end
	if situation == Rescue.LAND_CRASH then
		if overSea or not m:GetAttribute("Exploded") then
			return
		end
	elseif situation == Rescue.WATER_CRASH then
		if not overSea or not m:GetAttribute("Exploded") or pos.Y > WorldGen.SEA_LEVEL + 60 then
			return
		end
	else -- ditch: a landplane in one piece, in the sea
		if not overSea or Rescue.isWaterCapable(cfg) or pos.Y > WorldGen.SEA_LEVEL + 40 then
			return
		end
	end
	lastCall[p] = now
	if existing then
		EmergencyService.clear(p) -- a ditching that then broke up: send the right crews
	end
	counter += 1
	local inc: Incident = {
		id = `{p.UserId}-{counter}`,
		ownerUserId = p.UserId,
		situation = situation,
		pos = Vector3.new(pos.X, if overSea then WorldGen.SEA_LEVEL else pos.Y, pos.Z),
		aircraftId = cfg.id,
		passengers = Rescue.passengers(cfg),
		started = now,
	}
	incidents[p] = inc
	local r = hooks.remotes:FindFirstChild("Emergency") :: RemoteEvent?
	if r then
		r:FireAllClients(payload(inc))
	end
	hooks.notify(p, Rescue.callMessage(situation))
	task.delay(LIFETIME, function()
		if incidents[p] == inc then
			EmergencyService.clear(p)
		end
	end)
end

function EmergencyService.init(h: Hooks)
	hooks = h
	;(h.remotes:FindFirstChild("ReportEmergency") :: RemoteEvent).OnServerEvent:Connect(onReport)
	-- Someone joining while the crews are out sees them too.
	Players.PlayerAdded:Connect(function(newcomer)
		task.delay(8, function()
			local r = h.remotes:FindFirstChild("Emergency") :: RemoteEvent?
			if not r or not newcomer.Parent then
				return
			end
			for _, inc in incidents do
				r:FireClient(newcomer, payload(inc))
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		EmergencyService.clear(p)
		lastCall[p] = nil
	end)
end

return EmergencyService
