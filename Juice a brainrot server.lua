--this is a server script for a brainrot game where you juice brainrots to make juices and sell them for money

local rep = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ts = game:GetService("TweenService")
local rems = rep.remotes

local ProfileStore = require(script.ProfileStore)
local brainrot = require(script.Brainrot)
local Settings = require(game.ServerStorage.Settings)

local PROFILE_TEMPLATE = require(script.DataTemplate)

local Players = game:GetService("Players")

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}

local plots = {}
local brainrots = {}

local MAX_BR_PER_AREA = 20
local BR_DESPAWN_TIME = 300

local brId = 0

local TIME_DIV = 1
local SIZE_MULTI = 1.1
local MAX_BRS = 3

local COMBO_MULTIPLIERS = {
	[2] = 1.3,  
	[3] = 1.6,  
	[4] = 2.0,  
	[5] = 2.5,   
}

local moneyBoost = 0.05
local juicerDecreasePerUpgr = 0.05
local mixerDecreasePerUpgr = 0.05

local costPermoneyUpg = 100
local costPerJuicerUpg = 50
local costPerMixerUpgr = 75

local customers = {}

--functions
function tutorial(player:Player)
	local result = rems.confirm:InvokeClient(player, "Would you like to do the tutorial?")
	
	if result then
		rems.tut:FireClient(player)
	end
end

function checkStallForSales(plr)
	local plotNum = getPlot(plr)
	if not plotNum then return end

	local stall = workspace.bases:FindFirstChild(plotNum).stall
	local juicesFolder = stall:FindFirstChild("juices")

	if not juicesFolder then return end

	for _, juiceModel in juicesFolder:GetChildren() do
		if juiceModel:GetAttribute("waitingForBuyer") and customers[plr] > 0 then
			local value = juiceModel:GetAttribute("value")

			task.spawn(function()
				task.wait(0.5)

				giveMoney(plr, value)

				juiceModel:Destroy()

				customers[plr] = customers[plr] - 1
				rep.remotes.notify:FireClient(plr, "sold")

				print(string.format("%s auto-sold juice for $%d", plr.Name, value))
			end)

			break 
		end
	end
end

function Profile(player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then

		profile:AddUserId(player.UserId) 
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick(`Profile session end - Please rejoin`)
		end)

		if player.Parent == Players then
			Profiles[player] = profile
		else
			profile:EndSession()
		end

		return profile
	else
		player:Kick(`Profile load fail - Please rejoin`)
	end
end

function updateBag(plr)
	if not plr.Character then repeat task.wait() until plr.Character end
	local bcount = #Profiles[plr].Data.bag
	local bagSize = SIZE_MULTI ^ bcount
	local bag = plr.Character:FindFirstChild("bag")

	if bcount > MAX_BRS then
		for index, br in Profiles[plr].Data.bag do
			if index > MAX_BRS then
				table.remove(Profiles[plr].Data.bag, index)
			end
		end
	end

	if not bag then
		bag = script.bag:Clone()
		bag.Parent = plr.Character
		bag.CanCollide = false
		bag.Anchored = false
		bag.Color = Color3.new()

		local weld = Instance.new("Weld", bag)
		weld.Part1 = bag
		weld.Part0 = plr.Character.HumanoidRootPart
		weld.C1 = CFrame.new(.5,-1.25,0) * CFrame.Angles(0,0,math.rad(-90))
	end

	--bag.Size = Vector3.new(bagSize, bagSize, bagSize)
	bag.SurfaceGui.TextLabel.Text = bcount.."/"..MAX_BRS
	
	for _,tool:Tool in plr.Backpack:GetChildren() do
		if tool.Name == "Harpoon Gun" or string.find(string.lower(tool.Name), "juice") then continue end
		
		tool:Destroy()
	end
	
	for brIndex, brainrot in Profiles[plr].Data.bag do
		if brainrot.name then
			local tool = Instance.new("Tool", plr.Backpack)
			local n = ""

			for _,value in brainrot.modifiers do
				n = n.." "..value.name
			end

			tool.Name = n.." "..brainrot.name
			tool:SetAttribute("id", brainrot.id)
		end
	end
end

function calculateOfflineProgress(savedStart, savedDuration, currentTime)
	if not savedStart or not savedDuration then
		return 0, false
	end

	local expectedEnd = savedStart + savedDuration
	local elapsed = currentTime - savedStart

	if currentTime >= expectedEnd then
		return 0, true
	else
		local remaining = expectedEnd - currentTime
		return remaining, false
	end
end

function getPlot(plr: Player)
	for i, p: Player in plots do
		if p == plr then 
			return i 
		end
	end
	return nil
end

