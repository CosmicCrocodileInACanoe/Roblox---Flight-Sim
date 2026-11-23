--!strict
-- Localized, progressive structural damage.
--
-- Each aircraft component (wing, engine, tail, gear leg, fuselage section) has health
-- 0..1 and a state. Damage comes from:
--   * impacts: the local velocity change at the component (m/s) beyond a threshold,
--   * scraping: continuous contact while sliding (wear per metre slid),
--   * gear touchdown sink rate and side load,
--   * sustained over-g.
-- A component whose health reaches zero detaches (if detachable) and takes its child
-- components with it. Losing the centre fuselage breaks the aircraft apart.

local Damage = {}

export type ComponentState = {
	name: string,
	cfg: any,
	health: number,
	state: string, -- "normal" | "degraded" | "failed" | "detached"
	detachedWithParent: boolean,
	-- Break points: sections torn off this component (outer wing, fin top, ...).
	sectionsLost: { [string]: boolean },
	lostFraction: number, -- 0..1 of the component's lift/mass gone with those sections
}

export type DamageEvent = { component: string, state: string, health: number, section: string? }

export type DamageModel = {
	components: { [string]: ComponentState },
	order: { string },
	events: { DamageEvent },
	destroyed: boolean,
	totalImpact: number,
}

local STATE_RANK = { normal = 0, degraded = 1, failed = 2, detached = 3 }
Damage.STATE_RANK = STATE_RANK

local PROPAGATE_TO_PARENT = 0.25

function Damage.new(componentsCfg: { [string]: any }): DamageModel
	local comps = {}
	local order = {}
	for name, cfg in componentsCfg do
		comps[name] = {
			name = name, cfg = cfg, health = 1, state = "normal", detachedWithParent = false,
			sectionsLost = {}, lostFraction = 0,
		}
		table.insert(order, name)
	end
	table.sort(order)
	return { components = comps, order = order, events = {}, destroyed = false, totalImpact = 0 }
end

local function stateForHealth(c: ComponentState): string
	if c.health <= 0 then
		return if c.cfg.detachable then "detached" else "failed"
	elseif c.health < 0.3 then
		return "failed"
	elseif c.health < 0.7 then
		return "degraded"
	end
	return "normal"
end

local function pushEvent(d: DamageModel, c: ComponentState)
	table.insert(d.events, { component = c.name, state = c.state, health = c.health })
end

local detachChildren: (DamageModel, string) -> ()

local function setState(d: DamageModel, c: ComponentState, newState: string)
	if c.state == newState then
		return
	end
	-- States only get worse during a flight.
	if STATE_RANK[newState] < STATE_RANK[c.state] then
		return
	end
	c.state = newState
	if newState == "detached" then
		c.health = 0
	end
	pushEvent(d, c)
	if newState == "detached" then
		detachChildren(d, c.name)
	end
	if c.name == "Fuselage" and (newState == "failed" or newState == "detached") then
		d.destroyed = true
		-- Break-up: every directly attached major component separates.
		for _, other in d.components do
			if other.cfg.parent == "Fuselage" and other.state ~= "detached" then
				other.health = 0
				setState(d, other, "detached")
			end
		end
	end
end

detachChildren = function(d: DamageModel, parentName: string)
	for _, other in d.components do
		if other.cfg.parent == parentName and other.state ~= "detached" then
			other.detachedWithParent = true
			other.health = 0
			other.state = "detached"
			pushEvent(d, other)
			detachChildren(d, other.name)
		end
	end
end

-- Reduce health by `amount` (0..1+) and update state. Returns the applied amount.
function Damage.hurt(d: DamageModel, name: string, amount: number, propagate: boolean?): number
	local c = d.components[name]
	if not c or c.state == "detached" or amount <= 0 or amount ~= amount then
		return 0
	end
	-- Only the health actually removed spreads to the parent, so a huge impact on a
	-- wing tip cannot pass more than a quarter of one component's worth to the fuselage.
	local removed = math.min(amount, c.health)
	c.health = math.max(0, c.health - amount)
	setState(d, c, stateForHealth(c))
	if propagate ~= false and c.cfg.parent and removed > 0 then
		Damage.hurt(d, c.cfg.parent, removed * PROPAGATE_TO_PARENT, false)
	end
	return amount
end

-- Damage from a single impact with local velocity change `dv` (m/s).
-- Below the threshold nothing happens; at `impactDestroy` the component is destroyed.
function Damage.impactAmount(cfg: any, dv: number): number
	local thr, destroy = cfg.impactThreshold, cfg.impactDestroy
	if dv <= thr then
		return 0
	end
	local t = (dv - thr) / (destroy - thr)
	return t ^ 1.5
end

