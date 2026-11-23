--!strict
-- Server-side, versioned player progress. Only rewards computed by the server are
-- recorded. DataStore failures never break gameplay (progress just isn't saved).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProgressService = {}

local SCHEMA_VERSION = 1
local store: DataStore? = nil
local cache: { [Player]: any } = {}

local function defaultData()
	-- bestStunts: best Stunts ring-course time in seconds (0 = no finish yet)
	return { version = SCHEMA_VERSION, flights = 0, landings = 0, bestLanding = 0, totalScore = 0, bestStunts = 0 }
end

local function migrate(data: any): any
	if type(data) ~= "table" then
		return defaultData()
	end
	if data.version == nil then
		data.version = 1
	end
	-- future: if data.version == 1 then ... data.version = 2 end
	for k, v in defaultData() do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

local function withRetry(fn: () -> any): (boolean, any)
	local ok, res
	for attempt = 1, 3 do
		ok, res = pcall(fn)
		if ok then
			return ok, res
		end
		task.wait(attempt)
	end
	return ok, res
end

local function updateLeaderstats(p: Player, data: any)
	local ls = p:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = p
		local f = Instance.new("IntValue")
		f.Name = "Flights"
		f.Parent = ls
		local b = Instance.new("IntValue")
		b.Name = "Best Landing"
		b.Parent = ls
	end
	(ls :: any).Flights.Value = data.flights
	;(ls :: any)["Best Landing"].Value = data.bestLanding
end

local function load(p: Player)
	local data = defaultData()
	if store then
		local ok, res = withRetry(function()
			return (store :: DataStore):GetAsync("player_" .. p.UserId)
		end)
		if ok then
			data = migrate(res)
		else
			warn("[Progress] load failed for", p.UserId, res)
			data.loadFailed = true
		end
	end
	cache[p] = data
	updateLeaderstats(p, data)
end

local function save(p: Player)
	local data = cache[p]
	if not store or not data or data.loadFailed then
		return -- never overwrite a profile we failed to read
	end
	withRetry(function()
		return (store :: DataStore):UpdateAsync("player_" .. p.UserId, function(old)
			local merged = migrate(old)
			merged.flights = math.max(merged.flights, data.flights)
			merged.landings = math.max(merged.landings, data.landings)
			merged.bestLanding = math.max(merged.bestLanding, data.bestLanding)
			merged.totalScore = math.max(merged.totalScore, data.totalScore)
			-- lower is better; 0 means none
			if data.bestStunts > 0 and (merged.bestStunts <= 0 or data.bestStunts < merged.bestStunts) then
				merged.bestStunts = data.bestStunts
			end
			merged.version = SCHEMA_VERSION
			return merged
		end)
	end)
end

function ProgressService.recordLanding(p: Player, score: number)
	local data = cache[p]
	if not data then
		return
	end
	data.landings += 1
	data.totalScore += score
	data.bestLanding = math.max(data.bestLanding, score)
	updateLeaderstats(p, data)
end

-- A finished Stunts run (total seconds, penalties included). Returns the best time and
-- whether this run set it.
function ProgressService.recordStunts(p: Player, seconds: number): (number, boolean)
	local data = cache[p]
	if not data then
		return seconds, true
	end
	local isNew = data.bestStunts <= 0 or seconds < data.bestStunts
	if isNew then
		data.bestStunts = seconds
		task.spawn(save, p)
	end
	return data.bestStunts, isNew
end

function ProgressService.bestStunts(p: Player): number?
	local data = cache[p]
	if not data or data.bestStunts <= 0 then
		return nil
	end
	return data.bestStunts
end

function ProgressService.recordFlight(p: Player, _mission: any)
	local data = cache[p]
	if not data then
		return
	end
	data.flights += 1
	updateLeaderstats(p, data)
	task.spawn(save, p)
end

function ProgressService.init()
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore("FlightSimProgress")
	end)
	if ok then
		store = res
	else
		warn("[Progress] DataStore unavailable (enable API access in Studio to test saving):", res)
	end
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		cache[p] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)
end

return ProgressService