function getAvailablePlot()
	-- First, try to find an empty slot
	for i = 1, #workspace.bases:GetChildren() do
		if plots[i] == nil then
			return i
		end
	end

	local maxPlots = #workspace.bases:GetChildren()
	if #plots < maxPlots then
		return #plots + 1
	end

	return nil
end

function releasePlot(player: Player)
	for i, p in pairs(plots) do
		if p == player then
			plots[i] = nil

			local plotBase = workspace.bases:FindFirstChild(tostring(i))
			if plotBase then
				local nameLabel = plotBase:FindFirstChild("name")
				if nameLabel and nameLabel:FindFirstChild("SurfaceGui") then
					nameLabel.SurfaceGui.TextLabel.Text = ""
				end

				local stall = plotBase:FindFirstChild("stall")
				if stall then
					local juicesFolder = stall:FindFirstChild("juices")
					if juicesFolder then
						juicesFolder:ClearAllChildren()
					end
				end
			end

			print(string.format("Released plot %d from %s", i, player.Name))
			return true
		end
	end
	return false
end

function playerAdded(Player)
	local profile = Profile(Player)

	if not profile then
		return
	end

	local plot = getAvailablePlot()

	if not plot then
		Player:Kick("Server is full! No plots available. Please try again later.")
		return
	end

	plots[plot] = Player
	print(string.format("Assigned plot %d to %s", plot, Player.Name))

	local function teleportToPlot(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		local humanoid = char:WaitForChild("Humanoid", 5)

		if not hrp or not humanoid then
			warn("Character parts not loaded for", Player.Name)
			return
		end

		task.wait(0.1)

		local plotBase = workspace.bases:FindFirstChild(tostring(plot))
		if not plotBase then
			warn("Plot base not found:", plot)
			return
		end

		local spawnPart = plotBase:FindFirstChild("spawn")
		if not spawnPart then
			warn("Spawn part not found in plot:", plot)
			return
		end

		local spawnCFrame = spawnPart.CFrame * CFrame.new(0, 5, 0)

		char:PivotTo(spawnCFrame)
		hrp.CFrame = spawnCFrame

		char.Parent = workspace.Spawn

		task.wait(0.1)
		for i, jinfo in profile.Data.juices do
			if #jinfo.contains > 0 and jinfo.value > 0 then
				local tool = script.Juices:FindFirstChild(jinfo.jname):Clone()
				tool.Name = tool.Name.." "..jinfo.value.."$"
				tool.Parent = Player.Character
			else
				table.remove(Profiles[Player].Data.juices, i)
			end
		end
	end

	if Player.Character then
		task.spawn(function()
			teleportToPlot(Player.Character)
		end)
	end

	Player.CharacterAdded:Connect(function(char)
		task.spawn(function()
			teleportToPlot(char)
		end)
	end)

	local plotBase = workspace.bases:FindFirstChild(tostring(plot))
	if plotBase then
		local nameLabel = plotBase:FindFirstChild("name")
		if nameLabel and nameLabel:FindFirstChild("SurfaceGui") then
			nameLabel.SurfaceGui.TextLabel.Text = Player.DisplayName
		end
	end

	updateBag(Player)

	local now = tick()
	for i, j in profile.Data.juicers do
		if j.start and j.duration then
			local remaining, isFinished = calculateOfflineProgress(j.start, j.duration, now)

			if isFinished then
				profile.Data.juicers[i].timeleft = 0
				profile.Data.juicers[i].finished = true
				print(Player.Name.."'s juicer "..i.." finished while offline!")
			elseif remaining > 0 then
				profile.Data.juicers[i].timeleft = remaining
				startCountdown(Player, i, remaining, true)
				print(Player.Name.."'s juicer "..i.." resuming with "..math.floor(remaining).."s remaining")
			else
				profile.Data.juicers[i].timeleft = 0
				profile.Data.juicers[i].brsInside = {}
				profile.Data.juicers[i].juiceValue = 0
			end
		else
			profile.Data.juicers[i].timeleft = 0
			profile.Data.juicers[i].brsInside = {}
			profile.Data.juicers[i].juiceValue = 0
		end
	end

	if profile.Data.mixer.start and profile.Data.mixer.duration then
		local remaining, isFinished = calculateOfflineProgress(
			profile.Data.mixer.start, 
			profile.Data.mixer.duration, 
			now
		)

		if isFinished then
			profile.Data.mixer.timeleft = 0
			profile.Data.mixer.finished = true
			print(Player.Name.."'s mixer finished while offline!")
		elseif remaining > 0 then
			profile.Data.mixer.timeleft = remaining
			startMixerCountdown(Player, remaining, true)
			print(Player.Name.."'s mixer resuming with "..math.floor(remaining).."s remaining")
		else
			profile.Data.mixer.timeleft = 0
			profile.Data.mixer.juicesInside = {}
			profile.Data.mixer.endValue = 0
		end
	else
		profile.Data.mixer.timeleft = 0
		profile.Data.mixer.juicesInside = {}
		profile.Data.mixer.endValue = 0
	end

	local leaderstats = script.leaderstats:Clone()
	leaderstats.Parent = Player
	leaderstats.Money.Value = profile.Data.Money

	if profile.Data.jointime == 0 then
		tutorial(Player)
		profile.Data.jointime = tick()
	end
	
	if MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 1642743909) then
		profile.Data.hasvip = true 
		profile.Data.has2xmoney = true
		Player:SetAttribute("Title", "VIP")
		Player:SetAttribute("ColorCode", "EFBF04")
	end

	if MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 1642514018) then
		profile.Data.hasvip = true 
	end

	profile.Data.Money = math.clamp(profile.Data.Money, 0, math.huge)

	local plot = getPlot(Player)
	local plotModel = workspace.bases:FindFirstChild(plot)

	for i, jdata in profile.Data.juicers do
		local jInstance = plotModel.juicers:FindFirstChild(i)
		if not jInstance then continue end

		local label = jInstance.mix.SurfaceGui.TextLabel
		local glass = jInstance.glass
		local fill = jInstance.fill

		if jdata.finished then
			jInstance:SetAttribute("inuse", false)
			label.Text = "Claim"

			fill.Size = Vector3.new(fill.Size.X, glass.Size.Y, fill.Size.Z)
			local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
			fill.Position = Vector3.new(fill.Position.X, glassBottom + glass.Size.Y / 2, fill.Position.Z)
		else
			label.Text = "Juice"
		end
	end

	local mdata = profile.Data.mixer
	local mixer = plotModel.juicers:FindFirstChild("mixer")

	if mixer then
		local label = mixer.mix.SurfaceGui.TextLabel
		local glass = mixer.glass
		local fill = mixer.fill

		if mdata.finished then
			mixer:SetAttribute("inuse", false)
			label.Text = "Claim"

			fill.Size = Vector3.new(fill.Size.X, glass.Size.Y, fill.Size.Z)
			local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
			fill.Position = Vector3.new(fill.Position.X, glassBottom + glass.Size.Y / 2, fill.Position.Z)
		else
			label.Text = "Mix"
		end
	end
	
	customers[Player] = 0
	task.spawn(function()
		while task.wait(3) do
			if not Profiles[Player] then break end
			if customers[Player] < 5 then
				rep.remotes.notify:FireClient(Player, "addbuyer")
				customers[Player] += 1
				checkStallForSales(Player)
			end
		end
	end)