function Damage.applyImpact(d: DamageModel, name: string, dv: number): number
	local c = d.components[name]
	if not c then
		return 0
	end
	local amount = Damage.impactAmount(c.cfg, dv)
	d.totalImpact += amount
	return Damage.hurt(d, name, amount)
end

-- Wear from sliding contact. `speed` m/s, `dt` s. Rates are per metre slid.
local WEAR_PER_METRE = {
	engine = 0.0045,
	wing = 0.0012,
	fuselage = 0.00055,
	tail = 0.002,
	gear = 0.002,
}
Damage.WEAR_PER_METRE = WEAR_PER_METRE

function Damage.wearKind(name: string): string
	-- Gear first: "LeftWingGear" is landing gear, not a wing.
	if string.find(name, "Gear") then
		return "gear"
	elseif string.find(name, "Engine") then
		return "engine"
	elseif string.find(name, "Wing") then
		return "wing"
	elseif string.find(name, "Stab") then
		return "tail"
	end
	return "fuselage"
end

function Damage.applyScrape(d: DamageModel, name: string, speed: number, dt: number): number
	if speed < 3 then
		return 0
	end
	local rate = WEAR_PER_METRE[Damage.wearKind(name)]
	return Damage.hurt(d, name, rate * speed * dt, false)
end

-- Gear touchdown: sink rate (m/s) and side slip speed at first contact.
function Damage.applyGearTouchdown(d: DamageModel, name: string, sink: number, side: number, limits: any): string?
	local c = d.components[name]
	if not c or c.state == "detached" then
		return nil
	end
	if sink >= limits.sinkDetach then
		Damage.hurt(d, name, 1.0)
		return "collapsed"
	elseif sink >= limits.sinkFail or side >= limits.sideSpeedFail then
		Damage.hurt(d, name, math.max(0.75, c.health - 0.05))
		return "failed"
	elseif sink >= limits.sinkDegrade then
		local t = (sink - limits.sinkDegrade) / (limits.sinkFail - limits.sinkDegrade)
		Damage.hurt(d, name, 0.32 + 0.35 * t, false)
		return "degraded"
	end
	return nil
end

-- Sustained over-g damages both wings slowly.
function Damage.applyOverG(d: DamageModel, gLoad: number, gLimit: number, dt: number)
	if gLoad <= gLimit then
		return
	end
	local amount = (gLoad - gLimit) * 0.35 * dt
	Damage.hurt(d, "LeftWing", amount, false)
	Damage.hurt(d, "RightWing", amount, false)
end

function Damage.state(d: DamageModel, name: string): string
	local c = d.components[name]
	return if c then c.state else "detached"
end

function Damage.isAttached(d: DamageModel, name: string): boolean
	local c = d.components[name]
	return c ~= nil and c.state ~= "detached"
end

-- Aerodynamic/structural effectiveness multiplier for a component.
function Damage.effectiveness(d: DamageModel, name: string): number
	local c = d.components[name]
	if not c then
		return 1
	end
	local intact = 1 - c.lostFraction
	if c.state == "detached" then
		return 0
	elseif c.state == "failed" then
		return 0.35 * intact
	elseif c.state == "degraded" then
		return (0.55 + 0.45 * c.health) * intact
	end
	return intact
end

-- Tear a section (a break point from Crash profiles) off a component. The component
-- stays attached but loses `lost` of its lift and mass, and takes `hurtAmount` damage.
-- Emits a "section" event (state = "section", section = id). Returns true if it broke.
function Damage.breakSection(d: DamageModel, name: string, sectionId: string, lost: number, hurtAmount: number?): boolean
	local c = d.components[name]
	if not c or c.state == "detached" or c.sectionsLost[sectionId] then
		return false
	end
	c.sectionsLost[sectionId] = true
	c.lostFraction = math.clamp(c.lostFraction + lost, 0, 0.95)
	table.insert(d.events, { component = name, state = "section", health = c.health, section = sectionId })
	Damage.hurt(d, name, hurtAmount or 0.2)
	return true
end

-- Mass (kg) a component has shed through lost sections while still attached.
function Damage.sectionMassLost(d: DamageModel, name: string): number
	local c = d.components[name]
	if not c or c.state == "detached" then
		return 0
	end
	return (c.cfg.mass or 0) * c.lostFraction
end

function Damage.drainEvents(d: DamageModel): { DamageEvent }
	local ev = d.events
	d.events = {}
	return ev
end

-- A rough 0..1 summary used for grading and HUD.
function Damage.overall(d: DamageModel): number
	local sum, n = 0, 0
	for _, c in d.components do
		sum += c.health
		n += 1
	end
	return if n > 0 then sum / n else 1
end

return Damage