end

function RandomFromWeightedTable(OrderedTable)
	local success, result = pcall(function()
		local TotalWeight = 0

		for Piece, Weight in pairs(OrderedTable) do
			TotalWeight = TotalWeight + Weight
		end

		local Chance = math.random(1, TotalWeight)
		local Counter = 0
		for Piece, Weight in pairs(OrderedTable) do
			Counter = Counter + Weight
			if Chance <= Counter then
				return Piece
			end
		end
	end)

	if success then
		return result
	else
		warn("RandomFromWeightedTable failed:", result)
		return nil
	end
end

function spawnBrainrot(area:string)
	local orderedTable = {}

	local zone = workspace.brs:FindFirstChild(area)
	local rarityMul = zone and zone:GetAttribute("raritymul") or 1

	for _, b:Instance in rep.assets.Brainrots:GetChildren() do
		local s = Settings.baseBrainrotValues[b.Name]
		if s and s.rarity < 30 then
			orderedTable[b] = s.rarity * rarityMul
		end
	end

	brId += 1

	local object = brainrot.new(RandomFromWeightedTable(orderedTable).Name, brId, area)
	object.name = object.rig.Name
	object:rollModifiers()

	brainrots[brId] = object
end

function fillAreas()
	local areas = workspace.brs:GetChildren()

	for _,area:Instance in areas do
		for _,br:Instance in area:GetChildren() do
			if tick() - br:GetAttribute("spawntime") >= BR_DESPAWN_TIME then
				br:Destroy()--despawn after 5 mins
			end
		end

		if #area:GetChildren() < MAX_BR_PER_AREA then
			spawnBrainrot(area.Name)--spawn new brainrots
		end
	end
end

function lerp(a,b,t)
	return a + (b - a) * t
end

function FindValueBetween(min, max, value)
	local top = value - min	
	local bottom = max - min
	return top / bottom
end

function onJCountdownFinish(plr, juicer:number)
	Profiles[plr].Data.juicers[juicer].finished = true
	rems.notify:FireClient(plr, "jfinish")
end

function onMCountdownFinish(plr)
	Profiles[plr].Data.mixer.finished = true
end

function startCountdown(plr: Player, juicer: number, duration, isResuming)
	rems.notify:FireClient(plr, "startjuicer")
	local plot = getPlot(plr)
	local p = Profiles[plr]

	local start = tick()
	local stop = start + duration

	p.Data.juicers[juicer].timeleft = duration
	if not isResuming then
		p.Data.juicers[juicer].duration = duration
		p.Data.juicers[juicer].start = start
	else
		start = p.Data.juicers[juicer].start or tick()
		local savedDuration = p.Data.juicers[juicer].duration
		if savedDuration then
			stop = start + savedDuration
		else
			stop = start + duration
			p.Data.juicers[juicer].duration = duration
		end
	end

	local jInstance = workspace.bases:FindFirstChild(plot).juicers:FindFirstChild(juicer)
	local label = jInstance.mix.SurfaceGui.TextLabel
	local origText = label.Text

	jInstance:SetAttribute("inuse", true)

	local juicerModel: Model = jInstance:FindFirstChild("juicer")
	local animationRunning = true

	for _,c:ParticleEmitter in juicerModel.Parent.juicing_Vfx:GetChildren() do
		c.Enabled = true
	end

	-- animation params
	local pressDistance = 6
	local step = 0.02
	local holdTime = 0.1

	if juicerModel then
		task.spawn(function()
			local pivot = juicerModel:GetPivot()
			local x, z = pivot.Position.X, pivot.Position.Z
			local topY = pivot.Position.Y
			local bottomY = topY - pressDistance
			local rotation = pivot.Rotation

			while animationRunning do
				for t = 0, 1, step do
					local y = lerp(topY, bottomY, t)
					juicerModel:PivotTo(CFrame.new(x, y, z) * rotation)
					task.wait(step)
				end

				task.wait(holdTime)

				for t = 1, 0, -step do
					local y = lerp(topY, bottomY, t)
					juicerModel:PivotTo(CFrame.new(x, y, z) * rotation)
					task.wait(step)
				end

				task.wait(holdTime)
			end
		end)
	end

	local function tic()
		local remaining = stop - tick()
		p.Data.juicers[juicer].timeleft = remaining

		if remaining < 0 then
			remaining = 0
		end

		local hours = math.floor(remaining / 3600)
		local mins = math.floor((remaining % 3600) / 60)
		local seconds = math.floor(remaining % 60)

		label.Text = string.format("%02d:%02d:%02d", hours, mins, seconds)

		local glass = jInstance.glass
		local progress = FindValueBetween(start, stop, tick())
		local newHeight = lerp(0, glass.Size.Y, progress)

		local fill = jInstance.fill
		fill.Size = Vector3.new(fill.Size.X, newHeight, fill.Size.Z)

		local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
		fill.Position = Vector3.new(fill.Position.X, glassBottom + (newHeight / 2), fill.Position.Z)
	end

	task.spawn(function()
		tic()
		while task.wait(1) and stop > tick() and p.Data.juicers[juicer].timeleft > 0 do
			tic()
		end
		tic()

		animationRunning = false
		jInstance:SetAttribute("inuse", false)
		label.Text = "Claim"--origText

		onJCountdownFinish(plr, juicer)
		
		for _,c:ParticleEmitter in juicerModel.Parent.juicing_Vfx:GetChildren() do
			c.Enabled = false
		end
		
		for _,c:ParticleEmitter in juicerModel.Parent.doneJuicing_Vfx:GetChildren() do
			c:Emit(10)
		end
	end)
end

function startMixerCountdown(plr:Player, duration, isResuming)
	local plot = getPlot(plr)
	local p = Profiles[plr]

	local start = tick()
	local stop = start + duration

	p.Data.mixer.timeleft = duration
	if not isResuming then
		p.Data.mixer.duration = duration
		p.Data.mixer.start = start
	else
		start = p.Data.mixer.start or tick()
		local savedDuration = p.Data.mixer.duration
		if savedDuration then
			stop = start + savedDuration
		else
			stop = start + duration
			p.Data.mixer.duration = duration
		end
	end

	local mixerInstance = workspace.bases:FindFirstChild(plot).juicers:FindFirstChild("mixer")
	local label = mixerInstance.mix.SurfaceGui.TextLabel

	local origText = label.Text
	mixerInstance:SetAttribute("inuse", true)

	local function tic()
		local remaining = stop - tick()
		p.Data.mixer.timeleft = remaining

		if remaining < 0 then
			remaining = 0
		end

		local hours = math.floor(remaining / 3600)
		local mins = math.floor((remaining % 3600) / 60)
		local seconds = math.floor(remaining % 60)

		label.Text = string.format("%02d:%02d:%02d", hours, mins, seconds)

		local glass = mixerInstance.glass
		local progress = FindValueBetween(start, stop, tick())
		local newHeight = lerp(0, glass.Size.Y, progress)

		local fill = mixerInstance.fill
		fill.Size = Vector3.new(fill.Size.X, lerp(0, glass.Size.Y, progress), fill.Size.Z)

		local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
		fill.Position = Vector3.new(fill.Position.X, glassBottom + (newHeight / 2), fill.Position.Z)
	end

	task.spawn(function()
		tic()
		while task.wait(1) and stop > tick() and p.Data.mixer.timeleft > 0 do
			tic()
		end
		tic()
		mixerInstance:SetAttribute("inuse", false)
		label.Text = "Claim"--origText
		onMCountdownFinish(plr)
	end)
end

function calctime(brainrot, player)
	local base = brainrot.value or 20

	for _,mod in brainrot.modifiers do
		base = base * (mod.valueMul / TIME_DIV)
	end

	if player and Profiles[player] then
		local upgradeLevel = Profiles[player].Data.upgrades.juicerspeed
		local reduction = 1 - (upgradeLevel * juicerDecreasePerUpgr)
		base = base * math.max(reduction, 0.1) 
	end

	return base
end

function multiCalcTime(brs:{}, plr)
	local t = 0

	for _,v in brs do
		t += calctime(v,plr)
	end

	return t
end

function calcJuiceTime(juice, player)
	local base = juice.value / TIME_DIV

	if player and Profiles[player] then
		local upgradeLevel = Profiles[player].Data.upgrades.mixerspeed
		local reduction = 1 - (upgradeLevel * mixerDecreasePerUpgr)
		base = base * math.max(reduction, 0.1) 
	end

	return base
end

function multiCalcJuiceTime(juices:{}, plr)
	local t = 0

	for _,v in juices do
		t += calcJuiceTime(v, plr)
	end

	return t
end

function hold(plr, id)
	if brainrots[id].held or #Profiles[plr].Data.bag >= MAX_BRS then return else brainrots[id].held = true end

	brainrots[id].rig:Destroy()
	brainrots[id].rig = nil
	brainrots[id].spawnarea = brainrots[id].spawnarea.Name

	table.insert(Profiles[plr].Data.bag, brainrots[id])

	updateBag(plr)
	if #Profiles[plr].Data.bag >= MAX_BRS - 1 then
		rems.notify:FireClient(plr, "maxbag")
	end
	rems.notify:FireClient(plr, "caughtbr")
	return true
end

local productFunctions = {}

productFunctions[3476570311] = function(receipt, player) 
	if not Profiles[player] then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local mdata = Profiles[player].Data.mixer

	if mdata.timeleft > 0 then
		mdata.timeleft = 0
		mdata.finished = true

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

productFunctions[3476570176] = function(receipt, player) 
	if not Profiles[player] then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local plot = getPlot(player)
	local juicerNum = nil

	for i, jdata in Profiles[player].Data.juicers do
		if jdata.timeleft > 0 then
			juicerNum = i
			break
		end
	end

	if juicerNum then
		local jdata = Profiles[player].Data.juicers[juicerNum]

		jdata.timeleft = 0
		jdata.finished = true

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = productFunctions[receiptInfo.ProductId]
	if handler then
		return handler(receiptInfo, player)
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function initJuicer(plot, juicer)
	local prompt:ClickDetector = juicer.mix.ClickDetector

	local plotIndex = tonumber(plot.Name)	

	prompt.MouseClick:Connect(function(plr)
		local ownsPlot = getPlot(plr)

		if ownsPlot == plotIndex then
			if juicer.Name == "mixer" then
				local mdata = Profiles[plr].Data.mixer

				if not mdata.finished then
					if juicer:GetAttribute("inuse") == true then
						MarketplaceService:PromptProductPurchase(plr, 3476570311)
					else
						local result = rems.confirm:InvokeClient(plr, "Would you like to start mixing all the juices in your inventory?")

						if result then
							for _, tool in plr.Character:GetChildren() do
								if tool:IsA("Tool") and string.find(string.lower(tool.Name), "juice") then
									tool:Destroy()
								end
							end
							for _, tool in plr.Backpack:GetChildren() do
								if tool:IsA("Tool") and string.find(string.lower(tool.Name), "juice") then
									tool:Destroy()
								end
							end

							Profiles[plr].Data.mixer.juicesInside = table.clone(Profiles[plr].Data.juices)
							Profiles[plr].Data.juices = {}

							startMixerCountdown(plr, multiCalcJuiceTime(Profiles[plr].Data.mixer.juicesInside))
						end
					end
				else
					local endValue = 0

					for _,juice in mdata.juicesInside do
						endValue += juice.value
					end

					local numJuices = #mdata.juicesInside
					if numJuices >= 2 then
						local multiplier = COMBO_MULTIPLIERS[numJuices] or COMBO_MULTIPLIERS[5]  
						local originalValue = endValue
						endValue = math.floor(endValue * multiplier)
						print(string.format("🔥 %d-Juice Combo! %.0f%% bonus: $%d → $%d", 
							numJuices, 
							(multiplier - 1) * 100, 
							originalValue, 
							endValue
							))
					end

					local constructed = {
						value = endValue;
						jname = script.Juices:GetChildren()[math.random(1, #script.Juices:GetChildren())].Name;
						contains = mdata.juicesInside; 
					}

					table.insert(Profiles[plr].Data.juices, constructed)

					local tool = script.Juices:FindFirstChild(constructed.jname):Clone()
					tool.Name = tool.Name.." "..constructed.value.."$"
					tool.Parent = plr.Character

					local mixerInstance = workspace.bases:FindFirstChild(getPlot(plr)).juicers:FindFirstChild("mixer")
					local glass = mixerInstance.glass
					local fill = mixerInstance.fill

					fill.Size = Vector3.new(fill.Size.X, 0, fill.Size.Z)
					local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
					fill.Position = Vector3.new(fill.Position.X, glassBottom, fill.Position.Z)

					Profiles[plr].Data.mixer.finished = false
					Profiles[plr].Data.mixer.juicesInside = {}
					Profiles[plr].Data.mixer.endValue = 0
					Profiles[plr].Data.mixer.timeleft = 0

					mixerInstance.mix.SurfaceGui.TextLabel.Text = "Mix"

					print("Collected mixed juice worth $"..endValue.." from mixer! Take it to the shop to sell.")
				end
			else
				local jdata = Profiles[plr].Data.juicers[tonumber(juicer.Name)]

				if not jdata.finished then
					if juicer:GetAttribute("inuse") == true then
						juicer:SetAttribute("promptedJuicer", tonumber(juicer.Name))
						MarketplaceService:PromptProductPurchase(plr, 3476570176)
					else
						local result = rems.confirm:InvokeClient(plr, "Would you like to mix all the brainrots currently in your inventory?")

						if result and #Profiles[plr].Data.bag > 0 then
							Profiles[plr].Data.juicers[tonumber(juicer.Name)].brsInside = table.clone(Profiles[plr].Data.bag)
							Profiles[plr].Data.bag = {}

							for _, tool in plr.Character:GetChildren() do
								if tool:IsA("Tool") and tool.Name ~= "Harpoon Gun" and not string.find(string.lower(tool.Name), "juice") then
									tool:Destroy()
								end
							end
							for _, tool in plr.Backpack:GetChildren() do
								if tool:IsA("Tool") and tool.Name ~= "Harpoon Gun" and not string.find(string.lower(tool.Name), "juice") then
									tool:Destroy()
								end
							end

							updateBag(plr)

							startCountdown(plr, tonumber(juicer.Name), multiCalcTime(Profiles[plr].Data.juicers[tonumber(juicer.Name)].brsInside), false)
						end
					end
				else
					local endValue = 0

					for _,br in jdata.brsInside do
						local base = br.value

						for _,modif in br.modifiers do
							base *= modif.valueMul
						end

						endValue += base
					end

					local jInstance =  workspace.bases:FindFirstChild(getPlot(plr)).juicers:FindFirstChild(tonumber(juicer.Name))

					local glass = jInstance.glass
					local fill = jInstance.fill

					fill.Size = Vector3.new(fill.Size.X, 0, fill.Size.Z)
					local glassBottom = glass.Position.Y - (glass.Size.Y / 2)
					fill.Position = Vector3.new(fill.Position.X, glassBottom, fill.Position.Z)

					local constructed = {
						value = endValue;
						jname = script.Juices:GetChildren()[math.random(1, #script.Juices:GetChildren())].Name;
						contains = jdata.brsInside;
					}

					Profiles[plr].Data.juicers[tonumber(juicer.Name)].finished = false
					Profiles[plr].Data.juicers[tonumber(juicer.Name)].timeleft = 0
					Profiles[plr].Data.juicers[tonumber(juicer.Name)].brsInside = {}

					table.insert(Profiles[plr].Data.juices, constructed)

					
					local tool = script.Juices:FindFirstChild(constructed.jname):Clone()
					tool.Name = tool.Name.." "..constructed.value.."$"
					tool.Parent = plr.Character
					
					jInstance.mix.SurfaceGui.TextLabel.Text = "Juice"
					rems.notify:FireClient(plr, "claimedj")
				end
			end
		else
			MarketplaceService:PromptProductPurchase(plr, 3476574918)
		end
	end)
end

function giveMoney(plr, amount)
	local bonus = (Profiles[plr].Data.upgrades.moneyBonus * moneyBoost) * amount
	amount += bonus
	
	Profiles[plr].Data.Money += amount
	plr.leaderstats.Money.Value = Profiles[plr].Data.Money
	if Profiles[plr].Data.has2xmoney then
		if amount > 0 then
			amount *= 2
		end
	end
	rep.remotes.notify:FireClient(plr, "money",amount)
end

--connections
Players.PlayerAdded:Connect(playerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end

	customers[player] = nil

	releasePlot(player)

	print(player.Name.." has left the game")
end)

rep.remotes.notify.OnServerEvent:Connect(function(plr,event, ...)
	if event == "putHeldForSale" then
		print("Received")

		local character = plr.Character
		if not character then return end

		local heldTool = character:FindFirstChildOfClass("Tool")

		if heldTool and string.find(string.lower(heldTool.Name), "juice") then
			local juiceValue = 0
			local juiceIndex = nil

			for i, juice in ipairs(Profiles[plr].Data.juices) do
				if juice.jname and string.find(string.lower(heldTool.Name), string.lower(juice.jname)) then
					juiceValue = juice.value

					local numBrainrots = #juice.contains

					if numBrainrots >= 2 then
						local multiplier = COMBO_MULTIPLIERS[numBrainrots] or COMBO_MULTIPLIERS[5]
						juiceValue = math.floor(juiceValue * multiplier)
						print(string.format("Selling %d-brainrot juice with %.0f%% bonus!", numBrainrots, (multiplier - 1) * 100))
					end

					juiceIndex = i
					break
				end
			end

			if juiceIndex then
				local plotNum = getPlot(plr)
				local stall = workspace.bases:FindFirstChild(plotNum).stall
				local juicesFolder = stall:FindFirstChild("juices")

				if not juicesFolder then
					warn("Juices folder not found in stall for player:", plr.Name)
					return
				end

				local removedJuice = table.remove(Profiles[plr].Data.juices, juiceIndex)
				heldTool:Destroy()

				local juiceModel = script.Juices:FindFirstChild(removedJuice.jname):Clone()
				juiceModel.Name = removedJuice.jname.." "..juiceValue.."$"
				for _,p in juiceModel:GetChildren() do
					if p:IsA("BasePart") then
						p.Anchored = true
					end
				end

				local slotNum = #juicesFolder:GetChildren() + 1
				local offset = (slotNum - 1) * 2

				if juicesFolder:IsA("Model") and juicesFolder.PrimaryPart then
					juiceModel:PivotTo(juicesFolder:GetPivot() * CFrame.new(offset, 0, 0))
				elseif juicesFolder:IsA("BasePart") then
					juiceModel:PivotTo(juicesFolder.CFrame * CFrame.new(offset, 0, 0))
				end

				juiceModel.Parent = juicesFolder
				juiceModel:SetAttribute("value", juiceValue)
				juiceModel:SetAttribute("waitingForBuyer", true)

				print(string.format("%s placed juice worth $%d on stall", plr.Name, juiceValue))

				if customers[plr] and customers[plr] > 0 then
					task.spawn(function()
						task.wait(0.5) 

						giveMoney(plr, juiceValue)

						juiceModel:Destroy()

						customers[plr] = customers[plr] - 1
						rep.remotes.notify:FireClient(plr, "sold")

						rep.remotes.notify:FireClient(plr, "soldj")

						print(string.format("%s sold juice for $%d to customer!", plr.Name, juiceValue))
						rems.notify:FireClient(plr,"soldj")
					end)
				else
					print(plr.Name.." placed juice but no customers waiting")
				end
			else
				print(plr.Name.." is holding a juice but data not found!")
			end
		else
			print(plr.Name.." is not holding a juice!")
		end
	end
end)

rep.server.OnInvoke =function(event, plr, ...)
	if event == "putInBag" then
		local br = brainrots[...]

		br.rig:PivotTo(CFrame.new(0,100000,0))
		return hold(plr, ...)
	end
end

script.Parent.setvalueinstore.Event:Connect(function(plr, operator, vname, value)
	if operator == "=" then
		Profiles[plr].Data[vname] = value
	elseif operator == "+" then
		Profiles[plr].Data[vname] += value
	elseif operator == "-" then
		Profiles[plr].Data[vname] -= value
	end
end)

script.Parent.getvalueinstore.OnInvoke = function(plr, vname)
	return Profiles[plr].Data[vname]
end

rems.getjoin.OnServerInvoke = function(plr)
	if not Profiles[plr] then repeat task.wait() until Profiles[plr]end
		
	return Profiles[plr].Data.jointime
end

rems.buy.OnServerInvoke = function(plr, action)
	if not Profiles[plr] then repeat task.wait() until Profiles[plr] end
	local upgs = Profiles[plr].Data.upgrades
	
	local ret = {}
	if action == "costs" then
		ret.juicerspeed = (upgs.juicerspeed + 1) * costPerJuicerUpg
		ret.mixerspeed = (upgs.mixerspeed + 1) * costPerMixerUpgr
		ret.moneybonus = (upgs.moneyBonus + 1) * costPermoneyUpg
	elseif action == "juicerspeed" then
		local cost = (upgs.juicerspeed + 1) * costPerJuicerUpg
		ret.success = false
		if Profiles[plr].Data.Money >= cost then
			giveMoney(plr, -cost)
			ret.success = true
			
			Profiles[plr].Data.upgrades.juicerspeed += 1
			ret.nextbonus = (upgs.juicerspeed + 1) * juicerDecreasePerUpgr
			ret.curbonus = upgs.juicerspeed * juicerDecreasePerUpgr
			ret.newcost = (upgs.juicerspeed + 1) * costPerJuicerUpg
		end
	elseif action == "mixerspeed" then
		local cost = (upgs.mixerspeed + 1) * costPerMixerUpgr
		ret.success = false
		if Profiles[plr].Data.Money >= cost then
			giveMoney(plr, -cost)
			ret.success = true
			
			Profiles[plr].Data.upgrades.mixerspeed += 1
			ret.nextbonus = (upgs.mixerspeed + 1) * mixerDecreasePerUpgr
			ret.curbonus = upgs.mixerspeed * mixerDecreasePerUpgr
			ret.newcost = (upgs.mixerspeed + 1) * costPerMixerUpgr
		end
	elseif action == "moneybonus" then
		local cost = (upgs.moneyBonus + 1) * costPermoneyUpg
		ret.success = false
		if Profiles[plr].Data.Money >= cost then
			giveMoney(plr, -cost)
			ret.success = true
			
			Profiles[plr].Data.upgrades.moneyBonus += 1
			ret.nextbonus = (upgs.moneyBonus + 1) * moneyBoost
			ret.curbonus = upgs.moneyBonus * moneyBoost
			ret.newcost = (upgs.moneyBonus + 1) * costPermoneyUpg		
		end
	end
	return ret
end

rems.getplot.OnServerInvoke = function(plr) 
	local maxWait = 10  
	local waited = 0
	while waited < maxWait do
		local plot = getPlot(plr)
		if plot then
			return plot
		end
		task.wait(0.1)
		waited = waited + 0.1
	end
	warn("Could not find plot for player:", plr.Name)
	return nil
end

rems.getwalls.OnServerInvoke = function(plr)
	if not Profiles[plr] then repeat task.wait() until Profiles[plr] end
	return Profiles[plr].Data.wallsOpened
end
--init
for _, player in Players:GetPlayers() do
	task.spawn(playerAdded, player)
end

for _, plot in workspace.bases:GetChildren() do
	for _,juicer in plot.juicers:GetChildren() do
		initJuicer(plot, juicer)
	end
end

for _,spawnarea:Model in workspace.spawnareas:GetChildren() do
	local seperator = spawnarea:FindFirstChild("seperator")
	if seperator then
		local juices = seperator:GetAttribute("juices")
		local cash = seperator:GetAttribute("cash") 
		
		local prompt = Instance.new("ProximityPrompt", seperator)
		prompt.MaxIndicatorDistance = 60
		prompt.MaxActivationDistance = 60
		prompt.RequiresLineOfSight = true
		
		prompt.Triggered:Connect(function(plr)
			local data = Profiles[plr].Data 
			
			local hasj, hasmoney = false, false
			if #data.juices >= juices then
				for i=1,juices do
					table.remove(data, i)
				end
				
				for _, tool in plr.Character:GetChildren() do
					if tool:IsA("Tool") and string.find(string.lower(tool.Name), "juice") then
						tool:Destroy()
					end
				end
				for _, tool in plr.Backpack:GetChildren() do
					if tool:IsA("Tool") and string.find(string.lower(tool.Name), "juice") then
						tool:Destroy()
					end
				end
				
				for i,jinfo in data.juices do
					if #jinfo.contains > 0 and jinfo.value > 0 then
						local tool = script.Juices:FindFirstChild(jinfo.jname):Clone()
						tool.Name = tool.Name.." "..jinfo.value.."$"
						tool.Parent = plr.Character
					end
				end
				
				hasj = true
			end
			if data.Money >= cash then
				giveMoney(plr, -cash)
				hasmoney = true
			end
			
			if hasj and hasmoney then
				table.insert(Profiles[plr].Data.wallsOpened, spawnarea.Name)
				rems.notify:FireClient(plr, "haswall", spawnarea.Name)
			end
		end)
	end
end

script.Parent.sendmoney.Event:Connect(function(plr, amount)
	giveMoney(plr, amount)
end)

while task.wait(1) do
	fillAreas()
end

